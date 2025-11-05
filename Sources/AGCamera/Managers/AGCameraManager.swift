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
    public private(set) var lastZoomFactor: CGFloat = 1.0
    public var outputType: AGOutputType = .photo

    // Observable state for reactive UI
    public var capturedImage: UIImage?
    public var lastVideoURL: URL?
    public var lastCapturedPhotoData: Data?

    private let sessionManager: AGSessionManager
    private let captureManager: AGCaptureManager
    private let deviceControl: AGDeviceControlManager
    private let focusExposure: AGFocusExposureManager
    private let zoomManager: AGZoomManager
    private let qualitySettings: AGQualitySettingsManager
    private let mediaLibrary: AGMediaLibraryManager
    private let configuration: AGCameraConfiguration

    public let permissionManager: AGPermissionManager

    public init(configuration: AGCameraConfiguration = .default) {
        self.configuration = configuration
        self.permissionManager = AGPermissionManager()
        self.currentCameraPosition = configuration.defaultCameraPosition

        self.sessionManager = AGSessionManager(permissionManager: permissionManager)
        self.captureManager = AGCaptureManager(sessionManager: sessionManager)
        self.deviceControl = AGDeviceControlManager(sessionManager: sessionManager)
        self.focusExposure = AGFocusExposureManager(sessionManager: sessionManager)
        self.zoomManager = AGZoomManager(sessionManager: sessionManager)
        self.qualitySettings = AGQualitySettingsManager(sessionManager: sessionManager)
        self.mediaLibrary = AGMediaLibraryManager(permissionManager: permissionManager)

        super.init()

        // Apply default flash mode
        self.flashMode = configuration.defaultFlashMode
        self.captureManager.flashMode = configuration.defaultFlashMode

        captureManager.onRecordingStateChanged = { [weak self] isRecording, duration in
            guard let self = self else { return }
            Task { @MainActor in
                withAnimation {
                    self.isRecording = isRecording
                    self.recordingDuration = duration
                }
            }
        }
    }
}

// MARK: - Session Management

extension AGCameraManager {

    public func setupSession() async throws {
        if configuration.handlePermissions {
            guard permissionManager.isCameraAuthorized else {
                let error = CameraError.permissionDenied
                self.error = error
                throw error
            }
        }

        do {
            try await sessionManager.setupSession(for: currentCameraPosition)
            deviceControl.configureVideoMirroring(for: currentCameraPosition)
            currentZoomFactor = zoomManager.getCurrentZoomFactor()
            lastZoomFactor = currentZoomFactor
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
        let hasPermission = configuration.handlePermissions ? permissionManager.isCameraAuthorized : true
        if !isSessionRunning && hasPermission {
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
        let data = try await captureManager.capturePhoto()

        // Set observable state for reactive UI
        if let image = UIImage(data: data) {
            capturedImage = image
        }
        lastCapturedPhotoData = data

        return data
    }
}

// MARK: - Video Recording

extension AGCameraManager {

    public func startVideoRecording() async throws -> URL {
        let url = try await captureManager.startVideoRecording()
        lastVideoURL = url
        return url
    }

    public func stopVideoRecording() async throws -> URL {
        let url = try await captureManager.stopVideoRecording()
        lastVideoURL = url
        return url
    }
}

// MARK: - Camera Controls

extension AGCameraManager {

    public func switchCamera() async throws {
        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back

        try await sessionManager.switchCamera(to: newPosition)
        deviceControl.configureVideoMirroring(for: newPosition)

        currentCameraPosition = newPosition
        currentZoomFactor = 1.0
        lastZoomFactor = 1.0
        try? zoomManager.setZoom(factor: 1.0)
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

    public func setOutputType(_ type: AGOutputType) {
        outputType = type
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
        lastZoomFactor = currentZoomFactor
    }

    public func updateZoomInteractively(scale: CGFloat, isGestureEnded: Bool) throws {
        let newZoom = lastZoomFactor * scale
        let maxZoom = maxZoomFactor
        let minZoom = minZoomFactor
        let clampedZoom = min(max(newZoom, minZoom), maxZoom)

        currentZoomFactor = try zoomManager.setZoom(factor: clampedZoom)

        if isGestureEnded {
            lastZoomFactor = currentZoomFactor
        }
    }

    public var maxZoomFactor: CGFloat {
        zoomManager.getMaxZoomFactor(for: currentCameraPosition)
    }

    public var minZoomFactor: CGFloat {
        zoomManager.getMinZoomFactor()
    }

    public var availableZoomLevels: [CGFloat] {
        let minZoom = minZoomFactor
        let maxZoom = maxZoomFactor
        var levels: [CGFloat] = []

        if minZoom <= 0.5 && maxZoom >= 0.5 && currentCameraPosition == .back {
            levels.append(0.5)
        }

        levels.append(1.0)

        if maxZoom >= 2.0 {
            levels.append(2.0)
        }

        if maxZoom >= 3.0 {
            levels.append(3.0)
        }

        if maxZoom >= 5.0 {
            levels.append(5.0)
        }

        return levels
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

// MARK: - Presentation

extension AGCameraManager {

    public var flashIconName: String {
        switch flashMode {
        case .off:
            return "bolt.slash"
        case .on:
            return "bolt.fill"
        case .auto:
            return "bolt.badge.automatic"
        @unknown default:
            return "bolt.slash"
        }
    }

    public var formattedRecordingDuration: String {
        let totalSeconds = Int(recordingDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
