import SwiftUI

public struct AGCapturePhotoButton: View {
    let onCapture: () async -> Void

    public init(onCapture: @escaping () async -> Void) {
        self.onCapture = onCapture
    }

    public var body: some View {
        Button {
            Task { await onCapture() }
        } label: {
            Circle()
                .fill(.clear)
                .frame(width: 82, height: 82)
                .agCameraGlassCircle()
                .overlay(Circle().fill(.white).padding(7))
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel("Take photo")
    }
}
