# AGCamera usage

AGCamera is a SwiftUI package for iOS 26 and later. The current SDK exposes `AGCameraView` for a ready-to-use camera screen and `AGCameraManager` for custom controls. Camera capture must be tested on a physical iOS device.

## Installation and privacy descriptions

Add this repository as a Swift package dependency in Xcode, then link the `AGCamera` product to the host app. The package uses Swift 5 language mode and a Swift 6.0 or newer toolchain.

The host app must define `NSCameraUsageDescription` for preview and capture. Define `NSMicrophoneUsageDescription` when recording audio and `NSPhotoLibraryAddUsageDescription` when saving media to Photos. These keys belong in the host app's Info.plist, not in the Swift package.

## Ready-to-use view

```swift
import AGCamera
import SwiftUI

struct CameraScreen: View {
    @State private var camera = AGCameraManager()
    @State private var capturedImage: UIImage?
    @State private var recordingURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        AGCameraView(manager: camera)
            .onPhotoCapture { capturedImage = $0 }
            .onVideoStopped { recordingURL = $0 }
            .onError { errorMessage = $0.localizedDescription }
    }
}
```

`AGCameraView` requests camera permission by default, configures the capture session, starts it while the view is visible, and stops it when the view disappears. It does not automatically save captures to Photos. The URL returned for a video is in the temporary directory; move it or save it before relying on long-term retention.

Initial options can be supplied when creating the manager:

```swift
let configuration = AGCameraConfiguration(
    showDefaultControls: false,
    defaultCameraPosition: .back,
    defaultFlashMode: .off,
    defaultZoomScale: 1,
    sessionPreset: .hd1920x1080
)
let camera = AGCameraManager(configuration: configuration)
```

The view also exposes fluent configuration modifiers such as `.showDefaultControls(false)`, `.enableTapToFocus(false)`, `.defaultCameraPosition(.front)`, `.sessionPreset(.hd1920x1080)`, and `.videoFrameRate(30)`. Set initial options before the view starts its session. To manage camera permission yourself, use `.handlePermissions(false)` and authorize through `camera.permissionManager` first.

## Permissions

Camera access is required for preview and capture. The view requests it during setup when permission handling is enabled. Starting a recording requests microphone access when needed, and saving media requests photo library add access when needed. A user who denies either optional permission can still use camera-only features.

```swift
let camera = AGCameraManager()
let cameraGranted = await camera.permissionManager.requestCameraPermission()
let microphoneGranted = await camera.permissionManager.requestMicrophonePermission()
let libraryGranted = await camera.permissionManager.requestPhotoLibraryPermission()
```

`AGPermissionManager.requestAllPermissions()` is available when an app intentionally needs all three permissions, but it is not a prerequisite for photo capture.

## Custom controls

Hide the built-in controls and place app-specific controls above `AGCameraView`. The view continues to own preview and session lifecycle.

```swift
import AGCamera
import SwiftUI

struct CustomCameraScreen: View {
    @State private var camera = AGCameraManager()
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            AGCameraView(manager: camera)
                .showDefaultControls(false)

            HStack {
                Button("Capture") {
                    Task {
                        do {
                            _ = try await camera.capturePhoto()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                Button(camera.isRecording ? "Stop" : "Record") {
                    Task {
                        do {
                            if camera.isRecording {
                                _ = try await camera.stopVideoRecording()
                            } else {
                                _ = try await camera.startVideoRecording()
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                Button("Switch") {
                    Task {
                        do {
                            try await camera.switchCamera()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .padding()
        }
    }
}
```

`AGCameraPreview` is an implementation detail and is not part of the public package API. Use `AGCameraView` when building a custom camera screen.

## Capture results and saving

`capturePhoto()` returns encoded image `Data`. `startVideoRecording()` returns the temporary movie URL after recording starts. `stopVideoRecording()` returns the completed movie URL. Both video methods are asynchronous and throwing.

```swift
let photoData = try await camera.capturePhoto()

let recordingURL = try await camera.startVideoRecording()
let completedURL = try await camera.stopVideoRecording()

try await camera.savePhotoToLibrary(photoData)
try await camera.saveVideoToLibrary(url: completedURL)
```

The start URL and completed URL refer to the recording file. `saveVideoToLibrary(url:)` removes the temporary file after a successful save. The manager does not save photos or videos automatically.

## Camera controls

`AGCameraManager` exposes `switchCamera()`, `setFlashMode(_:)`, `toggleFlash()`, `setTorch(enabled:)`, `setZoom(factor:)`, `setFocus(at:)`, `setExposure(at:)`, and `setFocusAndExposure(at:)`. Focus and exposure points are normalized device points in the range 0...1. `AGCameraView` converts taps on its preview into device points. The manager also exposes photo quality, session preset, video stabilization, and frame rate controls.

`setupSession()` is required before using the manager without `AGCameraView`. Call `requestCameraPermission()` first, then `setupSession()` and `startSession()`. Call `stopSession()` when capture is no longer needed. The start and stop methods queue session work; observe `isSessionRunning` for the resulting state.

## Current scope

The SDK currently supports still photos, movie-file recording, a SwiftUI preview with built-in controls, and direct camera settings. It does not provide a media browser, capture format picker, editing pipeline, or automatic persistence. `AGCameraView` displays camera errors in an alert; the host app owns saved media.
