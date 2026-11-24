import SwiftUI
import AVFoundation

public struct AGCameraView: View {
    @Bindable var manager: AGCameraManager
    var configurationOverrides: [(inout AGCameraConfiguration) -> Void] = []
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
    @State private var zoomTask: Task<Void, Never>?

    @Environment(\.scenePhase) private var scenePhase

    var configuration: AGCameraConfiguration {
        var result = manager.configuration
        for apply in configurationOverrides { apply(&result) }
        return result
    }

    private var displayedConfiguration: AGCameraConfiguration {
        configuration
    }

    public init(manager: AGCameraManager) {
        self.manager = manager
    }

    private var tapToFocusHandler: ((CGPoint, CGPoint) -> Void)? {
        guard displayedConfiguration.tapToFocusBehavior != .none else { return nil }
        return { location, devicePoint in
            handleTapToFocus(at: location, devicePoint: devicePoint)
        }
    }
    
    public var body: some View {
        ZStack {
            cameraPreview

            if displayedConfiguration.showDefaultControls {
                VStack(spacing: 0) {
                    topControlsView
                    Spacer()
                    bottomControlsView
                }
                .disabled(manager.isSwitchingCamera)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: manager.capturedImage) { _, newValue in
            if let image = newValue {
                photoCaptureAction?(image)
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
            let initialConfiguration = configuration
            manager.configuration = initialConfiguration
            manager.setLoggingEnabled(initialConfiguration.enableLogging)
            manager.setFlashMode(initialConfiguration.defaultFlashMode)
            manager.setViewActive(scenePhase == .active)
            if initialConfiguration.handlePermissions {
                guard await manager.permissionManager.requestCameraPermission() else {
                    present(CameraError.permissionDenied)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await setupCamera()
        }
        .onDisappear {
            zoomTask?.cancel()
            focusTask?.cancel()
            manager.handleAppBackground()
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
            isSessionConfigured: manager.isSessionConfigured,
            isSessionRunning: manager.isSessionRunning,
            videoGravity: displayedConfiguration.videoGravity,
            cameraPosition: manager.currentCameraPosition,
            mirrorFrontCamera: displayedConfiguration.mirrorFrontCamera,
            log: manager.log,
            loggingEnabled: displayedConfiguration.enableLogging,
            onTapToFocus: tapToFocusHandler
        )
        .ignoresSafeArea()
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoomTask?.cancel()
                    zoomTask = Task {
                        try? await manager.updateZoomInteractively(scale: value.magnification, isGestureEnded: false)
                    }
                }
                .onEnded { value in
                    zoomTask?.cancel()
                    zoomTask = Task {
                        try? await manager.updateZoomInteractively(scale: value.magnification, isGestureEnded: true)
                    }
                }
        )
        .overlay { transitionSnapshotOverlay }
        .overlay {
            Color.black
                .opacity(manager.isSwitchingCamera ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay { AGCameraGridOverlay(grid: displayedConfiguration.grid) }
        .overlay { focusIndicatorOverlay }
    }

    @ViewBuilder
    private var focusIndicatorOverlay: some View {
        if showFocusIndicator, let point = focusPoint {
            displayedConfiguration.focusIndicator
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
            Task {
                do {
                    try await manager.setZoom(factor: newZoomLevel)
                } catch {
                    manager.log.error("Zoom error: \(error.localizedDescription)", category: "CameraView")
                    present(error)
                }
            }
        }
        .disabled(!manager.isSessionRunning)
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
        .disabled(!manager.isSessionRunning)
        .opacity(manager.isSessionRunning ? 1 : 0)
    }
}

// MARK: Useful Methods
private extension AGCameraView {
    private func setupCamera() async {
        do {
            try await manager.setupSession()
            guard !Task.isCancelled else { return }
            manager.log.info("Camera Info - Min Zoom: \(String(format: "%.1f", manager.minZoomFactor))×, Max Zoom: \(String(format: "%.1f", manager.maxZoomFactor))×, Current Zoom: \(String(format: "%.1f", manager.currentZoomFactor))×", category: "CameraView")
            manager.startSessionIfViewActive()
        } catch {
            present(error)
        }
    }

    private func handleTapToFocus(at location: CGPoint, devicePoint: CGPoint) {
        focusTask?.cancel()
        let behavior = displayedConfiguration.tapToFocusBehavior
        Task {
            do {
                switch behavior {
                case .none:
                    return
                case .focusOnly:
                    try await manager.setFocus(at: devicePoint)
                case .focusAndExposure:
                    try await manager.setFocusAndExposure(at: devicePoint)
                }
                focusPoint = location
                showFocusIndicator = true
                focusTask = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    withAnimation { showFocusIndicator = false }
                }
            } catch {
                present(error)
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
