import AVFoundation
import Testing
#if canImport(AGCamera)
@testable import AGCamera
#else
@testable import ag_camera
#endif

@MainActor
struct AGCameraViewConfigurationTests {
    @Test
    func modifiersKeepConfigurationOnTheViewUntilItAppears() {
        let manager = AGCameraManager()

        let view = AGCameraView(manager: manager)
            .handlePermissions(false)
            .showDefaultControls(false)
            .defaultCameraPosition(.front)

        #expect(view.configuration.handlePermissions == false)
        #expect(view.configuration.showDefaultControls == false)
        #expect(view.configuration.defaultCameraPosition == .front)
        #expect(manager.configuration.handlePermissions == true)
        #expect(manager.configuration.showDefaultControls == true)
        #expect(manager.configuration.defaultCameraPosition == .back)
    }

    @Test
    func callbackModifierDoesNotMutateManagerDuringViewConstruction() {
        let manager = AGCameraManager()

        let view = AGCameraView(manager: manager)
            .onPhotoCapture { _ in }

        #expect(view.photoCaptureAction != nil)
        #expect(manager.onPhotoCapture == nil)
    }
}
