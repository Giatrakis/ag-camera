import AVFoundation
import CoreGraphics

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

    func setFocusAndExposure(at point: CGPoint) async throws {
        try await sessionManager.performDeviceOperation { device, _ in
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
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
