import AVFoundation
import SwiftUI

struct AGFlashModeIcon: View {
    let mode: AVCaptureDevice.FlashMode
    let font: Font

    var body: some View {
        Image(systemName: AGCameraManager.flashIconName(for: mode))
            .font(font)
    }
}

struct AGLivePhotoModeIcon: View {
    let mode: AGLivePhotoMode
    let font: Font

    var body: some View {
        Image(systemName: symbolName)
            .font(font)
    }

    private var symbolName: String {
        switch mode {
        case .off: "livephoto.slash"
        case .on: "livephoto"
        case .auto: "livephoto.badge.a"
        }
    }
}
