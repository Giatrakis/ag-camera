//
//  AGSwitchCameraButton.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import SwiftUI

public struct AGSwitchCameraButton: View {
    var onSwitch: () async -> Void
    @State private var animate = false
    
    public var body: some View {
        Button {
            Task { await onSwitch() }
            animate = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { animate = false }
        } label: {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.title2)
                .padding(12)
                .foregroundStyle(.white)
        }
        .glassEffect(.regular.tint(.gray.opacity(0.3)), in: Circle())
        .scaleEffect(animate ? 1.15 : 1.0)
        .animation(.bouncy(duration: 0.3, extraBounce: 0.3), value: animate)
    }
}
