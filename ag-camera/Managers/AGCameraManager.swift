//
//  AGCameraManager.swift
//  ag-camera
//

import AVFoundation
import SwiftUI
import Observation
import Photos
import OSLog

@Observable
@MainActor
public class AGCameraManager: NSObject {

    private static let logger = Logger(subsystem: "com.agcamera", category: "CameraManager")

    public private(set) var currentCameraPosition: AVCaptureDevice.Position = .back
    public private(set) var flashMode: AVCaptureDevice.FlashMode = .off
    public private(set) var isSessionRunning = false
    public private(set) var error: CameraError?
    public private(set) var isRecording = false
    public private(set) var recordingDuration: TimeInterval = 0.0
    public private(set) var currentZoomFactor: CGFloat = 1.0

    private let sessionManager: AGSessionManager
    private let captureManager: AGCaptureManager
    private let deviceControl: AGDeviceControlManager
    private let focusExposure: AGFocusExposureManager
    private let zoomManager: AGZoomManager
    private let qualitySettings: AGQualitySettingsManager
    private let mediaLibrary: AGMediaLibraryManager
    private let permissionManager: AGPermissionManager

    public init(permissionManager: AGPermissionManager) {
        self.permissionManager = permissionManager

        self.sessionManager = AGSessionManager(permissionManager: permissionManager)
        self.captureManager = AGCaptureManager(sessionManager: sessionManager)
        self.deviceControl = AGDeviceControlManager(sessionManager: sessionManager)
        self.focusExposure = AGFocusExposureManager(sessionManager: sessionManager)
        self.zoomManager = AGZoomManager(sessionManager: sessionManager)
        self.qualitySettings = AGQualitySettingsManager(sessionManager: sessionManager)
        self.mediaLibrary = AGMediaLibraryManager(permissionManager: permissionManager)

        super.init()

        captureManager.onRecordingStateChanged = { [weak self] isRecording, duration in
            guard let self = self else { return }
            Task { @MainActor in
                self.isRecording = isRecording
                self.recordingDuration = duration
            }
        }
    }
}

// MARK: - Session Management

extension AGCameraManager {

    public func setupSession() async throws {
        guard permissionManager.isCameraAuthorized else {
            let error = CameraError.permissionDenied
            self.error = error
            throw error
        }

        do {
            try await sessionManager.setupSession(for: currentCameraPosition)
            deviceControl.configureVideoMirroring(for: currentCameraPosition)
            currentZoomFactor = zoomManager.getCurrentZoomFactor()
            self.error = nil
        } catch {
            self.error = error as? CameraError ?? .setupFailed
            throw error
        }
    }

    public func startSession() {
        sessionManager.startSession()
        isSessionRunning = sessionManager.captureSession.isRunning
    }

    public func stopSession() {
        sessionManager.stopSession()
        isSessionRunning = false
    }

    public func handleAppBackground() {
        if isSessionRunning {
            stopSession()
        }
    }

    public func handleAppForeground() {
        if !isSessionRunning && permissionManager.isCameraAuthorized {
            startSession()
        }
    }

    public func getCaptureSession() -> AVCaptureSession {
        return sessionManager.captureSession
    }
}

// MARK: - Photo Capture

extension AGCameraManager {

    public func capturePhoto() async throws -> Data {
        return try await captureManager.capturePhoto()
    }
}

// MARK: - Video Recording

extension AGCameraManager {

    public func startVideoRecording() async throws -> URL {
        return try await captureManager.startVideoRecording()
    }

    public func stopVideoRecording() {
        captureManager.stopVideoRecording()
    }
}

// MARK: - Camera Controls

extension AGCameraManager {

    public func switchCamera() async throws {
        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back

        try await sessionManager.switchCamera(to: newPosition)
        deviceControl.configureVideoMirroring(for: newPosition)

        currentCameraPosition = newPosition
        currentZoomFactor = zoomManager.getCurrentZoomFactor()
    }

    public func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        self.flashMode = mode
        captureManager.flashMode = mode
    }

    public func toggleFlash() {
        let newMode: AVCaptureDevice.FlashMode
        switch flashMode {
        case .off:
            newMode = .on
        case .on:
            newMode = .auto
        case .auto:
            newMode = .off
        @unknown default:
            newMode = .off
        }

        self.flashMode = newMode
        captureManager.flashMode = newMode
    }

    public var isFlashAvailable: Bool {
        deviceControl.isFlashAvailable
    }

    public func setTorch(enabled: Bool) throws {
        try deviceControl.setTorch(enabled: enabled)
    }
}

// MARK: - Focus & Exposure

extension AGCameraManager {

    public func setFocus(at point: CGPoint) throws {
        try focusExposure.setFocus(at: point)
    }

    public func setExposure(at point: CGPoint) throws {
        try focusExposure.setExposure(at: point)
    }

    public func setFocusAndExposure(at point: CGPoint) throws {
        try focusExposure.setFocusAndExposure(at: point)
    }

    public func setFocusMode(_ mode: AVCaptureDevice.FocusMode) throws {
        try focusExposure.setFocusMode(mode)
    }

    public func setExposureMode(_ mode: AVCaptureDevice.ExposureMode) throws {
        try focusExposure.setExposureMode(mode)
    }

    public func lockExposureAndFocus() throws {
        try focusExposure.lockExposureAndFocus()
    }

    public func resetFocusAndExposure() throws {
        try focusExposure.resetFocusAndExposure()
    }
}

// MARK: - Zoom Controls

extension AGCameraManager {

    public func setZoom(factor: CGFloat) throws {
        currentZoomFactor = try zoomManager.setZoom(factor: factor)
    }

    public var maxZoomFactor: CGFloat {
        zoomManager.getMaxZoomFactor(for: currentCameraPosition)
    }

    public var minZoomFactor: CGFloat {
        zoomManager.getMinZoomFactor()
    }
}

// MARK: - Quality Settings

extension AGCameraManager {

    public func setSessionPreset(_ preset: AVCaptureSession.Preset) throws {
        try qualitySettings.setSessionPreset(preset)
    }

    public func setPhotoQualityPrioritization(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) {
        qualitySettings.setPhotoQualityPrioritization(prioritization)
    }

    public var currentSessionPreset: AVCaptureSession.Preset {
        qualitySettings.currentSessionPreset
    }

    public var supportedSessionPresets: [AVCaptureSession.Preset] {
        qualitySettings.supportedSessionPresets
    }

    public func setVideoStabilizationMode(_ mode: AVCaptureVideoStabilizationMode) {
        qualitySettings.setVideoStabilizationMode(mode)
    }

    public func setFrameRate(fps: Int32) throws {
        try qualitySettings.setFrameRate(fps: fps)
    }
}

// MARK: - Photo Library

extension AGCameraManager {

    public func savePhotoToLibrary(_ data: Data) async throws {
        try await mediaLibrary.savePhotoToLibrary(data)
    }

    public func saveVideoToLibrary(url: URL) async throws {
        try await mediaLibrary.saveVideoToLibrary(url: url)
    }
}

// MARK: - Camera Errors

public enum CameraError: LocalizedError {
    case permissionDenied
    case cameraNotAvailable
    case setupFailed
    case captureFailed
    case recordingFailed
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied. Please enable camera access in Settings."
        case .cameraNotAvailable:
            return "Camera is not available on this device."
        case .setupFailed:
            return "Failed to setup camera session."
        case .captureFailed:
            return "Failed to capture photo."
        case .recordingFailed:
            return "Failed to record video."
        case .invalidConfiguration:
            return "Invalid camera configuration."
        }
    }
}
