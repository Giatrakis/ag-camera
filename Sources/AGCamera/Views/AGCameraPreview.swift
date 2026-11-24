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
    let onVideoRectChanged: (CGRect) -> Void

    init(
        session: AVCaptureSession,
        isSessionConfigured: Bool,
        isSessionRunning: Bool,
        videoGravity: AVLayerVideoGravity,
        cameraPosition: AVCaptureDevice.Position,
        mirrorFrontCamera: Bool,
        log: AGCameraLog,
        loggingEnabled: Bool,
        onTapToFocus: ((CGPoint, CGPoint) -> Void)?,
        onVideoRectChanged: @escaping (CGRect) -> Void
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
        self.onVideoRectChanged = onVideoRectChanged
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
        view.onVideoRectChanged = onVideoRectChanged
        updateMirroring(for: view)
        view.reportVideoRectIfChanged()
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
        uiView.onVideoRectChanged = onVideoRectChanged
        if shouldUpdateMirroring {
            updateMirroring(for: uiView)
        }
        uiView.reportVideoRectIfChanged()
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
        var onVideoRectChanged: ((CGRect) -> Void)?
        private var reportedVideoRect = CGRect.null

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
            reportVideoRectIfChanged()
        }

        func reportVideoRectIfChanged() {
            guard bounds.width > 0, bounds.height > 0 else { return }
            let imageRect = previewLayer.layerRectConverted(
                fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
            let visibleRect = imageRect.intersection(bounds)
            guard !visibleRect.isNull, !visibleRect.isEmpty, visibleRect != reportedVideoRect else { return }
            reportedVideoRect = visibleRect
            onVideoRectChanged?(visibleRect)
        }
    }
}
