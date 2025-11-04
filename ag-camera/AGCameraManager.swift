//
//  AGCameraManager.swift
//  ag-camera
//
//  Camera manager that handles all AVFoundation operations
//

import AVFoundation
import SwiftUI
import Observation
import Photos

/// Main camera manager class that provides all camera functionality
/// Use this class to control photo capture, video recording, and camera settings
@Observable
@MainActor
public class AGCameraManager: NSObject {

    // MARK: - Published Properties

    /// Current camera position (using Apple's native enum)
    public private(set) var currentCameraPosition: AVCaptureDevice.Position = .back

    /// Current flash mode (using Apple's native enum)
    public private(set) var flashMode: AVCaptureDevice.FlashMode = .off

    /// Whether camera session is running
    public private(set) var isSessionRunning = false

    /// Error state if any
    public private(set) var error: CameraError?

    /// Video recording state
    public private(set) var isRecording = false

    /// Recording duration in seconds (updates every 0.1s while recording)
    public private(set) var recordingDuration: TimeInterval = 0.0

    /// Current zoom factor (UI zoom - what user sees: 0.5×, 1×, 2×, etc.)
    public private(set) var currentZoomFactor: CGFloat = 1.0

    /// Display zoom multiplier (official Apple property since iOS 18)
    /// Converts device zoom to UI zoom: displayZoom = deviceZoom * multiplier
    /// For DualWideCamera: multiplier is typically 0.5 (so device 2.0 = UI 1.0×)
    private var displayZoomMultiplier: CGFloat {
        guard let device = currentDevice else { return 1.0 }
        // Use Apple's official property (iOS 18+)
        return device.displayVideoZoomFactorMultiplier
    }

    // MARK: - Private Properties

    /// Main capture session
    private let captureSession = AVCaptureSession()

    /// Serial queue for session configuration
    private let sessionQueue = DispatchQueue(label: "com.agcamera.sessionQueue")

    /// Current video device input
    private var videoDeviceInput: AVCaptureDeviceInput?

    /// Audio device input (for video recording with sound)
    private var audioDeviceInput: AVCaptureDeviceInput?

    /// Photo output
    private var photoOutput: AVCapturePhotoOutput?

    /// Movie file output for video recording
    private var movieFileOutput: AVCaptureMovieFileOutput?

    /// Current video device
    private var currentDevice: AVCaptureDevice?

    /// Permission manager reference
    private let permissionManager: AGPermissionManager

    /// Photo capture continuation
    private var photoCaptureCompletion: ((Result<Data, Error>) -> Void)?

    /// Video recording completion
    private var videoRecordingCompletion: ((Result<URL, Error>) -> Void)?

    /// Timer for tracking recording duration
    private var recordingTimer: Timer?

    /// Recording start time
    private var recordingStartTime: Date?

    // MARK: - Initialization

    public init(permissionManager: AGPermissionManager) {
        self.permissionManager = permissionManager
        super.init()
        setupNotifications()
    }

    deinit {
        // Stop session synchronously on background queue
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        // Timer is cleaned up in didFinishRecordingTo delegate method
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Setup and configure the camera session
    public func setupSession() async throws {
        guard permissionManager.isCameraAuthorized else {
            let error = CameraError.permissionDenied
            await MainActor.run { self.error = error }
            throw error
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }

                do {
                    // Begin configuration
                    self.captureSession.beginConfiguration()

                    // Set session preset for high quality
                    if self.captureSession.canSetSessionPreset(.photo) {
                        self.captureSession.sessionPreset = .photo
                    }

                    // Setup video input
                    try self.setupVideoInput(for: self.currentCameraPosition)

                    // Setup photo output
                    try self.setupPhotoOutput()

                    // Setup movie output for video recording
                    try self.setupMovieOutput()

                    // Setup audio input (for video recording with sound)
                    try? self.setupAudioInput() // Optional - video can work without audio

                    // Configure video mirroring AFTER outputs are added
                    self.configureVideoMirroring(for: self.currentCameraPosition)

                    // Commit configuration
                    self.captureSession.commitConfiguration()

                    // Clear error on success
                    Task { @MainActor in
                        self.error = nil
                    }

                    continuation.resume()
                } catch {
                    self.captureSession.commitConfiguration()

                    // Set error property
                    Task { @MainActor in
                        self.error = error as? CameraError ?? .setupFailed
                    }

                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Start the capture session
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()

                Task { @MainActor in
                    self.isSessionRunning = self.captureSession.isRunning
                }
            }
        }
    }

    /// Stop the capture session
    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()

                Task { @MainActor in
                    self.isSessionRunning = false
                }
            }
        }
    }

    /// Get the capture session (needed for preview layer)
    public func getCaptureSession() -> AVCaptureSession {
        return captureSession
    }

    // MARK: - Photo Capture

    /// Capture a photo
    /// - Returns: Photo data as Data
    public func capturePhoto() async throws -> Data {
        guard let photoOutput = photoOutput else {
            throw CameraError.captureFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Store the continuation to be called when photo is captured
            self.photoCaptureCompletion = { result in
                continuation.resume(with: result)
            }

            // Create photo settings
            let photoSettings = AVCapturePhotoSettings()

            // Configure flash mode
            if photoOutput.supportedFlashModes.contains(flashMode) {
                photoSettings.flashMode = flashMode
            }

            // Enable high resolution photo
            photoSettings.photoQualityPrioritization = .quality

            // Capture photo
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    // MARK: - Video Recording

    /// Start video recording
    /// - Returns: URL of the recorded video file
    public func startVideoRecording() async throws -> URL {
        guard let movieFileOutput = movieFileOutput else {
            throw CameraError.recordingFailed
        }

        guard !movieFileOutput.isRecording else {
            throw CameraError.recordingFailed
        }

        // Update recording state
        await MainActor.run {
            self.isRecording = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Store the continuation to be called when recording finishes
            self.videoRecordingCompletion = { result in
                continuation.resume(with: result)
            }

            // Create temporary file URL for the video
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            // Start recording
            movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    /// Stop video recording
    public func stopVideoRecording() {
        guard let movieFileOutput = movieFileOutput else { return }

        if movieFileOutput.isRecording {
            movieFileOutput.stopRecording()
        }
    }

    // MARK: - Camera Controls

    /// Switch between front and back camera
    public func switchCamera() async throws {
        // Determine the new position
        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }

                do {
                    // Begin configuration
                    self.captureSession.beginConfiguration()

                    // Setup new video input
                    try self.setupVideoInput(for: newPosition)

                    // Configure video mirroring for new camera position
                    self.configureVideoMirroring(for: newPosition)

                    // Commit configuration
                    self.captureSession.commitConfiguration()

                    // Update current position on main actor
                    Task { @MainActor in
                        self.currentCameraPosition = newPosition
                    }

                    continuation.resume()
                } catch {
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Set flash mode
    /// - Parameter mode: The flash mode to set (using Apple's native enum)
    public func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        Task { @MainActor in
            self.flashMode = mode
        }
    }

    /// Toggle flash mode (off -> on -> auto -> off)
    public func toggleFlash() {
        let newMode: AVCaptureDevice.FlashMode
        switch flashMode {
        case .off:
            newMode = .on
        case .on:
            newMode = .auto
        case .auto:
            newMode = .off
        @unknown default:
            newMode = .off
        }

        Task { @MainActor in
            self.flashMode = newMode
        }
    }

    /// Check if flash is available for current camera
    public var isFlashAvailable: Bool {
        guard let device = currentDevice else { return false }
        return device.hasFlash && device.isFlashAvailable
    }

    /// Enable/disable torch (flashlight) mode
    /// - Parameter enabled: Whether to enable torch mode
    public func setTorch(enabled: Bool) throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.hasTorch && device.isTorchAvailable else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if enabled {
            try device.setTorchModeOn(level: 1.0)
        } else {
            device.torchMode = .off
        }
    }

    // MARK: - Focus & Exposure Controls

    /// Set focus at a specific point in the preview
    /// - Parameter point: The point in the preview layer (normalized coordinates 0-1)
    public func setFocus(at point: CGPoint) throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isFocusPointOfInterestSupported else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
    }

    /// Set exposure at a specific point in the preview
    /// - Parameter point: The point in the preview layer (normalized coordinates 0-1)
    public func setExposure(at point: CGPoint) throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isExposurePointOfInterestSupported else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.exposurePointOfInterest = point
        device.exposureMode = .autoExpose
    }

    /// Set both focus and exposure at the same point
    /// - Parameter point: The point in the preview layer (normalized coordinates 0-1)
    public func setFocusAndExposure(at point: CGPoint) throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
        }

        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
        }
    }

    /// Set focus mode
    /// - Parameter mode: The focus mode to set (using Apple's native enum)
    public func setFocusMode(_ mode: AVCaptureDevice.FocusMode) throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isFocusModeSupported(mode) else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.focusMode = mode
    }

    /// Set exposure mode
    /// - Parameter mode: The exposure mode to set (using Apple's native enum)
    public func setExposureMode(_ mode: AVCaptureDevice.ExposureMode) throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isExposureModeSupported(mode) else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.exposureMode = mode
    }

    /// Lock current exposure and focus
    public func lockExposureAndFocus() throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.locked) {
            device.focusMode = .locked
        }

        if device.isExposureModeSupported(.locked) {
            device.exposureMode = .locked
        }
    }

    /// Reset to continuous auto focus and exposure
    public func resetFocusAndExposure() throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    // MARK: - Zoom Controls

    /// Set zoom factor
    /// - Parameter factor: The UI zoom factor (0.5 = ultra-wide, 1.0 = wide, 2.0+ = telephoto)
    public func setZoom(factor: CGFloat) throws {
        guard let device = currentDevice else {
            print("❌ No current device")
            throw CameraError.cameraNotAvailable
        }

        // Convert UI zoom to device zoom using Apple's official formula
        // deviceZoom = uiZoom / displayMultiplier
        let deviceZoom = factor / displayZoomMultiplier

        // Clamp to device's actual range
        let clampedDeviceZoom = min(max(deviceZoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)

        // Convert back to UI zoom for display
        let clampedUIZoom = clampedDeviceZoom * displayZoomMultiplier

        print("🎬 AGCameraManager.setZoom:")
        print("   UI zoom requested: \(String(format: "%.2f", factor))×")
        print("   Display multiplier: \(String(format: "%.2f", displayZoomMultiplier))")
        print("   Converted to device zoom: \(String(format: "%.2f", deviceZoom))")
        print("   Device range: [\(String(format: "%.2f", device.minAvailableVideoZoomFactor)) - \(String(format: "%.2f", device.maxAvailableVideoZoomFactor))]")
        print("   Clamped device zoom: \(String(format: "%.2f", clampedDeviceZoom))")
        print("   Final UI zoom: \(String(format: "%.2f", clampedUIZoom))×")

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.videoZoomFactor = clampedDeviceZoom
        print("   ✅ Applied videoZoomFactor = \(clampedDeviceZoom)")

        Task { @MainActor in
            self.currentZoomFactor = clampedUIZoom
        }
    }

    /// Get the maximum zoom factor available (capped at reasonable limit like Apple)
    /// Returns UI zoom value (e.g., 15.0 for 15×)
    public var maxZoomFactor: CGFloat {
        guard let device = currentDevice else { return 1.0 }
        let deviceMax = device.maxAvailableVideoZoomFactor

        // Different caps for front vs back camera
        let maxUIZoom: CGFloat = (currentCameraPosition == .front) ? 3.0 : 15.0

        // Cap device zoom to get reasonable UI zoom
        let cappedDeviceMax = min(deviceMax, maxUIZoom / displayZoomMultiplier)

        // Convert to UI zoom using Apple's formula
        return cappedDeviceMax * displayZoomMultiplier
    }

    /// Get the minimum zoom factor available
    /// Returns UI zoom value (e.g., 0.5 for ultra-wide)
    public var minZoomFactor: CGFloat {
        guard let device = currentDevice else { return 1.0 }

        // Convert device min to UI zoom using Apple's formula
        return device.minAvailableVideoZoomFactor * displayZoomMultiplier
    }

    // MARK: - Resolution & Quality Settings

    /// Set session preset (resolution)
    /// - Parameter preset: The session preset to use (using Apple's native enum)
    public func setSessionPreset(_ preset: AVCaptureSession.Preset) throws {
        guard captureSession.canSetSessionPreset(preset) else {
            throw CameraError.invalidConfiguration
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = preset
            self.captureSession.commitConfiguration()
        }
    }

    /// Set photo quality prioritization
    /// - Parameter prioritization: The quality prioritization level (using Apple's native enum)
    public func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        guard let photoOutput = photoOutput else { return }
        photoOutput.maxPhotoQualityPrioritization = prioritization
    }

    /// Get current session preset
    public var currentSessionPreset: AVCaptureSession.Preset {
        return captureSession.sessionPreset
    }

    /// Get all supported session presets for current configuration
    public var supportedSessionPresets: [AVCaptureSession.Preset] {
        let allPresets: [AVCaptureSession.Preset] = [
            .photo,
            .high,
            .medium,
            .low,
            .hd1280x720,
            .hd1920x1080,
            .hd4K3840x2160,
            .iFrame960x540,
            .iFrame1280x720,
            .vga640x480,
            .cif352x288
        ]

        return allPresets.filter { captureSession.canSetSessionPreset($0) }
    }

    /// Enable/disable video stabilization
    /// - Parameter mode: The video stabilization mode (using Apple's native enum)
    public func setVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) {
        guard let connection = movieFileOutput?.connection(with: .video) else { return }

        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = mode
        }
    }

    /// Set frame rate (FPS)
    /// - Parameter fps: Desired frames per second
    public func setFrameRate(fps: Int32) throws {
        guard let device = currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        // Find a format that supports the desired frame rate
        guard let format = device.formats.first(where: { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= Double(fps) && Double(fps) <= range.maxFrameRate
            }
        }) else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = format
        device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: fps)
        device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: fps)
    }

    // MARK: - Photo Library Management

    /// Save photo data to photo library
    /// - Parameter data: The photo data to save
    public func savePhotoToLibrary(_ data: Data) async throws {
        guard permissionManager.isPhotoLibraryAuthorized else {
            throw CameraError.permissionDenied
        }

        guard let image = UIImage(data: data) else {
            throw CameraError.captureFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAsset(from: image)
        }
    }

    /// Save video to photo library
    /// - Parameter url: The video file URL
    public func saveVideoToLibrary(url: URL) async throws {
        guard permissionManager.isPhotoLibraryAuthorized else {
            throw CameraError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }

        // Clean up temp file after saving
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private Setup Methods

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppWillResignActive() {
        // Stop session when app goes to background
        if isSessionRunning {
            stopSession()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        // Restart session when app becomes active
        if !isSessionRunning && permissionManager.isCameraAuthorized {
            startSession()
        }
    }

    private func setupVideoInput(for position: AVCaptureDevice.Position) throws {
        // Remove existing input if any
        if let currentInput = videoDeviceInput {
            captureSession.removeInput(currentInput)
        }

        // Get the camera device
        guard let camera = getCamera(for: position) else {
            throw CameraError.cameraNotAvailable
        }

        // Create input from device
        let videoInput = try AVCaptureDeviceInput(device: camera)

        // Add input to session
        guard captureSession.canAddInput(videoInput) else {
            throw CameraError.setupFailed
        }

        captureSession.addInput(videoInput)
        videoDeviceInput = videoInput
        currentDevice = camera

        // Initialize current zoom factor based on device's current zoom
        Task { @MainActor in
            // Convert device zoom to UI zoom using Apple's formula
            self.currentZoomFactor = camera.videoZoomFactor * camera.displayVideoZoomFactorMultiplier
        }
    }

    private func setupPhotoOutput() throws {
        let output = AVCapturePhotoOutput()

        guard captureSession.canAddOutput(output) else {
            throw CameraError.setupFailed
        }

        captureSession.addOutput(output)
        photoOutput = output

        // Configure photo output for high quality
        output.maxPhotoQualityPrioritization = .quality
    }

    private func setupMovieOutput() throws {
        let output = AVCaptureMovieFileOutput()

        guard captureSession.canAddOutput(output) else {
            throw CameraError.setupFailed
        }

        captureSession.addOutput(output)
        movieFileOutput = output
    }

    private func setupAudioInput() throws {
        // Get the default audio device
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.setupFailed
        }

        // Create audio input
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)

        // Add audio input to session
        guard captureSession.canAddInput(audioInput) else {
            throw CameraError.setupFailed
        }

        captureSession.addInput(audioInput)
        audioDeviceInput = audioInput
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Priority order: try multi-camera devices first for seamless zoom
        // This is Apple's recommended approach for accessing all lenses

        print("\n🔍 Searching for camera at position: \(position == .back ? "Back" : "Front")")

        // List all available devices
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: position
        )

        print("📱 Available devices:")
        for device in discoverySession.devices {
            print("   - \(device.deviceType.rawValue)")
            print("     Min zoom: \(device.minAvailableVideoZoomFactor)")
            print("     Max zoom: \(device.maxAvailableVideoZoomFactor)")
        }

        // 1. Try dual wide camera FIRST (iPhone 11/12/13/14/15 Pro - ultra-wide + wide)
        // This uses ultra-wide (0.5×) as base, allowing access to full range
        if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
            print("✅ Selected: Dual Wide Camera")
            print("   Min: \(device.minAvailableVideoZoomFactor)× Max: \(device.maxAvailableVideoZoomFactor)×")
            print("   Virtual device switch points: \(device.virtualDeviceSwitchOverVideoZoomFactors)")

            // Check constituent devices
            if let constituentDevices = device.constituentDevices as? [AVCaptureDevice] {
                print("   Constituent devices:")
                for constituent in constituentDevices {
                    print("      - \(constituent.deviceType.rawValue)")
                }
            }

            return device
        }

        // 2. Try triple camera (fallback - but this uses wide as base, no 0.5×)
        if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
            print("✅ Selected: Triple Camera (no ultra-wide access)")
            print("   Min: \(device.minAvailableVideoZoomFactor)× Max: \(device.maxAvailableVideoZoomFactor)×")
            return device
        }

        // 3. Try dual camera (older Pro models - wide + telephoto)
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
            print("✅ Selected: Dual Camera")
            print("   Min: \(device.minAvailableVideoZoomFactor)× Max: \(device.maxAvailableVideoZoomFactor)×")
            return device
        }

        // 4. Fallback to single wide camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            print("✅ Selected: Single Wide Camera")
            print("   Min: \(device.minAvailableVideoZoomFactor)× Max: \(device.maxAvailableVideoZoomFactor)×")
            return device
        }

        print("❌ No camera found!")
        return nil
    }

    private func configureVideoMirroring(for position: AVCaptureDevice.Position) {
        // DON'T mirror any output - we want captured photos/videos to be NOT mirrored
        let shouldMirror = false  // Always false for both cameras

        print("\n🔄 Configuring mirroring for: \(position == .front ? "FRONT" : "BACK") camera")
        print("   Should mirror: \(shouldMirror)")

        // Configure photo output connection
        if let photoOutput = photoOutput {
            print("   Photo output exists: ✓")
            if let photoConnection = photoOutput.connection(with: .video) {
                print("   Photo connection exists: ✓")
                if photoConnection.isVideoMirroringSupported {
                    print("   Photo mirroring supported: ✓")
                    photoConnection.automaticallyAdjustsVideoMirroring = false
                    photoConnection.isVideoMirrored = shouldMirror
                    print("   ✅ Photo mirroring set to: \(photoConnection.isVideoMirrored)")
                } else {
                    print("   ❌ Photo mirroring NOT supported")
                }
            } else {
                print("   ❌ Photo connection is NIL")
            }
        } else {
            print("   ❌ Photo output is NIL")
        }

        // Configure video output connection
        if let movieFileOutput = movieFileOutput {
            print("   Video output exists: ✓")
            if let videoConnection = movieFileOutput.connection(with: .video) {
                print("   Video connection exists: ✓")
                if videoConnection.isVideoMirroringSupported {
                    print("   Video mirroring supported: ✓")
                    videoConnection.automaticallyAdjustsVideoMirroring = false
                    videoConnection.isVideoMirrored = shouldMirror
                    print("   ✅ Video mirroring set to: \(videoConnection.isVideoMirrored)")
                } else {
                    print("   ❌ Video mirroring NOT supported")
                }
            } else {
                print("   ❌ Video connection is NIL")
            }
        } else {
            print("   ❌ Video output is NIL")
        }
        print("")
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension AGCameraManager: AVCapturePhotoCaptureDelegate {

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            photoCaptureCompletion?(.failure(error))
            photoCaptureCompletion = nil
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            photoCaptureCompletion?(.failure(CameraError.captureFailed))
            photoCaptureCompletion = nil
            return
        }

        photoCaptureCompletion?(.success(imageData))
        photoCaptureCompletion = nil
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension AGCameraManager: AVCaptureFileOutputRecordingDelegate {

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        // Apple's recommended approach: start timer when recording actually begins
        Task { @MainActor in
            self.recordingStartTime = Date()
            self.recordingDuration = 0.0

            // Create timer that fires every 0.1 seconds for smooth UI updates
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateRecordingDuration()
            }

            print("🎬 Recording started at: \(fileURL)")
        }
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            // Stop and invalidate timer
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.recordingStartTime = nil

            self.isRecording = false
            self.recordingDuration = 0.0

            print("🎬 Recording stopped. Duration was: \(String(format: "%.1f", self.recordingDuration))s")
        }

        if let error = error {
            videoRecordingCompletion?(.failure(error))
            videoRecordingCompletion = nil
            return
        }

        videoRecordingCompletion?(.success(outputFileURL))
        videoRecordingCompletion = nil
    }

    @MainActor
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
    }
}

// MARK: - Camera Errors

/// Camera errors
public enum CameraError: LocalizedError {
    case permissionDenied
    case cameraNotAvailable
    case setupFailed
    case captureFailed
    case recordingFailed
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied. Please enable camera access in Settings."
        case .cameraNotAvailable:
            return "Camera is not available on this device."
        case .setupFailed:
            return "Failed to setup camera session."
        case .captureFailed:
            return "Failed to capture photo."
        case .recordingFailed:
            return "Failed to record video."
        case .invalidConfiguration:
            return "Invalid camera configuration."
        }
    }
}
