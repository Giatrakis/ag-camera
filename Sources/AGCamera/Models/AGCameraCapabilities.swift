import AVFoundation

public struct AGCameraCapabilities: Equatable {
    public let position: AVCaptureDevice.Position
    public let supportsFlash: Bool
    public let supportsTorch: Bool
    public let supportsLivePhoto: Bool
    public let supportsFocusPoint: Bool
    public let supportsExposurePoint: Bool
    public let supportsManualFocus: Bool
    public let supportsCustomExposure: Bool
    public let supportsWhiteBalanceLock: Bool
    public let supportedPhotoCodecs: [AVVideoCodecType]
    public let supportedPhotoFileTypes: [AVFileType]
    public let supportedSessionPresets: [AVCaptureSession.Preset]
}
