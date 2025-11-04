import SwiftUI
import AVFoundation
import OSLog

public struct AGCameraView: View {
    private static let logger = Logger(subsystem: "com.agcamera", category: "CameraView")
    @State private var permissionManager = AGPermissionManager()
    @State private var cameraManager: AGCameraManager?
    @State private var capturedImage: UIImage?
    @State private var showImagePreview = false
    @State private var showError = false
    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var focusTask: Task<Void, Never>?
    @State private var flipRotation: Double = 0
    @State private var isBlurred: Bool = false
    
    @Environment(\.scenePhase) private var scenePhase

    private var controlsOpacity: Double {
        guard let cameraManager = cameraManager else { return 1.0 }
        return cameraManager.currentZoomFactor >= 3.0 ? 0.3 : 1.0
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            if let cameraManager = cameraManager {
                GeometryReader { previewGeometry in
                    AGCameraPreview(
                        session: cameraManager.getCaptureSession(),
                        cameraPosition: cameraManager.currentCameraPosition
                    )
                    .ignoresSafeArea()
                    .onTapGesture { location in
                        handleTapToFocus(at: location, in: previewGeometry.size)
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                try? cameraManager.updateZoomInteractively(scale: value, isGestureEnded: false)
                            }
                            .onEnded { value in
                                try? cameraManager.updateZoomInteractively(scale: value, isGestureEnded: true)
                            }
                    )
                    .blur(radius: isBlurred ? 20 : 0)
                    .rotation3DEffect(
                        .degrees(flipRotation),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .overlay {
                        if showFocusIndicator, let point = focusPoint {
                            FocusIndicatorView()
                                .position(point)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                Color.black.ignoresSafeArea()
            }
            
            VStack {
                topBar
                    .padding()
                    .opacity(controlsOpacity)
                    .animation(.easeInOut(duration: 0.3), value: controlsOpacity)
                
                Spacer()

                if let manager = cameraManager, manager.isRecording {
                    recordingTimer
                        .padding(.top, 20)
                }

                if cameraManager != nil {
                    zoomIndicator
                        .padding(.bottom, 10)
                }

                if cameraManager != nil {
                    zoomButtons
                        .padding(.bottom, 20)
                        .id(cameraManager?.currentCameraPosition)
                }

                bottomBar
                    .padding()
                    .opacity(controlsOpacity)
                    .animation(.easeInOut(duration: 0.3), value: controlsOpacity)
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
            Button("OK") {
                showError = false
            }
        } message: {
            Text(cameraManager?.error?.localizedDescription ?? "Unknown error")
        }
        .sheet(isPresented: $showImagePreview) { [capturedImage] in
            if let image = capturedImage {
                ImagePreviewView(image: image, onDismiss: {
                    showImagePreview = false
                    self.capturedImage = nil
                })
            }
        }
    }
    
    private var topBar: some View {
        HStack {
            Button(action: {
                cameraManager?.toggleFlash()
            }) {
                Image(systemName: cameraManager?.flashIconName ?? "bolt.slash")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            Spacer()

            Button(action: {
                try? cameraManager?.setSessionPreset(.hd4K3840x2160)
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
        HStack(spacing: 40) {
            Button(action: {
                Task {
                    await switchCameraWithAnimation()
                }
            }) {
                Image(systemName: "camera.rotate")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding(16)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }

            Button(action: {
                Task {
                    await capturePhoto()
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 70, height: 70)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                }
            }

            Button(action: {
                Task {
                    await toggleVideoRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(cameraManager?.isRecording == true ? Color.red : Color.white.opacity(0.8))
                        .frame(width: 50, height: 50)

                    if cameraManager?.isRecording == true {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                    }
                }
            }
        }
    }
    
    private var zoomButtons: some View {
        HStack(spacing: 15) {
            let availableLevels = cameraManager?.availableZoomLevels ?? [1.0]
            let currentZoom = cameraManager?.currentZoomFactor ?? 1.0

            ForEach(availableLevels, id: \.self) { level in
                ZoomButton(level: level, currentZoom: currentZoom) {
                    setZoom(to: level)
                }
            }
        }
    }
    
    private var zoomIndicator: some View {
        Text(String(format: "%.1f×", cameraManager?.currentZoomFactor ?? 1.0))
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

            Text(cameraManager?.formattedRecordingDuration ?? "00:00")
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
        let result = await permissionManager.requestAllPermissions()

        guard result.camera else {
            showError = true
            return
        }

        let manager = AGCameraManager(permissionManager: permissionManager)
        cameraManager = manager

        do {
            try await manager.setupSession()
            manager.startSession()

            Self.logger.info("Camera Info - Min Zoom: \(String(format: "%.1f", manager.minZoomFactor))×, Max Zoom: \(String(format: "%.1f", manager.maxZoomFactor))×, Current Zoom: \(String(format: "%.1f", manager.currentZoomFactor))×")
        } catch {
            showError = true
        }
    }

    private func capturePhoto() async {
        guard let cameraManager = cameraManager else { return }

        do {
            let imageData = try await cameraManager.capturePhoto()

            if let image = UIImage(data: imageData) {
                capturedImage = image
                await MainActor.run {
                    showImagePreview = true
                }
            }
        } catch {
            showError = true
        }
    }

    private func toggleVideoRecording() async {
        guard let cameraManager = cameraManager else { return }

        if cameraManager.isRecording {
            cameraManager.stopVideoRecording()
        } else {
            do {
                let videoURL = try await cameraManager.startVideoRecording()
                Self.logger.info("Video saved to: \(videoURL)")
            } catch {
                showError = true
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

        try? cameraManager?.setFocusAndExposure(at: normalizedPoint)

        focusTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                showFocusIndicator = false
            }
        }
    }

    private func setZoom(to level: CGFloat) {
        guard let cameraManager = cameraManager else { return }

        do {
            try cameraManager.setZoom(factor: level)
        } catch {
            Self.logger.error("Zoom error: \(error.localizedDescription)")
            showError = true
        }
    }

    private func switchCameraWithAnimation() async {
        guard let cameraManager = cameraManager else { return }

        let flipDirection: Double = cameraManager.currentCameraPosition == .back ? 180 : -180

        withAnimation(.easeOut(duration: 0.1)) {
            isBlurred = true
        }

        withAnimation(.easeInOut(duration: 0.5)) {
            flipRotation += flipDirection
        }

        try? await Task.sleep(nanoseconds: 250_000_000)

        try? await cameraManager.switchCamera()

        try? await Task.sleep(nanoseconds: 100_000_000)

        withAnimation(.easeIn(duration: 0.15)) {
            isBlurred = false
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard let cameraManager = cameraManager else { return }

        switch newPhase {
        case .background:
            cameraManager.handleAppBackground()

        case .active:
            cameraManager.handleAppForeground()

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

private struct FocusIndicatorView: View {
    @State private var animate = false

    var body: some View {
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
    AGCameraView()
}

public var onPhotoCaptured: ((UIImage) -> Void)?
public var onVideoRecordingStarted: ((URL) -> Void)? = nil
public var onVideoCaptured: ((URL) -> Void)?
public var onFlashModeChanged: ((AVCaptureDevice.FlashMode) -> Void)? = nil
public var onCameraPositionChanged: ((AVCaptureDevice.Position) -> Void)? = nil
public var onZoomChanged: ((CGFloat) -> Void)? = nil
public var onError: ((Error) -> Void)? = nil
