import SwiftUI
import AVFoundation

public struct AGCameraConfiguration {
    public var handlePermissions: Bool
    public var showDefaultControls: Bool
    public var enableTapToFocus: Bool
    public var videoGravity: AVLayerVideoGravity
    public var focusIndicator: AnyView
    public var defaultCameraPosition: AVCaptureDevice.Position
    public var defaultFlashMode: AVCaptureDevice.FlashMode
    public var defaultZoomScale: CGFloat
    public var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    public var sessionPreset: AVCaptureSession.Preset
    public var videoFrameRate: Int32

    public init(
        handlePermissions: Bool = true,
        showDefaultControls: Bool = true,
        enableTapToFocus: Bool = true,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        focusIndicator: some View = AGFocusIndicatorView(),
        defaultCameraPosition: AVCaptureDevice.Position = .back,
        defaultFlashMode: AVCaptureDevice.FlashMode = .off,
        defaultZoomScale: CGFloat = 1.0,
        photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization = .quality,
        sessionPreset: AVCaptureSession.Preset = .photo,
        videoFrameRate: Int32 = 30
    ) {
        self.handlePermissions = handlePermissions
        self.showDefaultControls = showDefaultControls
        self.enableTapToFocus = enableTapToFocus
        self.videoGravity = videoGravity
        self.focusIndicator = AnyView(focusIndicator)
        self.defaultCameraPosition = defaultCameraPosition
        self.defaultFlashMode = defaultFlashMode
        self.defaultZoomScale = defaultZoomScale
        self.photoQualityPrioritization = photoQualityPrioritization
        self.sessionPreset = sessionPreset
        self.videoFrameRate = videoFrameRate
    }

    public static let `default` = AGCameraConfiguration()
}
