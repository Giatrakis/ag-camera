import SwiftUI

struct AGCameraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    @ViewBuilder
    func agCameraGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.black.opacity(0.25)), in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func agCameraGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.black.opacity(0.25)), in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func agCameraControlsSheetBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationBackground(.ultraThinMaterial)
        }
    }
}
