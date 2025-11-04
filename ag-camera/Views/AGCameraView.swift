//
//  AGCameraView.swift
//  ag-camera
//
//  SwiftUI demo view showing how to use the camera library with custom buttons
//

import SwiftUI
import AVFoundation
import OSLog

public struct AGCameraView: View {
    enum UI {
        static let captureButtonOuterSize: CGFloat = 70
        static let captureButtonInnerSize: CGFloat = 60
        static let captureButtonBorderWidth: CGFloat = 4
        static let videoRecordingButtonSize: CGFloat = 50
        static let videoRecordingStopIconSize: CGFloat = 20
        static let videoRecordingStopCornerRadius: CGFloat = 4
        static let controlButtonSize: CGFloat = 12
        static let controlButtonBackgroundSize: CGFloat = 16
        static let zoomButtonWidth: CGFloat = 44
        static let zoomButtonHeight: CGFloat = 32
        static let recordingDotSize: CGFloat = 12
        static let focusIndicatorSize: CGFloat = 80
        static let focusIndicatorCornerRadius: CGFloat = 4
        static let focusIndicatorBorderWidth: CGFloat = 2
        static let zoomSpacing: CGFloat = 15
        static let controlSpacing: CGFloat = 40
    }

    private static let logger = Logger(subsystem: "com.agcamera", category: "CameraView")
    @State private var permissionManager = AGPermissionManager()
    @State private var cameraManager: AGCameraManager?
    @State private var capturedImage: UIImage?
    @State private var showImagePreview = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Focus indicator state
    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var focusTask: Task<Void, Never>?

    // Zoom state
    @State private var currentZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0

    // Camera flip animation
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    @State private var flipRotation: Double = 0
    @State private var isBlurred: Bool = false
    
    @Environment(\.scenePhase) private var scenePhase

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let cameraManager = cameraManager {
                    AGCameraPreview(
                        session: cameraManager.getCaptureSession(),
                        cameraPosition: cameraPosition
                    )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .onTapGesture { location in
                            handleTapToFocus(at: location, in: geometry.size)
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    handleZoom(scale: value)
                                }
                                .onEnded { _ in
                                    lastZoom = currentZoom
                                }
                        )
                        .blur(radius: isBlurred ? 20 : 0)
                        .rotation3DEffect(
                            .degrees(flipRotation),
                            axis: (x: 0, y: 1, z: 0)
                        )
                } else {
                    Color.black.ignoresSafeArea()
                }

                if showFocusIndicator, let point = focusPoint {
                    FocusIndicatorView()
                        .position(point)
                        .allowsHitTesting(false)
                }

                VStack {
                    topBar
                        .padding()

                    Spacer()

                    // Recording timer (when recording)
                    if let manager = cameraManager, manager.isRecording {
                        recordingTimer
                            .padding(.top, 20)
                    }

                    // Zoom level indicator (always visible)
                    if cameraManager != nil {
                        zoomIndicator
                            .padding(.bottom, 10)
                    }

                    // Zoom buttons (like Apple)
                    if cameraManager != nil {
                        zoomButtons
                            .padding(.bottom, 20)
                            .id(cameraPosition) // Force re-render when camera switches
                    }

                    // Bottom bar with capture controls
                    bottomBar
                        .padding()
                }
            }
        }
        .task {
            await setupCamera()
        }
        .onDisappear {
            cameraManager?.stopSession()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showImagePreview) {
            if let image = capturedImage {
                ImagePreviewView(image: image, onDismiss: {
                    showImagePreview = false
                    capturedImage = nil
                })
            }
        }
    }

    private var topBar: some View {
        HStack {
            // Flash button
            Button(action: {
                cameraManager?.toggleFlash()
            }) {
                Image(systemName: flashIcon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(UI.controlButtonSize)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            Spacer()

            // Settings button (example)
            Button(action: {
                // Custom action - change resolution
                try? cameraManager?.setSessionPreset(.hd4K3840x2160)
            }) {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(UI.controlButtonSize)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: UI.controlSpacing) {
            // Switch camera button
            Button(action: {
                Task {
                    await switchCameraWithAnimation()
                }
            }) {
                Image(systemName: "camera.rotate")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding(UI.controlButtonBackgroundSize)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            // Capture photo button (custom design)
            Button(action: {
                Task {
                    await capturePhoto()
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: UI.captureButtonBorderWidth)
                        .frame(width: UI.captureButtonOuterSize, height: UI.captureButtonOuterSize)

                    Circle()
                        .fill(Color.white)
                        .frame(width: UI.captureButtonInnerSize, height: UI.captureButtonInnerSize)
                }
            }

            // Video recording button (custom design)
            Button(action: {
                Task {
                    await toggleVideoRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(cameraManager?.isRecording == true ? Color.red : Color.white.opacity(0.8))
                        .frame(width: UI.videoRecordingButtonSize, height: UI.videoRecordingButtonSize)

                    if cameraManager?.isRecording == true {
                        RoundedRectangle(cornerRadius: UI.videoRecordingStopCornerRadius)
                            .fill(Color.white)
                            .frame(width: UI.videoRecordingStopIconSize, height: UI.videoRecordingStopIconSize)
                    }
                }
            }
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: UI.zoomSpacing) {
            // Get current camera's zoom capabilities
            let minZoom = cameraManager?.minZoomFactor ?? 1.0
            let maxZoom = cameraManager?.maxZoomFactor ?? 1.0

            // Only show 0.5× if device actually supports it (ultra-wide lens)
            // Front camera typically doesn't have this
            if minZoom <= 0.5 && maxZoom >= 0.5 && cameraPosition == .back {
                ZoomButton(level: 0.5, currentZoom: currentZoom) {
                    setZoom(to: 0.5)
                }
            }

            // Always show 1.0×
            ZoomButton(level: 1.0, currentZoom: currentZoom) {
                setZoom(to: 1.0)
            }

            // Only show 2× if device supports it
            if maxZoom >= 2.0 {
                ZoomButton(level: 2.0, currentZoom: currentZoom) {
                    setZoom(to: 2.0)
                }
            }

            // Show 3× if device supports it
            if maxZoom >= 3.0 {
                ZoomButton(level: 3.0, currentZoom: currentZoom) {
                    setZoom(to: 3.0)
                }
            }

            // Show 5× if device supports it (typically only back camera)
            if maxZoom >= 5.0 {
                ZoomButton(level: 5.0, currentZoom: currentZoom) {
                    setZoom(to: 5.0)
                }
            }
        }
    }

    private var zoomIndicator: some View {
        Text(String(format: "%.1f×", currentZoom))
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
    }

    private var recordingTimer: some View {
        HStack(spacing: 8) {
            // Red recording dot (pulsing)
            RecordingDot()

            // Time display
            Text(formatRecordingDuration(cameraManager?.recordingDuration ?? 0))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .monospacedDigit() // Prevents width changes as numbers update
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
        )
    }

    /// Format recording duration as MM:SS
    private func formatRecordingDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var flashIcon: String {
        guard let flashMode = cameraManager?.flashMode else { return "bolt.slash" }

        switch flashMode {
        case .off:
            return "bolt.slash"
        case .on:
            return "bolt.fill"
        case .auto:
            return "bolt.badge.automatic"
        @unknown default:
            return "bolt.slash"
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() async {
        // Request permissions
        let result = await permissionManager.requestAllPermissions()

        guard result.camera else {
            errorMessage = "Camera permission is required"
            showError = true
            return
        }

        // Initialize camera manager
        let manager = AGCameraManager(permissionManager: permissionManager)
        cameraManager = manager

        do {
            // Setup and start session
            try await manager.setupSession()
            manager.startSession()

            // Initialize camera position state
            cameraPosition = manager.currentCameraPosition

            // Initialize zoom state to match manager's current zoom (UI zoom)
            currentZoom = manager.currentZoomFactor
            lastZoom = manager.currentZoomFactor

            // Log zoom capabilities (now showing UI zoom values)
            Self.logger.info("Camera Info - Min Zoom: \(String(format: "%.1f", manager.minZoomFactor))×, Max Zoom: \(String(format: "%.1f", manager.maxZoomFactor))×, Current Zoom: \(String(format: "%.1f", manager.currentZoomFactor))×")
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Camera Actions (Custom button handlers)

    /// Example: Custom photo capture handler
    private func capturePhoto() async {
        guard let cameraManager = cameraManager else { return }

        do {
            let imageData = try await cameraManager.capturePhoto()

            // Convert to UIImage
            if let image = UIImage(data: imageData) {
                capturedImage = image
                showImagePreview = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Example: Custom video recording toggle handler
    private func toggleVideoRecording() async {
        guard let cameraManager = cameraManager else { return }

        if cameraManager.isRecording {
            // Stop recording
            cameraManager.stopVideoRecording()
        } else {
            // Start recording
            do {
                let videoURL = try await cameraManager.startVideoRecording()
                Self.logger.info("Video saved to: \(videoURL)")
                // You can now save to photo library or process the video
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// Example: Tap to focus handler
    private func handleTapToFocus(at location: CGPoint, in viewSize: CGSize) {
        // Cancel previous focus task if any
        focusTask?.cancel()

        // Show focus indicator at tap location
        focusPoint = location
        showFocusIndicator = true

        // Convert tap location to normalized coordinates (0-1)
        let normalizedPoint = CGPoint(
            x: location.x / viewSize.width,
            y: location.y / viewSize.height
        )

        try? cameraManager?.setFocusAndExposure(at: normalizedPoint)

        // Hide indicator after 1 second
        focusTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                showFocusIndicator = false
            }
        }
    }

    /// Handle pinch to zoom gesture
    private func handleZoom(scale: CGFloat) {
        guard let cameraManager = cameraManager else { return }

        let newZoom = lastZoom * scale

        // Get actual camera capabilities (updates when camera switches)
        let maxZoom = cameraManager.maxZoomFactor
        let minZoom = cameraManager.minZoomFactor

        // Clamp zoom between min and max for current camera
        let clampedZoom = min(max(newZoom, minZoom), maxZoom)
        currentZoom = clampedZoom

        // Apply zoom immediately
        do {
            try cameraManager.setZoom(factor: clampedZoom)
        } catch {
            Self.logger.error("Zoom error: \(error.localizedDescription)")
        }
    }

    /// Set zoom to specific level with smooth animation
    private func setZoom(to level: CGFloat) {
        guard let cameraManager = cameraManager else { return }

        // Animate UI state
        withAnimation(.easeInOut(duration: 0.25)) {
            currentZoom = level
            lastZoom = level
        }

        // Apply zoom directly - let AVFoundation handle smoothing
        do {
            try cameraManager.setZoom(factor: level)
        } catch {
            Self.logger.error("Zoom error: \(error.localizedDescription)")
            errorMessage = "Failed to zoom: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Switch camera with flip animation (like Apple Camera app)
    private func switchCameraWithAnimation() async {
        guard let cameraManager = cameraManager else { return }

        // Determine flip direction based on current camera
        // Back camera: flip right (+180), Front camera: flip left (-180)
        let flipDirection: Double = cameraPosition == .back ? 180 : -180

        // Apply blur immediately
        withAnimation(.easeOut(duration: 0.1)) {
            isBlurred = true
        }

        // Start flip animation with blur visible
        withAnimation(.easeInOut(duration: 0.5)) {
            flipRotation += flipDirection
        }

        // Wait for halfway through animation (when view is edge-on)
        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds

        // Switch the actual camera at the midpoint
        try? await cameraManager.switchCamera()

        // Update local camera position state
        cameraPosition = cameraManager.currentCameraPosition

        // Reset zoom to 1.0× when switching cameras
        currentZoom = 1.0
        lastZoom = 1.0
        try? cameraManager.setZoom(factor: 1.0)

        // Wait a bit more for camera to stabilize
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Remove blur to reveal new camera
        withAnimation(.easeIn(duration: 0.15)) {
            isBlurred = false
        }
    }

    /// Ease-in-out function for smooth animation
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    // MARK: - App Lifecycle

    /// Handle app moving to background/foreground (SwiftUI way)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard let cameraManager = cameraManager else { return }

        switch newPhase {
        case .background:
            // App moved to background
            cameraManager.handleAppBackground()

        case .active:
            // App became active
            cameraManager.handleAppForeground()

        case .inactive:
            // App becoming inactive (e.g., during phone call) - keep session running
            break

        @unknown default:
            break
        }
    }
}

// MARK: - Image Preview View

private struct ImagePreviewView: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            onDismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Zoom Button View

private struct ZoomButton: View {
    let level: CGFloat
    let currentZoom: CGFloat
    let action: () -> Void

    private var isActive: Bool {
        abs(currentZoom - level) < 0.1
    }

    private var displayText: String {
        if level < 1.0 {
            return "\(level)×"
        } else {
            return "\(Int(level))×"
        }
    }

    var body: some View {
        Button(action: action) {
            Text(displayText)
                .font(.body)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? .black : .white)
                .frame(width: AGCameraView.UI.zoomButtonWidth, height: AGCameraView.UI.zoomButtonHeight)
                .background(
                    Capsule()
                        .fill(isActive ? Color.yellow : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.clear : Color.white.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

// MARK: - Focus Indicator View

private struct FocusIndicatorView: View {
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: AGCameraView.UI.focusIndicatorCornerRadius)
            .stroke(Color.yellow, lineWidth: AGCameraView.UI.focusIndicatorBorderWidth)
            .frame(width: AGCameraView.UI.focusIndicatorSize, height: AGCameraView.UI.focusIndicatorSize)
            .scaleEffect(animate ? 1.0 : 0.8)
            .opacity(animate ? 1.0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
                    animate = true
                }
            }
    }
}

// MARK: - Recording Dot View

private struct RecordingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: AGCameraView.UI.recordingDotSize, height: AGCameraView.UI.recordingDotSize)
            .opacity(isPulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    AGCameraView()
}
