//
//  AGCameraPreview.swift
//  ag-camera
//
//  UIViewRepresentable bridge for AVCaptureVideoPreviewLayer
//

import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI wrapper for AVCaptureVideoPreviewLayer
public struct AGCameraPreview: UIViewRepresentable {

    // MARK: - Properties

    /// The capture session to display
    let session: AVCaptureSession

    /// Video gravity (aspect fill, aspect fit, resize)
    let videoGravity: AVLayerVideoGravity

    /// Current camera position (to control mirroring)
    let cameraPosition: AVCaptureDevice.Position

    // MARK: - Initialization

    public init(
        session: AVCaptureSession,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        cameraPosition: AVCaptureDevice.Position = .back
    ) {
        self.session = session
        self.videoGravity = videoGravity
        self.cameraPosition = cameraPosition
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = videoGravity
        updateOrientation(for: view)

        // Observe orientation changes
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak view] _ in
            guard let view = view else { return }
            self.updateOrientation(for: view)
        }

        return view
    }

    public func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.previewLayer.videoGravity = videoGravity
        updateOrientation(for: uiView)
    }

    private func updateOrientation(for view: PreviewView) {
        guard let connection = view.previewLayer.connection else { return }

        let orientation = UIDevice.current.orientation
        let angle: CGFloat

        switch orientation {
        case .portrait:
            angle = 90
        case .portraitUpsideDown:
            angle = 270
        case .landscapeLeft:
            angle = 180
        case .landscapeRight:
            angle = 0
        default:
            angle = 90 // Default to portrait
        }

        connection.videoRotationAngle = angle

        // DON'T mirror preview - show as others see you (not like a mirror)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false  // Never mirror, even for front camera
            print("🖼️ Preview mirroring: \(connection.isVideoMirrored) (camera: \(cameraPosition == .front ? "front" : "back"))")
        }
    }

    // MARK: - Preview View

    /// Custom UIView that hosts the AVCaptureVideoPreviewLayer
    public class PreviewView: UIView {

        /// The preview layer
        public var previewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        override public class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupView()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupView()
        }

        private func setupView() {
            backgroundColor = .black
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}
