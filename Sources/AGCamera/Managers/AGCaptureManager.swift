//
//  AGCaptureManager.swift
//  ag-camera
//

import AVFoundation
import OSLog

@MainActor
class AGCaptureManager: NSObject {

    private static let logger = Logger(subsystem: "com.agcamera", category: "CaptureManager")

    private let sessionManager: AGSessionManager
    private var photoCaptureCompletion: ((Result<Data, Error>) -> Void)?
    private var photoCaptureTask: Task<Data, Error>?
    private var videoRecordingStartCompletion: ((Result<URL, Error>) -> Void)?
    private var videoRecordingStartTask: Task<URL, Error>?
    private var videoRecordingStopCompletion: ((Result<URL, Error>) -> Void)?
    private var videoRecordingStopTask: Task<URL, Error>?

    var flashMode: AVCaptureDevice.FlashMode = .off

    private(set) var isRecording = false
    private(set) var recordingDuration: TimeInterval = 0.0

    private var recordingTimerTask: Task<Void, Never>?
    private var recordingStartTime: Date?

    var onRecordingStateChanged: ((Bool, TimeInterval) -> Void)?

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
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

                let photoSettings = AVCapturePhotoSettings()

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

        guard !movieFileOutput.isRecording else {
            throw CameraError.recordingFailed
        }

        // If start already in progress, return the existing task result
        if let existingTask = videoRecordingStartTask {
            return try await existingTask.value
        }

        let task = Task<URL, Error> {
            self.isRecording = true
            self.onRecordingStateChanged?(true, 0.0)

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
}

extension AGCaptureManager: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
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
}

extension AGCaptureManager: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.recordingStartTime = Date()
            self.recordingDuration = 0.0

            self.startRecordingDurationTracking()

            Self.logger.info("Recording started at: \(fileURL)")

            self.videoRecordingStartCompletion?(.success(fileURL))
            self.videoRecordingStartCompletion = nil
        }
    }

    func fileOutput(
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

            Self.logger.info("Recording stopped. Duration was: \(String(format: "%.1f", finalDuration))s")

            if let error = error {
                self.videoRecordingStopCompletion?(.failure(error))
            } else {
                self.videoRecordingStopCompletion?(.success(outputFileURL))
            }
            self.videoRecordingStopCompletion = nil
        }
    }
}
