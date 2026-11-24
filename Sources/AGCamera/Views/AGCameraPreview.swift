//
//  AGCameraPreview.swift
//  ag-camera
//
//  UIViewRepresentable bridge for AVCaptureVideoPreviewLayer
//

import SwiftUI
import AVFoundation
import UIKit

struct AGCameraPreview: UIViewRepresentable {

    let session: AVCaptureSession
    let isSessionConfigured: Bool
    let isSessionRunning: Bool
    let videoGravity: AVLayerVideoGravity
    let cameraPosition: AVCaptureDevice.Position
    let mirrorFrontCamera: Bool
    let log: AGCameraLog
    let loggingEnabled: Bool
    let onTapToFocus: ((CGPoint, CGPoint) -> Void)?

    init(
        session: AVCaptureSession,
        isSessionConfigured: Bool,
        isSessionRunning: Bool,
        videoGravity: AVLayerVideoGravity,
        cameraPosition: AVCaptureDevice.Position,
        mirrorFrontCamera: Bool,
        log: AGCameraLog,
        loggingEnabled: Bool,
        onTapToFocus: ((CGPoint, CGPoint) -> Void)?
    ) {
        self.session = session
        self.isSessionConfigured = isSessionConfigured
        self.isSessionRunning = isSessionRunning
        self.videoGravity = videoGravity
        self.cameraPosition = cameraPosition
        self.mirrorFrontCamera = mirrorFrontCamera
        self.log = log
        self.loggingEnabled = loggingEnabled
        self.onTapToFocus = onTapToFocus
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = videoGravity
        view.isSessionConfigured = isSessionConfigured
        view.isSessionRunning = isSessionRunning
        view.cameraPosition = cameraPosition
        view.mirrorFrontCamera = mirrorFrontCamera
        view.log = log
        view.loggingEnabled = loggingEnabled
        view.onTapToFocus = onTapToFocus
        updateMirroring(for: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        let sessionChanged = uiView.previewLayer.session !== session
        let shouldUpdateMirroring = sessionChanged
            || uiView.isSessionConfigured != isSessionConfigured
            || uiView.isSessionRunning != isSessionRunning
            || uiView.cameraPosition != cameraPosition
            || uiView.mirrorFrontCamera != mirrorFrontCamera

        if sessionChanged {
            uiView.previewLayer.session = session
        }
        if uiView.previewLayer.videoGravity != videoGravity {
            uiView.previewLayer.videoGravity = videoGravity
        }
        uiView.isSessionConfigured = isSessionConfigured
        uiView.isSessionRunning = isSessionRunning
        uiView.cameraPosition = cameraPosition
        uiView.mirrorFrontCamera = mirrorFrontCamera
        uiView.log = log
        uiView.loggingEnabled = loggingEnabled
        uiView.onTapToFocus = onTapToFocus
        if shouldUpdateMirroring {
            updateMirroring(for: uiView)
        }
    }

    private func updateMirroring(for view: PreviewView) {
        guard isSessionConfigured, let connection = view.previewLayer.connection else { return }

        if connection.isVideoMirroringSupported {
            if connection.automaticallyAdjustsVideoMirroring != view.mirrorFrontCamera {
                connection.automaticallyAdjustsVideoMirroring = view.mirrorFrontCamera
            }
            if !view.mirrorFrontCamera && connection.isVideoMirrored {
                connection.isVideoMirrored = false
            }
            if loggingEnabled {
                log.debug("Preview mirroring: \(connection.isVideoMirrored) (camera: \(view.cameraPosition == .front ? "front" : "back"))", category: "CameraPreview")
            }
        }
    }

    class PreviewView: UIView {
        var isSessionConfigured = false
        var isSessionRunning = false
        var cameraPosition: AVCaptureDevice.Position = .back
        var mirrorFrontCamera = true
        var log: AGCameraLog?
        var loggingEnabled = true
        var onTapToFocus: ((CGPoint, CGPoint) -> Void)?

        var previewLayer: AVCaptureVideoPreviewLayer {
            guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
                if loggingEnabled {
                    log?.error("Layer is not AVCaptureVideoPreviewLayer, got \(String(describing: type(of: self.layer)))", category: "CameraPreview")
                }
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
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let onTapToFocus else { return }
            let location = recognizer.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
            onTapToFocus(location, devicePoint)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }

    }
}
