import AVFoundation
import SwiftUI

struct AGCameraMoreControlsView: View {
    @Binding var isDetailPresented: Bool
    let manager: AGCameraManager
    let onFlashSelected: (AVCaptureDevice.FlashMode) -> Void
    let onLiveSelected: (AGLivePhotoMode) -> Void
    let onAspectSelected: (AGPhotoAspectRatio) -> Void

    @State private var page: Page = .grid
    @State private var selectedDetent: PresentationDetent = .height(446)

    private enum Page: String {
        case grid
        case flash
        case live
        case aspect

        var title: String { rawValue.uppercased() }
    }

    var body: some View {
        Group {
            if page == .grid {
                ScrollView {
                    controlsGrid
                        .padding(.horizontal, 20)
                        .padding(.top, 50)
                        .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                detailControls
                    .padding(.horizontal, 27)
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .presentationDetents(
            [.height(152), .height(446), .large],
            selection: $selectedDetent
        )
        .presentationDragIndicator(page == .grid ? .visible : .hidden)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("cameraMoreControls")
    }

    private var controlsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 32) {
            gridButton(title: "Flash", icon: AGFlashModeIcon(mode: manager.flashMode, font: .title2)) {
                show(.flash)
            }
            gridButton(title: "Live", icon: AGLivePhotoModeIcon(mode: manager.livePhotoMode, font: .title2)) {
                show(.live)
            }
            gridButton(title: "Aspect", icon: AGAspectRatioIcon(ratio: manager.photoAspectRatio), caption: manager.photoAspectRatio.title) {
                show(.aspect)
            }
            placeholder(title: "Timer", icon: "timer")
            placeholder(title: "Exposure", icon: "plusminus")
            placeholder(title: "Styles", icon: "camera.filters")
            placeholder(title: "Depth", icon: "f.cursive")
            placeholder(title: "Night Mode", icon: "moon.fill")
            placeholder(title: "Format", icon: "square.stack.3d.up")
        }
    }

    private var detailControls: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    show(.grid)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.38), in: Circle())
                }
                .buttonStyle(AGCameraPressStyle())
                .accessibilityLabel("All camera controls")
                .offset(y: 15)
                Spacer()
                Text(page.title)
                    .font(.footnote)
                    .tracking(1.5)
                Spacer()
                Color.clear.frame(width: 34, height: 34)
            }

            Text(currentSelectionTitle)
                .font(.largeTitle)
                .fontDesign(.rounded)
                .minimumScaleFactor(0.7)

            HStack(alignment: .top, spacing: 8) {
                switch page {
                case .flash:
                    detailOption(title: "Auto", icon: AGFlashModeIcon(mode: .auto, font: .title2),
                           selected: manager.flashMode == .auto,
                           enabled: manager.capabilities?.supportsFlash == true) {
                        onFlashSelected(.auto)
                    }
                    detailOption(title: "On", icon: AGFlashModeIcon(mode: .on, font: .title2), selected: manager.flashMode == .on,
                           enabled: manager.capabilities?.supportsFlash == true) {
                        onFlashSelected(.on)
                    }
                    detailOption(title: "Off", icon: AGFlashModeIcon(mode: .off, font: .title2), selected: manager.flashMode == .off) {
                        onFlashSelected(.off)
                    }
                case .live:
                    detailOption(title: "Auto", icon: AGLivePhotoModeIcon(mode: .auto, font: .title),
                           selected: manager.livePhotoMode == .auto,
                           enabled: manager.capabilities?.supportsLivePhoto == true) {
                        onLiveSelected(.auto)
                    }
                    detailOption(title: "On", icon: AGLivePhotoModeIcon(mode: .on, font: .title),
                           selected: manager.livePhotoMode == .on,
                           enabled: manager.capabilities?.supportsLivePhoto == true) {
                        onLiveSelected(.on)
                    }
                    detailOption(title: "Off", icon: AGLivePhotoModeIcon(mode: .off, font: .title),
                           selected: manager.livePhotoMode == .off) {
                        onLiveSelected(.off)
                    }
                case .aspect:
                    ForEach(AGPhotoAspectRatio.allCases) { ratio in
                        aspectOption(ratio) {
                            onAspectSelected(ratio)
                        }
                    }
                case .grid:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .offset(y: -5)
        }
    }

    private var currentSelectionTitle: String {
        switch page {
        case .flash:
            switch manager.flashMode {
            case .auto: "Auto"
            case .on: "On"
            case .off: "Off"
            @unknown default: "Off"
            }
        case .live: manager.livePhotoMode.title
        case .aspect: manager.photoAspectRatio.title
        case .grid: ""
        }
    }

    private func gridButton<Icon: View>(
        title: String,
        icon: Icon,
        caption: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                iconCircle(icon)
                Text(title.uppercased())
                    .font(.caption)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel("\(title), \(caption ?? currentValue(for: title))")
    }

    private func placeholder(title: String, icon: String) -> some View {
        VStack(spacing: 14) {
            iconCircle(Image(systemName: icon).font(.title2))
            Text(title.uppercased())
                .font(.caption)
                .tracking(1)
        }
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title), unavailable")
    }

    private func detailOption<Icon: View>(
        title: String,
        icon: Icon,
        selected: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon
                .foregroundStyle(selected ? .yellow : .white)
                .frame(width: 70, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(AGCameraPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func aspectOption(_ ratio: AGPhotoAspectRatio, action: @escaping () -> Void) -> some View {
        let selected = manager.photoAspectRatio == ratio
        return Button(action: action) {
            AGAspectRatioIcon(ratio: ratio)
            .foregroundStyle(selected ? .yellow : .white)
            .frame(width: 70, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(AGCameraPressStyle())
        .accessibilityLabel(ratio.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func iconCircle<Icon: View>(_ icon: Icon) -> some View {
        ZStack {
            Circle().fill(.black.opacity(0.5))
            icon
        }
        .foregroundStyle(.white)
        .frame(width: 68, height: 68)
    }

    private func currentValue(for title: String) -> String {
        switch title {
        case "Flash":
            switch manager.flashMode {
            case .auto: "Auto"
            case .on: "On"
            case .off: "Off"
            @unknown default: "Off"
            }
        case "Live": manager.livePhotoMode.title
        default: manager.photoAspectRatio.title
        }
    }

    private func show(_ destination: Page) {
        page = destination
        isDetailPresented = destination != .grid
        selectedDetent = destination == .grid ? .height(446) : .height(152)
    }
}
