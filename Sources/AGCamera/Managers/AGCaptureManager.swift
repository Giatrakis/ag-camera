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
    private var videoRecordingStartCompletion: ((Result<URL, Error>) -> Void)?
    private var videoRecordingStopCompletion: ((Result<URL, Error>) -> Void)?

    var flashMode: AVCaptureDevice.FlashMode = .off

    private(set) var isRecording = false
    private(set) var recordingDuration: TimeInterval = 0.0

    private var recordingTimer: Timer?
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

        return try await withCheckedThrowingContinuation { continuation in
            self.photoCaptureCompletion = { result in
                continuation.resume(with: result)
            }

            let photoSettings = AVCapturePhotoSettings()

            if photoOutput.supportedFlashModes.contains(flashMode) {
                photoSettings.flashMode = flashMode
            }

            photoSettings.photoQualityPrioritization = .quality
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    func startVideoRecording() async throws -> URL {
        guard let movieFileOutput = sessionManager.movieFileOutput else {
            throw CameraError.recordingFailed
        }

        guard !movieFileOutput.isRecording else {
            throw CameraError.recordingFailed
        }

        isRecording = true
        onRecordingStateChanged?(true, 0.0)

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

    func stopVideoRecording() async throws -> URL {
        guard let movieFileOutput = sessionManager.movieFileOutput else {
            throw CameraError.recordingFailed
        }

        guard movieFileOutput.isRecording else {
            throw CameraError.recordingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.videoRecordingStopCompletion = { result in
                continuation.resume(with: result)
            }

            movieFileOutput.stopRecording()
        }
    }

    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
        onRecordingStateChanged?(isRecording, recordingDuration)
    }
}

extension AGCaptureManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(
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

extension AGCaptureManager: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.recordingStartTime = Date()
            self.recordingDuration = 0.0

            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateRecordingDuration()
            }

            Self.logger.info("Recording started at: \(fileURL)")

            // Notify that recording started successfully
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
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.recordingStartTime = nil

            let finalDuration = self.recordingDuration
            self.isRecording = false
            self.recordingDuration = 0.0
            self.onRecordingStateChanged?(false, 0.0)

            Self.logger.info("Recording stopped. Duration was: \(String(format: "%.1f", finalDuration))s")

            // Notify that recording stopped with final URL
            if let error = error {
                self.videoRecordingStopCompletion?(.failure(error))
            } else {
                self.videoRecordingStopCompletion?(.success(outputFileURL))
            }
            self.videoRecordingStopCompletion = nil
        }
    }
}
