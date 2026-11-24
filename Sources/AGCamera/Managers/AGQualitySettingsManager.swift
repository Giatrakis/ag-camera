//
//  AGQualitySettingsManager.swift
//  ag-camera
//

import AVFoundation

@MainActor
class AGQualitySettingsManager {

    private let sessionManager: AGSessionManager
    private var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode?

    var currentSessionPreset: AVCaptureSession.Preset {
        sessionManager.currentSessionPreset
    }

    var supportedSessionPresets: [AVCaptureSession.Preset] {
        sessionManager.supportedSessionPresets
    }

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
    }

    func setSessionPreset(_ preset: AVCaptureSession.Preset) async throws {
        try await sessionManager.setSessionPreset(preset)
    }

    func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        sessionManager.setPhotoQualityPrioritization(prioritization)
    }

    func setVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) async {
        preferredVideoStabilizationMode = mode
        await applyVideoStabilizationMode()
    }

    func applyVideoStabilizationMode() async {
        guard let mode = preferredVideoStabilizationMode else { return }
        await sessionManager.applyVideoStabilizationMode(mode)
    }

    func setFrameRate(fps: Int32) async throws {
        try await sessionManager.setFrameRate(fps: fps)
    }
}
