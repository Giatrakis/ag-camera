//
//  AGSZoomControlView.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import SwiftUI

public struct AGSZoomControlView: View {
    @Bindable var manager: AGCameraManager
    var onZoomChange: (CGFloat) -> Void
    @State private var animate = false

    public init(manager: AGCameraManager, onZoomChange: @escaping (CGFloat) -> Void) {
        self.manager = manager
        self.onZoomChange = onZoomChange
    }
    
    private var zoomLevels: [CGFloat] {
        Array(manager.availableZoomLevels.prefix(3))
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(zoomLevels, id: \.self) { level in
                ZoomButton(level: level, currentZoom: manager.currentZoomFactor) { zoom in
                    onZoomChange(zoom)
                }
            }
        }
    }
    
    private struct ZoomButton: View {
        var level: CGFloat
        var currentZoom: CGFloat
        var action: (CGFloat) -> Void
        @State private var animate = false
        
        private var isSelected: Bool {
            level == currentZoom 
        }
        
        private var selectedSuffix: String {
            isSelected ? "×" : ""
        }
        
        var body: some View {
            Button {
                action(level)
                animate = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { animate = false }
            } label: {
                    Text(level.truncatingRemainder(dividingBy: 1) == 0 ?
                         String(format: "%.0f\(selectedSuffix)", level) :
                            String(format: "%.1f\(selectedSuffix)", level))
                    .monospaced()
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .yellow : .white)
                    .shadow(color: .black, radius: isSelected ? 0 : 1.5, x: 0, y: 0)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? Color.black.opacity(0.4) : .white.opacity(0.001))
                    .clipShape(Circle())
                    .scaleEffect(animate ? 0.9 : 1.0)
                    .animation(.bouncy(duration: 0.3, extraBounce: 0.3), value: animate)
            }
            .buttonStyle(.plain)
        }
    }
}
