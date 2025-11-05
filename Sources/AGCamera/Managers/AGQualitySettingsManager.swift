//
//  AGQualitySettingsManager.swift
//  ag-camera
//

import AVFoundation

@MainActor
class AGQualitySettingsManager {

    private let sessionManager: AGSessionManager

    var currentSessionPreset: AVCaptureSession.Preset {
        return sessionManager.captureSession.sessionPreset
    }

    var supportedSessionPresets: [AVCaptureSession.Preset] {
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

        return allPresets.filter { sessionManager.captureSession.canSetSessionPreset($0) }
    }

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
    }

    func setSessionPreset(_ preset: AVCaptureSession.Preset) throws {
        guard sessionManager.captureSession.canSetSessionPreset(preset) else {
            throw CameraError.invalidConfiguration
        }

        sessionManager.sessionQueue.async { [weak sessionManager] in
            guard let sessionManager = sessionManager else { return }

            sessionManager.captureSession.beginConfiguration()
            sessionManager.captureSession.sessionPreset = preset
            sessionManager.captureSession.commitConfiguration()
        }
    }

    func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        guard let photoOutput = sessionManager.photoOutput else { return }
        photoOutput.maxPhotoQualityPrioritization = prioritization
    }

    func setVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) {
        guard let connection = sessionManager.movieFileOutput?.connection(with: .video) else { return }

        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = mode
        }
    }

    func setFrameRate(fps: Int32) throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

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
}
