import SwiftUI
import AVFoundation

@MainActor
public struct AGCameraConfiguration {
    public var handlePermissions: Bool
    public var showDefaultControls: Bool
    public var enableTapToFocus: Bool {
        get { tapToFocusBehavior != .none }
        set {
            tapToFocusBehavior = newValue
                ? (tapToFocusBehavior == .none ? .focusAndExposure : tapToFocusBehavior)
                : .none
        }
    }
    public var tapToFocusBehavior: AGTapToFocusBehavior
    public var grid: AGCameraGrid
    public var videoGravity: AVLayerVideoGravity
    public var focusIndicator: AnyView
    public var defaultCameraPosition: AVCaptureDevice.Position
    public var defaultFlashMode: AVCaptureDevice.FlashMode
    public var defaultZoomScale: CGFloat
    public var maxFrontZoomFactor: CGFloat
    public var maxBackZoomFactor: CGFloat
    public var mirrorFrontCamera: Bool
    public var torchLevel: Float
    public var defaultFocusMode: AVCaptureDevice.FocusMode
    public var defaultExposureMode: AVCaptureDevice.ExposureMode
    public var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization
    public var photoFormat: AGPhotoFormat
    public var livePhotoMode: AGLivePhotoMode
    public var sessionPreset: AVCaptureSession.Preset
    public var videoFrameRate: Int32
    public var videoCodec: AVVideoCodecType?
    public var enableLogging: Bool

    public init(
        handlePermissions: Bool = true,
        showDefaultControls: Bool = true,
        enableTapToFocus: Bool = true,
        tapToFocusBehavior: AGTapToFocusBehavior = .focusAndExposure,
        grid: AGCameraGrid = .none,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        focusIndicator: some View = AGFocusIndicatorView(),
        defaultCameraPosition: AVCaptureDevice.Position = .back,
        defaultFlashMode: AVCaptureDevice.FlashMode = .off,
        defaultZoomScale: CGFloat = 1.0,
        maxFrontZoomFactor: CGFloat = 3.0,
        maxBackZoomFactor: CGFloat = 15.0,
        mirrorFrontCamera: Bool = true,
        torchLevel: Float = 1.0,
        defaultFocusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus,
        defaultExposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure,
        photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization = .quality,
        photoFormat: AGPhotoFormat = .automatic,
        livePhotoMode: AGLivePhotoMode = .off,
        sessionPreset: AVCaptureSession.Preset = .photo,
        videoFrameRate: Int32 = 30,
        videoCodec: AVVideoCodecType? = nil,
        enableLogging: Bool = true
    ) {
        self.handlePermissions = handlePermissions
        self.showDefaultControls = showDefaultControls
        self.tapToFocusBehavior = enableTapToFocus ? tapToFocusBehavior : .none
        self.grid = grid
        self.videoGravity = videoGravity
        self.focusIndicator = AnyView(focusIndicator)
        self.defaultCameraPosition = defaultCameraPosition
        self.defaultFlashMode = defaultFlashMode
        self.defaultZoomScale = defaultZoomScale
        self.maxFrontZoomFactor = maxFrontZoomFactor
        self.maxBackZoomFactor = maxBackZoomFactor
        self.mirrorFrontCamera = mirrorFrontCamera
        self.torchLevel = torchLevel
        self.defaultFocusMode = defaultFocusMode
        self.defaultExposureMode = defaultExposureMode
        self.photoQualityPrioritization = photoQualityPrioritization
        self.photoFormat = photoFormat
        self.livePhotoMode = livePhotoMode
        self.sessionPreset = sessionPreset
        self.videoFrameRate = videoFrameRate
        self.videoCodec = videoCodec
        self.enableLogging = enableLogging
    }

    public static let `default` = AGCameraConfiguration()
}
