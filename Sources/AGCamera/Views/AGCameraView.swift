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
    @State private var focusRequestID = UUID()
    @State private var showFocusIndicator = false
    @State private var focusTask: Task<Void, Never>?
    @State private var exposureTask: Task<Void, Never>?
    @State private var exposureDragStartBias: Float?
    @State private var pendingExposureBias: Float?
    @State private var displayedExposureBias: Float = 0
    @State private var zoomTask: Task<Void, Never>?
    @State private var visibleVideoRect = CGRect.zero

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
            focusRequestID = UUID()
            focusTask?.cancel()
            exposureTask?.cancel()
            pendingExposureBias = nil
            exposureDragStartBias = nil
            showFocusIndicator = false
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
            focusRequestID = UUID()
            zoomTask?.cancel()
            focusTask?.cancel()
            exposureTask?.cancel()
            pendingExposureBias = nil
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
            onTapToFocus: tapToFocusHandler,
            onVideoRectChanged: { rect in
                Task { @MainActor in
                    if visibleVideoRect != rect {
                        visibleVideoRect = rect
                    }
                }
            }
        )
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged(handleExposureDragChanged)
                .onEnded { _ in
                    guard exposureDragStartBias != nil else { return }
                    exposureDragStartBias = nil
                    scheduleFocusIndicatorDismissal()
                }
        )
        .overlay { transitionSnapshotOverlay }
        .overlay {
            Color.black
                .opacity(manager.isSwitchingCamera ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            AGCameraGridOverlay(grid: displayedConfiguration.grid)
                .frame(width: visibleVideoRect.width, height: visibleVideoRect.height)
                .offset(x: visibleVideoRect.minX, y: visibleVideoRect.minY)
        }
        .overlay(alignment: .topLeading) { focusIndicatorOverlay }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var focusIndicatorOverlay: some View {
        if showFocusIndicator, let point = focusPoint, !visibleVideoRect.isEmpty {
            ZStack {
                displayedConfiguration.focusIndicator
                    .position(
                        x: point.x - visibleVideoRect.minX,
                        y: point.y - visibleVideoRect.minY
                    )

                if displayedConfiguration.tapToFocusBehavior == .focusAndExposure,
                   manager.maxExposureBias > manager.minExposureBias {
                    Capsule()
                        .fill(.yellow.opacity(0.8))
                        .frame(width: 1, height: 70)
                        .position(x: exposureSunX(for: point), y: point.y - visibleVideoRect.minY)

                    Image(systemName: "sun.max.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                        .position(x: exposureSunX(for: point), y: exposureSunY(for: point))
                }
            }
            .frame(width: visibleVideoRect.width, height: visibleVideoRect.height)
            .clipped()
            .offset(x: visibleVideoRect.minX, y: visibleVideoRect.minY)
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
            .padding(.horizontal)
        }
        .padding(.bottom, 30)
    }
    
    private var zoomButton: some View {
        AGSZoomControlView(manager: manager) { newZoomLevel in
            zoomTask?.cancel()
            zoomTask = Task {
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
        .disabled(manager.isPreparingVideoRecording)
    }
    
    private var switchCameraButton: some View {
        AGSwitchCameraButton {
            do {
                try await manager.switchCamera()
            } catch {
                present(error)
            }
        }
        .disabled(!manager.isSessionRunning || manager.isPreparingVideoRecording)
        .opacity(manager.isSessionRunning ? 1 : 0)
    }
}

// MARK: Useful Methods
private extension AGCameraView {
    private func setupCamera() async {
        guard !manager.isSessionConfigured else { return }
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
        let requestID = UUID()
        focusRequestID = requestID
        focusTask?.cancel()
        let previousExposureTask = exposureTask
        exposureTask?.cancel()
        exposureTask = nil
        pendingExposureBias = nil
        exposureDragStartBias = nil
        showFocusIndicator = false
        let behavior = displayedConfiguration.tapToFocusBehavior
        Task {
            await previousExposureTask?.value
            guard focusRequestID == requestID, !manager.isSwitchingCamera else { return }
            do {
                switch behavior {
                case .none:
                    return
                case .focusOnly:
                    try await manager.setFocus(at: devicePoint)
                case .focusAndExposure:
                    try await manager.focusAndResetExposure(at: devicePoint)
                }
                guard focusRequestID == requestID, !manager.isSwitchingCamera else { return }
                focusPoint = location
                displayedExposureBias = manager.currentExposureBias
                showFocusIndicator = true
                scheduleFocusIndicatorDismissal()
            } catch {
                present(error)
            }
        }
    }

    private func handleExposureDragChanged(_ value: DragGesture.Value) {
        guard manager.isSessionRunning, !manager.isSwitchingCamera,
              displayedConfiguration.tapToFocusBehavior == .focusAndExposure,
              showFocusIndicator, focusPoint != nil,
              visibleVideoRect.contains(value.startLocation),
              manager.maxExposureBias > manager.minExposureBias else { return }

        if exposureDragStartBias == nil {
            exposureDragStartBias = manager.currentExposureBias
            focusTask?.cancel()
        }
        guard let startBias = exposureDragStartBias else { return }
        let requestedBias = startBias - Float(value.translation.height / 120)
        let clampedBias = min(max(requestedBias, manager.minExposureBias), manager.maxExposureBias)
        guard abs(clampedBias - displayedExposureBias) >= 0.01 else { return }
        displayedExposureBias = clampedBias
        pendingExposureBias = clampedBias
        guard exposureTask == nil else { return }
        exposureTask = Task {
            while let bias = pendingExposureBias, !Task.isCancelled {
                pendingExposureBias = nil
                do {
                    try await manager.setExposureBias(bias)
                } catch {
                    present(error)
                    break
                }
            }
            exposureTask = nil
        }
    }

    private func scheduleFocusIndicatorDismissal() {
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showFocusIndicator = false }
        }
    }

    private func exposureSunX(for point: CGPoint) -> CGFloat {
        let localX = point.x - visibleVideoRect.minX
        let proposedX = localX + (localX + 70 < visibleVideoRect.width ? 60 : -60)
        return min(max(proposedX, 18), visibleVideoRect.width - 18)
    }

    private func exposureSunY(for point: CGPoint) -> CGFloat {
        let localY = point.y - visibleVideoRect.minY
        let maximumMagnitude = max(abs(manager.minExposureBias), abs(manager.maxExposureBias))
        let offset = maximumMagnitude > 0 ? CGFloat(displayedExposureBias / maximumMagnitude) * 28 : 0
        return min(max(localY - offset, 18), visibleVideoRect.height - 18)
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
