//
//  AGDeviceControlManager.swift
//  ag-camera
//

import AVFoundation
import OSLog

@MainActor
class AGDeviceControlManager {

    private static let logger = Logger(subsystem: "com.agcamera", category: "DeviceControl")

    private let sessionManager: AGSessionManager

    var isFlashAvailable: Bool {
        guard let device = sessionManager.currentDevice else { return false }
        return device.hasFlash && device.isFlashAvailable
    }

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
    }

    func setTorch(enabled: Bool) throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard sessionManager.currentPosition == .back else {
            throw CameraError.invalidConfiguration
        }

        guard device.hasTorch && device.isTorchAvailable else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if enabled {
            try device.setTorchModeOn(level: 1.0)
        } else {
            device.torchMode = .off
        }
    }

    func configureVideoMirroring(for position: AVCaptureDevice.Position) {
        let shouldMirror = position == .front

        Self.logger.debug("Configuring mirroring for \(position == .front ? "FRONT" : "BACK") camera - shouldMirror: \(shouldMirror)")

        if let photoOutput = sessionManager.photoOutput {
            if let photoConnection = photoOutput.connection(with: .video) {
                if photoConnection.isVideoMirroringSupported {
                    photoConnection.automaticallyAdjustsVideoMirroring = false
                    photoConnection.isVideoMirrored = shouldMirror
                    Self.logger.debug("Photo mirroring set to: \(photoConnection.isVideoMirrored)")
                } else {
                    Self.logger.warning("Photo mirroring NOT supported")
                }
            } else {
                Self.logger.warning("Photo connection is NIL")
            }
        } else {
            Self.logger.warning("Photo output is NIL")
        }

        if let movieFileOutput = sessionManager.movieFileOutput {
            if let videoConnection = movieFileOutput.connection(with: .video) {
                if videoConnection.isVideoMirroringSupported {
                    videoConnection.automaticallyAdjustsVideoMirroring = false
                    videoConnection.isVideoMirrored = shouldMirror
                    Self.logger.debug("Video mirroring set to: \(videoConnection.isVideoMirrored)")
                } else {
                    Self.logger.warning("Video mirroring NOT supported")
                }
            } else {
                Self.logger.warning("Video connection is NIL")
            }
        } else {
            Self.logger.warning("Video output is NIL")
        }
    }
}
