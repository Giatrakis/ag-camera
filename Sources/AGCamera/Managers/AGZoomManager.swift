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
        let multiplier = device.displayVideoZoomFactorMultiplier
        return multiplier.isFinite && multiplier > 0 ? multiplier : 1.0
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
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

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

    func getAvailableZoomLevels(maximumZoomFactor: CGFloat) -> [CGFloat] {
        guard let device = sessionManager.currentDevice else { return [1.0] }
        let multiplier = device.displayVideoZoomFactorMultiplier
        guard multiplier.isFinite, multiplier > 0 else { return [1.0] }

        let minimum = device.minAvailableVideoZoomFactor * multiplier
        let maximum = max(minimum, min(maximumZoomFactor, device.maxAvailableVideoZoomFactor * multiplier))
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let nativeResolutionStops = device.activeFormat.secondaryNativeResolutionZoomFactors
        return AGZoomStops.make(
            minimum: minimum,
            maximum: maximum,
            displayMultiplier: multiplier,
            switchOvers: switchOvers,
            nativeResolutionStops: nativeResolutionStops
        )
    }
}

enum AGZoomStops {
    static func nextOneXZoom(current: CGFloat, maximum: CGFloat) -> (factor: CGFloat, focalLength: Int) {
        if current < 1.1, maximum >= 1.2 {
            return (1.2, 28)
        }
        if current < 1.35, maximum >= 1.5 {
            return (1.5, 35)
        }
        return (1.0, 24)
    }

    static func make(
        minimum: CGFloat,
        maximum: CGFloat,
        displayMultiplier: CGFloat,
        switchOvers: [CGFloat],
        nativeResolutionStops: [CGFloat]
    ) -> [CGFloat] {
        guard minimum.isFinite, maximum.isFinite, displayMultiplier.isFinite,
              minimum > 0, maximum >= minimum, displayMultiplier > 0 else { return [1.0] }

        let tolerance: CGFloat = 0.005
        let candidates = [minimum, 1.0] + (switchOvers + nativeResolutionStops).map { $0 * displayMultiplier }
        let valid = candidates.filter {
            $0.isFinite && $0 >= minimum && $0 <= maximum
        }.sorted()

        return valid.reduce(into: [CGFloat]()) { levels, level in
            guard levels.last.map({ abs($0 - level) > tolerance }) ?? true else { return }
            levels.append(level)
        }
    }
}
