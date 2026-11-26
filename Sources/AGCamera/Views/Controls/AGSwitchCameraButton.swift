import SwiftUI

public struct AGSwitchCameraButton: View {
    let onSwitch: () async -> Void

    public init(onSwitch: @escaping () async -> Void) {
        self.onSwitch = onSwitch
    }

    public var body: some View {
        Button {
            Task { await onSwitch() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel("Switch camera")
    }
}
