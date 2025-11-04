//
//  AGCameraPreview.swift
//  ag-camera
//
//  UIViewRepresentable bridge for AVCaptureVideoPreviewLayer
//

import SwiftUI
import AVFoundation
import UIKit
import OSLog

public struct AGCameraPreview: UIViewRepresentable {

    private static let logger = Logger(subsystem: "com.agcamera", category: "CameraPreview")
    let session: AVCaptureSession
    let videoGravity: AVLayerVideoGravity
    let cameraPosition: AVCaptureDevice.Position

    public init(
        session: AVCaptureSession,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
//        videoGravity: AVLayerVideoGravity = .resizeAspect,
        cameraPosition: AVCaptureDevice.Position = .back
    ) {
        self.session = session
        self.videoGravity = videoGravity
        self.cameraPosition = cameraPosition
    }

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

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
            Self.logger.debug("Preview mirroring: \(connection.isVideoMirrored) (camera: \(cameraPosition == .front ? "front" : "back"))")
        }
    }

    public class PreviewView: UIView {
        public var previewLayer: AVCaptureVideoPreviewLayer {
            guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("Expected AVCaptureVideoPreviewLayer but got \(type(of: layer))")
            }
            return previewLayer
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
