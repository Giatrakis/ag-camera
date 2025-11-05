//
//  ContentView.swift
//  ag-camera-app
//
//  Created by Alex Giatrakis on 31/10/25.
//

import SwiftUI
import ag_camera
internal import AVFoundation

struct ContentView: View {
    @State private var cameraManager = AGCameraManager()
    
    var body: some View {
        AGCameraView(manager: cameraManager, configuration: AGCameraConfiguration(videoGravity: .resizeAspectFill)) { image in
            
        } onVideoRecordingStopped: { url in
            
        }
    }
}

#Preview {
    ContentView()
}
