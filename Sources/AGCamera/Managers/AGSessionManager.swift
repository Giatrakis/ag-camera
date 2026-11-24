import AVFoundation
import OSLog

@MainActor
public final class AGSessionManager {
    private let worker = CameraSessionWorker()
    private let permissionManager: AGPermissionManager
    private var isSwitchingCamera = false

    public var captureSession: AVCaptureSession { worker.captureSession }
    var videoDeviceInput: AVCaptureDeviceInput? { worker.videoDeviceInput }
    var audioDeviceInput: AVCaptureDeviceInput? { worker.audioDeviceInput }
    var photoOutput: AVCapturePhotoOutput? { worker.photoOutput }
    var movieFileOutput: AVCaptureMovieFileOutput? { worker.movieFileOutput }
    var currentDevice: AVCaptureDevice? { worker.currentDevice }
    var currentPosition: AVCaptureDevice.Position { worker.currentPosition }
    var isConfigured: Bool { worker.isConfigured }

    init(permissionManager: AGPermissionManager) {
        self.permissionManager = permissionManager
    }

    deinit {
        worker.stopSession { _ in }
    }

    func setupSession(for position: AVCaptureDevice.Position, preset: AVCaptureSession.Preset = .photo) async throws {
        guard permissionManager.isCameraAuthorized else {
            throw CameraError.permissionDenied
        }

        try await worker.setupSession(
            for: position,
            preset: preset,
            includeAudio: permissionManager.isMicrophoneAuthorized
        )
    }

    func ensureAudioInput() async throws {
        try await worker.ensureAudioInput()
    }

    func startSession(completion: @escaping @Sendable (Bool) -> Void) {
        worker.startSession(completion: completion)
    }

    func stopSession(completion: @escaping @Sendable (Bool) -> Void) {
        worker.stopSession(completion: completion)
    }

    func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        worker.setPhotoQualityPrioritization(prioritization)
    }

    func setSessionPreset(_ preset: AVCaptureSession.Preset) throws {
        try worker.setSessionPreset(preset)
    }

    func switchCamera(to newPosition: AVCaptureDevice.Position) async throws {
        guard !isSwitchingCamera else { return }
        isSwitchingCamera = true
        defer { isSwitchingCamera = false }
        try await worker.switchCamera(to: newPosition)
    }
}

// The serial queue owns every mutation of the capture session graph and stored references.
// Remove @unchecked Sendable when AVFoundation provides a Sendable session abstraction.
private final class CameraSessionWorker: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.agcamera", category: "SessionWorker")

    let captureSession = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.agcamera.sessionQueue")

    private var storedVideoDeviceInput: AVCaptureDeviceInput?
    private var storedAudioDeviceInput: AVCaptureDeviceInput?
    private var storedPhotoOutput: AVCapturePhotoOutput?
    private var storedMovieFileOutput: AVCaptureMovieFileOutput?
    private var storedCurrentDevice: AVCaptureDevice?
    private var storedCurrentPosition: AVCaptureDevice.Position = .back
    private var storedIsConfigured = false

    var videoDeviceInput: AVCaptureDeviceInput? { queue.sync { storedVideoDeviceInput } }
    var audioDeviceInput: AVCaptureDeviceInput? { queue.sync { storedAudioDeviceInput } }
    var photoOutput: AVCapturePhotoOutput? { queue.sync { storedPhotoOutput } }
    var movieFileOutput: AVCaptureMovieFileOutput? { queue.sync { storedMovieFileOutput } }
    var currentDevice: AVCaptureDevice? { queue.sync { storedCurrentDevice } }
    var currentPosition: AVCaptureDevice.Position { queue.sync { storedCurrentPosition } }
    var isConfigured: Bool { queue.sync { storedIsConfigured } }

    func setupSession(
        for position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset,
        includeAudio: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.storedIsConfigured else {
                    continuation.resume()
                    return
                }

                let originalPreset = self.captureSession.sessionPreset
                self.captureSession.beginConfiguration()

                do {
                    guard self.captureSession.canSetSessionPreset(preset) else {
                        throw CameraError.invalidConfiguration
                    }
                    self.captureSession.sessionPreset = preset
                    try self.replaceVideoInput(for: position)
                    try self.setupPhotoOutput()
                    try self.setupMovieOutput()

                    if includeAudio {
                        do {
                            try self.setupAudioInput()
                        } catch {
                            Self.logger.warning("Microphone input unavailable: \(error.localizedDescription)")
                        }
                    }

                    self.storedCurrentPosition = position
                    self.storedIsConfigured = true
                    self.captureSession.commitConfiguration()
                    continuation.resume()
                } catch {
                    self.removePartialConfiguration()
                    if self.captureSession.canSetSessionPreset(originalPreset) {
                        self.captureSession.sessionPreset = originalPreset
                    }
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func ensureAudioInput() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.storedIsConfigured else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }
                guard self.storedAudioDeviceInput == nil else {
                    continuation.resume()
                    return
                }

                self.captureSession.beginConfiguration()
                do {
                    try self.setupAudioInput()
                    self.captureSession.commitConfiguration()
                    continuation.resume()
                } catch {
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startSession(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            if self.storedIsConfigured && !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            completion(self.captureSession.isRunning)
        }
    }

    func stopSession(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            completion(self.captureSession.isRunning)
        }
    }

    func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        queue.async {
            self.storedPhotoOutput?.maxPhotoQualityPrioritization = prioritization
        }
    }

    func setSessionPreset(_ preset: AVCaptureSession.Preset) throws {
        guard queue.sync(execute: { captureSession.canSetSessionPreset(preset) }) else {
            throw CameraError.invalidConfiguration
        }
        queue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = preset
            self.captureSession.commitConfiguration()
        }
    }

    func switchCamera(to newPosition: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.storedIsConfigured else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }

                self.captureSession.beginConfiguration()
                do {
                    try self.replaceVideoInput(for: newPosition)
                    self.storedCurrentPosition = newPosition
                    self.captureSession.commitConfiguration()
                    continuation.resume()
                } catch {
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func replaceVideoInput(for position: AVCaptureDevice.Position) throws {
        guard let camera = getCamera(for: position) else {
            throw CameraError.cameraNotAvailable
        }
        let replacement = try AVCaptureDeviceInput(device: camera)
        let previous = storedVideoDeviceInput

        if let previous {
            captureSession.removeInput(previous)
        }

        guard captureSession.canAddInput(replacement) else {
            if let previous, captureSession.canAddInput(previous) {
                captureSession.addInput(previous)
            } else {
                storedVideoDeviceInput = nil
                storedCurrentDevice = nil
                storedIsConfigured = false
            }
            throw CameraError.setupFailed
        }

        captureSession.addInput(replacement)
        storedVideoDeviceInput = replacement
        storedCurrentDevice = camera
    }

    private func setupPhotoOutput() throws {
        guard storedPhotoOutput == nil else { return }
        let output = AVCapturePhotoOutput()
        guard captureSession.canAddOutput(output) else {
            throw CameraError.setupFailed
        }
        captureSession.addOutput(output)
        storedPhotoOutput = output
    }

    private func setupMovieOutput() throws {
        guard storedMovieFileOutput == nil else { return }
        let output = AVCaptureMovieFileOutput()
        guard captureSession.canAddOutput(output) else {
            throw CameraError.setupFailed
        }
        captureSession.addOutput(output)
        storedMovieFileOutput = output
    }

    private func setupAudioInput() throws {
        guard storedAudioDeviceInput == nil else { return }
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.setupFailed
        }
        let input = try AVCaptureDeviceInput(device: audioDevice)
        guard captureSession.canAddInput(input) else {
            throw CameraError.setupFailed
        }
        captureSession.addInput(input)
        storedAudioDeviceInput = input
    }

    private func removePartialConfiguration() {
        if let output = storedPhotoOutput { captureSession.removeOutput(output) }
        if let output = storedMovieFileOutput { captureSession.removeOutput(output) }
        if let input = storedAudioDeviceInput { captureSession.removeInput(input) }
        if let input = storedVideoDeviceInput { captureSession.removeInput(input) }
        storedPhotoOutput = nil
        storedMovieFileOutput = nil
        storedAudioDeviceInput = nil
        storedVideoDeviceInput = nil
        storedCurrentDevice = nil
        storedIsConfigured = false
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return nil
    }
}
