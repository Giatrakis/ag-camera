//
//  AGCaptureManager.swift
//  ag-camera
//

import AVFoundation

@MainActor
class AGCaptureManager: NSObject {

    private let sessionManager: AGSessionManager
    private let log: AGCameraLog
    private var photoCaptureCompletion: ((Result<Data, Error>) -> Void)?
    private var photoProcessingResult: Result<Data, Error>?
    private var photoCaptureTask: Task<Data, Error>?
    private var videoRecordingStartCompletion: ((Result<URL, Error>) -> Void)?
    private var videoRecordingStartTask: Task<URL, Error>?
    private var videoRecordingStopCompletion: ((Result<URL, Error>) -> Void)?
    private var videoRecordingStopTask: Task<URL, Error>?

    var flashMode: AVCaptureDevice.FlashMode = .off
    var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization = .quality
    var videoCodec: AVVideoCodecType?

    private(set) var isRecording = false
    private(set) var recordingDuration: TimeInterval = 0.0

    private var recordingTimerTask: Task<Void, Never>?
    private var recordingStartTime: Date?

    var onRecordingStateChanged: ((Bool, TimeInterval) -> Void)?

    init(sessionManager: AGSessionManager, log: AGCameraLog) {
        self.sessionManager = sessionManager
        self.log = log
        super.init()
    }

    func capturePhoto() async throws -> Data {
        guard let photoOutput = sessionManager.photoOutput else {
            throw CameraError.captureFailed
        }

        // If capture already in progress, return the existing task result
        if let existingTask = photoCaptureTask {
            return try await existingTask.value
        }

        let task = Task<Data, Error> {
            try await withCheckedThrowingContinuation { continuation in
                self.photoCaptureCompletion = { result in
                    continuation.resume(with: result)
                }
                self.photoProcessingResult = nil

                let photoSettings = AVCapturePhotoSettings()
                photoSettings.photoQualityPrioritization = photoQualityPrioritization

                if photoOutput.supportedFlashModes.contains(flashMode) {
                    photoSettings.flashMode = flashMode
                }

                photoOutput.capturePhoto(with: photoSettings, delegate: self)
            }
        }

        photoCaptureTask = task

        do {
            let result = try await task.value
            photoCaptureTask = nil
            return result
        } catch {
            photoCaptureTask = nil
            throw error
        }
    }

    func startVideoRecording() async throws -> URL {
        guard let movieFileOutput = sessionManager.movieFileOutput else {
            throw CameraError.recordingFailed
        }

        guard movieFileOutput.connection(with: .audio) != nil else {
            throw CameraError.recordingFailed
        }

        guard !movieFileOutput.isRecording else {
            throw CameraError.recordingFailed
        }

        // If start already in progress, return the existing task result
        if let existingTask = videoRecordingStartTask {
            return try await existingTask.value
        }

        guard let videoConnection = movieFileOutput.connection(with: .video) else {
            throw CameraError.recordingFailed
        }

        if let videoCodec {
            guard movieFileOutput.supportedOutputSettingsKeys(for: videoConnection).contains(AVVideoCodecKey),
                  movieFileOutput.availableVideoCodecTypes.contains(videoCodec) else {
                throw CameraError.invalidConfiguration
            }
            movieFileOutput.setOutputSettings([AVVideoCodecKey: videoCodec], for: videoConnection)
        } else {
            movieFileOutput.setOutputSettings(nil, for: videoConnection)
        }

        let task = Task<URL, Error> {
            return try await withCheckedThrowingContinuation { continuation in
                self.videoRecordingStartCompletion = { result in
                    continuation.resume(with: result)
                }

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")

                movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
            }
        }

        videoRecordingStartTask = task

        do {
            let result = try await task.value
            videoRecordingStartTask = nil
            return result
        } catch {
            videoRecordingStartTask = nil
            throw error
        }
    }

    func stopVideoRecording() async throws -> URL {
        guard let movieFileOutput = sessionManager.movieFileOutput else {
            throw CameraError.recordingFailed
        }

        guard movieFileOutput.isRecording else {
            throw CameraError.recordingFailed
        }

        // If stop already in progress, return the existing task result
        if let existingTask = videoRecordingStopTask {
            return try await existingTask.value
        }

        let task = Task<URL, Error> {
            try await withCheckedThrowingContinuation { continuation in
                self.videoRecordingStopCompletion = { result in
                    continuation.resume(with: result)
                }

                movieFileOutput.stopRecording()
            }
        }

        videoRecordingStopTask = task

        do {
            let result = try await task.value
            videoRecordingStopTask = nil
            return result
        } catch {
            videoRecordingStopTask = nil
            throw error
        }
    }

    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
        onRecordingStateChanged?(isRecording, recordingDuration)
    }

    private func startRecordingDurationTracking() {
        recordingTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { break }
                updateRecordingDuration()
            }
        }
    }

    static func resolvedPhotoResult(
        processingResult: Result<Data, Error>?,
        captureError: Error?
    ) -> Result<Data, Error> {
        if let captureError { return .failure(captureError) }
        return processingResult ?? .failure(CameraError.captureFailed)
    }
}

extension AGCaptureManager: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let imageData = photo.fileDataRepresentation()
        DispatchQueue.main.async {
            if let error {
                self.photoProcessingResult = .failure(error)
            } else if let imageData {
                self.photoProcessingResult = .success(imageData)
            } else {
                self.photoProcessingResult = .failure(CameraError.captureFailed)
            }
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        DispatchQueue.main.async {
            guard let completion = self.photoCaptureCompletion else { return }
            self.photoCaptureCompletion = nil
            let result = Self.resolvedPhotoResult(
                processingResult: self.photoProcessingResult,
                captureError: error
            )
            self.photoProcessingResult = nil
            completion(result)
        }
    }
}

extension AGCaptureManager: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.isRecording = true
            self.onRecordingStateChanged?(true, 0.0)
            self.recordingStartTime = Date()
            self.recordingDuration = 0.0

            self.startRecordingDurationTracking()

            self.log.info("Recording started at: \(fileURL)", category: "CaptureManager")

            self.videoRecordingStartCompletion?(.success(fileURL))
            self.videoRecordingStartCompletion = nil
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.recordingTimerTask?.cancel()
            self.recordingTimerTask = nil
            self.recordingStartTime = nil

            let finalDuration = self.recordingDuration
            self.isRecording = false
            self.recordingDuration = 0.0
            self.onRecordingStateChanged?(false, 0.0)

            self.log.info("Recording stopped. Duration was: \(String(format: "%.1f", finalDuration))s", category: "CaptureManager")

            if self.videoRecordingStartCompletion != nil {
                self.videoRecordingStartCompletion?(.failure(error ?? CameraError.recordingFailed))
                self.videoRecordingStartCompletion = nil
            }

            if let error = error {
                self.videoRecordingStopCompletion?(.failure(error))
            } else {
                self.videoRecordingStopCompletion?(.success(outputFileURL))
            }
            self.videoRecordingStopCompletion = nil
        }
    }
}
