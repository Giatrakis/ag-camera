import SwiftUI

struct AGCameraStatusToast: Identifiable {
    let id = UUID()
    let title: String
    let highlighted: Bool
}

struct AGCameraStatusToastView: View {
    let toast: AGCameraStatusToast

    var body: some View {
        Text(toast.title)
            .font(.caption)
            .fontWeight(.regular)
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(toast.highlighted ? Color.yellow : Color.white, in: RoundedRectangle(cornerRadius: 6))
            .allowsHitTesting(false)
    }
}
