import AVFoundation
import CoreGraphics

struct AGExposureBiasState: Sendable {
    let current: Float
    let minimum: Float
    let maximum: Float
}

@MainActor
final class AGFocusExposureManager {
    private let sessionManager: AGSessionManager

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
    }

    func configureDefaultModes(
        focusMode: AVCaptureDevice.FocusMode,
        exposureMode: AVCaptureDevice.ExposureMode
    ) async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            guard device.isFocusModeSupported(focusMode),
                  device.isExposureModeSupported(exposureMode) else {
                throw CameraError.invalidConfiguration
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.focusMode = focusMode
            device.exposureMode = exposureMode
        }
    }

    func setFocus(at point: CGPoint) async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            guard device.isFocusPointOfInterestSupported else {
                throw CameraError.invalidConfiguration
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
        }
    }

    func setFocusMode(_ mode: AVCaptureDevice.FocusMode) async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            guard device.isFocusModeSupported(mode) else {
                throw CameraError.invalidConfiguration
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.focusMode = mode
        }
    }

    func setExposure(at point: CGPoint) async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            guard device.isExposurePointOfInterestSupported else {
                throw CameraError.invalidConfiguration
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
        }
    }

    func setExposureMode(_ mode: AVCaptureDevice.ExposureMode) async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            guard device.isExposureModeSupported(mode) else {
                throw CameraError.invalidConfiguration
            }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.exposureMode = mode
        }
    }

    func exposureBiasState() async throws -> AGExposureBiasState {
        try await sessionManager.performDeviceOperation { device, _ in
            AGExposureBiasState(
                current: device.exposureTargetBias,
                minimum: device.minExposureTargetBias,
                maximum: device.maxExposureTargetBias
            )
        }
    }

    func setExposureBias(_ bias: Float) async throws -> Float {
        guard bias.isFinite else { throw CameraError.invalidConfiguration }
        return try await sessionManager.performDeviceOperation { device, _ in
            guard device.exposureMode != .custom else { throw CameraError.invalidConfiguration }
            let clampedBias = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setExposureTargetBias(clampedBias, completionHandler: nil)
            return clampedBias
        }
    }

    func setFocusAndExposure(at point: CGPoint, resetExposureBias: Bool = false) async throws -> Float {
        try await sessionManager.performDeviceOperation { device, _ in
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let bias: Float
            if resetExposureBias {
                bias = min(max(0, device.minExposureTargetBias), device.maxExposureTargetBias)
                device.setExposureTargetBias(bias, completionHandler: nil)
            } else {
                bias = device.exposureTargetBias
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            return bias
        }
    }

    func lockExposureAndFocus() async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        }
    }

    func resetFocusAndExposure() async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }
    }
}
