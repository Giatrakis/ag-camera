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
            .defaultZoomScale(2)
            .maxFrontZoomFactor(2.5)
            .maxBackZoomFactor(8)
            .photoQuality(.speed)
            .sessionPreset(.hd1920x1080)
            .videoFrameRate(24)
            .videoCodec(.hevc)
            .mirrorFrontCamera(false)
            .torchLevel(0.4)
            .defaultFocusMode(.locked)
            .defaultExposureMode(.locked)
            .tapToFocusBehavior(.focusOnly)
            .grid(.rule3x3)
            .enableLogging(false)

        #expect(view.configuration.handlePermissions == false)
        #expect(view.configuration.showDefaultControls == false)
        #expect(view.configuration.defaultCameraPosition == .front)
        #expect(view.configuration.defaultZoomScale == 2)
        #expect(view.configuration.maxFrontZoomFactor == 2.5)
        #expect(view.configuration.maxBackZoomFactor == 8)
        #expect(view.configuration.photoQualityPrioritization == .speed)
        #expect(view.configuration.sessionPreset == .hd1920x1080)
        #expect(view.configuration.videoFrameRate == 24)
        #expect(view.configuration.videoCodec == .hevc)
        #expect(view.configuration.mirrorFrontCamera == false)
        #expect(view.configuration.torchLevel == 0.4)
        #expect(view.configuration.defaultFocusMode == .locked)
        #expect(view.configuration.defaultExposureMode == .locked)
        #expect(view.configuration.tapToFocusBehavior == .focusOnly)
        #expect(view.configuration.enableTapToFocus)
        #expect(view.configuration.grid == .rule3x3)
        #expect(view.configuration.enableLogging == false)
        #expect(manager.configuration.handlePermissions == true)
        #expect(manager.configuration.showDefaultControls == true)
        #expect(manager.configuration.defaultCameraPosition == .back)
        #expect(manager.configuration.videoCodec == nil)
        #expect(manager.configuration.enableLogging)
    }

    @Test
    func callbackModifierDoesNotMutateManagerDuringViewConstruction() {
        let manager = AGCameraManager()

        let view = AGCameraView(manager: manager)
            .onPhotoCapture { _ in }

        #expect(view.photoCaptureAction != nil)
        #expect(manager.onPhotoCapture == nil)
    }

    @Test
    func viewOverridesPreserveLaterManagerSettings() {
        let manager = AGCameraManager()
        let view = AGCameraView(manager: manager)
            .showDefaultControls(false)
            .defaultZoomScale(2)

        manager.configuration.videoFrameRate = 60
        manager.configuration.defaultZoomScale = 1.5

        #expect(view.configuration.videoFrameRate == 60)
        #expect(view.configuration.defaultZoomScale == 2)
        #expect(view.configuration.showDefaultControls == false)
        #expect(manager.configuration.defaultZoomScale == 1.5)
    }

    @Test
    func tapBehaviorHasOneSourceOfTruth() {
        var configuration = AGCameraConfiguration(tapToFocusBehavior: .focusOnly)
        #expect(configuration.enableTapToFocus)

        configuration.enableTapToFocus = false
        #expect(configuration.tapToFocusBehavior == .none)

        configuration.enableTapToFocus = true
        #expect(configuration.tapToFocusBehavior == .focusAndExposure)

        let manager = AGCameraManager()
        let view = AGCameraView(manager: manager)
            .tapToFocusBehavior(.focusOnly)
            .enableTapToFocus(true)
        #expect(view.configuration.tapToFocusBehavior == .focusOnly)
    }

    @Test
    func terminalPhotoResultCompletesAfterEarlyFailure() {
        let result = AGCaptureManager.resolvedPhotoResult(
            processingResult: nil,
            captureError: nil
        )
        if case .failure(let error as CameraError) = result {
            #expect(error == .captureFailed)
        } else {
            Issue.record("An early photo failure must produce captureFailed")
        }

        let photo = Data([1, 2, 3])
        let success = AGCaptureManager.resolvedPhotoResult(
            processingResult: .success(photo),
            captureError: nil
        )
        if case .success(let data) = success {
            #expect(data == photo)
        } else {
            Issue.record("Processed photo data must survive the terminal callback")
        }
    }

    @Test
    func livePhotoResultRequiresACompletedStillAndMovie() {
        let photoData = Data([1, 2, 3])
        let movieURL = URL(fileURLWithPath: "/tmp/live-photo-test.mov")
        let complete = AGCaptureManager.resolvedLivePhotoResult(
            photoResult: .success(photoData),
            movieResult: .success(movieURL)
        )
        if case .success(let capture) = complete {
            #expect(capture.photoData == photoData)
            #expect(capture.pairedVideoURL == movieURL)
        } else {
            Issue.record("A completed Live Photo must contain both resources")
        }

        let incomplete = AGCaptureManager.resolvedLivePhotoResult(
            photoResult: .success(photoData),
            movieResult: nil
        )
        if case .failure(let error as CameraError) = incomplete {
            #expect(error == .captureFailed)
        } else {
            Issue.record("A missing paired movie must fail the capture")
        }
    }

    @Test
    func loggingCanBeDisabledForOneCameraInstance() {
        let quietCamera = AGCameraManager(configuration: .init(enableLogging: false))
        let otherCamera = AGCameraManager()

        #expect(quietCamera.log.isEnabled == false)
        #expect(otherCamera.log.isEnabled)

        quietCamera.setLoggingEnabled(true)
        #expect(quietCamera.log.isEnabled)
        #expect(quietCamera.configuration.enableLogging)
        #expect(otherCamera.configuration.enableLogging)
    }

    @Test
    func invalidFrameRateFailsBeforeCameraAccess() async {
        let manager = AGCameraManager()

        do {
            try await manager.setFrameRate(fps: 0)
            Issue.record("Zero frame rate must be rejected")
        } catch let error as CameraError {
            #expect(error == .invalidConfiguration)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
