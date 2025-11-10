//
//  AGCameraViewModifiers.swift
//  ag-camera
//
//  View modifier extensions for AGCameraView event handling
//

import SwiftUI
import AVFoundation

// MARK: - Camera Event View Modifiers

extension AGCameraView {

    /// Called when a photo is captured
    public func onPhotoCapture(_ action: @escaping (UIImage) -> Void) -> Self {
        manager.onPhotoCapture = action
        return self
    }

    /// Called when video recording starts
    public func onVideoStarted(_ action: @escaping (URL) -> Void) -> Self {
        manager.onVideoStarted = action
        return self
    }

    /// Called when video recording stops
    public func onVideoStopped(_ action: @escaping (URL) -> Void) -> Self {
        manager.onVideoStopped = action
        return self
    }

    /// Called when camera position changes (front/back)
    public func onCameraPositionChanged(_ action: @escaping (AVCaptureDevice.Position) -> Void) -> Self {
        manager.onCameraPositionChanged = action
        return self
    }

    /// Called when zoom level changes
    public func onZoomChanged(_ action: @escaping (CGFloat) -> Void) -> Self {
        manager.onZoomChanged = action
        return self
    }

    /// Called when flash mode changes
    public func onFlashModeChanged(_ action: @escaping (AVCaptureDevice.FlashMode) -> Void) -> Self {
        manager.onFlashModeChanged = action
        return self
    }

    /// Called when an error occurs
    public func onError(_ action: @escaping (CameraError) -> Void) -> Self {
        manager.onError = action
        return self
    }
}

// MARK: - Configuration View Modifiers

extension AGCameraView {

    /// Enable/disable automatic permission handling
    public func handlePermissions(_ enabled: Bool) -> Self {
        manager.configuration.handlePermissions = enabled
        return self
    }

    /// Show/hide default camera controls
    public func showDefaultControls(_ show: Bool) -> Self {
        manager.configuration.showDefaultControls = show
        return self
    }

    /// Set video preview gravity mode
    public func videoGravity(_ gravity: AVLayerVideoGravity) -> Self {
        manager.configuration.videoGravity = gravity
        return self
    }

    /// Set default camera position (front/back)
    public func defaultCameraPosition(_ position: AVCaptureDevice.Position) -> Self {
        manager.configuration.defaultCameraPosition = position
        return self
    }

    /// Set default flash mode
    public func defaultFlashMode(_ mode: AVCaptureDevice.FlashMode) -> Self {
        manager.configuration.defaultFlashMode = mode
        return self
    }

    /// Set default zoom scale
    public func defaultZoomScale(_ scale: CGFloat) -> Self {
        manager.configuration.defaultZoomScale = scale
        return self
    }

    /// Set photo quality prioritization
    public func photoQuality(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) -> Self {
        manager.configuration.photoQualityPrioritization = prioritization
        return self
    }

    /// Set session preset for capture quality
    public func sessionPreset(_ preset: AVCaptureSession.Preset) -> Self {
        manager.configuration.sessionPreset = preset
        return self
    }

    /// Set video frame rate
    public func videoFrameRate(_ fps: Int32) -> Self {
        manager.configuration.videoFrameRate = fps
        return self
    }

    /// Customize the focus indicator view
    public func focusIndicator<V: View>(_ indicator: V) -> Self {
        manager.configuration.focusIndicator = AnyView(indicator)
        return self
    }
}
