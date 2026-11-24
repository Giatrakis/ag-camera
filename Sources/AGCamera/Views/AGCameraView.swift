import SwiftUI
import AVFoundation
import OSLog

public struct AGCameraView: View {
    private static let logger = Logger(subsystem: "com.agcamera", category: "CameraView")
    @Bindable var manager: AGCameraManager
    var configuration: AGCameraConfiguration
    var photoCaptureAction: ((UIImage) -> Void)?
    var videoStartedAction: ((URL) -> Void)?
    var videoStoppedAction: ((URL) -> Void)?
    var cameraPositionChangedAction: ((AVCaptureDevice.Position) -> Void)?
    var zoomChangedAction: ((CGFloat) -> Void)?
    var flashModeChangedAction: ((AVCaptureDevice.FlashMode) -> Void)?
    var errorAction: ((CameraError) -> Void)?

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var focusTask: Task<Void, Never>?

    @Environment(\.scenePhase) private var scenePhase

    public init(manager: AGCameraManager) {
        self.manager = manager
        self.configuration = manager.configuration
    }

    private var tapToFocusHandler: ((CGPoint, CGPoint) -> Void)? {
        guard configuration.enableTapToFocus else { return nil }
        return { location, devicePoint in
            handleTapToFocus(at: location, devicePoint: devicePoint)
        }
    }
    
    public var body: some View {
        ZStack {
            cameraPreview

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
                photoCaptureAction?(image)
                manager.capturedImage = nil
            }
        }
        .onChange(of: manager.lastStartedVideoURL) { oldValue, newValue in
            guard let url = newValue, oldValue != newValue else { return }
            videoStartedAction?(url)
        }
        .onChange(of: manager.lastStoppedVideoURL) { oldValue, newValue in
            guard let url = newValue, oldValue != newValue else { return }
            videoStoppedAction?(url)
        }
        .onChange(of: manager.currentZoomFactor) { _, newValue in
            zoomChangedAction?(newValue)
        }
        .onChange(of: manager.currentCameraPosition) { _, newValue in
            cameraPositionChangedAction?(newValue)
        }
        .onChange(of: manager.flashMode) { _, newValue in
            flashModeChangedAction?(newValue)
        }
        .onChange(of: manager.error) { _, newValue in
            if let error = newValue {
                errorAction?(error)
                present(error)
            }
        }
        .task {
            manager.configuration = configuration
            manager.setFlashMode(configuration.defaultFlashMode)
            if configuration.handlePermissions {
                guard await manager.permissionManager.requestCameraPermission() else {
                    present(CameraError.permissionDenied)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await setupCamera()
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
        .alert("Camera Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var cameraPreview: some View {
        AGCameraPreview(
            session: manager.getCaptureSession(),
            videoGravity: configuration.videoGravity,
            cameraPosition: manager.currentCameraPosition,
            onTapToFocus: tapToFocusHandler
        )
        .ignoresSafeArea()
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    try? manager.updateZoomInteractively(scale: value.magnification, isGestureEnded: false)
                }
                .onEnded { value in
                    try? manager.updateZoomInteractively(scale: value.magnification, isGestureEnded: true)
                }
        )
        .overlay { transitionSnapshotOverlay }
        .blur(radius: manager.isBlurred ? 50 : 0)
        .overlay { focusIndicatorOverlay }
    }

    @ViewBuilder
    private var focusIndicatorOverlay: some View {
        if showFocusIndicator, let point = focusPoint {
            configuration.focusIndicator
                .position(point)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var transitionSnapshotOverlay: some View {
        if let snapshot = manager.transitionSnapshot {
            Image(uiImage: snapshot)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
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
                present(error)
            }
        }
    }
    
    private var capturePhotoButton: some View {
        AGCapturePhotoButton {
            do {
                _ = try await manager.capturePhoto()
            } catch {
                present(error)
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
                present(error)
            }
        }
    }
    
    private var switchCameraButton: some View {
        AGSwitchCameraButton {
            do {
                try await manager.switchCamera()
            } catch {
                present(error)
            }
        }
    }
}

// MARK: Useful Methods
private extension AGCameraView {
    private func setupCamera() async {
        do {
            try await manager.setupSession()
            guard !Task.isCancelled else { return }
            manager.startSession()

            Self.logger.info("Camera Info - Min Zoom: \(String(format: "%.1f", manager.minZoomFactor))×, Max Zoom: \(String(format: "%.1f", manager.maxZoomFactor))×, Current Zoom: \(String(format: "%.1f", manager.currentZoomFactor))×")
        } catch {
            present(error)
        }
    }

    private func handleTapToFocus(at location: CGPoint, devicePoint: CGPoint) {
        focusTask?.cancel()

        focusPoint = location
        showFocusIndicator = true

        do {
            try manager.setFocusAndExposure(at: devicePoint)
        } catch {
            present(error)
        }

        focusTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                showFocusIndicator = false
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

#Preview {
    @Previewable let cameraManager = AGCameraManager()
    AGCameraView(manager: cameraManager)
        .defaultCameraPosition(.back)
        .defaultFlashMode(.auto)
        .defaultZoomScale(2.0)
        .showDefaultControls(true)
        .handlePermissions(true)
        .onPhotoCapture { image in
            print("Photo captured: \(image.size)")
        }
        .onVideoStopped { url in
            print("Video saved to: \(url)")
        }
        .onError { error in
            print("Camera error: \(error.localizedDescription)")
        }
}
