# ``AGCamera``

Add a SwiftUI camera view or build custom controls around an observable camera manager.

## Overview

Create an ``AGCameraManager`` and pass it to ``AGCameraView``. The view displays a camera preview, manages its session while visible, and can display built-in capture controls. Set initial behavior with ``AGCameraConfiguration`` or view modifiers. Clients can hide the built-in controls and add their own SwiftUI controls without creating a UIKit preview.

The host app must provide `NSCameraUsageDescription` for preview and capture. Video recording always includes audio and requires `NSMicrophoneUsageDescription`; recording fails if microphone access is denied or audio input setup fails. Saving to Photos requires `NSPhotoLibraryAddUsageDescription`. These descriptions belong to the host app, not the package. Camera capture requires a physical iOS device.

## Start with the view

```swift
import AGCamera
import SwiftUI

struct CameraScreen: View {
    @State private var camera = AGCameraManager()
    @State private var capturedImage: UIImage?
    @State private var recordingURL: URL?

    var body: some View {
        AGCameraView(manager: camera)
            .onPhotoCapture { capturedImage = $0 }
            .onVideoStopped { recordingURL = $0 }
    }
}
```

The view requests camera permission by default, then configures and starts the session. It stops the session when removed. Captures are returned to the caller; the SDK does not save them automatically. A completed movie is stored at a temporary URL, so the host app must move or save it for long-term retention.

For custom controls, apply `.showDefaultControls(false)`, place SwiftUI buttons above the view, and call the manager's photo, recording, and switching methods. No UIKit code is required in the host app.

The built-in controls include flash and Live Photo toggles with status labels, a centered Photo/Video mode selector, capture and rotate buttons, and a recent-capture preview. The six-dot control opens a draggable Flash, Live, and Aspect sheet; `.onMoreControlsTap` replaces that action. The `ƒ` control uses `.onStyleControlsTap` for a host-provided action. Use `.onGalleryTap` to replace the recent-capture action with a host app gallery.

## Configure and control

Use ``AGCameraConfiguration`` to supply settings when constructing a manager. The view's fluent modifiers are initial-only overrides applied before the first session setup. The manager remains the source of truth for live setting changes; changing modifiers while the view is mounted does not reconfigure an active session. Methods that cannot apply a requested camera setting throw ``CameraError``; handle these errors in custom controls.

`capturePhoto()` returns encoded image data. Use ``AGPhotoFormat`` in the configuration, `.photoFormat(_:)` on the view, or `setPhotoFormat(_:)` on the manager to select JPEG or HEIF. The default `.automatic` preserves AVFoundation's choice. The active camera's `supportedPhotoFormats` lists available options. `startVideoRecording()` returns the temporary recording URL when recording begins, and `stopVideoRecording()` returns the completed movie URL. Video methods are asynchronous. `setSessionPreset(_:)` is asynchronous and throws if the selected preset is unsupported.

Use ``AGPhotoAspectRatio`` in the configuration, `.photoAspectRatio(_:)` on the view, or `setPhotoAspectRatio(_:)` on the manager to choose 4:3, 16:9, or 1:1. The ratio crops the preview and encoded still image. Live Photo stills are cropped; their paired movies keep the camera's original dimensions.

After session setup, `AGCameraManager.capabilities` reports the active camera's supported controls, photo formats, and session presets. `isPhotoCaptureReady` combines the photo output's capture readiness with session and Live Photo state for custom shutter controls.

When using ``AGCameraManager`` without ``AGCameraView``, request camera permission first, then call `setupSession()` and `startSession()`. Call `stopSession()` when capture is no longer needed. The start and stop methods queue work; observe `isSessionRunning` for their resulting state.

## Topics

### Camera UI

- ``AGCameraView``
- ``AGCameraConfiguration``
- ``AGPhotoFormat``
- ``AGPhotoAspectRatio``

### Camera control and permissions

- ``AGCameraManager``
- ``AGPermissionManager``
- ``CameraError``
