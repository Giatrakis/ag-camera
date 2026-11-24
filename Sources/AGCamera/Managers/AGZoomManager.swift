//
//  AGZoomManager.swift
//  ag-camera
//

import AVFoundation
import CoreGraphics

@MainActor
class AGZoomManager {

    private let sessionManager: AGSessionManager
    private let log: AGCameraLog

    private var displayZoomMultiplier: CGFloat {
        guard let device = sessionManager.currentDevice else { return 1.0 }
        return device.displayVideoZoomFactorMultiplier
    }

    init(sessionManager: AGSessionManager, log: AGCameraLog) {
        self.sessionManager = sessionManager
        self.log = log
    }

    @discardableResult func setZoom(factor: CGFloat, maximumZoomFactor: CGFloat? = nil) async throws -> CGFloat {
        guard factor.isFinite, factor > 0 else {
            throw CameraError.invalidConfiguration
        }
        if let maximumZoomFactor {
            guard maximumZoomFactor.isFinite, maximumZoomFactor > 0 else {
                throw CameraError.invalidConfiguration
            }
        }

        return try await sessionManager.performDeviceOperation { [log] device, position in
            let multiplier = device.displayVideoZoomFactorMultiplier
            guard multiplier.isFinite, multiplier > 0 else {
                throw CameraError.invalidConfiguration
            }
            let hardwareMinimum = device.minAvailableVideoZoomFactor * multiplier
            let hardwareMaximum = device.maxAvailableVideoZoomFactor * multiplier
            let defaultMaximum: CGFloat = position == .front ? 3.0 : 15.0
            let requestedMaximum = maximumZoomFactor ?? defaultMaximum
            let maxUIZoom = max(hardwareMinimum, min(requestedMaximum, hardwareMaximum))
            let requestedZoom = min(max(factor, hardwareMinimum), maxUIZoom)
            let deviceZoom = requestedZoom / multiplier

            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = deviceZoom
            let applied = device.videoZoomFactor * multiplier
            log.debug("Applied display zoom \(applied)×", category: "ZoomManager")
            return applied
        }
    }

    func getMaxZoomFactor(
        for position: AVCaptureDevice.Position,
        configuredMaximum: CGFloat? = nil
    ) -> CGFloat {
        guard let device = sessionManager.currentDevice else { return 1.0 }
        let hardwareMinimum = device.minAvailableVideoZoomFactor * displayZoomMultiplier
        let hardwareMaximum = device.maxAvailableVideoZoomFactor * displayZoomMultiplier
        let defaultMaximum: CGFloat = position == .front ? 3.0 : 15.0
        let requestedMaximum = configuredMaximum ?? defaultMaximum
        return max(hardwareMinimum, min(requestedMaximum, hardwareMaximum))
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
