# AGCamera

AGCamera is a SwiftUI camera package for iOS 26 and later. It provides a ready-to-use camera view and an observable manager for photo capture, video recording, focus, zoom, flash, torch, and camera switching. The SDK is under active development.

## Add the package

Add this repository as a Swift package dependency in Xcode and link the `AGCamera` product to the app target. The package uses Swift 5 language mode and requires the Swift 6.0 toolchain or newer to evaluate its manifest.

Add these usage descriptions to the **host app** as needed:

| Info.plist key | Required for |
| --- | --- |
| `NSCameraUsageDescription` | Camera preview and photo/video capture |
| `NSMicrophoneUsageDescription` | Video recording with audio |
| `NSPhotoLibraryAddUsageDescription` | Saving media to the photo library |

## Quick start

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

`AGCameraView` requests camera access when permission handling is enabled. Recording requests microphone access when needed, and the explicit save methods request photo library add access when needed. The camera requires a physical device for capture validation.

See [USAGE.md](USAGE.md) for configuration, custom controls, and the manager API.

## Current scope

The package supports one active capture session with still photos and movie-file recordings. It does not yet provide a full camera product surface such as an in-app media browser, capture format selection, or a processing pipeline. The host app owns its permission descriptions and captured media handling. `AGCameraView` presents camera errors in an alert.
