import SwiftUI
import AVFoundation
import OSLog

enum OutputType: CaseIterable, Identifiable {
    case photo, video
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .photo:
            "Photo"
        case .video:
            "Video"
        }
    }
}

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

    @State private var capturedImage: UIImage?
    @State private var showError = false
    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var focusTask: Task<Void, Never>?
    @State private var flipRotation: Double = 0
    @State private var isBlurred: Bool = false
    @State private var outputType: OutputType = .photo

    @Environment(\.scenePhase) private var scenePhase

    private var controlsOpacity: Double {
        manager.currentZoomFactor >= 3.0 ? 0.3 : 1.0
    }

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
                VStack {
                    topBar
                        .padding()
                        .opacity(controlsOpacity)
                        .animation(.easeInOut(duration: 0.3), value: controlsOpacity)

                    Spacer()

                    if manager.isRecording {
                        recordingTimer
                            .padding(.top, 20)
                    }

                    zoomIndicator
                        .padding(.bottom, 10)

                    AGSZoomControlView(manager: manager) { newZoomLevel in
                        setZoom(to: newZoomLevel)
                    }

                    bottomBar
                        .padding()
                        .opacity(controlsOpacity)
                        .animation(.easeInOut(duration: 0.3), value: controlsOpacity)
                }
            }
        }
        .task {
            await setupCamera()
        }
        .onDisappear {
            manager.stopSession()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(manager.error?.localizedDescription ?? "Unknown error")
        }
    }
    
    private var topBar: some View {
        HStack {
            Button(action: {
                manager.toggleFlash()
                onFlashModeChanged?(manager.flashMode)
            }) {
                Image(systemName: manager.flashIconName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            Spacer()

            Button(action: {
                try? manager.setSessionPreset(.hd4K3840x2160)
            }) {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
    }
    
    private var bottomBar: some View {
        VStack {
            switch outputType {
            case .photo:
                AGCapturePhotoButton {
                    await capturePhoto()
                }
            case .video:
                AGCaptureVideoButton(isRecording: manager.isRecording) {
                    await toggleVideoRecording()
                }
            }
            
            HStack(spacing: 40) {
                Circle()
                    .frame(width: 70, height: 70)
                AGInputPickerButton(outputType: $outputType)
                AGSwitchCameraButton {
                    await switchCamera()
                }
            }
            .padding(.horizontal)
        }
    }

    private var zoomIndicator: some View {
        Text(String(format: "%.1f×", manager.currentZoomFactor))
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
            RecordingDot()

            Text(manager.formattedRecordingDuration)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
        )
    }

    private func setupCamera() async {
        do {
            try await manager.setupSession()
            manager.startSession()

            Self.logger.info("Camera Info - Min Zoom: \(String(format: "%.1f", manager.minZoomFactor))×, Max Zoom: \(String(format: "%.1f", manager.maxZoomFactor))×, Current Zoom: \(String(format: "%.1f", manager.currentZoomFactor))×")
        } catch {
            showError = true
            onError?(error)
        }
    }

    private func capturePhoto() async {
        do {
            let imageData = try await manager.capturePhoto()

            if let image = UIImage(data: imageData) {
                capturedImage = image
                onPhotoCaptured?(image)
                await MainActor.run {
                    self.capturedImage = nil
                }
            }
        } catch {
            showError = true
            onError?(error)
        }
    }

    private func toggleVideoRecording() async {
        if manager.isRecording {
            do {
                let videoURL = try await manager.stopVideoRecording()
                onVideoRecordingStopped?(videoURL)
                Self.logger.info("Video recording stopped: \(videoURL)")
            } catch {
                showError = true
                onError?(error)
            }
        } else {
            do {
                let videoURL = try await manager.startVideoRecording()
                onVideoRecordingStarted?(videoURL)
                Self.logger.info("Video recording started: \(videoURL)")
            } catch {
                showError = true
                onError?(error)
            }
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

    private func setZoom(to level: CGFloat) {
        do {
            try manager.setZoom(factor: level)
            onZoomChanged?(level)
        } catch {
            Self.logger.error("Zoom error: \(error.localizedDescription)")
            showError = true
            onError?(error)
        }
    }

    private func switchCamera() async {
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

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
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
                .frame(width: 44, height: 32)
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

public struct FocusIndicatorView: View {
    @State private var animate = false
    
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 80, height: 80)
            .scaleEffect(animate ? 1.0 : 0.8)
            .opacity(animate ? 1.0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
                    animate = true
                }
            }
    }
}

private struct RecordingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .opacity(isPulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

#Preview {
    @Previewable let cameraManager = AGCameraManager()
    AGCameraView(manager: cameraManager)
}


public struct AGSZoomControlView: View {
    @Bindable var manager: AGCameraManager
    var onZoomChange: (CGFloat) -> Void
    @State private var animate = false
    
    private var zoomLevels: [CGFloat] {
        Array(manager.availableZoomLevels.prefix(3))
    }
    
    public var body: some View {
        HStack(spacing: 15) {
            ForEach(zoomLevels, id: \.self) { level in
                ZoomButton(level: level, currentZoom: manager.currentZoomFactor) { zoom in
                    onZoomChange(zoom)
                }
            }
        }
    }
    
    private struct ZoomButton: View {
        var level: CGFloat
        var currentZoom: CGFloat
        var action: (CGFloat) -> Void
        @State private var animate = false
        
        private var isSelected: Bool {
            level == currentZoom
        }
        
        private var selectedSuffix: String {
            isSelected ? "×" : ""
        }
        
        var body: some View {
            Button {
                action(level)
                animate = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { animate = false }
            } label: {
                    Text(level.truncatingRemainder(dividingBy: 1) == 0 ?
                         String(format: "%.0f\(selectedSuffix)", level) :
                            String(format: "%.1f\(selectedSuffix)", level))
                    .monospaced()
                    .monospacedDigit()
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .yellow : .white)
                    .shadow(color: .black, radius: isSelected ? 0 : 2, x: 0, y: 0)
                    .frame(width: 33, height: 33)
                    .background(isSelected ? Color.black.opacity(0.4) : .clear)
                    .clipShape(Circle())
                    .scaleEffect(animate ? 0.9 : 1.0)
                    .animation(.bouncy(duration: 0.3, extraBounce: 0.3), value: animate)
            }
            .buttonStyle(.plain)
        }
    }
}
