//
//  AGCaptureManager.swift
//  ag-camera
//

import AVFoundation

@MainActor
class AGCaptureManager: NSObject {

    private let sessionManager: AGSessionManager
    private let log: AGCameraLog
    private let videoRecorder: AGVideoRecordingWriter
    private var photoCaptureCompletion: ((Result<AGPhotoCaptureResult, Error>) -> Void)?
    private var photoProcessingResult: Result<Data, Error>?
    private var livePhotoMovieResult: Result<URL, Error>?
    private var pendingLivePhotoURL: URL?
    private var photoCaptureTask: Task<AGPhotoCaptureResult, Error>?
    private var isLivePhotoCapture = false
    private var videoRecordingStartTask: Task<URL, Error>?
    private var videoRecordingStopTask: Task<URL, Error>?

    var flashMode: AVCaptureDevice.FlashMode = .off
    var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization = .quality
    var videoCodec: AVVideoCodecType?

    private(set) var isRecording = false
    private(set) var recordingDuration: TimeInterval = 0.0

    private var recordingTimerTask: Task<Void, Never>?
    private var recordingStartTime: Date?

    var onRecordingStateChanged: ((Bool, TimeInterval) -> Void)?
    var recordingVideoOutput: AVCaptureVideoDataOutput { videoRecorder.videoOutput }
    var recordingAudioOutput: AVCaptureAudioDataOutput { videoRecorder.audioOutput }
    var isCapturingPhoto: Bool { photoCaptureTask != nil }

    init(sessionManager: AGSessionManager, log: AGCameraLog) {
        self.sessionManager = sessionManager
        self.log = log
        self.videoRecorder = AGVideoRecordingWriter(log: log)
        super.init()
    }

    func capturePhoto() async throws -> Data {
        let result = try await capturePhoto(live: false)
        guard case .still(let data) = result else { throw CameraError.captureFailed }
        return data
    }

    func captureLivePhoto() async throws -> AGLivePhotoCapture {
        let result = try await capturePhoto(live: true)
        guard case .live(let capture) = result else { throw CameraError.captureFailed }
        return capture
    }

    private func capturePhoto(live: Bool) async throws -> AGPhotoCaptureResult {
        guard let photoOutput = sessionManager.photoOutput else {
            throw CameraError.captureFailed
        }

        if let existingTask = photoCaptureTask {
            guard isLivePhotoCapture == live else { throw CameraError.captureFailed }
            return try await existingTask.value
        }
        if live {
            guard sessionManager.livePhotoState.isEnabled else { throw CameraError.livePhotoUnavailable }
        }

        let task = Task<AGPhotoCaptureResult, Error> {
            try await withCheckedThrowingContinuation { continuation in
                self.photoCaptureCompletion = { result in
                    continuation.resume(with: result)
                }
                self.photoProcessingResult = nil
                self.livePhotoMovieResult = nil

                let photoSettings = AVCapturePhotoSettings()
                photoSettings.photoQualityPrioritization = photoQualityPrioritization
                if live {
                    let movieURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mov")
                    self.pendingLivePhotoURL = movieURL
                    photoSettings.livePhotoMovieFileURL = movieURL
                } else {
                    self.pendingLivePhotoURL = nil
                }

                if photoOutput.supportedFlashModes.contains(flashMode) {
                    photoSettings.flashMode = flashMode
                }

                photoOutput.capturePhoto(with: photoSettings, delegate: self)
            }
        }

        photoCaptureTask = task
        isLivePhotoCapture = live

        defer {
            photoCaptureTask = nil
            isLivePhotoCapture = false
        }
        return try await task.value
    }

    func startVideoRecording() async throws -> URL {
        if let existingTask = videoRecordingStartTask {
            return try await existingTask.value
        }
        guard !isRecording,
              recordingVideoOutput.connection(with: .video) != nil,
              recordingAudioOutput.connection(with: .audio) != nil else {
            throw CameraError.recordingFailed
        }
        let task = Task<URL, Error> {
            try await videoRecorder.start(codec: videoCodec)
        }

        videoRecordingStartTask = task

        do {
            let result = try await task.value
            videoRecordingStartTask = nil
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            onRecordingStateChanged?(true, 0)
            startRecordingDurationTracking()
            log.info("Recording started at: \(result)", category: "CaptureManager")
            return result
        } catch {
            videoRecordingStartTask = nil
            throw error
        }
    }

    func stopVideoRecording() async throws -> URL {
        if let existingTask = videoRecordingStopTask {
            return try await existingTask.value
        }
        guard isRecording else { throw CameraError.recordingFailed }
        let task = Task<URL, Error> { try await videoRecorder.stop() }

        videoRecordingStopTask = task

        do {
            let result = try await task.value
            videoRecordingStopTask = nil
            finishRecordingDurationTracking()
            log.info("Recording stopped at: \(result)", category: "CaptureManager")
            return result
        } catch {
            videoRecordingStopTask = nil
            finishRecordingDurationTracking()
            throw error
        }
    }

    func setRecordingVideoPaused(_ paused: Bool) async {
        await videoRecorder.setVideoPaused(paused)
    }

    private func finishRecordingDurationTracking() {
        recordingTimerTask?.cancel()
        recordingTimerTask = nil
        recordingStartTime = nil
        isRecording = false
        recordingDuration = 0
        onRecordingStateChanged?(false, 0)
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

    static func resolvedLivePhotoResult(
        photoResult: Result<Data, Error>,
        movieResult: Result<URL, Error>?
    ) -> Result<AGLivePhotoCapture, Error> {
        switch (photoResult, movieResult) {
        case (.success(let data), .some(.success(let movieURL))):
            return .success(AGLivePhotoCapture(photoData: data, pairedVideoURL: movieURL))
        case (.failure(let error), _):
            return .failure(error)
        case (_, .some(.failure(let error))):
            return .failure(error)
        default:
            return .failure(CameraError.captureFailed)
        }
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
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.livePhotoMovieResult = error.map { .failure($0) } ?? .success(outputFileURL)
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
            let photoResult = Self.resolvedPhotoResult(
                processingResult: self.photoProcessingResult,
                captureError: error
            )
            let result: Result<AGPhotoCaptureResult, Error>
            if self.isLivePhotoCapture {
                result = Self.resolvedLivePhotoResult(
                    photoResult: photoResult,
                    movieResult: self.livePhotoMovieResult
                ).map(AGPhotoCaptureResult.live)
            } else {
                result = photoResult.map(AGPhotoCaptureResult.still)
            }
            if case .failure = result, let movieURL = self.pendingLivePhotoURL {
                try? FileManager.default.removeItem(at: movieURL)
            }
            self.photoProcessingResult = nil
            self.livePhotoMovieResult = nil
            self.pendingLivePhotoURL = nil
            completion(result)
        }
    }
}
