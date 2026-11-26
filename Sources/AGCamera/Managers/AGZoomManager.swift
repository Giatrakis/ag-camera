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
    private var focalLengthCache: (deviceID: String, anchors: [(zoom: CGFloat, focalLength: CGFloat)])?

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
            let defaultMaximum: CGFloat = position == .front ? 3.0 : 40.0
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
        let defaultMaximum: CGFloat = position == .front ? 3.0 : 40.0
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

    func estimatedFocalLengthIn35mmFilm(for displayZoom: CGFloat) -> Int? {
        guard #available(iOS 26.0, *), displayZoom.isFinite, displayZoom > 0,
              let device = sessionManager.currentDevice else { return nil }

        if focalLengthCache?.deviceID != device.uniqueID {
            let lenses = device.constituentDevices.isEmpty ? [device] : device.constituentDevices
            let wideLens = lenses.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? lenses.first
            let wideFocalLength = CGFloat(wideLens?.nominalFocalLengthIn35mmFilm ?? 0)
            let anchors: [(zoom: CGFloat, focalLength: CGFloat)] = lenses.compactMap { lens in
                let focalLength = CGFloat(lens.nominalFocalLengthIn35mmFilm)
                guard focalLength > 0, wideFocalLength > 0 else { return nil }
                let relativeZoom = focalLength / wideFocalLength
                guard let stop = [CGFloat(0.5), 1, 2, 4, 8].min(by: {
                    abs(log2($0 / relativeZoom)) < abs(log2($1 / relativeZoom))
                }) else { return nil }
                return (stop, focalLength)
            }
            focalLengthCache = (device.uniqueID, anchors)
        }
        guard let anchor = focalLengthCache?.anchors.min(by: {
            abs(log2($0.zoom / displayZoom)) < abs(log2($1.zoom / displayZoom))
        }) else { return nil }
        return Int((anchor.focalLength * displayZoom / anchor.zoom).rounded())
    }

    func physicalLensFocalLengthIn35mmFilm(at displayZoom: CGFloat) -> Int? {
        guard estimatedFocalLengthIn35mmFilm(for: displayZoom) != nil else { return nil }
        guard let anchor = focalLengthCache?.anchors.first(where: { abs($0.zoom - displayZoom) < 0.01 }) else {
            return nil
        }
        return Int(anchor.focalLength.rounded())
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
