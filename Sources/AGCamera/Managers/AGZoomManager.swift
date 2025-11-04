//
//  AGZoomManager.swift
//  ag-camera
//

import AVFoundation
import OSLog
import CoreGraphics

@MainActor
class AGZoomManager {

    private static let logger = Logger(subsystem: "com.agcamera", category: "ZoomManager")

    private let sessionManager: AGSessionManager

    private var displayZoomMultiplier: CGFloat {
        guard let device = sessionManager.currentDevice else { return 1.0 }
        return device.displayVideoZoomFactorMultiplier
    }

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
    }

    @discardableResult func setZoom(factor: CGFloat) throws -> CGFloat {
        guard let device = sessionManager.currentDevice else {
            Self.logger.error("No current device available for zoom")
            throw CameraError.cameraNotAvailable
        }

        let deviceZoom = factor / displayZoomMultiplier
        let clampedDeviceZoom = min(max(deviceZoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        let clampedUIZoom = clampedDeviceZoom * displayZoomMultiplier

        Self.logger.debug("setZoom - UI requested: \(String(format: "%.2f", factor))×, Display multiplier: \(String(format: "%.2f", self.displayZoomMultiplier)), Device zoom: \(String(format: "%.2f", deviceZoom)), Device range: [\(String(format: "%.2f", device.minAvailableVideoZoomFactor))-\(String(format: "%.2f", device.maxAvailableVideoZoomFactor))], Clamped: \(String(format: "%.2f", clampedDeviceZoom)), Final UI: \(String(format: "%.2f", clampedUIZoom))×")

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.videoZoomFactor = clampedDeviceZoom
        Self.logger.debug("Applied videoZoomFactor = \(clampedDeviceZoom)")

        return clampedUIZoom
    }

    func getMaxZoomFactor(for position: AVCaptureDevice.Position) -> CGFloat {
        guard let device = sessionManager.currentDevice else { return 1.0 }
        let deviceMax = device.maxAvailableVideoZoomFactor

        let maxUIZoom: CGFloat = (position == .front) ? 3.0 : 15.0
        let cappedDeviceMax = min(deviceMax, maxUIZoom / displayZoomMultiplier)

        return cappedDeviceMax * displayZoomMultiplier
    }

    func getMinZoomFactor() -> CGFloat {
        guard let device = sessionManager.currentDevice else { return 1.0 }
        return device.minAvailableVideoZoomFactor * displayZoomMultiplier
    }

    func getCurrentZoomFactor() -> CGFloat {
        guard let device = sessionManager.currentDevice else { return 1.0 }
        return device.videoZoomFactor * displayZoomMultiplier
    }
}
