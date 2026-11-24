import AVFoundation

struct AGZoomState: Sendable {
    let factor: CGFloat
    let minimum: CGFloat
    let maximum: CGFloat
    let didApplyDeviceSettings: Bool
}

struct AGLivePhotoState: Sendable {
    let isSupported: Bool
    let isEnabled: Bool
}

// The caller configures the output before registration; only this queue changes its session membership.
// Remove this wrapper when AVFoundation output types become Sendable.
private struct QueuedVideoDataOutput: @unchecked Sendable {
    let value: AVCaptureVideoDataOutput
}

// The session queue alone changes output membership; remove when AVFoundation outputs are Sendable.
private struct QueuedRecordingOutputs: @unchecked Sendable {
    let video: AVCaptureVideoDataOutput
    let audio: AVCaptureAudioDataOutput
}

@MainActor
final class AGSessionManager {
    private let worker: CameraSessionWorker
    private let permissionManager: AGPermissionManager
    private var isSwitchingCamera = false

    var captureSession: AVCaptureSession { worker.captureSession }
    var videoDeviceInput: AVCaptureDeviceInput? { worker.videoDeviceInput }
    var audioDeviceInput: AVCaptureDeviceInput? { worker.audioDeviceInput }
    var photoOutput: AVCapturePhotoOutput? { worker.photoOutput }
    var livePhotoState: AGLivePhotoState { worker.livePhotoState }
    var currentDevice: AVCaptureDevice? { worker.currentDevice }
    var currentPosition: AVCaptureDevice.Position { worker.currentPosition }
    var isConfigured: Bool { worker.isConfigured }
    var currentSessionPreset: AVCaptureSession.Preset { worker.currentSessionPreset }
    var supportedSessionPresets: [AVCaptureSession.Preset] { worker.supportedSessionPresets }

    init(permissionManager: AGPermissionManager, log: AGCameraLog) {
        self.permissionManager = permissionManager
        self.worker = CameraSessionWorker(log: log)
    }

    deinit {
        worker.stopSession { _ in }
    }

    func setupSession(
        for position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset = .photo,
        prepareLivePhoto: Bool = false
    ) async throws {
        guard permissionManager.isCameraAuthorized else {
            throw CameraError.permissionDenied
        }

        try await worker.setupSession(
            for: position,
            preset: preset,
            prepareLivePhoto: prepareLivePhoto
        )
    }

    func configureLivePhotoCapture(enabled: Bool, keepAudioInput: Bool) async throws -> AGLivePhotoState {
        try await worker.configureLivePhotoCapture(enabled: enabled, keepAudioInput: keepAudioInput)
    }

    func prepareVideoRecording(
        videoOutput: AVCaptureVideoDataOutput,
        audioOutput: AVCaptureAudioDataOutput,
        mirrorFrontCamera: Bool
    ) async throws {
        try await worker.prepareVideoRecording(
            videoOutput: videoOutput,
            audioOutput: audioOutput,
            mirrorFrontCamera: mirrorFrontCamera
        )
    }

    func configureVideoMirroring(for position: AVCaptureDevice.Position, mirrorFrontCamera: Bool) {
        worker.configureVideoMirroring(for: position, mirrorFrontCamera: mirrorFrontCamera)
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

    func applyVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) async {
        await worker.applyVideoStabilizationMode(mode)
    }

    func setSessionPreset(_ preset: AVCaptureSession.Preset) async throws {
        try await worker.setSessionPreset(preset)
    }

    func addVideoDataOutput(_ output: AVCaptureVideoDataOutput) async throws {
        try await worker.addVideoDataOutput(output)
    }

    func setFrameRate(fps: Int32) async throws {
        guard fps > 0 else { throw CameraError.invalidConfiguration }
        try await performDeviceOperation { device, _ in
            guard !device.isAutoVideoFrameRateEnabled,
                  device.activeFormat.videoSupportedFrameRateRanges.contains(where: { range in
                      range.minFrameRate <= Double(fps) && Double(fps) <= range.maxFrameRate
                  }) else {
                throw CameraError.invalidConfiguration
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let duration = CMTime(value: 1, timescale: fps)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    func performDeviceOperation<Value: Sendable>(
        _ operation: @escaping @Sendable (AVCaptureDevice, AVCaptureDevice.Position) throws -> Value
    ) async throws -> Value {
        try await worker.performDeviceOperation(operation)
    }

    func switchCamera(
        to newPosition: AVCaptureDevice.Position,
        zoomFactor: CGFloat,
        maximumZoomFactor: CGFloat,
        focusMode: AVCaptureDevice.FocusMode,
        exposureMode: AVCaptureDevice.ExposureMode,
        mirrorFrontCamera: Bool
    ) async throws -> AGZoomState {
        guard !isSwitchingCamera else { throw CameraError.cameraSwitchInProgress }
        isSwitchingCamera = true
        defer { isSwitchingCamera = false }
        return try await worker.switchCamera(
            to: newPosition,
            zoomFactor: zoomFactor,
            maximumZoomFactor: maximumZoomFactor,
            focusMode: focusMode,
            exposureMode: exposureMode,
            mirrorFrontCamera: mirrorFrontCamera
        )
    }
}

// The serial queue owns every mutation of the capture session graph and stored references.
// Remove @unchecked Sendable when AVFoundation provides a Sendable session abstraction.
private final class CameraSessionWorker: @unchecked Sendable {
    private let log: AGCameraLog

    let captureSession = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.agcamera.sessionQueue")

    private var storedVideoDeviceInput: AVCaptureDeviceInput?
    private var storedAudioDeviceInput: AVCaptureDeviceInput?
    private var storedPhotoOutput: AVCapturePhotoOutput?
    private var storedRecordingVideoOutput: AVCaptureVideoDataOutput?
    private var storedRecordingAudioOutput: AVCaptureAudioDataOutput?
    private var storedCurrentDevice: AVCaptureDevice?
    private var storedCurrentPosition: AVCaptureDevice.Position = .back
    private var storedIsConfigured = false

    init(log: AGCameraLog) {
        self.log = log
    }

    var videoDeviceInput: AVCaptureDeviceInput? { queue.sync { storedVideoDeviceInput } }
    var audioDeviceInput: AVCaptureDeviceInput? { queue.sync { storedAudioDeviceInput } }
    var photoOutput: AVCapturePhotoOutput? { queue.sync { storedPhotoOutput } }
    var livePhotoState: AGLivePhotoState { queue.sync { livePhotoStateOnQueue() } }
    var currentDevice: AVCaptureDevice? { queue.sync { storedCurrentDevice } }
    var currentPosition: AVCaptureDevice.Position { queue.sync { storedCurrentPosition } }
    var isConfigured: Bool { queue.sync { storedIsConfigured } }
    var currentSessionPreset: AVCaptureSession.Preset { queue.sync { captureSession.sessionPreset } }
    var supportedSessionPresets: [AVCaptureSession.Preset] {
        queue.sync {
            let presets: [AVCaptureSession.Preset] = [
                .photo, .high, .medium, .low, .hd1280x720, .hd1920x1080,
                .hd4K3840x2160, .iFrame960x540, .iFrame1280x720,
                .vga640x480, .cif352x288
            ]
            return presets.filter { captureSession.canSetSessionPreset($0) }
        }
    }

    func setupSession(
        for position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset,
        prepareLivePhoto: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let startedAt = ProcessInfo.processInfo.systemUptime
                defer {
                    self.log.timing(
                        "Session configuration",
                        elapsed: ProcessInfo.processInfo.systemUptime - startedAt,
                        category: "SessionWorker"
                    )
                }
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
                    if prepareLivePhoto {
                        try self.setupAudioInput()
                    }
                    try self.setupPhotoOutput()
                    if prepareLivePhoto, let output = self.storedPhotoOutput,
                       output.isLivePhotoCaptureSupported {
                        output.isLivePhotoCaptureEnabled = true
                    } else if prepareLivePhoto, let input = self.storedAudioDeviceInput {
                        self.captureSession.removeInput(input)
                        self.storedAudioDeviceInput = nil
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

    func prepareVideoRecording(
        videoOutput: AVCaptureVideoDataOutput,
        audioOutput: AVCaptureAudioDataOutput,
        mirrorFrontCamera: Bool
    ) async throws {
        let outputs = QueuedRecordingOutputs(video: videoOutput, audio: audioOutput)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.storedIsConfigured else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }
                guard self.storedAudioDeviceInput == nil || self.storedRecordingVideoOutput == nil || self.storedRecordingAudioOutput == nil else {
                    if self.storedRecordingVideoOutput?.connection(with: .video) != nil,
                       self.storedRecordingAudioOutput?.connection(with: .audio) != nil {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: CameraError.recordingFailed)
                    }
                    return
                }

                let hadAudioInput = self.storedAudioDeviceInput != nil
                let hadVideoOutput = self.storedRecordingVideoOutput != nil
                let hadAudioOutput = self.storedRecordingAudioOutput != nil
                self.captureSession.beginConfiguration()
                do {
                    try self.setupAudioInput()
                    try self.setupRecordingVideoOutput(outputs.video)
                    try self.setupRecordingAudioOutput(outputs.audio)
                    self.captureSession.commitConfiguration()
                    guard self.storedRecordingVideoOutput?.connection(with: .video) != nil,
                          self.storedRecordingAudioOutput?.connection(with: .audio) != nil else {
                        self.captureSession.beginConfiguration()
                        if !hadAudioInput, let input = self.storedAudioDeviceInput {
                            self.captureSession.removeInput(input)
                            self.storedAudioDeviceInput = nil
                        }
                        if !hadVideoOutput, let output = self.storedRecordingVideoOutput {
                            self.captureSession.removeOutput(output)
                            self.storedRecordingVideoOutput = nil
                        }
                        if !hadAudioOutput, let output = self.storedRecordingAudioOutput {
                            self.captureSession.removeOutput(output)
                            self.storedRecordingAudioOutput = nil
                        }
                        self.captureSession.commitConfiguration()
                        continuation.resume(throwing: CameraError.recordingFailed)
                        return
                    }
                    self.configureVideoMirroringOnQueue(
                        for: self.storedCurrentPosition,
                        mirrorFrontCamera: mirrorFrontCamera
                    )
                    continuation.resume()
                } catch {
                    if !hadAudioInput, let input = self.storedAudioDeviceInput {
                        self.captureSession.removeInput(input)
                        self.storedAudioDeviceInput = nil
                    }
                    if !hadVideoOutput, let output = self.storedRecordingVideoOutput {
                        self.captureSession.removeOutput(output)
                        self.storedRecordingVideoOutput = nil
                    }
                    if !hadAudioOutput, let output = self.storedRecordingAudioOutput {
                        self.captureSession.removeOutput(output)
                        self.storedRecordingAudioOutput = nil
                    }
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func configureLivePhotoCapture(enabled: Bool, keepAudioInput: Bool) async throws -> AGLivePhotoState {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AGLivePhotoState, Error>) in
            queue.async {
                guard self.storedIsConfigured, let output = self.storedPhotoOutput else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }
                self.captureSession.beginConfiguration()
                let hadAudioInput = self.storedAudioDeviceInput != nil
                do {
                    if enabled {
                        try self.setupAudioInput()
                        if output.isLivePhotoCaptureSupported {
                            output.isLivePhotoCaptureEnabled = true
                            output.isLivePhotoCaptureSuspended = false
                        } else if !keepAudioInput,
                                  let input = self.storedAudioDeviceInput {
                            self.captureSession.removeInput(input)
                            self.storedAudioDeviceInput = nil
                        }
                    } else {
                        if output.isLivePhotoCaptureEnabled {
                            output.isLivePhotoCaptureSuspended = true
                        }
                        if !keepAudioInput, let input = self.storedAudioDeviceInput {
                            self.captureSession.removeInput(input)
                            self.storedAudioDeviceInput = nil
                        }
                    }
                    self.captureSession.commitConfiguration()
                    continuation.resume(returning: self.livePhotoStateOnQueue())
                } catch {
                    if !hadAudioInput, !keepAudioInput,
                       let input = self.storedAudioDeviceInput {
                        self.captureSession.removeInput(input)
                        self.storedAudioDeviceInput = nil
                    }
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func livePhotoStateOnQueue() -> AGLivePhotoState {
        guard let output = storedPhotoOutput else {
            return AGLivePhotoState(isSupported: false, isEnabled: false)
        }
        return AGLivePhotoState(
            isSupported: output.isLivePhotoCaptureSupported,
            isEnabled: output.isLivePhotoCaptureEnabled
                && !output.isLivePhotoCaptureSuspended
                && storedAudioDeviceInput != nil
        )
    }

    func startSession(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            if self.storedIsConfigured && !self.captureSession.isRunning {
                let startedAt = ProcessInfo.processInfo.systemUptime
                self.captureSession.startRunning()
                self.log.timing(
                    "Session startRunning",
                    elapsed: ProcessInfo.processInfo.systemUptime - startedAt,
                    category: "SessionWorker"
                )
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
        queue.sync {
            self.storedPhotoOutput?.maxPhotoQualityPrioritization = prioritization
        }
    }

    func applyVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let connection = self.storedRecordingVideoOutput?.connection(with: .video),
                   connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = mode
                }
                continuation.resume()
            }
        }
    }

    func configureVideoMirroring(for position: AVCaptureDevice.Position, mirrorFrontCamera: Bool) {
        queue.sync {
            configureVideoMirroringOnQueue(for: position, mirrorFrontCamera: mirrorFrontCamera)
        }
    }

    func setSessionPreset(_ preset: AVCaptureSession.Preset) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.captureSession.canSetSessionPreset(preset) else {
                    continuation.resume(throwing: CameraError.invalidConfiguration)
                    return
                }
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = preset
                self.captureSession.commitConfiguration()
                continuation.resume()
            }
        }
    }

    func addVideoDataOutput(_ output: AVCaptureVideoDataOutput) async throws {
        let queuedOutput = QueuedVideoDataOutput(value: output)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let output = queuedOutput.value
                guard self.storedIsConfigured else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }
                guard !self.captureSession.outputs.contains(where: { $0 === output }) else {
                    continuation.resume()
                    return
                }

                self.captureSession.beginConfiguration()
                guard self.captureSession.canAddOutput(output) else {
                    self.captureSession.commitConfiguration()
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }
                self.captureSession.addOutput(output)
                self.captureSession.commitConfiguration()
                continuation.resume()
            }
        }
    }

    func performDeviceOperation<Value: Sendable>(
        _ operation: @escaping @Sendable (AVCaptureDevice, AVCaptureDevice.Position) throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            queue.async {
                guard let device = self.storedCurrentDevice else {
                    continuation.resume(throwing: CameraError.cameraNotAvailable)
                    return
                }
                do {
                    continuation.resume(returning: try operation(device, self.storedCurrentPosition))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func switchCamera(
        to newPosition: AVCaptureDevice.Position,
        zoomFactor: CGFloat,
        maximumZoomFactor: CGFloat,
        focusMode: AVCaptureDevice.FocusMode,
        exposureMode: AVCaptureDevice.ExposureMode,
        mirrorFrontCamera: Bool
    ) async throws -> AGZoomState {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AGZoomState, Error>) in
            queue.async {
                let startedAt = ProcessInfo.processInfo.systemUptime
                defer {
                    self.log.timing(
                        "Camera switch",
                        elapsed: ProcessInfo.processInfo.systemUptime - startedAt,
                        category: "SessionWorker"
                    )
                }
                guard self.storedIsConfigured else {
                    continuation.resume(throwing: CameraError.setupFailed)
                    return
                }

                do {
                    guard let camera = self.getCamera(for: newPosition) else {
                        throw CameraError.cameraNotAvailable
                    }
                    guard zoomFactor.isFinite, zoomFactor > 0,
                          maximumZoomFactor.isFinite, maximumZoomFactor > 0,
                          camera.isFocusModeSupported(focusMode),
                          camera.isExposureModeSupported(exposureMode) else {
                        throw CameraError.invalidConfiguration
                    }
                    let replacement = try AVCaptureDeviceInput(device: camera)

                    self.captureSession.beginConfiguration()
                    do {
                        try self.replaceVideoInput(with: replacement)
                    } catch {
                        self.captureSession.commitConfiguration()
                        throw error
                    }
                    self.storedCurrentPosition = newPosition
                    self.captureSession.commitConfiguration()
                    let zoomState: AGZoomState
                    do {
                        zoomState = try self.configureDevice(
                            factor: zoomFactor,
                            maximumZoomFactor: maximumZoomFactor,
                            focusMode: focusMode,
                            exposureMode: exposureMode,
                            on: camera
                        )
                    } catch {
                        self.log.warning(
                            "Camera switched, but device settings could not be applied: \(error.localizedDescription)",
                            category: "SessionWorker"
                        )
                        let currentState = self.zoomState(for: camera, maximumZoomFactor: maximumZoomFactor)
                        zoomState = AGZoomState(
                            factor: currentState.factor,
                            minimum: currentState.minimum,
                            maximum: currentState.maximum,
                            didApplyDeviceSettings: false
                        )
                    }
                    self.configureVideoMirroringOnQueue(
                        for: newPosition,
                        mirrorFrontCamera: mirrorFrontCamera
                    )
                    continuation.resume(returning: zoomState)
                } catch {
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
        try replaceVideoInput(with: replacement)
    }

    private func replaceVideoInput(with replacement: AVCaptureDeviceInput) throws {
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
        storedCurrentDevice = replacement.device
    }

    private func configureDevice(
        factor: CGFloat,
        maximumZoomFactor: CGFloat,
        focusMode: AVCaptureDevice.FocusMode,
        exposureMode: AVCaptureDevice.ExposureMode,
        on device: AVCaptureDevice
    ) throws -> AGZoomState {
        let multiplier = device.displayVideoZoomFactorMultiplier
        guard factor.isFinite, factor > 0,
              maximumZoomFactor.isFinite, maximumZoomFactor > 0,
              multiplier.isFinite, multiplier > 0,
              device.isFocusModeSupported(focusMode),
              device.isExposureModeSupported(exposureMode) else {
            throw CameraError.invalidConfiguration
        }

        let limits = zoomState(for: device, maximumZoomFactor: maximumZoomFactor)
        let appliedZoom = min(max(factor, limits.minimum), limits.maximum)

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.videoZoomFactor = appliedZoom / multiplier
        device.focusMode = focusMode
        device.exposureMode = exposureMode
        return AGZoomState(
            factor: device.videoZoomFactor * multiplier,
            minimum: limits.minimum,
            maximum: limits.maximum,
            didApplyDeviceSettings: true
        )
    }

    private func zoomState(for device: AVCaptureDevice, maximumZoomFactor: CGFloat) -> AGZoomState {
        let displayMultiplier = device.displayVideoZoomFactorMultiplier
        let multiplier = displayMultiplier.isFinite && displayMultiplier > 0 ? displayMultiplier : 1
        let minimum = device.minAvailableVideoZoomFactor * multiplier
        let maximum = max(minimum, min(maximumZoomFactor, device.maxAvailableVideoZoomFactor * multiplier))
        return AGZoomState(
            factor: device.videoZoomFactor * multiplier,
            minimum: minimum,
            maximum: maximum,
            didApplyDeviceSettings: true
        )
    }

    private func configureVideoMirroringOnQueue(
        for position: AVCaptureDevice.Position,
        mirrorFrontCamera: Bool
    ) {
        let shouldMirror = position == .front && mirrorFrontCamera
        if let connection = storedRecordingVideoOutput?.connection(with: .video),
           let device = storedCurrentDevice {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            let rightAngle = ((angle / 90).rounded() * 90).truncatingRemainder(dividingBy: 360)
            let rotation = rightAngle < 0 ? rightAngle + 360 : rightAngle
            if connection.isVideoRotationAngleSupported(rotation) {
                connection.videoRotationAngle = rotation
                log.info("Recording rotation: \(rotation) degrees for \(position.rawValue)", category: "SessionWorker")
            } else {
                log.warning("Recording rotation is unsupported: \(rotation) degrees", category: "SessionWorker")
            }
        }
        let outputs: [AVCaptureOutput?] = [storedPhotoOutput, storedRecordingVideoOutput]
        for output in outputs.compactMap({ $0 }) {
            guard let connection = output.connection(with: .video),
                  connection.isVideoMirroringSupported else { continue }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = shouldMirror
        }
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

    private func setupRecordingVideoOutput(_ output: AVCaptureVideoDataOutput) throws {
        guard storedRecordingVideoOutput == nil else { return }
        guard captureSession.canAddOutput(output) else {
            throw CameraError.setupFailed
        }
        captureSession.addOutput(output)
        storedRecordingVideoOutput = output
    }

    private func setupRecordingAudioOutput(_ output: AVCaptureAudioDataOutput) throws {
        guard storedRecordingAudioOutput == nil else { return }
        guard captureSession.canAddOutput(output) else {
            throw CameraError.setupFailed
        }
        captureSession.addOutput(output)
        storedRecordingAudioOutput = output
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
        if let output = storedRecordingVideoOutput { captureSession.removeOutput(output) }
        if let output = storedRecordingAudioOutput { captureSession.removeOutput(output) }
        if let input = storedAudioDeviceInput { captureSession.removeInput(input) }
        if let input = storedVideoDeviceInput { captureSession.removeInput(input) }
        storedPhotoOutput = nil
        storedRecordingVideoOutput = nil
        storedRecordingAudioOutput = nil
        storedAudioDeviceInput = nil
        storedVideoDeviceInput = nil
        storedCurrentDevice = nil
        storedIsConfigured = false
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
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
