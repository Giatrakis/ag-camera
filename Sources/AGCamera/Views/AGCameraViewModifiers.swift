import SwiftUI
import AVFoundation

extension AGCameraView {
    private func overriding<Value>(_ keyPath: WritableKeyPath<AGCameraConfiguration, Value>, with value: Value) -> Self {
        var view = self
        view.configurationOverrides.append { $0[keyPath: keyPath] = value }
        return view
    }

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
        overriding(\.handlePermissions, with: enabled)
    }

    public func showDefaultControls(_ show: Bool) -> Self {
        overriding(\.showDefaultControls, with: show)
    }

    public func enableTapToFocus(_ enabled: Bool) -> Self {
        if !enabled { return tapToFocusBehavior(.none) }
        let behavior = configuration.tapToFocusBehavior
        return tapToFocusBehavior(behavior == .none ? .focusAndExposure : behavior)
    }

    public func tapToFocusBehavior(_ behavior: AGTapToFocusBehavior) -> Self {
        overriding(\.tapToFocusBehavior, with: behavior)
    }

    public func grid(_ grid: AGCameraGrid) -> Self {
        overriding(\.grid, with: grid)
    }

    public func videoGravity(_ gravity: AVLayerVideoGravity) -> Self {
        overriding(\.videoGravity, with: gravity)
    }

    public func defaultCameraPosition(_ position: AVCaptureDevice.Position) -> Self {
        overriding(\.defaultCameraPosition, with: position)
    }

    public func defaultFlashMode(_ mode: AVCaptureDevice.FlashMode) -> Self {
        overriding(\.defaultFlashMode, with: mode)
    }

    public func defaultZoomScale(_ scale: CGFloat) -> Self {
        overriding(\.defaultZoomScale, with: scale)
    }

    public func maxFrontZoomFactor(_ factor: CGFloat) -> Self {
        overriding(\.maxFrontZoomFactor, with: factor)
    }

    public func maxBackZoomFactor(_ factor: CGFloat) -> Self {
        overriding(\.maxBackZoomFactor, with: factor)
    }

    public func mirrorFrontCamera(_ enabled: Bool) -> Self {
        overriding(\.mirrorFrontCamera, with: enabled)
    }

    public func torchLevel(_ level: Float) -> Self {
        overriding(\.torchLevel, with: level)
    }

    public func defaultFocusMode(_ mode: AVCaptureDevice.FocusMode) -> Self {
        overriding(\.defaultFocusMode, with: mode)
    }

    public func defaultExposureMode(_ mode: AVCaptureDevice.ExposureMode) -> Self {
        overriding(\.defaultExposureMode, with: mode)
    }

    public func photoQuality(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) -> Self {
        overriding(\.photoQualityPrioritization, with: prioritization)
    }

    public func sessionPreset(_ preset: AVCaptureSession.Preset) -> Self {
        overriding(\.sessionPreset, with: preset)
    }

    public func videoFrameRate(_ fps: Int32) -> Self {
        overriding(\.videoFrameRate, with: fps)
    }

    public func videoCodec(_ codec: AVVideoCodecType?) -> Self {
        overriding(\.videoCodec, with: codec)
    }

    public func enableLogging(_ enabled: Bool) -> Self {
        overriding(\.enableLogging, with: enabled)
    }

    public func exposureBias(_ value: Binding<Float>) -> Self {
        var view = self
        view.exposureBiasBinding = value
        return view
    }

    public func focusIndicator<V: View>(_ indicator: V) -> Self {
        overriding(\.focusIndicator, with: AnyView(indicator))
    }
}
