//
//  AGCapturePhotoButton.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import SwiftUI

public struct AGCapturePhotoButton: View {
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
                    .frame(width: 85, height: 85)
                    .opacity(0.6)
                
                Circle()
                    .foregroundStyle(.white)
                    .frame(width: 75, height: 75)
                    .scaleEffect(animate ? 0.9 : 1.0)
                    .animation(.spring(response: 0.3), value: animate)
            }
        }
        .buttonStyle(.plain)
    }
}
