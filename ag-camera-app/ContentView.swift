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

    init() {
        let configuration = AGCameraConfiguration(videoGravity: .resizeAspect)
        self._cameraManager = State(initialValue: AGCameraManager(configuration: configuration))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AGCameraView(manager: cameraManager)
                .onPhotoCapture { presentedSheet = .photo(CapturedPhoto(image: $0)) }
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
                CapturePhotoPreview(photo: photo.image)
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
            HStack(spacing: 20) {
                Button {
                    runCameraAction { _ = try await cameraManager.capturePhoto() }
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
}

private enum PresentedSheet: Identifiable {
    case settings
    case photo(CapturedPhoto)
    case video(CapturedVideo)

    var id: String {
        switch self {
        case .settings:
            "settings"
        case .photo(let photo):
            photo.id.uuidString
        case .video(let video):
            video.id.uuidString
        }
    }
}

private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct CapturedVideo: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CapturePhotoPreview: View {
    let photo: UIImage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFit()
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .padding()
                }
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
