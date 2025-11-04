//
//  AGPermissionManager.swift
//  ag-camera
//
//  Manages all camera-related permissions (camera, microphone, photo library)
//

import AVFoundation
import Photos
import SwiftUI
import Observation

/// Permission manager that handles camera, microphone, and photo library permissions
@Observable
@MainActor
public class AGPermissionManager {

    // MARK: - Published Properties

    /// Camera permission status (using Apple's native enum)
    public private(set) var cameraStatus: AVAuthorizationStatus = .notDetermined

    /// Microphone permission status (using Apple's native enum)
    public private(set) var microphoneStatus: AVAuthorizationStatus = .notDetermined

    /// Photo library permission status (using Apple's native enum)
    public private(set) var photoLibraryStatus: PHAuthorizationStatus = .notDetermined

    // MARK: - Initialization

    public init() {
        updateAllStatuses()
    }

    // MARK: - Public Methods

    /// Check and request camera permission
    public func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            self.cameraStatus = .authorized
            return true

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            self.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            return granted

        case .denied, .restricted:
            self.cameraStatus = status
            return false

        @unknown default:
            self.cameraStatus = status
            return false
        }
    }

    /// Check and request microphone permission
    public func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            self.microphoneStatus = .authorized
            return true

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            self.microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            return granted

        case .denied, .restricted:
            self.microphoneStatus = status
            return false

        @unknown default:
            self.microphoneStatus = status
            return false
        }
    }

    /// Check and request photo library permission
    public func requestPhotoLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            self.photoLibraryStatus = status
            return true

        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            self.photoLibraryStatus = newStatus
            return newStatus == .authorized || newStatus == .limited

        case .denied, .restricted:
            self.photoLibraryStatus = status
            return false

        @unknown default:
            self.photoLibraryStatus = status
            return false
        }
    }

    /// Request all permissions needed for full camera functionality
    public func requestAllPermissions() async -> AGPermissionsResult {
        async let cameraGranted = requestCameraPermission()
        async let microphoneGranted = requestMicrophonePermission()
        async let photoLibraryGranted = requestPhotoLibraryPermission()

        let results = await (cameraGranted, microphoneGranted, photoLibraryGranted)

        return AGPermissionsResult(
            camera: results.0,
            microphone: results.1,
            photoLibrary: results.2
        )
    }

    /// Check if camera permission is granted
    public var isCameraAuthorized: Bool {
        cameraStatus == .authorized
    }

    /// Check if microphone permission is granted
    public var isMicrophoneAuthorized: Bool {
        microphoneStatus == .authorized
    }

    /// Check if photo library permission is granted
    public var isPhotoLibraryAuthorized: Bool {
        photoLibraryStatus == .authorized || photoLibraryStatus == .limited
    }

    /// Check if all permissions are granted
    public var areAllPermissionsGranted: Bool {
        isCameraAuthorized && isMicrophoneAuthorized && isPhotoLibraryAuthorized
    }

    /// Update all permission statuses without requesting
    public func updateAllStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        photoLibraryStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    /// Open Settings app to allow user to change permissions
    public func openSettings() async {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(settingsURL)
        }
    }
}
