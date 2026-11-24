import AVFoundation
import SwiftUI
import Testing
#if canImport(AGCamera)
import AGCamera
#else
import ag_camera
#endif

@MainActor
struct AGCameraPublicAPITests {
    @Test
    func builtInControlsAreConstructibleByClients() {
        let manager = AGCameraManager()
        let photo = AGCapturePhotoButton(onCapture: {})
        let video = AGCaptureVideoButton(isRecording: false, onCapture: {})
        let switchCamera = AGSwitchCameraButton(onSwitch: {})
        let picker = AGInputPickerButton(outputType: .constant(.photo))
        let zoom = AGSZoomControlView(manager: manager, onZoomChange: { _ in })
        let duration = AGVideoDurationView(duration: "00:00:00")
        let indicator = AGFocusIndicatorView()

        #expect(type(of: photo) == AGCapturePhotoButton.self)
        #expect(type(of: video) == AGCaptureVideoButton.self)
        #expect(type(of: switchCamera) == AGSwitchCameraButton.self)
        #expect(type(of: picker) == AGInputPickerButton.self)
        #expect(type(of: zoom) == AGSZoomControlView.self)
        #expect(type(of: duration) == AGVideoDurationView.self)
        #expect(type(of: indicator) == AGFocusIndicatorView.self)
    }

    @Test
    func videoDataOutputRequiresConfiguredSession() async {
        let manager = AGCameraManager()

        await #expect(throws: CameraError.setupFailed) {
            try await manager.addVideoDataOutput(AVCaptureVideoDataOutput())
        }
    }
}
