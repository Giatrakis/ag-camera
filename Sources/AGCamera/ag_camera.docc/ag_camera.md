# ``AGCamera``

Add a SwiftUI camera view or build custom controls around an observable camera manager.

## Overview

Create an ``AGCameraManager`` and pass it to ``AGCameraView``. The view displays a camera preview, manages its session while visible, and can display built-in capture controls. Set initial behavior with ``AGCameraConfiguration`` or view modifiers. Request camera access before starting a session; request microphone and photo library access only for features that need them.

Camera capture requires a physical iOS device. The host app must provide the relevant privacy usage descriptions in its Info.plist.

## Topics

### Camera UI

- ``AGCameraView``
- ``AGCameraConfiguration``

### Camera control and permissions

- ``AGCameraManager``
- ``AGPermissionManager``
- ``CameraError``
