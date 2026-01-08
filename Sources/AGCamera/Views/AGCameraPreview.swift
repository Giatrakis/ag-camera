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

struct AGCameraPreview: UIViewRepresentable {

    private static let logger = Logger(subsystem: "com.agcamera", category: "CameraPreview")
    let session: AVCaptureSession
    let videoGravity: AVLayerVideoGravity
    let cameraPosition: AVCaptureDevice.Position

    init(
        session: AVCaptureSession,
        videoGravity: AVLayerVideoGravity,
        cameraPosition: AVCaptureDevice.Position
    ) {
        self.session = session
        self.videoGravity = videoGravity
        self.cameraPosition = cameraPosition
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = videoGravity
        view.cameraPosition = cameraPosition
        view.orientationUpdateHandler = { [weak view] in
            guard let view = view else { return }
            self.updateMirroring(for: view)
        }
        updateMirroring(for: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.previewLayer.videoGravity = videoGravity
        uiView.cameraPosition = cameraPosition
        updateMirroring(for: uiView)
    }

    private func updateMirroring(for view: PreviewView) {
        guard let connection = view.previewLayer.connection else { return }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (view.cameraPosition == .front)
            Self.logger.debug("Preview mirroring: \(connection.isVideoMirrored) (camera: \(view.cameraPosition == .front ? "front" : "back"))")
        }
    }

    class PreviewView: UIView {
        var orientationUpdateHandler: (() -> Void)?
        var cameraPosition: AVCaptureDevice.Position = .back

        var previewLayer: AVCaptureVideoPreviewLayer {
            guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
                AGCameraPreview.logger.error("Layer is not AVCaptureVideoPreviewLayer, got \(String(describing: type(of: self.layer)))")
                let fallbackLayer = AVCaptureVideoPreviewLayer()
                fallbackLayer.frame = bounds
                return fallbackLayer
            }
            return previewLayer
        }

        override class var layerClass: AnyClass {
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

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            orientationUpdateHandler?()
        }
    }
}
