import SwiftUI

public struct AGCaptureVideoButton: View {
    let isRecording: Bool
    let onCapture: () async -> Void

    public init(isRecording: Bool, onCapture: @escaping () async -> Void) {
        self.isRecording = isRecording
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
                .overlay {
                    RoundedRectangle(cornerRadius: isRecording ? 6 : 35)
                        .fill(.red)
                        .frame(width: isRecording ? 36 : 68, height: isRecording ? 36 : 68)
                        .animation(.smooth(duration: 0.25), value: isRecording)
                }
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
