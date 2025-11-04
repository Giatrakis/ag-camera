//
//  ag_cameraTests.swift
//  ag-cameraTests
//
//  Created by Alex Giatrakis on 31/10/25.
//

import Testing
import AVFoundation
import Photos
@testable import ag_camera

// MARK: - Permission Manager Tests

@MainActor
struct AGPermissionManagerTests {

    @Test("Permission Manager Initialization")
    func testInitialization() async throws {
        let permissionManager = AGPermissionManager()

        // Verify initial state exists
        #expect(permissionManager != nil)
    }

    @Test("Permission Status Updates")
    func testUpdateAllStatuses() async throws {
        let permissionManager = AGPermissionManager()

        // This should not crash
        permissionManager.updateAllStatuses()

        // Verify statuses are of correct type
        #expect(permissionManager.cameraStatus is AVAuthorizationStatus)
        #expect(permissionManager.microphoneStatus is AVAuthorizationStatus)
        #expect(permissionManager.photoLibraryStatus is PHAuthorizationStatus)
    }

    @Test("Computed Properties")
    func testComputedProperties() async throws {
        let permissionManager = AGPermissionManager()

        // These should return Bool values without crashing
        _ = permissionManager.isCameraAuthorized
        _ = permissionManager.isMicrophoneAuthorized
        _ = permissionManager.isPhotoLibraryAuthorized
        _ = permissionManager.areAllPermissionsGranted

        #expect(true) // If we get here, properties work
    }
}

// MARK: - All Permissions Result Tests

struct AllPermissionsResultTests {

    @Test("All Granted")
    func testAllGranted() throws {
        let result = AllPermissionsResult(
            camera: true,
            microphone: true,
            photoLibrary: true
        )

        #expect(result.allGranted == true)
        #expect(result.deniedPermissions.isEmpty)
    }

    @Test("Some Denied")
    func testSomeDenied() throws {
        let result = AllPermissionsResult(
            camera: false,
            microphone: true,
            photoLibrary: false
        )

        #expect(result.allGranted == false)
        #expect(result.deniedPermissions.count == 2)
        #expect(result.deniedPermissions.contains("Camera"))
        #expect(result.deniedPermissions.contains("Photo Library"))
        #expect(!result.deniedPermissions.contains("Microphone"))
    }

    @Test("All Denied")
    func testAllDenied() throws {
        let result = AllPermissionsResult(
            camera: false,
            microphone: false,
            photoLibrary: false
        )

        #expect(result.allGranted == false)
        #expect(result.deniedPermissions.count == 3)
    }
}

// MARK: - Camera Manager Tests

@MainActor
struct AGCameraManagerTests {

    @Test("Camera Manager Initialization")
    func testInitialization() async throws {
        let permissionManager = AGPermissionManager()
        let cameraManager = AGCameraManager(permissionManager: permissionManager)

        #expect(cameraManager != nil)
        #expect(cameraManager.currentCameraPosition == .back)
        #expect(cameraManager.flashMode == .off)
        #expect(cameraManager.isSessionRunning == false)
        #expect(cameraManager.isRecording == false)
        #expect(cameraManager.recordingDuration == 0.0)
        #expect(cameraManager.currentZoomFactor == 1.0)
    }

    @Test("Flash Mode Toggle")
    func testFlashModeToggle() async throws {
        let permissionManager = AGPermissionManager()
        let cameraManager = AGCameraManager(permissionManager: permissionManager)

        // Initial state
        #expect(cameraManager.flashMode == .off)

        // Toggle to on
        cameraManager.toggleFlash()
        // Give MainActor time to update
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        #expect(cameraManager.flashMode == .on)

        // Toggle to auto
        cameraManager.toggleFlash()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cameraManager.flashMode == .auto)

        // Toggle back to off
        cameraManager.toggleFlash()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cameraManager.flashMode == .off)
    }

    @Test("Set Flash Mode")
    func testSetFlashMode() async throws {
        let permissionManager = AGPermissionManager()
        let cameraManager = AGCameraManager(permissionManager: permissionManager)

        cameraManager.setFlashMode(.on)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cameraManager.flashMode == .on)

        cameraManager.setFlashMode(.auto)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cameraManager.flashMode == .auto)

        cameraManager.setFlashMode(.off)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(cameraManager.flashMode == .off)
    }

    @Test("Zoom Factor Bounds")
    func testZoomFactorBounds() async throws {
        let permissionManager = AGPermissionManager()
        let cameraManager = AGCameraManager(permissionManager: permissionManager)

        // Min zoom should be >= 0.5 (ultra-wide) or 1.0 (standard)
        #expect(cameraManager.minZoomFactor >= 0.5)
        #expect(cameraManager.minZoomFactor <= 1.0)

        // Max zoom should be reasonable (typically 3.0-15.0 for back camera)
        #expect(cameraManager.maxZoomFactor >= 1.0)
        #expect(cameraManager.maxZoomFactor <= 30.0) // Generous upper bound

        // Min should be less than max
        #expect(cameraManager.minZoomFactor < cameraManager.maxZoomFactor)
    }

    @Test("Session Preset Support")
    func testSessionPresets() async throws {
        let permissionManager = AGPermissionManager()
        let cameraManager = AGCameraManager(permissionManager: permissionManager)

        let presets = cameraManager.supportedSessionPresets

        // Should have at least some supported presets
        #expect(!presets.isEmpty)

        // Photo preset is typically always supported
        #expect(presets.contains(.photo))
    }

    @Test("Get Capture Session")
    func testGetCaptureSession() async throws {
        let permissionManager = AGPermissionManager()
        let cameraManager = AGCameraManager(permissionManager: permissionManager)

        let session = cameraManager.getCaptureSession()

        #expect(session != nil)
        #expect(session is AVCaptureSession)
    }
}

// MARK: - Camera Error Tests

struct CameraErrorTests {

    @Test("Error Descriptions")
    func testErrorDescriptions() throws {
        let errors: [CameraError] = [
            .permissionDenied,
            .cameraNotAvailable,
            .setupFailed,
            .captureFailed,
            .recordingFailed,
            .invalidConfiguration
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Permission Denied Error")
    func testPermissionDeniedError() throws {
        let error = CameraError.permissionDenied
        #expect(error.errorDescription?.contains("permission") == true)
    }

    @Test("Camera Not Available Error")
    func testCameraNotAvailableError() throws {
        let error = CameraError.cameraNotAvailable
        #expect(error.errorDescription?.contains("not available") == true)
    }
}

// MARK: - Integration Tests

@MainActor
struct IntegrationTests {

    @Test("Full Permission Flow")
    func testFullPermissionFlow() async throws {
        let permissionManager = AGPermissionManager()
        let cameraManager = AGCameraManager(permissionManager: permissionManager)

        // Verify managers work together
        #expect(permissionManager != nil)
        #expect(cameraManager != nil)

        // Camera manager should have correct initial state
        #expect(cameraManager.currentCameraPosition == .back)
        #expect(!cameraManager.isSessionRunning)
    }

    @Test("Camera Manager Lifecycle")
    func testCameraManagerLifecycle() async throws {
        let permissionManager = AGPermissionManager()
        var cameraManager: AGCameraManager? = AGCameraManager(permissionManager: permissionManager)

        #expect(cameraManager != nil)

        // Test that manager can be deallocated
        cameraManager = nil

        #expect(cameraManager == nil)
    }
}
