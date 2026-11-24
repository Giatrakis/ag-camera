//
//  AGCaptureVideoButton.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import SwiftUI

public struct AGCaptureVideoButton: View {
    let isRecording: Bool
    var onCapture: () async -> Void
    @State private var animate = false

    public init(isRecording: Bool, onCapture: @escaping () async -> Void) {
        self.isRecording = isRecording
        self.onCapture = onCapture
    }
    
    public var body: some View {
        Button {
            Task { await onCapture() }
            animate = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { animate = false }
        } label: {
            ZStack {
                if #available(iOS 26.0, *) {
                    Circle()
                        .frame(width: 80, height: 80)
                        .glassEffect(.regular.tint(.gray.opacity(0.3)), in: Circle())
                } else {
                    Circle()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.gray.opacity(0.3))
                }
                
                RoundedRectangle(cornerRadius: isRecording ? 6 : 35)
                    .frame(width: isRecording ? 36 : 70, height: isRecording ? 36 : 70)
                    .foregroundStyle(.red)
                    .animation(.smooth, value: isRecording)
            }
        }
        .buttonStyle(.plain)
    }
}
