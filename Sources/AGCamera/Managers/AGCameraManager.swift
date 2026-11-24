//
//  AGCameraManager.swift
//  ag-camera
//

import AVFoundation
import SwiftUI
import Observation
import Photos

@Observable
@MainActor
public class AGCameraManager: NSObject {

    public internal(set) var currentCameraPosition: AVCaptureDevice.Position = .back
    public private(set) var flashMode: AVCaptureDevice.FlashMode = .off
    public private(set) var isSessionRunning = false
    public private(set) var isSessionConfigured = false
    public private(set) var error: CameraError?
    public private(set) var isRecording = false
    public private(set) var isPreparingVideoRecording = false
    public private(set) var recordingDuration: TimeInterval = 0.0
    public private(set) var currentZoomFactor: CGFloat = 1.0
    public private(set) var lastZoomFactor: CGFloat = 1.0
    public private(set) var minZoomFactor: CGFloat = 1.0
    public private(set) var maxZoomFactor: CGFloat = 1.0
    public private(set) var availableZoomLevels: [CGFloat] = [1.0]
    public private(set) var isTorchOn = false
    public private(set) var isSwitchingCamera = false
    public var outputType: AGOutputType = .photo

    // Observable state for reactive UI
    public var capturedImage: UIImage?
    public var lastVideoURL: URL?
    public private(set) var lastStartedVideoURL: URL?
    public private(set) var lastStoppedVideoURL: URL?
    public var lastCapturedPhotoData: Data?

    // Camera switch animation state
    public var isBlurred: Bool = false
    public var flipRotation: Double = 0
    public var transitionSnapshot: UIImage?

    // Callback handlers for events
    public var onPhotoCapture: ((UIImage) -> Void)?
    public var onVideoStarted: ((URL) -> Void)?
    public var onVideoStopped: ((URL) -> Void)?
    public var onCameraPositionChanged: ((AVCaptureDevice.Position) -> Void)?
    public var onZoomChanged: ((CGFloat) -> Void)?
    public var onFlashModeChanged: ((AVCaptureDevice.FlashMode) -> Void)?
    public var onError: ((CameraError) -> Void)?

    let sessionManager: AGSessionManager
    private let captureManager: AGCaptureManager
    private let deviceControl: AGDeviceControlManager
    private let focusExposure: AGFocusExposureManager
    private let zoomManager: AGZoomManager
    private let qualitySettings: AGQualitySettingsManager
    private let mediaLibrary: AGMediaLibraryManager
    private var sessionCommandID = 0
    private var isSessionStartQueued = false
    private var isViewActive = true
    private var runningObservation: NSKeyValueObservation?
    private var interruptionObservation: NSKeyValueObservation?
    private var observedIsRunning = false
    private var observedIsInterrupted = false
    private var zoomCommandID = 0
    @ObservationIgnored let log: AGCameraLog

    public var configuration: AGCameraConfiguration
    public let permissionManager: AGPermissionManager

    private var configuredZoomMaximum: CGFloat {
        currentCameraPosition == .front
            ? configuration.maxFrontZoomFactor
            : configuration.maxBackZoomFactor
    }

    public init(configuration suppliedConfiguration: AGCameraConfiguration? = nil) {
        let configuration = suppliedConfiguration ?? .default
        self.configuration = configuration
        self.permissionManager = AGPermissionManager()
        self.currentCameraPosition = configuration.defaultCameraPosition
        let log = AGCameraLog(enabled: configuration.enableLogging)
        self.log = log

        self.sessionManager = AGSessionManager(permissionManager: permissionManager, log: log)
        self.captureManager = AGCaptureManager(sessionManager: sessionManager, log: log)
        self.deviceControl = AGDeviceControlManager(sessionManager: sessionManager)
        self.focusExposure = AGFocusExposureManager(sessionManager: sessionManager)
        self.zoomManager = AGZoomManager(sessionManager: sessionManager, log: log)
        self.qualitySettings = AGQualitySettingsManager(sessionManager: sessionManager)
        self.mediaLibrary = AGMediaLibraryManager(permissionManager: permissionManager)

        super.init()

        let session = sessionManager.captureSession
        runningObservation = session.observe(\.isRunning, options: [.initial, .new]) { [weak self] _, change in
            let isRunning = change.newValue ?? false
            DispatchQueue.main.async { [weak self] in
                self?.observedIsRunning = isRunning
                self?.updateObservedSessionState()
            }
        }
        interruptionObservation = session.observe(\.isInterrupted, options: [.initial, .new]) { [weak self] _, change in
            let isInterrupted = change.newValue ?? false
            DispatchQueue.main.async { [weak self] in
                self?.observedIsInterrupted = isInterrupted
                self?.updateObservedSessionState()
            }
        }

        // Apply default flash mode
        self.flashMode = configuration.defaultFlashMode
        self.captureManager.flashMode = configuration.defaultFlashMode
        self.captureManager.photoQualityPrioritization = configuration.photoQualityPrioritization
        self.captureManager.videoCodec = configuration.videoCodec

        captureManager.onRecordingStateChanged = { [weak self] isRecording, duration in
            guard let self = self else { return }
            Task { @MainActor in
                withAnimation {
                    self.isRecording = isRecording
                    self.recordingDuration = duration
                }
            }
        }
    }

    private func reportError(_ failure: Error, fallback: CameraError) {
        let cameraError = failure as? CameraError ?? fallback
        error = cameraError
        onError?(cameraError)
    }

    private func updateObservedSessionState() {
        isSessionRunning = observedIsRunning && !observedIsInterrupted && isViewActive
    }

    private func refreshZoomState() {
        currentZoomFactor = zoomManager.getCurrentZoomFactor()
        lastZoomFactor = currentZoomFactor
        minZoomFactor = zoomManager.getMinZoomFactor()
        maxZoomFactor = zoomManager.getMaxZoomFactor(
            for: currentCameraPosition,
            configuredMaximum: configuredZoomMaximum
        )
        availableZoomLevels = zoomManager.getAvailableZoomLevels(maximumZoomFactor: configuredZoomMaximum)
    }
}

// MARK: - Session Management

extension AGCameraManager {

    public func setupSession() async throws {
        if configuration.handlePermissions {
            guard permissionManager.isCameraAuthorized else {
                let error = CameraError.permissionDenied
                reportError(error, fallback: .permissionDenied)
                throw error
            }
        }

        do {
            guard configuration.maxFrontZoomFactor.isFinite,
                  configuration.maxFrontZoomFactor > 0,
                  configuration.maxBackZoomFactor.isFinite,
                  configuration.maxBackZoomFactor > 0,
                  configuration.defaultZoomScale.isFinite,
                  configuration.defaultZoomScale > 0,
                  configuration.torchLevel.isFinite,
                  (0.0...1.0).contains(configuration.torchLevel),
                  configuration.videoFrameRate > 0 else {
                throw CameraError.invalidConfiguration
            }

            if !sessionManager.isConfigured {
                currentCameraPosition = configuration.defaultCameraPosition
                try await sessionManager.setupSession(for: currentCameraPosition, preset: configuration.sessionPreset)
            }
            sessionManager.configureVideoMirroring(
                for: currentCameraPosition,
                mirrorFrontCamera: configuration.mirrorFrontCamera
            )

            sessionManager.setPhotoQualityPrioritization(configuration.photoQualityPrioritization)
            captureManager.photoQualityPrioritization = configuration.photoQualityPrioritization
            captureManager.videoCodec = configuration.videoCodec
            try await focusExposure.configureDefaultModes(
                focusMode: configuration.defaultFocusMode,
                exposureMode: configuration.defaultExposureMode
            )

            _ = try? await zoomManager.setZoom(
                factor: configuration.defaultZoomScale,
                maximumZoomFactor: configuredZoomMaximum
            )
            refreshZoomState()

            isSessionConfigured = true
            self.error = nil
        } catch {
            reportError(error, fallback: .setupFailed)
            throw error
        }
    }

    public func startSession() {
        guard !isSessionStartQueued else { return }
        isSessionStartQueued = true
        sessionCommandID += 1
        let commandID = sessionCommandID
        sessionManager.startSession { [weak self] isRunning in
            Task { @MainActor [weak self] in
                guard let self, self.sessionCommandID == commandID else { return }
                self.isSessionStartQueued = false
                self.observedIsRunning = isRunning
                self.updateObservedSessionState()
            }
        }
    }

    public func stopSession() {
        isSessionStartQueued = false
        sessionCommandID += 1
        let commandID = sessionCommandID
        sessionManager.stopSession { [weak self] isRunning in
            Task { @MainActor [weak self] in
                guard let self, self.sessionCommandID == commandID else { return }
                self.observedIsRunning = isRunning
                self.updateObservedSessionState()
            }
        }
    }

    public func addVideoDataOutput(_ output: AVCaptureVideoDataOutput) async throws {
        try await sessionManager.addVideoDataOutput(output)
        refreshZoomState()
    }

    public func handleAppBackground() {
        isViewActive = false
        updateObservedSessionState()
        stopSession()
    }

    public func handleAppForeground() {
        isViewActive = true
        updateObservedSessionState()
        let hasPermission = configuration.handlePermissions ? permissionManager.isCameraAuthorized : true
        if hasPermission && isSessionConfigured {
            startSession()
        }
    }

    func setViewActive(_ active: Bool) {
        if active {
            handleAppForeground()
        } else {
            handleAppBackground()
        }
    }

    func startSessionIfViewActive() {
        guard isViewActive else { return }
        startSession()
    }

    func getCaptureSession() -> AVCaptureSession {
        return sessionManager.captureSession
    }
}

// MARK: - Photo Capture

extension AGCameraManager {

    public func capturePhoto() async throws -> Data {
        guard !isSwitchingCamera else {
            log.warning("Photo capture blocked - camera switch in progress", category: "CameraManager")
            throw CameraError.cameraSwitchInProgress
        }

        let data: Data
        do {
            data = try await captureManager.capturePhoto()
        } catch {
            reportError(error, fallback: .captureFailed)
            throw error
        }

        // Set observable state for reactive UI
        lastCapturedPhotoData = data
        if let image = UIImage(data: data) {
            capturedImage = image
            onPhotoCapture?(image)
        }

        return data
    }
}

// MARK: - Video Recording

extension AGCameraManager {

    public func startVideoRecording() async throws -> URL {
        guard !isSwitchingCamera else {
            log.warning("Video recording blocked - camera switch in progress", category: "CameraManager")
            throw CameraError.cameraSwitchInProgress
        }
        guard !isPreparingVideoRecording else { throw CameraError.recordingFailed }
        isPreparingVideoRecording = true
        defer { isPreparingVideoRecording = false }

        let savedZoom = currentZoomFactor

        guard await permissionManager.requestMicrophonePermission() else {
            reportError(CameraError.microphonePermissionDenied, fallback: .microphonePermissionDenied)
            throw CameraError.microphonePermissionDenied
        }
        do {
            try await sessionManager.prepareVideoRecording(
                videoOutput: captureManager.recordingVideoOutput,
                audioOutput: captureManager.recordingAudioOutput,
                mirrorFrontCamera: configuration.mirrorFrontCamera
            )
        } catch {
            reportError(error, fallback: .recordingFailed)
            throw error
        }
        await qualitySettings.applyVideoStabilizationMode()

        do {
            try await qualitySettings.setFrameRate(fps: configuration.videoFrameRate)
        } catch {
            reportError(error, fallback: .invalidConfiguration)
            throw error
        }

        _ = try? await zoomManager.setZoom(
            factor: savedZoom,
            maximumZoomFactor: configuredZoomMaximum
        )
        refreshZoomState()
        captureManager.videoCodec = configuration.videoCodec

        let url: URL
        do {
            url = try await captureManager.startVideoRecording()
        } catch {
            reportError(error, fallback: .recordingFailed)
            throw error
        }
        lastVideoURL = url
        lastStartedVideoURL = url
        onVideoStarted?(url)
        return url
    }

    public func stopVideoRecording() async throws -> URL {
        let url: URL
        do {
            url = try await captureManager.stopVideoRecording()
        } catch {
            reportError(error, fallback: .recordingFailed)
            throw error
        }
        lastVideoURL = url
        lastStoppedVideoURL = url
        onVideoStopped?(url)
        return url
    }
}

// MARK: - Camera Controls

extension AGCameraManager {

    public func switchCamera(animated: Bool = true) async throws {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        defer {
            log.timing(
                "Camera switch request",
                elapsed: ProcessInfo.processInfo.systemUptime - requestedAt,
                category: "CameraManager"
            )
        }
        guard !isSwitchingCamera else {
            log.warning("Camera switch blocked - already in progress", category: "CameraManager")
            return
        }
        guard !isPreparingVideoRecording else {
            log.warning("Camera switch blocked - recording is starting", category: "CameraManager")
            return
        }

        isSwitchingCamera = true
        let wasRecording = isRecording
        if wasRecording {
            await captureManager.setRecordingVideoPaused(true)
        }

        do {
            if animated {
                withAnimation(.easeOut(duration: 0.1)) {
                    isBlurred = true
                }
            }

            let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back

            let zoomState = try await sessionManager.switchCamera(
                to: newPosition,
                zoomFactor: configuration.defaultZoomScale,
                maximumZoomFactor: newPosition == .front
                    ? configuration.maxFrontZoomFactor
                    : configuration.maxBackZoomFactor,
                focusMode: configuration.defaultFocusMode,
                exposureMode: configuration.defaultExposureMode,
                mirrorFrontCamera: configuration.mirrorFrontCamera
            )
            if wasRecording {
                await captureManager.setRecordingVideoPaused(false)
            }

            currentCameraPosition = newPosition
            isTorchOn = false
            if isRecording {
                do {
                    try await qualitySettings.setFrameRate(fps: configuration.videoFrameRate)
                } catch {
                    log.warning("Requested video frame rate is unavailable on the selected camera", category: "CameraManager")
                }
                await qualitySettings.applyVideoStabilizationMode()
            }
            refreshZoomState()
            onCameraPositionChanged?(newPosition)
            onZoomChanged?(currentZoomFactor)
            if !zoomState.didApplyDeviceSettings {
                reportError(CameraError.invalidConfiguration, fallback: .invalidConfiguration)
            }

            if animated {
                withAnimation(.easeIn(duration: 0.15)) {
                    isBlurred = false
                }
            }

            isSwitchingCamera = false
        } catch {
            isBlurred = false
            if wasRecording {
                await captureManager.setRecordingVideoPaused(false)
            }
            isSwitchingCamera = false
            reportError(error, fallback: .setupFailed)
            throw error
        }
    }

    public func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        self.flashMode = mode
        captureManager.flashMode = mode
        onFlashModeChanged?(mode)
    }

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

        self.flashMode = newMode
        captureManager.flashMode = newMode
        onFlashModeChanged?(newMode)
    }

    public var isFlashAvailable: Bool {
        deviceControl.isFlashAvailable
    }

    public func setTorch(enabled: Bool) async throws {
        isTorchOn = try await deviceControl.setTorch(enabled: enabled, level: configuration.torchLevel)
    }

    public func openTorch() async throws {
        try await setTorch(enabled: true)
    }

    public func closeTorch() async throws {
        try await setTorch(enabled: false)
    }

    public func setTorch(level: Float) async throws {
        guard level.isFinite, (0.0...1.0).contains(level) else {
            throw CameraError.invalidConfiguration
        }
        isTorchOn = try await deviceControl.setTorch(enabled: level > 0, level: level)
        configuration.torchLevel = level
    }

    public func toggleTorch() async throws {
        if isTorchOn {
            try await closeTorch()
        } else {
            try await openTorch()
        }
    }

    public func setOutputType(_ type: AGOutputType) {
        outputType = type
    }
}

// MARK: - Focus & Exposure

extension AGCameraManager {

    public func setFocus(at point: CGPoint) async throws {
        try await focusExposure.setFocus(at: point)
    }

    public func setExposure(at point: CGPoint) async throws {
        try await focusExposure.setExposure(at: point)
    }

    public func setFocusAndExposure(at point: CGPoint) async throws {
        try await focusExposure.setFocusAndExposure(at: point)
    }

    public func setFocusMode(_ mode: AVCaptureDevice.FocusMode) async throws {
        try await focusExposure.setFocusMode(mode)
    }

    public func setExposureMode(_ mode: AVCaptureDevice.ExposureMode) async throws {
        try await focusExposure.setExposureMode(mode)
    }

    public func lockExposureAndFocus() async throws {
        try await focusExposure.lockExposureAndFocus()
    }

    public func resetFocusAndExposure() async throws {
        try await focusExposure.resetFocusAndExposure()
    }
}

// MARK: - Zoom Controls

extension AGCameraManager {

    public func setZoom(factor: CGFloat) async throws {
        guard !Task.isCancelled else { return }
        zoomCommandID += 1
        let commandID = zoomCommandID
        try await zoomManager.setZoom(
            factor: factor,
            maximumZoomFactor: configuredZoomMaximum
        )
        guard !Task.isCancelled, commandID == zoomCommandID else { return }
        refreshZoomState()
        onZoomChanged?(currentZoomFactor)
    }

    public func updateZoomInteractively(scale: CGFloat, isGestureEnded: Bool) async throws {
        guard !Task.isCancelled else { return }
        zoomCommandID += 1
        let commandID = zoomCommandID
        let newZoom = lastZoomFactor * scale
        let maxZoom = zoomManager.getMaxZoomFactor(for: currentCameraPosition, configuredMaximum: configuredZoomMaximum)
        let minZoom = zoomManager.getMinZoomFactor()
        let clampedZoom = min(max(newZoom, minZoom), maxZoom)

        let applied = try await zoomManager.setZoom(
            factor: clampedZoom,
            maximumZoomFactor: configuredZoomMaximum
        )
        guard !Task.isCancelled, commandID == zoomCommandID else { return }
        currentZoomFactor = applied
        onZoomChanged?(currentZoomFactor)

        if isGestureEnded {
            refreshZoomState()
        }
    }
}

// MARK: - Quality Settings

extension AGCameraManager {

    public func setSessionPreset(_ preset: AVCaptureSession.Preset) async throws {
        try await qualitySettings.setSessionPreset(preset)
        configuration.sessionPreset = preset
        refreshZoomState()
    }

    public func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        qualitySettings.setPhotoQualityPrioritization(prioritization)
        captureManager.photoQualityPrioritization = prioritization
        configuration.photoQualityPrioritization = prioritization
    }

    public func setVideoCodec(_ codec: AVVideoCodecType?) {
        configuration.videoCodec = codec
        captureManager.videoCodec = codec
    }

    public func setLoggingEnabled(_ enabled: Bool) {
        configuration.enableLogging = enabled
        log.setEnabled(enabled)
    }

    public var currentSessionPreset: AVCaptureSession.Preset {
        qualitySettings.currentSessionPreset
    }

    public var supportedSessionPresets: [AVCaptureSession.Preset] {
        qualitySettings.supportedSessionPresets
    }

    public func setVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) async {
        await qualitySettings.setVideoStabilizationMode(mode)
    }

    public func setFrameRate(fps: Int32) async throws {
        try await qualitySettings.setFrameRate(fps: fps)
        configuration.videoFrameRate = fps
        refreshZoomState()
    }
}

// MARK: - Photo Library

extension AGCameraManager {

    public func savePhotoToLibrary(_ data: Data) async throws {
        try await mediaLibrary.savePhotoToLibrary(data)
    }

    public func saveVideoToLibrary(url: URL) async throws {
        try await mediaLibrary.saveVideoToLibrary(url: url)
    }
}

// MARK: - Presentation

extension AGCameraManager {

    public var flashIconName: String {
        switch flashMode {
        case .off:
            return "bolt.slash"
        case .on:
            return "bolt.fill"
        case .auto:
            return "bolt.badge.automatic"
        @unknown default:
            return "bolt.slash"
        }
    }

    public var formattedRecordingDuration: String {
        let totalSeconds = Int(recordingDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Camera Errors

public enum CameraError: LocalizedError, Sendable, Equatable {
    case permissionDenied
    case microphonePermissionDenied
    case cameraNotAvailable
    case setupFailed
    case captureFailed
    case recordingFailed
    case invalidConfiguration
    case cameraSwitchInProgress

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied. Please enable camera access in Settings."
        case .microphonePermissionDenied:
            return "Microphone permission denied. Video recording requires audio access."
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
        case .cameraSwitchInProgress:
            return "Camera is currently switching. Please wait."
        }
    }
}
