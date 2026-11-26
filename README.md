# AGCamera

**Beta · 0.1.0-beta.2** · iOS 18+

AGCamera provides a SwiftUI camera view and an observable camera manager. Apps can use the built-in controls or supply their own SwiftUI interface without building a UIKit camera preview.

The public API is still evolving. Test capture behavior on a physical device before shipping an app that depends on this beta.

## Features

- Photo capture with automatic, JPEG, or HEIF output; Live Photos with Off, On, and Auto modes
- Video recording with audio and front/back camera switching in a single movie
- Preview controls for zoom, focus, exposure, flash, torch, grid, and photo aspect ratio
- Device capability and capture-readiness reporting for custom controls
- Configurable camera defaults and SwiftUI modifiers
- An Xcode demo in [`Examples/AGCameraDemo`](Examples/AGCameraDemo)

The built-in mode picker currently captures **Photo** and **Video**. Other mode names are visible as disabled labels while their capture implementations are in development.

## Installation

Add the package URL in Xcode or declare the beta version in `Package.swift`:

```swift
.package(url: "https://github.com/Giatrakis/ag-camera.git", exact: "0.1.0-beta.2")
```

Link the `AGCamera` product to the app target. AGCamera requires iOS 18 or later and a Swift 6 toolchain; its source uses Swift 5 language mode.

Add the privacy descriptions needed by the host app:

| Info.plist key | Used for |
| --- | --- |
| `NSCameraUsageDescription` | Preview and capture |
| `NSMicrophoneUsageDescription` | Video and Live Photos with audio |
| `NSPhotoLibraryAddUsageDescription` | Saving to Photos |

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

`AGCameraView` requests camera access by default and manages the capture session while visible. Capture callbacks return media to the host app. The manager's recording URL is temporary; move or save the movie when it must persist.

## Custom controls

Apply `.showDefaultControls(false)` to hide the built-in interface, then call methods on `AGCameraManager` from custom SwiftUI buttons. The manager also exposes `capabilities`, `isPhotoCaptureReady`, the current zoom and exposure values, and their supported ranges. Initial behavior can be set with `AGCameraConfiguration` or view modifiers; use manager methods for changes after the session starts.

See [USAGE.md](USAGE.md) for configuration, custom-control examples, permissions, capture results, and saving. [DocC documentation](Sources/AGCamera/ag_camera.docc/ag_camera.md) covers the main public types.

## Demo and tests

Open `ag-camera.xcodeproj` and run the `ag-camera-app` scheme on an iPhone. The demo exercises the built-in controls and exposes configuration options through Settings. The `ag-camera` scheme runs the framework tests.

AGCamera currently provides capture and direct camera controls, not a full media browser or editing pipeline. The host app owns long-term media storage. Video may briefly hold a frame when switching cameras during recording.

## License

AGCamera is available under the [MIT License](LICENSE).
