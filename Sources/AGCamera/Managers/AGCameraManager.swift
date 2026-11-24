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

    public internal(set) var currentCameraPosition: AVCaptureDevice.Position = .back
    public private(set) var flashMode: AVCaptureDevice.FlashMode = .off
    public private(set) var isSessionRunning = false
    public private(set) var error: CameraError?
    public private(set) var isRecording = false
    public private(set) var recordingDuration: TimeInterval = 0.0
    public private(set) var currentZoomFactor: CGFloat = 1.0
    public private(set) var lastZoomFactor: CGFloat = 1.0
    public private(set) var isTorchOn = false
    public private(set) var isSwitchingCamera = false
    public var outputType: AGOutputType = .photo

    // Observable state for reactive UI
    public var capturedImage: UIImage?
    public var lastVideoURL: URL?
    public private(set) var lastStartedVideoURL: URL?
    public private(set) var lastStoppedVideoURL: URL?
    public var lastCapturedPhotoData: Data?

    // Camera switch animation state
    public var isBlurred: Bool = false
    public var flipRotation: Double = 0
    public var transitionSnapshot: UIImage?

    // Callback handlers for events
    public var onPhotoCapture: ((UIImage) -> Void)?
    public var onVideoStarted: ((URL) -> Void)?
    public var onVideoStopped: ((URL) -> Void)?
    public var onCameraPositionChanged: ((AVCaptureDevice.Position) -> Void)?
    public var onZoomChanged: ((CGFloat) -> Void)?
    public var onFlashModeChanged: ((AVCaptureDevice.FlashMode) -> Void)?
    public var onError: ((CameraError) -> Void)?

    public let sessionManager: AGSessionManager
    private let captureManager: AGCaptureManager
    private let deviceControl: AGDeviceControlManager
    private let focusExposure: AGFocusExposureManager
    private let zoomManager: AGZoomManager
    private let qualitySettings: AGQualitySettingsManager
    private let mediaLibrary: AGMediaLibraryManager
    private var sessionCommandID = 0

    public var configuration: AGCameraConfiguration
    public let permissionManager: AGPermissionManager

    public init(configuration suppliedConfiguration: AGCameraConfiguration? = nil) {
        let configuration = suppliedConfiguration ?? .default
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

    private func reportError(_ failure: Error, fallback: CameraError) {
        let cameraError = failure as? CameraError ?? fallback
        error = cameraError
        onError?(cameraError)
    }
}

// MARK: - Session Management

extension AGCameraManager {

    public func setupSession() async throws {
        guard !sessionManager.isConfigured else {
            Self.logger.info("Session already configured, skipping setup")
            return
        }

        if configuration.handlePermissions {
            guard permissionManager.isCameraAuthorized else {
                let error = CameraError.permissionDenied
                reportError(error, fallback: .permissionDenied)
                throw error
            }
        }

        do {
            currentCameraPosition = configuration.defaultCameraPosition
            try await sessionManager.setupSession(for: currentCameraPosition, preset: configuration.sessionPreset)
            deviceControl.configureVideoMirroring(for: currentCameraPosition)

            sessionManager.setPhotoQualityPrioritization(configuration.photoQualityPrioritization)

            let appliedZoom = (try? zoomManager.setZoom(factor: configuration.defaultZoomScale))
                ?? zoomManager.getCurrentZoomFactor()
            currentZoomFactor = appliedZoom
            lastZoomFactor = appliedZoom

            self.error = nil
        } catch {
            reportError(error, fallback: .setupFailed)
            throw error
        }
    }

    public func startSession() {
        sessionCommandID += 1
        let commandID = sessionCommandID
        sessionManager.startSession { [weak self] isRunning in
            Task { @MainActor [weak self] in
                guard let self, self.sessionCommandID == commandID else { return }
                self.isSessionRunning = isRunning
            }
        }
    }

    public func stopSession() {
        sessionCommandID += 1
        let commandID = sessionCommandID
        sessionManager.stopSession { [weak self] isRunning in
            Task { @MainActor [weak self] in
                guard let self, self.sessionCommandID == commandID else { return }
                self.isSessionRunning = isRunning
            }
        }
    }

    public func handleAppBackground() {
        stopSession()
    }

    public func handleAppForeground() {
        let hasPermission = configuration.handlePermissions ? permissionManager.isCameraAuthorized : true
        if hasPermission && sessionManager.isConfigured {
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
        guard !isSwitchingCamera else {
            Self.logger.warning("⚠️ Photo capture blocked - camera switch in progress")
            throw CameraError.cameraSwitchInProgress
        }

        let data: Data
        do {
            data = try await captureManager.capturePhoto()
        } catch {
            reportError(error, fallback: .captureFailed)
            throw error
        }

        // Set observable state for reactive UI
        if let image = UIImage(data: data) {
            capturedImage = image
            onPhotoCapture?(image)
        }
        lastCapturedPhotoData = data

        return data
    }
}

// MARK: - Video Recording

extension AGCameraManager {

    public func startVideoRecording() async throws -> URL {
        guard !isSwitchingCamera else {
            Self.logger.warning("⚠️ Video recording blocked - camera switch in progress")
            throw CameraError.cameraSwitchInProgress
        }

        let savedZoom = currentZoomFactor

        if await permissionManager.requestMicrophonePermission() {
            do {
                try await sessionManager.ensureAudioInput()
            } catch {
                Self.logger.warning("Recording without audio: \(error.localizedDescription)")
            }
        }

        try? qualitySettings.setFrameRate(fps: configuration.videoFrameRate)

        _ = try? zoomManager.setZoom(factor: savedZoom)
        currentZoomFactor = savedZoom

        let url: URL
        do {
            url = try await captureManager.startVideoRecording()
        } catch {
            reportError(error, fallback: .recordingFailed)
            throw error
        }
        lastVideoURL = url
        lastStartedVideoURL = url
        onVideoStarted?(url)
        return url
    }

    public func stopVideoRecording() async throws -> URL {
        let url: URL
        do {
            url = try await captureManager.stopVideoRecording()
        } catch {
            reportError(error, fallback: .recordingFailed)
            throw error
        }
        lastVideoURL = url
        lastStoppedVideoURL = url
        onVideoStopped?(url)
        return url
    }
}

// MARK: - Camera Controls

extension AGCameraManager {

    public func switchCamera(animated: Bool = true) async throws {
        guard !isSwitchingCamera else {
            Self.logger.warning("⚠️ Camera switch blocked - already in progress")
            return
        }

        isSwitchingCamera = true

        do {
            if animated {
                // Capture snapshot from current camera before switching
                if let photoData = try? await captureManager.capturePhoto(),
                   let image = UIImage(data: photoData) {
                    transitionSnapshot = image
                }

                let flipDirection: Double = currentCameraPosition == .back ? 180 : -180

                // Start blur animation
                withAnimation(.easeOut(duration: 0.1)) {
                    isBlurred = true
                }

                // Start flip animation
                withAnimation(.easeInOut(duration: 0.5)) {
                    flipRotation += flipDirection
                }

                // Wait for half the flip animation before switching
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            // Perform the actual camera switch
            let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back

            try await sessionManager.switchCamera(to: newPosition)
            deviceControl.configureVideoMirroring(for: newPosition)

            currentCameraPosition = newPosition
            onCameraPositionChanged?(newPosition)
            currentZoomFactor = configuration.defaultZoomScale
            lastZoomFactor = configuration.defaultZoomScale
            if let appliedZoom = try? zoomManager.setZoom(factor: configuration.defaultZoomScale) {
                currentZoomFactor = appliedZoom
                lastZoomFactor = appliedZoom
                onZoomChanged?(appliedZoom)
            }

            if animated {
                // Wait for flip to complete and preview to stabilize
                try await Task.sleep(nanoseconds: 100_000_000)

                // Remove snapshot and blur
                withAnimation(.easeIn(duration: 0.15)) {
                    transitionSnapshot = nil
                    isBlurred = false
                }
            }

            isSwitchingCamera = false
        } catch {
            transitionSnapshot = nil
            isBlurred = false
            isSwitchingCamera = false
            reportError(error, fallback: .setupFailed)
            throw error
        }
    }

    public func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        self.flashMode = mode
        captureManager.flashMode = mode
        onFlashModeChanged?(mode)
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
        onFlashModeChanged?(newMode)
    }

    public var isFlashAvailable: Bool {
        deviceControl.isFlashAvailable
    }

    public func setTorch(enabled: Bool) throws {
        try deviceControl.setTorch(enabled: enabled)
        isTorchOn = enabled
    }

    public func openTorch() throws {
        try deviceControl.setTorch(enabled: true)
        isTorchOn = true
    }

    public func closeTorch() throws {
        try deviceControl.setTorch(enabled: false)
        isTorchOn = false
    }

    public func toggleTorch() throws {
        if isTorchOn {
            try closeTorch()
        } else {
            try openTorch()
        }
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
        onZoomChanged?(currentZoomFactor)
    }

    public func updateZoomInteractively(scale: CGFloat, isGestureEnded: Bool) throws {
        let newZoom = lastZoomFactor * scale
        let maxZoom = maxZoomFactor
        let minZoom = minZoomFactor
        let clampedZoom = min(max(newZoom, minZoom), maxZoom)

        currentZoomFactor = try zoomManager.setZoom(factor: clampedZoom)
        onZoomChanged?(currentZoomFactor)

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

public enum CameraError: LocalizedError, Sendable {
    case permissionDenied
    case cameraNotAvailable
    case setupFailed
    case captureFailed
    case recordingFailed
    case invalidConfiguration
    case cameraSwitchInProgress

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
        case .cameraSwitchInProgress:
            return "Camera is currently switching. Please wait."
        }
    }
}
