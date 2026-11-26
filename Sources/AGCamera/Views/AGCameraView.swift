import SwiftUI
import AVFoundation

public struct AGCameraView: View {
    @Bindable var manager: AGCameraManager
    var configurationOverrides: [(inout AGCameraConfiguration) -> Void] = []
    var photoCaptureAction: ((UIImage) -> Void)?
    var livePhotoCaptureAction: ((AGLivePhotoCapture) -> Void)?
    var videoStartedAction: ((URL) -> Void)?
    var videoStoppedAction: ((URL) -> Void)?
    var cameraPositionChangedAction: ((AVCaptureDevice.Position) -> Void)?
    var zoomChangedAction: ((CGFloat) -> Void)?
    var flashModeChangedAction: ((AVCaptureDevice.FlashMode) -> Void)?
    var errorAction: ((CameraError) -> Void)?
    var galleryAction: (() -> Void)?
    var galleryThumbnail: UIImage?
    var styleControlsAction: (() -> Void)?
    var moreControlsAction: (() -> Void)?
    var exposureBiasBinding: Binding<Float>?

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
    @State private var statusToast: AGCameraStatusToast?
    @State private var isChangingLivePhotoMode = false
    @State private var recentCapture: AGRecentCapture?
    @State private var presentedRecentCapture: AGRecentCapture?
    @State private var isMoreControlsPresented = false
    @State private var isMoreControlsDetailPresented = false
    @State private var isModePickerExpanded = false
    @State private var shouldOpenStyleControlsAfterDismiss = false
    @Namespace private var moreControlsNamespace

    @Environment(\.scenePhase) private var scenePhase

    var configuration: AGCameraConfiguration {
        var result = manager.configuration
        for apply in configurationOverrides { apply(&result) }
        return result
    }

    private var displayedConfiguration: AGCameraConfiguration {
        configuration
    }

    private var flashModeTitle: String {
        switch manager.flashMode {
        case .off: "Off"
        case .auto: "Auto"
        case .on: "On"
        @unknown default: "Off"
        }
    }

    private var previewVerticalOffset: CGFloat {
        guard displayedConfiguration.showDefaultControls else { return 0 }
        let croppedPhoto = manager.outputType == .photo && manager.photoAspectRatio != .fourThree
        if croppedPhoto { return 36 }
        return displayedConfiguration.videoGravity == .resizeAspect ? 55 : 0
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
        cameraLifecycle
            .alert("Camera Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $presentedRecentCapture) { capture in
                AGRecentCaptureView(capture: capture)
            }
            .sheet(isPresented: $isMoreControlsPresented, onDismiss: {
                isMoreControlsDetailPresented = false
                if shouldOpenStyleControlsAfterDismiss {
                    shouldOpenStyleControlsAfterDismiss = false
                    styleControlsAction?()
                }
            }) {
                AGCameraMoreControlsView(
                    isDetailPresented: $isMoreControlsDetailPresented,
                    manager: manager,
                    onFlashSelected: selectFlash,
                    onLiveSelected: selectLivePhoto,
                    onAspectSelected: selectPhotoAspectRatio
                )
                .navigationTransition(.zoom(sourceID: "moreControls", in: moreControlsNamespace))
                .presentationBackgroundInteraction(.enabled)
                .agCameraControlsSheetBackground()
            }
    }

    private var cameraLayout: some View {
        ZStack {
            GeometryReader { geometry in
                let cropPreview = manager.outputType == .photo && manager.photoAspectRatio != .fourThree
                let isLandscape = geometry.size.width > geometry.size.height
                let frameWidth = cropPreview && isLandscape
                    ? min(geometry.size.width, geometry.size.height * manager.photoAspectRatio.landscapeRatio)
                    : geometry.size.width
                let frameHeight = cropPreview && !isLandscape
                    ? min(geometry.size.height, geometry.size.width * manager.photoAspectRatio.landscapeRatio)
                    : geometry.size.height
                cameraPreview
                    .frame(width: frameWidth, height: frameHeight)
                    .clipped()
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2 - previewVerticalOffset
                    )
            }

            if isMoreControlsPresented {
                Button {
                    isMoreControlsPresented = false
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss camera controls")
            }

            if displayedConfiguration.showDefaultControls {
                VStack(spacing: 0) {
                    topControlsView
                    Spacer()
                    bottomControlsView
                        .disabled(manager.isSwitchingCamera)
                        .opacity(isMoreControlsPresented && !isMoreControlsDetailPresented ? 0 : 1)
                        .allowsHitTesting(!isMoreControlsPresented || isMoreControlsDetailPresented)
                        .accessibilityHidden(isMoreControlsPresented && !isMoreControlsDetailPresented)
                        .animation(.easeOut(duration: 0.16), value: isMoreControlsPresented)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var cameraEvents: some View {
        cameraLayout
        .onChange(of: manager.capturedImage) { _, newValue in
            if let image = newValue {
                recentCapture = AGRecentCapture(content: .photo(image), thumbnail: image)
                photoCaptureAction?(image)
            }
        }
        .onChange(of: manager.lastCapturedLivePhoto?.pairedVideoURL) { oldValue, newValue in
            guard oldValue != newValue, let capture = manager.lastCapturedLivePhoto else { return }
            recentCapture = AGRecentCapture(content: .live(capture), thumbnail: UIImage(data: capture.photoData))
            livePhotoCaptureAction?(capture)
        }
        .onChange(of: manager.lastStartedVideoURL) { oldValue, newValue in
            guard let url = newValue, oldValue != newValue else { return }
            videoStartedAction?(url)
        }
        .onChange(of: manager.lastStoppedVideoURL) { oldValue, newValue in
            guard let url = newValue, oldValue != newValue else { return }
            recentCapture = AGRecentCapture(content: .video(url), thumbnail: nil)
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
        .onChange(of: exposureBiasBinding?.wrappedValue) { _, newValue in
            guard let newValue else { return }
            applyBoundExposureBias(newValue)
        }
        .onChange(of: manager.currentExposureBias) { _, newValue in
            guard exposureTask == nil else { return }
            displayedExposureBias = newValue
            synchronizeExposureBinding(to: newValue)
        }
        .onChange(of: manager.isSessionConfigured) { _, isConfigured in
            guard isConfigured, let exposureBiasBinding else { return }
            applyBoundExposureBias(exposureBiasBinding.wrappedValue)
        }
        .onChange(of: manager.isSwitchingCamera) { _, isSwitching in
            guard !isSwitching, manager.isSessionConfigured else { return }
            synchronizeExposureBinding(to: manager.currentExposureBias)
        }
        .onChange(of: manager.error) { _, newValue in
            if let error = newValue {
                errorAction?(error)
                present(error)
            }
        }
    }

    private var cameraLifecycle: some View {
        cameraEvents
        .task {
            let initialConfiguration = configuration
            manager.configuration = initialConfiguration
            manager.setLoggingEnabled(initialConfiguration.enableLogging)
            manager.setFlashMode(initialConfiguration.defaultFlashMode)
            manager.setPhotoAspectRatio(initialConfiguration.photoAspectRatio)
            manager.setViewActive(scenePhase == .active)
            if initialConfiguration.handlePermissions {
                guard await manager.permissionManager.requestCameraPermission() else {
                    present(CameraError.permissionDenied)
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await setupCamera()
            if let exposureBiasBinding {
                applyBoundExposureBias(exposureBiasBinding.wrappedValue)
            }
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
    }

    private var cameraPreview: some View {
        AGCameraPreview(
            session: manager.getCaptureSession(),
            isSessionConfigured: manager.isSessionConfigured,
            isSessionRunning: manager.isSessionRunning,
            videoGravity: manager.outputType == .photo && manager.photoAspectRatio != .fourThree
                ? .resizeAspectFill : displayedConfiguration.videoGravity,
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
        }
    }
}

// MARK: Default Controls
private extension AGCameraView {
    private var topControlsView: some View {
        HStack(spacing: 0) {
            if manager.outputType == .photo {
                Button(action: cycleFlash) {
                    AGFlashModeIcon(mode: manager.flashMode, font: .body)
                        .foregroundStyle(manager.flashMode == .on ? .yellow : .white)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.smooth(duration: 0.25), value: manager.flashMode)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AGCameraPressStyle())
                .accessibilityLabel("Flash: \(flashModeTitle)")

                Button(action: cycleLivePhoto) {
                    AGLivePhotoModeIcon(mode: manager.livePhotoMode, font: .body)
                        .foregroundStyle(manager.livePhotoMode == .on ? .yellow : .white)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.smooth(duration: 0.25), value: manager.livePhotoMode)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AGCameraPressStyle())
                .accessibilityLabel("Live Photo: \(manager.livePhotoMode.title)")

                Color.clear
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if manager.isRecording {
                AGVideoDurationView(duration: manager.formattedRecordingDuration)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .overlay(alignment: .top) {
            if let statusToast {
                AGCameraStatusToastView(toast: statusToast)
                    .offset(y: 92)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.top, 12)
        .task(id: statusToast?.id) {
            guard let toastID = statusToast?.id else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, statusToast?.id == toastID else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                statusToast = nil
            }
        }
    }
    
    private var bottomControlsView: some View {
        VStack(spacing: 20) {
            zoomButton
                .offset(y: -12)

            HStack {
                styleControlsButton
                    .frame(width: 48)
                Spacer()
                Group {
                    switch manager.outputType {
                    case .photo: capturePhotoButton
                    case .video: captureVideoButton
                    }
                }
                Spacer()
                moreControlsButton
                    .frame(width: 48)
                    .opacity(isMoreControlsDetailPresented ? 0 : 1)
                    .allowsHitTesting(!isMoreControlsDetailPresented)
            }
            .padding(.horizontal, 33)
            .offset(y: isMoreControlsDetailPresented ? 0 : -4)

            if !isMoreControlsDetailPresented {
                ZStack {
                    AGInputPickerButton(
                        outputType: $manager.outputType,
                        moreControlsNamespace: moreControlsNamespace,
                        onInteractionChanged: { isModePickerExpanded = $0 }
                    )
                        .disabled(manager.isRecording || manager.isPreparingVideoRecording)

                    HStack(spacing: 0) {
                        galleryButton
                            .frame(width: 48)
                            .offset(x: 16)
                        Spacer()
                        switchCameraButton
                            .frame(width: 48)
                            .offset(x: -17)
                    }
                    .padding(.horizontal, 16)
                    .opacity(isModePickerExpanded ? 0 : 1)
                    .allowsHitTesting(!isModePickerExpanded)
                    .accessibilityHidden(isModePickerExpanded)
                    .animation(.easeOut(duration: 0.15), value: isModePickerExpanded)
                }
                .offset(y: 6)
            }
        }
        .padding(.bottom, isMoreControlsDetailPresented ? 214 : 40)
    }

    private var styleControlsButton: some View {
        Button {
            if isMoreControlsDetailPresented {
                shouldOpenStyleControlsAfterDismiss = styleControlsAction != nil
                isMoreControlsPresented = false
            } else {
                styleControlsAction?()
            }
        } label: {
            Image(systemName: "f.cursive")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.1), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel("Style controls")
        .opacity(manager.outputType == .video && styleControlsAction == nil ? 0.45 : 1)
        .disabled(styleControlsAction == nil && !isMoreControlsDetailPresented)
    }

    private var moreControlsButton: some View {
        Button {
            if let moreControlsAction {
                moreControlsAction()
            } else {
                isMoreControlsPresented = true
            }
        } label: {
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { _ in
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .frame(height: 6)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.1), in: Circle())
            .contentShape(Rectangle())
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel("More camera controls")
        .disabled(manager.outputType != .photo && moreControlsAction == nil)
    }

    private var galleryButton: some View {
        Button {
            if let galleryAction {
                galleryAction()
            } else {
                presentedRecentCapture = recentCapture
            }
        } label: {
            Group {
                if let thumbnail = galleryThumbnail ?? recentCapture?.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: recentCapture == nil ? "photo.on.rectangle" : "video.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48, height: 48)
            .agCameraGlassCircle()
            .clipShape(Circle())
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel("Recent capture")
        .disabled(galleryAction == nil && recentCapture == nil)
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
        .simultaneousGesture(
            TapGesture().onEnded {
                if isMoreControlsDetailPresented {
                    isMoreControlsPresented = false
                }
            }
        )
    }
    
    private var capturePhotoButton: some View {
        AGCapturePhotoButton {
            if isMoreControlsDetailPresented {
                isMoreControlsPresented = false
            }
            do {
                _ = try await manager.captureSelectedPhoto()
            } catch {
                present(error)
            }
        }
        .disabled(!manager.isPhotoCaptureReady)
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
    private func cycleFlash() {
        defer {
            if isMoreControlsPresented { isMoreControlsPresented = false }
        }
        guard manager.isSessionConfigured else {
            showStatus("CAMERA STARTING", highlighted: false)
            return
        }
        guard !manager.isSwitchingCamera else {
            showStatus("CAMERA SWITCHING", highlighted: false)
            return
        }
        guard manager.capabilities?.supportsFlash == true else {
            showStatus("FLASH UNAVAILABLE", highlighted: false)
            return
        }
        manager.toggleFlash()
        showStatus("FLASH \(flashModeTitle.uppercased())", highlighted: manager.flashMode != .off)
    }

    private func cycleLivePhoto() {
        defer {
            if isMoreControlsPresented { isMoreControlsPresented = false }
        }
        guard manager.isSessionConfigured else {
            showStatus("CAMERA STARTING", highlighted: false)
            return
        }
        guard !manager.isSwitchingCamera else {
            showStatus("CAMERA SWITCHING", highlighted: false)
            return
        }
        guard !isChangingLivePhotoMode else {
            showStatus("LIVE UPDATING", highlighted: false)
            return
        }
        let nextMode: AGLivePhotoMode
        if manager.capabilities?.supportsLivePhoto != true {
            guard manager.livePhotoMode != .off else {
                showStatus("LIVE UNAVAILABLE", highlighted: false)
                return
            }
            nextMode = .off
        } else {
            switch manager.livePhotoMode {
            case .auto: nextMode = .off
            case .off: nextMode = .on
            case .on: nextMode = .auto
            }
        }
        selectLivePhoto(nextMode)
    }

    private func selectFlash(_ mode: AVCaptureDevice.FlashMode) {
        guard manager.isSessionConfigured, !manager.isSwitchingCamera else { return }
        guard mode == .off || manager.capabilities?.supportsFlash == true else {
            showStatus("FLASH UNAVAILABLE", highlighted: false)
            return
        }
        manager.setFlashMode(mode)
        showStatus("FLASH \(flashModeTitle.uppercased())", highlighted: mode != .off)
    }

    private func selectLivePhoto(_ mode: AGLivePhotoMode) {
        guard manager.isSessionConfigured, !manager.isSwitchingCamera, !isChangingLivePhotoMode else { return }
        guard mode == .off || manager.capabilities?.supportsLivePhoto == true else {
            showStatus("LIVE UNAVAILABLE", highlighted: false)
            return
        }
        isChangingLivePhotoMode = true
        Task {
            defer { isChangingLivePhotoMode = false }
            do {
                try await manager.setLivePhotoMode(mode)
                showStatus(
                    mode == .on ? "LIVE" : "LIVE \(mode.title.uppercased())",
                    highlighted: mode != .off
                )
            } catch {
                present(error)
            }
        }
    }

    private func selectPhotoAspectRatio(_ ratio: AGPhotoAspectRatio) {
        manager.setPhotoAspectRatio(ratio)
    }

    private func showStatus(_ title: String, highlighted: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            statusToast = AGCameraStatusToast(title: title, highlighted: highlighted)
        }
    }

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
        requestExposureBias(clampedBias)
    }

    private func applyBoundExposureBias(_ requestedBias: Float) {
        guard manager.isSessionConfigured, !manager.isSwitchingCamera else { return }
        guard requestedBias.isFinite else {
            synchronizeExposureBinding(to: manager.currentExposureBias)
            return
        }
        let bias = min(max(requestedBias, manager.minExposureBias), manager.maxExposureBias)
        if exposureTask != nil, abs(bias - displayedExposureBias) < 0.01 { return }
        if abs(bias - manager.currentExposureBias) < 0.01 {
            synchronizeExposureBinding(to: bias)
            return
        }
        requestExposureBias(bias)
    }

    private func requestExposureBias(_ bias: Float) {
        displayedExposureBias = bias
        pendingExposureBias = bias
        synchronizeExposureBinding(to: bias)
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
            if !Task.isCancelled {
                synchronizeExposureBinding(to: manager.currentExposureBias)
            }
            exposureTask = nil
        }
    }

    private func synchronizeExposureBinding(to bias: Float) {
        guard let exposureBiasBinding,
              !exposureBiasBinding.wrappedValue.isFinite
                || abs(exposureBiasBinding.wrappedValue - bias) >= 0.01 else { return }
        exposureBiasBinding.wrappedValue = bias
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
