//
//  AGFocusExposureManager.swift
//  ag-camera
//

import AVFoundation
import CoreGraphics

@MainActor
class AGFocusExposureManager {

    private let sessionManager: AGSessionManager

    init(sessionManager: AGSessionManager) {
        self.sessionManager = sessionManager
    }

    func setFocus(at point: CGPoint) throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isFocusPointOfInterestSupported else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
    }

    func setFocusMode(_ mode: AVCaptureDevice.FocusMode) throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isFocusModeSupported(mode) else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.focusMode = mode
    }

    func setExposure(at point: CGPoint) throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isExposurePointOfInterestSupported else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.exposurePointOfInterest = point
        device.exposureMode = .autoExpose
    }

    func setExposureMode(_ mode: AVCaptureDevice.ExposureMode) throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        guard device.isExposureModeSupported(mode) else {
            throw CameraError.invalidConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.exposureMode = mode
    }

    func setFocusAndExposure(at point: CGPoint) throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

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

    func lockExposureAndFocus() throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.locked) {
            device.focusMode = .locked
        }

        if device.isExposureModeSupported(.locked) {
            device.exposureMode = .locked
        }
    }

    func resetFocusAndExposure() throws {
        guard let device = sessionManager.currentDevice else {
            throw CameraError.cameraNotAvailable
        }

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
