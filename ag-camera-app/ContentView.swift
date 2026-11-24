import AVFoundation
import AVKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import ag_camera

struct ContentView: View {
    @State private var cameraManager: AGCameraManager
    @State private var cameraIdentity = UUID()
    @State private var presentedSheet: PresentedSheet?
    @State private var showControlError = false
    @State private var controlErrorMessage = ""
    @State private var exposureBias: Float = 0

    init() {
        let configuration = AGCameraConfiguration(videoGravity: .resizeAspect)
        self._cameraManager = State(initialValue: AGCameraManager(configuration: configuration))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AGCameraView(manager: cameraManager)
                .exposureBias($exposureBias)
                .onPhotoCapture { image in
                    guard let data = cameraManager.lastCapturedPhotoData else { return }
                    presentedSheet = .photo(CapturedPhoto(image: image, data: data))
                }
                .onLivePhotoCapture { presentedSheet = .live($0) }
                .onVideoStopped { presentedSheet = .video(CapturedVideo(url: $0)) }
                .id(cameraIdentity)

            if !cameraManager.configuration.showDefaultControls {
                customControls
            }

            HStack(spacing: 12) {
                Button {
                    runCameraAction { try await cameraManager.toggleTorch() }
                } label: {
                    Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .disabled(!cameraManager.isSessionRunning || cameraManager.currentCameraPosition != .back)
                .accessibilityLabel("Toggle torch")

                Button {
                    presentedSheet = .settings
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Camera settings")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.black.opacity(0.55), in: Capsule())
            .padding()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .settings:
                CameraSettingsView(configuration: cameraManager.configuration, onApply: applySettings)
            case .photo(let photo):
                CapturePhotoPreview(photo: photo, cameraManager: cameraManager)
            case .live(let capture):
                CaptureLivePhotoPreview(capture: capture, cameraManager: cameraManager)
            case .video(let video):
                CaptureVideoPreview(url: video.url)
            }
        }
        .alert("Camera Control", isPresented: $showControlError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(controlErrorMessage)
        }
    }

    private var customControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    Label("Exposure", systemImage: "sun.max.fill")
                    Spacer()
                    Text(String(format: "%+.1f EV", exposureBias))
                        .monospacedDigit()
                }
                Slider(value: $exposureBias, in: exposureRange)
                    .tint(.yellow)
                    .disabled(!cameraManager.isSessionRunning || cameraManager.maxExposureBias <= cameraManager.minExposureBias)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            HStack(spacing: 20) {
                Button {
                    runCameraAction { _ = try await cameraManager.captureSelectedPhoto() }
                } label: {
                    Label("Photo", systemImage: "camera")
                }

                Button {
                    runCameraAction {
                        if cameraManager.isRecording {
                            _ = try await cameraManager.stopVideoRecording()
                        } else {
                            _ = try await cameraManager.startVideoRecording()
                        }
                    }
                } label: {
                    Label(cameraManager.isRecording ? "Stop" : "Record", systemImage: "video")
                }

                Button {
                    runCameraAction { try await cameraManager.switchCamera() }
                } label: {
                    Label("Rotate", systemImage: "camera.rotate")
                }
                .disabled(!cameraManager.isSessionRunning || cameraManager.isPreparingVideoRecording)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(.bottom, 24)
        }
    }

    private var exposureRange: ClosedRange<Float> {
        cameraManager.maxExposureBias > cameraManager.minExposureBias
            ? cameraManager.minExposureBias...cameraManager.maxExposureBias
            : 0...1
    }
}

private enum PresentedSheet: Identifiable {
    case settings
    case photo(CapturedPhoto)
    case live(AGLivePhotoCapture)
    case video(CapturedVideo)

    var id: String {
        switch self {
        case .settings:
            "settings"
        case .photo(let photo):
            photo.id.uuidString
        case .live(let capture):
            capture.pairedVideoURL.absoluteString
        case .video(let video):
            video.id.uuidString
        }
    }
}

private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
}

private struct CapturedVideo: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CapturePhotoPreview: View {
    let photo: CapturedPhoto
    let cameraManager: AGCameraManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .safeAreaInset(edge: .bottom) {
                    CaptureSaveBar {
                        try await cameraManager.savePhotoToLibrary(photo.data)
                    }
                }
                .navigationTitle("Photo")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

private struct CaptureLivePhotoPreview: View {
    let capture: AGLivePhotoCapture
    let cameraManager: AGCameraManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AGLivePhotoView(capture: capture)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .accessibilityHint("Press and hold to play the Live Photo")
                .safeAreaInset(edge: .bottom) {
                    CaptureSaveBar(instruction: "Press and hold the photo to play") {
                        try await cameraManager.saveLivePhotoToLibrary(capture)
                    }
                }
                .navigationTitle("Live Photo")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .onDisappear {
            try? FileManager.default.removeItem(at: capture.pairedVideoURL)
        }
    }
}

private struct CaptureSaveBar: View {
    let instruction: String?
    let save: @MainActor () async throws -> Void

    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    @Environment(\.dismiss) private var dismiss

    init(instruction: String? = nil, save: @escaping @MainActor () async throws -> Void) {
        self.instruction = instruction
        self.save = save
    }

    var body: some View {
        VStack(spacing: 12) {
            if let instruction {
                Label(instruction, systemImage: "livephoto")
                    .font(.footnote)
                    .foregroundStyle(.white)
            }

            Button {
                Task { await saveToPhotos() }
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.85))
        .alert("Could Not Save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}

private struct CaptureVideoPreview: View {
    let url: URL

    @State private var player: AVPlayer

    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.url = url
        self._player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .navigationTitle("Video Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: SharedRecording(url: url), preview: SharePreview("Recorded Video")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share recording")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}

private struct SharedRecording: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .quickTimeMovie) { recording in
            SentTransferredFile(recording.url)
        }
    }
}

private extension ContentView {
    func applySettings(_ configuration: AGCameraConfiguration) {
        presentedSheet = nil
        exposureBias = 0
        cameraManager = AGCameraManager(configuration: configuration)
        cameraIdentity = UUID()
    }

    func runCameraAction(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                controlErrorMessage = error.localizedDescription
                showControlError = true
            }
        }
    }
}

#Preview {
    ContentView()
}
