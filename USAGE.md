# AGCamera usage

AGCamera is a SwiftUI package for iOS 18 and later. The current SDK exposes `AGCameraView` for a ready-to-use camera screen and `AGCameraManager` for custom controls. Camera capture must be tested on a physical iOS device.

## Installation and privacy descriptions

Add this repository as a Swift package dependency in Xcode, then link the `AGCamera` product to the host app. The package uses Swift 5 language mode and a Swift 6.0 or newer toolchain.

The host app must define `NSCameraUsageDescription` for preview and capture. Video recording always requires audio, so any app that records video must also define `NSMicrophoneUsageDescription`. Define `NSPhotoLibraryAddUsageDescription` when saving media to Photos. These keys belong in the host app's Info.plist, not in the Swift package.

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

The demo app has a settings button above the preview. It exposes grid, tap behavior, mirroring, zoom, focus and exposure defaults, photo quality, session preset, video frame rate and codec, torch power, and logging. Tap **Apply** to create a new camera manager and session with those initial settings. The torch button beside Settings tests the chosen power level.

Initial options can be supplied when creating the manager:

```swift
let configuration = AGCameraConfiguration(
    showDefaultControls: false,
    defaultCameraPosition: .back,
    defaultFlashMode: .off,
    defaultZoomScale: 1.5,
    maxFrontZoomFactor: 3,
    maxBackZoomFactor: 8,
    mirrorFrontCamera: true,
    torchLevel: 0.5,
    defaultFocusMode: .continuousAutoFocus,
    defaultExposureMode: .continuousAutoExposure,
    photoQualityPrioritization: .balanced,
    sessionPreset: .hd1920x1080,
    videoFrameRate: 30,
    videoCodec: .hevc,
    enableLogging: false
)
let camera = AGCameraManager(configuration: configuration)
```

The view also exposes fluent modifiers for these settings, plus `.tapToFocusBehavior(.focusOnly)` and `.grid(.rule3x3)`. Tap behavior is `.none`, `.focusOnly`, or `.focusAndExposure`; `.enableTapToFocus(false)` disables taps. Grid options are `.none`, `.rule3x3`, and `.square4x4`. Modifiers are initial-only overrides applied before the first session setup; they are not a way to reconfigure an active session. Unmodified options continue to use the manager's latest configuration at setup time. Use manager methods for live changes. To manage camera permission yourself, use `.handlePermissions(false)` and authorize through `camera.permissionManager` first.

Photo quality accepts `.speed`, `.balanced`, or `.quality`. The session preset accepts any `AVCaptureSession.Preset` supported by the current camera, including `.photo`, `.high`, `.hd1920x1080`, and `.hd4K3840x2160`. Frame rate is an integer such as 24, 30, or 60 fps; the selected camera format must support it. For video codec, use `.h264`, `.hevc`, or `nil` to leave the system default. Recordings use a `.mov` container regardless of codec. Unsupported preset, frame rate, or codec selections report `CameraError.invalidConfiguration` when applied.

The front camera is mirrored by default in the preview and captured media. Set `mirrorFrontCamera: false` to turn that off. Zoom caps are in the displayed zoom scale and are also limited by hardware support. Torch level is from `0` (off) to `1` (full power); the torch must be available on the selected camera. Logging is enabled by default and can be disabled per camera manager.

## Permissions

Camera access is required for preview and capture. The view requests it during setup when permission handling is enabled. Starting any video recording requests microphone access; recording fails when access is denied or an audio input cannot be configured. Photo capture remains available without microphone access. Saving media requests photo library add access when needed; denial prevents saving to Photos but does not prevent capture.

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

## Custom video processing

Configure an `AVCaptureVideoDataOutput` and its sample buffer delegate before calling `camera.addVideoDataOutput(output)`. Wait until `camera.isSessionConfigured` is true, then await the throwing method. The SDK attaches the output on its session queue; it reports `CameraError.setupFailed` if the session is not configured or cannot accept the output. Keep the output and delegate alive while processing frames.

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

Movie output and microphone input are prepared when recording first starts, so the first recording can take longer to begin than later recordings.

## Camera controls

`AGCameraManager` exposes `switchCamera()`, `setFlashMode(_:)`, `toggleFlash()`, `setTorch(enabled:)`, `setTorch(level:)`, `setZoom(factor:)`, `setFocus(at:)`, `setExposure(at:)`, and `setFocusAndExposure(at:)`. Focus and exposure points are normalized device points in the range 0...1. `AGCameraView` converts taps on its preview into device points. The manager also exposes `setPhotoQualityPrioritization(_:)`, `setSessionPreset(_:)`, `setFrameRate(fps:)`, `setVideoCodec(_:)`, and `setLoggingEnabled(_:)`. The session preset setter is asynchronous and throws if unsupported; the frame rate setter throws if unsupported. Codec support is checked when recording starts.

Zoom, focus, exposure, torch, frame rate, and session preset setters are `async throws` so camera-device configuration runs off the main actor. Call them with `try await` from custom controls. Video stabilization is also asynchronous (`await camera.setVideoStabilizationMode(_:)`). Flash mode, photo quality, codec, and logging setters remain synchronous.

`minZoomFactor`, `maxZoomFactor`, and `currentZoomFactor` use the camera's display zoom scale. `availableZoomLevels` provides button stops derived from the active device's minimum zoom, virtual-camera lens switch points, and native-resolution zoom factors, limited by the configured maximum. The built-in zoom control fills its available width, centers the selected stop, and applies a new stop when scrolling settles. Tapping the selected 1× stop cycles through 1.2×, 1.5×, and 1× when supported, briefly showing 28 MM, 35 MM, and 24 MM respectively with a fade transition. These focal-length labels are fixed UI presets; they are not read from the camera hardware. Pinch zoom and `setZoom(factor:)` also accept values between stops; requested values outside the supported range are clamped. Available stops can change when the camera, session preset, or frame rate changes.

`outputType` and `setOutputType(_:)` select the built-in photo or video button. Both capture methods remain available to custom controls regardless of that selection.

```swift
try await camera.setSessionPreset(.hd1920x1080)
```

`setupSession()` is required before using the manager without `AGCameraView`. Call `requestCameraPermission()` first, then `setupSession()` and `startSession()`. Call `stopSession()` when capture is no longer needed. The start and stop methods queue session work; observe `isSessionRunning` for the resulting state.

## Current scope

The SDK currently supports still photos, movie-file recording, a SwiftUI preview with built-in controls, and direct camera settings. It does not provide a media browser, capture format picker, editing pipeline, or automatic persistence. `AGCameraView` displays camera errors in an alert; the host app owns saved media.
