//
//  AGFocusIndicatorView.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import SwiftUI

public struct AGFocusIndicatorView: View {
    @State private var animate = false
    
    public nonisolated init() {}

    public var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1)
            .frame(width: 75, height: 75)
            .overlay(alignment: .leading) { horizontalLine }
            .overlay(alignment: .trailing) { horizontalLine }
            .overlay(alignment: .top) { verticalLine }
            .overlay(alignment: .bottom) { verticalLine }
            .scaleEffect(animate ? 1.0 : 1.2)
            .opacity(animate ? 1.0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.15)) {
                    animate = true
                }
            }
    }
    
    private var horizontalLine: some View {
        Color.yellow
            .frame(width: 5, height: 1)
    }
    
    private var verticalLine: some View {
        Color.yellow
            .frame(width: 1, height: 5)
    }
}
