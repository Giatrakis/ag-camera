# AG Camera Library - Usage Guide

A powerful, reusable iOS camera library built with SwiftUI and AVFoundation, supporting iOS 26+.

## Architecture

```
┌─────────────────────────────────────────┐
│      SwiftUI Layer (Your Custom UI)     │
│   Add any buttons/controls you want     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      AGCameraManager                    │
│  All camera methods at your disposal:   │
│  • capturePhoto()                       │
│  • startVideoRecording()                │
│  • stopVideoRecording()                 │
│  • switchCamera()                       │
│  • toggleFlash()                        │
│  • setZoom(factor:)                     │
│  • setFocus(at:)                        │
│  • and many more...                     │
└─────────────────────────────────────────┘
```

## Key Features

✅ **Photo Capture** - High-quality photo capture with flash support
✅ **Video Recording** - Video recording with audio
✅ **Camera Switching** - Front/back camera toggle
✅ **Flash Control** - Off, On, Auto modes
✅ **Torch Mode** - Flashlight for video recording
✅ **Focus & Exposure** - Tap to focus, manual controls
✅ **Zoom** - Pinch to zoom functionality
✅ **Resolution Control** - 4K, 1080p, 720p, photo presets
✅ **Quality Settings** - Quality vs speed prioritization
✅ **Video Stabilization** - Smooth video recording
✅ **Frame Rate Control** - FPS settings
✅ **All Apple Native Enums** - No custom wrappers!

## Quick Start

### 1. Request Permissions

```swift
let permissionManager = AGPermissionManager()

// Request all permissions
let result = await permissionManager.requestAllPermissions()

// Or request individually
let cameraGranted = await permissionManager.requestCameraPermission()
let micGranted = await permissionManager.requestMicrophonePermission()
let photoGranted = await permissionManager.requestPhotoLibraryPermission()
```

### 2. Setup Camera Manager

```swift
// Initialize with permission manager
let cameraManager = AGCameraManager(permissionManager: permissionManager)

// Setup session
try await cameraManager.setupSession()

// Start session
cameraManager.startSession()
```

### 3. Display Camera Preview

```swift
AGCameraPreview(
    session: cameraManager.getCaptureSession(),
    videoGravity: .resizeAspectFill
)
```

### 4. Add Custom Buttons

```swift
// Photo capture button
Button("Take Photo") {
    Task {
        let photoData = try await cameraManager.capturePhoto()
        let image = UIImage(data: photoData)
        // Do something with the image
    }
}

// Video recording button
Button(cameraManager.isRecording ? "Stop" : "Record") {
    if cameraManager.isRecording {
        cameraManager.stopVideoRecording()
    } else {
        Task {
            let videoURL = try await cameraManager.startVideoRecording()
            // Video saved at videoURL
        }
    }
}

// Switch camera button
Button("Flip") {
    Task {
        try await cameraManager.switchCamera()
    }
}

// Flash toggle button
Button("Flash") {
    cameraManager.toggleFlash()
}
```

## Complete Method Reference

### Photo Capture
```swift
// Capture photo
let photoData = try await cameraManager.capturePhoto()
```

### Video Recording
```swift
// Start recording (returns URL when stopped)
let videoURL = try await cameraManager.startVideoRecording()

// Stop recording
cameraManager.stopVideoRecording()

// Check recording state
if cameraManager.isRecording { }
```

### Camera Controls
```swift
// Switch camera
try await cameraManager.switchCamera()

// Get current position
let position = cameraManager.currentCameraPosition // .back or .front
```

### Flash Controls
```swift
// Toggle flash (off -> on -> auto -> off)
cameraManager.toggleFlash()

// Set specific mode
cameraManager.setFlashMode(.on)    // Use Apple's enum
cameraManager.setFlashMode(.off)
cameraManager.setFlashMode(.auto)

// Check availability
if cameraManager.isFlashAvailable { }

// Torch (flashlight) for video
try cameraManager.setTorch(enabled: true)
```

### Focus & Exposure
```swift
// Tap to focus (point is normalized 0-1)
try cameraManager.setFocus(at: CGPoint(x: 0.5, y: 0.5))

// Set exposure point
try cameraManager.setExposure(at: CGPoint(x: 0.5, y: 0.5))

// Both at once (common use case)
try cameraManager.setFocusAndExposure(at: point)

// Set modes (using Apple's native enums)
try cameraManager.setFocusMode(.autoFocus)
try cameraManager.setFocusMode(.continuousAutoFocus)
try cameraManager.setFocusMode(.locked)

try cameraManager.setExposureMode(.autoExpose)
try cameraManager.setExposureMode(.continuousAutoExposure)
try cameraManager.setExposureMode(.locked)

// Lock current settings
try cameraManager.lockExposureAndFocus()

// Reset to auto
try cameraManager.resetFocusAndExposure()
```

### Zoom Controls
```swift
// Set zoom factor
try cameraManager.setZoom(factor: 2.0)  // 2x zoom

// Get current zoom
let currentZoom = cameraManager.currentZoomFactor

// Get zoom limits
let maxZoom = cameraManager.maxZoomFactor
let minZoom = cameraManager.minZoomFactor
```

### Resolution & Quality
```swift
// Set resolution preset (using Apple's native enums)
try cameraManager.setSessionPreset(.hd4K3840x2160)
try cameraManager.setSessionPreset(.hd1920x1080)
try cameraManager.setSessionPreset(.hd1280x720)
try cameraManager.setSessionPreset(.photo)

// Get current preset
let preset = cameraManager.currentSessionPreset

// Get supported presets
let supported = cameraManager.supportedSessionPresets

// Set photo quality prioritization
cameraManager.setPhotoQualityPrioritization(.quality)
cameraManager.setPhotoQualityPrioritization(.balanced)
cameraManager.setPhotoQualityPrioritization(.speed)

// Video stabilization
cameraManager.setVideoStabilizationMode(.auto)
cameraManager.setVideoStabilizationMode(.cinematic)
cameraManager.setVideoStabilizationMode(.standard)

// Frame rate
try cameraManager.setFrameRate(fps: 60)
try cameraManager.setFrameRate(fps: 30)
```

### Session Management
```swift
// Start session
cameraManager.startSession()

// Stop session
cameraManager.stopSession()

// Check if running
if cameraManager.isSessionRunning { }
```

## Example: Custom Camera UI

```swift
struct MyCameraView: View {
    @State private var permissionManager = AGPermissionManager()
    @State private var cameraManager: AGCameraManager?

    var body: some View {
        ZStack {
            // Camera preview
            if let manager = cameraManager {
                AGCameraPreview(session: manager.getCaptureSession())
                    .ignoresSafeArea()
            }

            // Your custom UI
            VStack {
                HStack {
                    // Custom flash button
                    MyFlashButton(action: {
                        cameraManager?.toggleFlash()
                    })

                    Spacer()

                    // Custom settings button
                    MySettingsButton()
                }

                Spacer()

                HStack(spacing: 40) {
                    // Custom camera switch button
                    MySwitchButton {
                        try? await cameraManager?.switchCamera()
                    }

                    // Custom capture button
                    MyCaptureButton {
                        let data = try? await cameraManager?.capturePhoto()
                        // Process photo
                    }

                    // Custom video button
                    MyVideoButton {
                        if cameraManager?.isRecording == true {
                            cameraManager?.stopVideoRecording()
                        } else {
                            let url = try? await cameraManager?.startVideoRecording()
                        }
                    }
                }
            }
            .padding()
        }
        .task {
            await setupCamera()
        }
    }

    private func setupCamera() async {
        await permissionManager.requestAllPermissions()
        let manager = AGCameraManager(permissionManager: permissionManager)
        try? await manager.setupSession()
        manager.startSession()
        cameraManager = manager
    }
}
```

## Native Enums Used

This library uses Apple's native enums directly - no custom wrappers!

- `AVCaptureDevice.Position` (.front, .back)
- `AVCaptureDevice.FlashMode` (.off, .on, .auto)
- `AVCaptureDevice.FocusMode` (.autoFocus, .continuousAutoFocus, .locked)
- `AVCaptureDevice.ExposureMode` (.autoExpose, .continuousAutoExposure, .locked)
- `AVCaptureSession.Preset` (.photo, .hd4K3840x2160, etc.)
- `AVCapturePhotoOutput.QualityPrioritization` (.quality, .balanced, .speed)
- `AVCaptureVideoStabilizationMode` (.auto, .cinematic, .standard, .off)
- `AVAuthorizationStatus` (for permissions)
- `PHAuthorizationStatus` (for photo library)

## Error Handling

```swift
do {
    let photo = try await cameraManager.capturePhoto()
} catch CameraError.permissionDenied {
    // Handle permission error
} catch CameraError.cameraNotAvailable {
    // Handle camera not available
} catch CameraError.captureFailed {
    // Handle capture failure
} catch {
    // Handle other errors
}
```

## Requirements

- iOS 26.0+
- Swift 6.0+
- Xcode 16.0+

## License

See project license.
