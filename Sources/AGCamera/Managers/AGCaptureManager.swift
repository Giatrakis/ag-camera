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
    private var photoCaptureCompletion: ((Result<Data, Error>) -> Void)?
    private var photoProcessingResult: Result<Data, Error>?
    private var photoCaptureTask: Task<Data, Error>?
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

    init(sessionManager: AGSessionManager, log: AGCameraLog) {
        self.sessionManager = sessionManager
        self.log = log
        self.videoRecorder = AGVideoRecordingWriter(log: log)
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
