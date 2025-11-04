//
//  ContentView.swift
//  ag-camera-app
//
//  Created by Alex Giatrakis on 31/10/25.
//

import SwiftUI
import ag_camera

struct ContentView: View {
    @State private var cameraManager = AGCameraManager()
    
    var body: some View {
        AGCameraView(manager: cameraManager) { image in
            
        } onVideoRecordingStopped: { url in
            
        }
    }
}
