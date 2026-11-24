import AVFoundation
import SwiftUI
import ag_camera

struct ContentView: View {
    @State private var cameraManager: AGCameraManager
    @State private var cameraIdentity = UUID()
    @State private var capturedPhoto: CapturedPhoto?
    @State private var showSettings = false
    @State private var showControlError = false
    @State private var controlErrorMessage = ""

    init() {
        let configuration = AGCameraConfiguration(videoGravity: .resizeAspect)
        self._cameraManager = State(initialValue: AGCameraManager(configuration: configuration))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AGCameraView(manager: cameraManager)
                .onPhotoCapture { capturedPhoto = CapturedPhoto(image: $0) }
                .onVideoStopped { print("VIDEO URL: \($0)") }
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
                    showSettings = true
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
        .sheet(isPresented: $showSettings) {
            CameraSettingsView(configuration: cameraManager.configuration, onApply: applySettings)
        }
        .sheet(item: $capturedPhoto) { photo in
            CapturePhotoPreview(photo: photo.image)
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
                .disabled(!cameraManager.isSessionRunning)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(.bottom, 24)
        }
    }
}

private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
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

private extension ContentView {
    func applySettings(_ configuration: AGCameraConfiguration) {
        capturedPhoto = nil
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
