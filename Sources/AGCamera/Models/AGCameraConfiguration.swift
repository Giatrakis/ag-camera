import SwiftUI
import AVFoundation

public struct AGCameraConfiguration {
    public var handlePermissions: Bool
    public var showDefaultControls: Bool
    public var videoGravity: AVLayerVideoGravity
    public var focusIndicator: AnyView
    public var defaultCameraPosition: AVCaptureDevice.Position
    public var defaultFlashMode: AVCaptureDevice.FlashMode

    public init(
        handlePermissions: Bool = true,
        showDefaultControls: Bool = true,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        focusIndicator: some View = FocusIndicatorView(),
        defaultCameraPosition: AVCaptureDevice.Position = .back,
        defaultFlashMode: AVCaptureDevice.FlashMode = .off
    ) {
        self.handlePermissions = handlePermissions
        self.showDefaultControls = showDefaultControls
        self.videoGravity = videoGravity
        self.focusIndicator = AnyView(focusIndicator)
        self.defaultCameraPosition = defaultCameraPosition
        self.defaultFlashMode = defaultFlashMode
    }

    public static let `default` = AGCameraConfiguration()
}
