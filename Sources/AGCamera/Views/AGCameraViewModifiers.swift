import SwiftUI
import AVFoundation

extension AGCameraView {
    public func onPhotoCapture(_ action: @escaping (UIImage) -> Void) -> Self {
        var view = self
        view.photoCaptureAction = action
        return view
    }

    public func onVideoStarted(_ action: @escaping (URL) -> Void) -> Self {
        var view = self
        view.videoStartedAction = action
        return view
    }

    public func onVideoStopped(_ action: @escaping (URL) -> Void) -> Self {
        var view = self
        view.videoStoppedAction = action
        return view
    }

    public func onCameraPositionChanged(_ action: @escaping (AVCaptureDevice.Position) -> Void) -> Self {
        var view = self
        view.cameraPositionChangedAction = action
        return view
    }

    public func onZoomChanged(_ action: @escaping (CGFloat) -> Void) -> Self {
        var view = self
        view.zoomChangedAction = action
        return view
    }

    public func onFlashModeChanged(_ action: @escaping (AVCaptureDevice.FlashMode) -> Void) -> Self {
        var view = self
        view.flashModeChangedAction = action
        return view
    }

    public func onError(_ action: @escaping (CameraError) -> Void) -> Self {
        var view = self
        view.errorAction = action
        return view
    }

    public func handlePermissions(_ enabled: Bool) -> Self {
        var view = self
        view.configuration.handlePermissions = enabled
        return view
    }

    public func showDefaultControls(_ show: Bool) -> Self {
        var view = self
        view.configuration.showDefaultControls = show
        return view
    }

    public func enableTapToFocus(_ enabled: Bool) -> Self {
        var view = self
        view.configuration.enableTapToFocus = enabled
        return view
    }

    public func videoGravity(_ gravity: AVLayerVideoGravity) -> Self {
        var view = self
        view.configuration.videoGravity = gravity
        return view
    }

    public func defaultCameraPosition(_ position: AVCaptureDevice.Position) -> Self {
        var view = self
        view.configuration.defaultCameraPosition = position
        return view
    }

    public func defaultFlashMode(_ mode: AVCaptureDevice.FlashMode) -> Self {
        var view = self
        view.configuration.defaultFlashMode = mode
        return view
    }

    public func defaultZoomScale(_ scale: CGFloat) -> Self {
        var view = self
        view.configuration.defaultZoomScale = scale
        return view
    }

    public func photoQuality(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) -> Self {
        var view = self
        view.configuration.photoQualityPrioritization = prioritization
        return view
    }

    public func sessionPreset(_ preset: AVCaptureSession.Preset) -> Self {
        var view = self
        view.configuration.sessionPreset = preset
        return view
    }

    public func videoFrameRate(_ fps: Int32) -> Self {
        var view = self
        view.configuration.videoFrameRate = fps
        return view
    }

    public func focusIndicator<V: View>(_ indicator: V) -> Self {
        var view = self
        view.configuration.focusIndicator = AnyView(indicator)
        return view
    }
}
