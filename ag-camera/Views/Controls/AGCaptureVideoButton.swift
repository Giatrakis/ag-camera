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
    
    public var body: some View {
        Button {
            Task { await onCapture() }
            animate = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { animate = false }
        } label: {
            ZStack {
                Circle()
                    .foregroundStyle(.gray)
                    .frame(width: 70, height: 70)
                    .opacity(0.3)
                
                RoundedRectangle(cornerRadius: isRecording ? 6 : 30)
                    .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
                    .foregroundStyle(.red)
                    .animation(.smooth, value: isRecording)
            }
        }
        .buttonStyle(.plain)
    }
}
