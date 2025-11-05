import SwiftUI
import AVFoundation
import OSLog

public struct AGCameraView: View {
    private static let logger = Logger(subsystem: "com.agcamera", category: "CameraView")
    @Bindable var manager: AGCameraManager
    private let configuration: AGCameraConfiguration

    public var onPhotoCaptured: ((UIImage) -> Void)?
    public var onVideoRecordingStarted: ((URL) -> Void)?
    public var onVideoRecordingStopped: ((URL) -> Void)?
    public var onFlashModeChanged: ((AVCaptureDevice.FlashMode) -> Void)?
    public var onCameraPositionChanged: ((AVCaptureDevice.Position) -> Void)?
    public var onZoomChanged: ((CGFloat) -> Void)?
    public var onError: ((Error) -> Void)?

    @State private var showError = false
    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var focusTask: Task<Void, Never>?
    @State private var flipRotation: Double = 0
    @State private var isBlurred: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    public init(
        manager: AGCameraManager,
        configuration: AGCameraConfiguration = .default,
        onPhotoCaptured: ((UIImage) -> Void)? = nil,
        onVideoRecordingStarted: ((URL) -> Void)? = nil,
        onVideoRecordingStopped: ((URL) -> Void)? = nil,
        onFlashModeChanged: ((AVCaptureDevice.FlashMode) -> Void)? = nil,
        onCameraPositionChanged: ((AVCaptureDevice.Position) -> Void)? = nil,
        onZoomChanged: ((CGFloat) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.manager = manager
        self.configuration = configuration
        self.onPhotoCaptured = onPhotoCaptured
        self.onVideoRecordingStarted = onVideoRecordingStarted
        self.onVideoRecordingStopped = onVideoRecordingStopped
        self.onFlashModeChanged = onFlashModeChanged
        self.onCameraPositionChanged = onCameraPositionChanged
        self.onZoomChanged = onZoomChanged
        self.onError = onError
    }
    
    public var body: some View {
        ZStack {
            GeometryReader { previewGeometry in
                AGCameraPreview(
                    session: manager.getCaptureSession(),
                    videoGravity: configuration.videoGravity,
                    cameraPosition: manager.currentCameraPosition
                )
                .ignoresSafeArea()
                .onTapGesture { location in
                    handleTapToFocus(at: location, in: previewGeometry.size)
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            try? manager.updateZoomInteractively(scale: value, isGestureEnded: false)
                        }
                        .onEnded { value in
                            try? manager.updateZoomInteractively(scale: value, isGestureEnded: true)
                        }
                )
                .blur(radius: isBlurred ? 20 : 0)
                .rotation3DEffect(
                    .degrees(flipRotation),
                    axis: (x: 0, y: 1, z: 0)
                )
                .overlay {
                    if showFocusIndicator, let point = focusPoint {
                        configuration.focusIndicator
                            .position(point)
                            .allowsHitTesting(false)
                    }
                }
            }
            
            if configuration.showDefaultControls {
                VStack(spacing: 0) {
                    topControlsView
                    Spacer()
                    bottomControlsView
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: manager.capturedImage) { _, newValue in
            if let image = newValue {
                onPhotoCaptured?(image)
                manager.capturedImage = nil
            }
        }
        .onChange(of: manager.lastVideoURL) { oldValue, newValue in
            guard let url = newValue, oldValue != newValue else { return }

            if manager.isRecording {
                onVideoRecordingStarted?(url)
            } else {
                onVideoRecordingStopped?(url)
            }

            // Clear after handling so the same URL can trigger onChange again
            manager.lastVideoURL = nil
        }
        .onChange(of: manager.currentZoomFactor) { _, newValue in
            onZoomChanged?(newValue)
        }
        .onChange(of: manager.currentCameraPosition) { _, newValue in
            onCameraPositionChanged?(newValue)
        }
        .onChange(of: manager.flashMode) { _, newValue in
            onFlashModeChanged?(newValue)
        }
        .onChange(of: manager.error) { _, newValue in
            if let error = newValue {
                onError?(error)
                showError = true
            }
        }
        .task {
            if configuration.handlePermissions {
                let result = await manager.permissionManager.requestAllPermissions()
                if result.allGranted {
                    await setupCamera()
                } else {
                    showError = true
                }
            } else {
                await setupCamera()
            }
        }
        .onDisappear {
            manager.stopSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                manager.handleAppBackground()
            case .active:
                manager.handleAppForeground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(manager.error?.localizedDescription ?? "Unknown error")
        }
    }
}

// MARK: Default Controls
private extension AGCameraView {
    private var topControlsView: some View {
        HStack {
            Button {
                manager.toggleFlash()
            } label: {
                Image(systemName: manager.flashIconName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            if manager.isRecording {
                AGVideoDurationView(duration: manager.formattedRecordingDuration)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else {
                Spacer()
            }

            Button {
                try? manager.setSessionPreset(.hd4K3840x2160)
            } label: {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
        .padding()
    }
    
    private var bottomControlsView: some View {
        VStack(spacing: 30) {
            zoomButton
            
            switch manager.outputType {
            case .photo:
                capturePhotoButton
            case .video:
                captureVideoButton
            }
            
            HStack(spacing: 30) {
                Circle().frame(width: 50, height: 50)
                AGInputPickerButton(outputType: $manager.outputType)
                switchCameraButton
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 30)
    }
    
    private var zoomButton: some View {
        AGSZoomControlView(manager: manager) { newZoomLevel in
            do {
                try manager.setZoom(factor: newZoomLevel)
            } catch {
                Self.logger.error("Zoom error: \(error.localizedDescription)")
                showError = true
            }
        }
    }
    
    private var capturePhotoButton: some View {
        AGCapturePhotoButton {
            do {
                _ = try await manager.capturePhoto()
            } catch {
                showError = true
            }
        }
    }
    
    private var captureVideoButton: some View {
        AGCaptureVideoButton(isRecording: manager.isRecording) {
            do {
                if manager.isRecording {
                    _ = try await manager.stopVideoRecording()
                } else {
                    _ = try await manager.startVideoRecording()
                }
            } catch {
                showError = true
            }
        }
    }
    
    private var switchCameraButton: some View {
        AGSwitchCameraButton {
            let flipDirection: Double = manager.currentCameraPosition == .back ? 180 : -180

            withAnimation(.easeOut(duration: 0.1)) {
                isBlurred = true
            }

            withAnimation(.easeInOut(duration: 0.5)) {
                flipRotation += flipDirection
            }

            try? await Task.sleep(nanoseconds: 250_000_000)

            try? await manager.switchCamera()
            onCameraPositionChanged?(manager.currentCameraPosition)

            try? await Task.sleep(nanoseconds: 100_000_000)

            withAnimation(.easeIn(duration: 0.15)) {
                isBlurred = false
            }
        }
    }
}

// MARK: Useful Methods
private extension AGCameraView {
    private func setupCamera() async {
        do {
            try await manager.setupSession()
            manager.startSession()

            Self.logger.info("Camera Info - Min Zoom: \(String(format: "%.1f", manager.minZoomFactor))×, Max Zoom: \(String(format: "%.1f", manager.maxZoomFactor))×, Current Zoom: \(String(format: "%.1f", manager.currentZoomFactor))×")
        } catch {
            showError = true
        }
    }

    private func handleTapToFocus(at location: CGPoint, in viewSize: CGSize) {
        focusTask?.cancel()

        focusPoint = location
        showFocusIndicator = true

        let normalizedPoint = CGPoint(
            x: location.x / viewSize.width,
            y: location.y / viewSize.height
        )

        try? manager.setFocusAndExposure(at: normalizedPoint)

        focusTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                showFocusIndicator = false
            }
        }
    }
}

#Preview {
    @Previewable let cameraManager = AGCameraManager()
    AGCameraView(manager: cameraManager)
}
