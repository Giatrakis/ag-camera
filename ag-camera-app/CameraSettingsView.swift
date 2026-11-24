import AVFoundation
import SwiftUI
import ag_camera

struct CameraSettingsView: View {
    let onApply: (AGCameraConfiguration) -> Void

    @State private var draft: AGCameraConfiguration

    @Environment(\.dismiss) private var dismiss

    init(configuration: AGCameraConfiguration, onApply: @escaping (AGCameraConfiguration) -> Void) {
        self.onApply = onApply
        self._draft = State(initialValue: configuration)
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                cameraSection
                focusSection
                captureSection
                diagnosticsSection
            }
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            Picker("Grid", selection: $draft.grid) {
                Text("Off").tag(AGCameraGrid.none)
                Text("Rule of Thirds").tag(AGCameraGrid.rule3x3)
                Text("4 × 4").tag(AGCameraGrid.square4x4)
            }
            .pickerStyle(.inline)
            Picker("Tap to focus", selection: $draft.tapToFocusBehavior) {
                Text("Off").tag(AGTapToFocusBehavior.none)
                Text("Focus only").tag(AGTapToFocusBehavior.focusOnly)
                Text("Focus and exposure").tag(AGTapToFocusBehavior.focusAndExposure)
            }
            Toggle("Mirror front camera", isOn: $draft.mirrorFrontCamera)
            Toggle("Built-in controls", isOn: $draft.showDefaultControls)
        }
    }

    private var cameraSection: some View {
        Section("Camera") {
            Picker("Starting camera", selection: $draft.defaultCameraPosition) {
                Text("Rear").tag(AVCaptureDevice.Position.back)
                Text("Front").tag(AVCaptureDevice.Position.front)
            }
            Stepper(
                "Starting zoom: \(String(format: "%.1f", Double(draft.defaultZoomScale)))×",
                value: $draft.defaultZoomScale,
                in: 0.5...3,
                step: 0.5
            )
            Stepper("Front zoom limit: \(Int(draft.maxFrontZoomFactor))×", value: $draft.maxFrontZoomFactor, in: 1...5)
            Stepper("Rear zoom limit: \(Int(draft.maxBackZoomFactor))×", value: $draft.maxBackZoomFactor, in: 1...15)
            HStack {
                Text("Torch power")
                Slider(value: $draft.torchLevel, in: 0...1)
                Text("\(Int(draft.torchLevel * 100))%")
                    .monospacedDigit()
            }
        }
    }

    private var focusSection: some View {
        Section("Default Focus and Exposure") {
            Picker("Focus", selection: $draft.defaultFocusMode) {
                Text("Auto").tag(AVCaptureDevice.FocusMode.autoFocus)
                Text("Continuous").tag(AVCaptureDevice.FocusMode.continuousAutoFocus)
                Text("Locked").tag(AVCaptureDevice.FocusMode.locked)
            }
            Picker("Exposure", selection: $draft.defaultExposureMode) {
                Text("Auto").tag(AVCaptureDevice.ExposureMode.autoExpose)
                Text("Continuous").tag(AVCaptureDevice.ExposureMode.continuousAutoExposure)
                Text("Locked").tag(AVCaptureDevice.ExposureMode.locked)
            }
        }
    }

    private var captureSection: some View {
        Section {
            Picker("Photo quality", selection: $draft.photoQualityPrioritization) {
                Text("Speed").tag(AVCapturePhotoOutput.QualityPrioritization.speed)
                Text("Balanced").tag(AVCapturePhotoOutput.QualityPrioritization.balanced)
                Text("Quality").tag(AVCapturePhotoOutput.QualityPrioritization.quality)
            }
            Picker("Session preset", selection: $draft.sessionPreset) {
                Text("Photo").tag(AVCaptureSession.Preset.photo)
                Text("High").tag(AVCaptureSession.Preset.high)
                Text("1080p").tag(AVCaptureSession.Preset.hd1920x1080)
                Text("4K").tag(AVCaptureSession.Preset.hd4K3840x2160)
            }
            Picker("Video frame rate", selection: $draft.videoFrameRate) {
                Text("24 fps").tag(Int32(24))
                Text("30 fps").tag(Int32(30))
                Text("60 fps").tag(Int32(60))
            }
            Picker("Video codec", selection: $draft.videoCodec) {
                Text("System default").tag(nil as AVVideoCodecType?)
                Text("H.264").tag(AVVideoCodecType.h264 as AVVideoCodecType?)
                Text("HEVC").tag(AVVideoCodecType.hevc as AVVideoCodecType?)
            }
        } header: {
            Text("Capture")
        } footer: {
            Text("The camera reports unsupported presets, frame rates, and codecs when they are applied.")
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Toggle("Enable logging", isOn: $draft.enableLogging)
        }
    }
}
