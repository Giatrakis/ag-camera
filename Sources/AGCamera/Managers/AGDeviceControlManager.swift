//
//  AGDeviceControlManager.swift
//  ag-camera
//

import AVFoundation

@MainActor
class AGDeviceControlManager {

    private let sessionManager: AGSessionManager

    var isFlashAvailable: Bool {
        guard let device = sessionManager.currentDevice else { return false }
        return device.hasFlash && device.isFlashAvailable
    }

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
    }

    @discardableResult
    func setTorch(enabled: Bool, level: Float = 1.0) async throws -> Bool {
        guard !enabled || (level.isFinite && (0.0...1.0).contains(level)) else {
            throw CameraError.invalidConfiguration
        }

        let shouldEnable = enabled && level > 0
        return try await sessionManager.performDeviceOperation { device, position in
            guard device.hasTorch else {
                if !shouldEnable { return false }
                throw CameraError.invalidConfiguration
            }
            guard !shouldEnable || (position == .back && device.isTorchAvailable) else {
                throw CameraError.invalidConfiguration
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if shouldEnable {
                try device.setTorchModeOn(level: level)
                return true
            }
            device.torchMode = .off
            return false
        }
    }

}
