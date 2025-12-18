//
//  AGSessionManager.swift
//  ag-camera
//

import AVFoundation
import OSLog

@MainActor
public class AGSessionManager {

    private static let logger = Logger(subsystem: "com.agcamera", category: "SessionManager")

    public let captureSession = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "com.agcamera.sessionQueue")

    private(set) var videoDeviceInput: AVCaptureDeviceInput?
    private(set) var audioDeviceInput: AVCaptureDeviceInput?
    private(set) var photoOutput: AVCapturePhotoOutput?
    private(set) var movieFileOutput: AVCaptureMovieFileOutput?
    private(set) var currentDevice: AVCaptureDevice?
    private(set) var currentPosition: AVCaptureDevice.Position = .back

    private let permissionManager: AGPermissionManager

    init(permissionManager: AGPermissionManager) {
        self.permissionManager = permissionManager
    }

    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func setupSession(for position: AVCaptureDevice.Position, preset: AVCaptureSession.Preset = .photo) async throws {
        guard permissionManager.isCameraAuthorized else {
            throw CameraError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }

                do {
                    self.captureSession.beginConfiguration()

                    // Map 4:3 presets to 16:9 equivalents to prevent stretching
                    let adjustedPreset: AVCaptureSession.Preset
                    switch preset {
                    case .photo:
                        adjustedPreset = .hd1920x1080
                    case .high:
                        adjustedPreset = .hd1920x1080
                    default:
                        adjustedPreset = preset
                    }

                    if self.captureSession.canSetSessionPreset(adjustedPreset) {
                        self.captureSession.sessionPreset = adjustedPreset
                    } else if self.captureSession.canSetSessionPreset(preset) {
                        self.captureSession.sessionPreset = preset
                    }

                    try self.setupVideoInput(for: position)
                    try self.setupPhotoOutput()
                    try self.setupMovieOutput()
                    try? self.setupAudioInput()

                    self.currentPosition = position

                    self.captureSession.commitConfiguration()
                    continuation.resume()
                } catch {
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        photoOutput?.maxPhotoQualityPrioritization = prioritization
    }

    func switchCamera(to newPosition: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }

                do {
                    self.captureSession.beginConfiguration()
                    try self.setupVideoInput(for: newPosition)
                    self.currentPosition = newPosition
                    self.captureSession.commitConfiguration()
                    continuation.resume()
                } catch {
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func setupVideoInput(for position: AVCaptureDevice.Position) throws {
        if let currentInput = videoDeviceInput {
            captureSession.removeInput(currentInput)
        }

        guard let camera = getCamera(for: position) else {
            throw CameraError.cameraNotAvailable
        }

        let videoInput = try AVCaptureDeviceInput(device: camera)

        guard captureSession.canAddInput(videoInput) else {
            throw CameraError.setupFailed
        }

        captureSession.addInput(videoInput)
        videoDeviceInput = videoInput
        currentDevice = camera

        // Log format dimensions for debugging
        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        let aspectRatio = Float(dimensions.width) / Float(dimensions.height)
        Self.logger.info("Camera \(position == .front ? "FRONT" : "BACK") - Format: \(dimensions.width)x\(dimensions.height), Aspect: \(String(format: "%.2f", aspectRatio)), Zoom multiplier: \(camera.displayVideoZoomFactorMultiplier)")
    }

    private func setupPhotoOutput() throws {
        let output = AVCapturePhotoOutput()

        guard captureSession.canAddOutput(output) else {
            throw CameraError.setupFailed
        }

        captureSession.addOutput(output)
        photoOutput = output
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
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.setupFailed
        }

        let audioInput = try AVCaptureDeviceInput(device: audioDevice)

        guard captureSession.canAddInput(audioInput) else {
            throw CameraError.setupFailed
        }

        captureSession.addInput(audioInput)
        audioDeviceInput = audioInput
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        Self.logger.debug("Searching for camera at position: \(position == .back ? "Back" : "Front")")

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

        Self.logger.debug("Available devices: \(discoverySession.devices.map { "\($0.deviceType.rawValue) (min: \($0.minAvailableVideoZoomFactor), max: \($0.maxAvailableVideoZoomFactor))" }.joined(separator: ", "))")

        // Priority: DualWide > Triple > Dual > Wide
        if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
            Self.logger.info("Selected: Dual Wide Camera")
            return device
        }

        if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
            Self.logger.info("Selected: Triple Camera")
            return device
        }

        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
            Self.logger.info("Selected: Dual Camera")
            return device
        }

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            Self.logger.info("Selected: Wide Camera")
            return device
        }

        Self.logger.error("No camera found")
        return nil
    }
}
