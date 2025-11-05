//
//  AGVideoDurationView.swift
//  ag-camera
//
//  Created by Alex Giatrakis on 5/11/25.
//

import SwiftUI

public struct AGVideoDurationView: View {
    let duration: String
    
    public var body: some View {
        Text(duration)
            .font(.system(size: 18))
            .monospaced()
            .monospacedDigit()
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.red)
            .clipShape(.rect(cornerRadius: 5))
    }
}
