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
    @State private var capturedPhoto: UIImage?
    
    var body: some View {
        AGCameraView(manager: cameraManager)
            .videoGravity(.resizeAspectFill)
            .defaultZoomScale(1)
            .onPhotoCapture { image in
                capturedPhoto = image
            }
            .onVideoStopped { videoURL in
                print("VIDEO URL: \(videoURL)")
            }
            .sheet(item: $capturedPhoto) { photo in
                CapturePhotoPreview(photo: photo)
            }
    }
}

private struct CapturePhotoPreview: View {
    let photo: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .overlay(alignment: .topLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
        }
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: UUID { UUID() }
}

#Preview {
    ContentView()
}
