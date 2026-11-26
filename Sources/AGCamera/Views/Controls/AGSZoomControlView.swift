import SwiftUI

public struct AGSZoomControlView: View {
    @Bindable var manager: AGCameraManager
    let onZoomChange: (CGFloat) -> Void

    @State private var selectedLevel: CGFloat?
    @State private var requestedZoom: CGFloat?
    @State private var didUserScroll = false
    @State private var focalLengthPreview: Int?
    @State private var isDialVisible = false
    @State private var dialStartZoom: CGFloat?
    @State private var dialZoom: CGFloat = 1
    @State private var lastDialRequest: CGFloat?
    @State private var dialDismissTask: Task<Void, Never>?
    @State private var hapticTick = 0

    private var zoomLevels: [CGFloat] {
        manager.availableZoomLevels
    }

    private var selectedZoom: CGFloat {
        guard let selectedLevel else { return manager.currentZoomFactor }
        let upperBound = zoomLevels.first(where: { $0 > selectedLevel + 0.005 }) ?? manager.maxZoomFactor + 0.01
        let current = manager.currentZoomFactor
        if isOneXAlternate(current, for: selectedLevel) { return current }
        return current >= selectedLevel - 0.05 && current < upperBound - 0.005 ? current : selectedLevel
    }

    public init(manager: AGCameraManager, onZoomChange: @escaping (CGFloat) -> Void) {
        self.manager = manager
        self.onZoomChange = onZoomChange
    }

    public var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(zoomLevels, id: \.self) { level in
                            ZoomStopButton(
                                level: level,
                                isSelected: selectedLevel == level,
                                selectedZoom: selectedZoom,
                                focalLengthPreview: selectedLevel == level ? focalLengthPreview : nil,
                                onDialDrag: { translation, ended in
                                    updateDial(translation: translation, ended: ended, using: proxy)
                                }
                            ) {
                                selectZoom(level, using: proxy)
                            }
                            .id(level)
                        }
                    }
                    .padding(.horizontal, max(0, (geometry.size.width - 36) / 2))
                }
                .scrollIndicators(.hidden)
                .opacity(isDialVisible ? 0 : 1)
                .onScrollPhaseChange { _, phase, context in
                    switch phase {
                    case .interacting, .decelerating:
                        didUserScroll = true
                    case .idle:
                        guard didUserScroll, !zoomLevels.isEmpty else { return }
                        didUserScroll = false
                        let offset = context.geometry.contentOffset.x
                        guard offset.isFinite else { return }
                        let index = Int((offset / 36).rounded())
                        let clampedIndex = min(max(index, 0), zoomLevels.count - 1)
                        applyStop(zoomLevels[clampedIndex], using: proxy)
                    default:
                        break
                    }
                }
                .overlay(alignment: .bottom) {
                    if isDialVisible {
                        AGZoomDialView(
                            zoom: dialZoom,
                            minimum: manager.minZoomFactor,
                            maximum: manager.maxZoomFactor,
                            focalLength: { manager.estimatedFocalLengthIn35mmFilm(for: $0) },
                            physicalLensFocalLength: { manager.physicalLensFocalLengthIn35mmFilm(at: $0) }
                        )
                        .frame(height: 140)
                        .offset(y: 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .onAppear { centerCurrentZoom(using: proxy) }
            .task(id: focalLengthPreview) {
                guard focalLengthPreview != nil else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    focalLengthPreview = nil
                }
                requestedZoom = nil
            }
            .onChange(of: zoomLevels) { _, _ in centerCurrentZoom(using: proxy) }
            .onChange(of: selectedLevel) { oldValue, newValue in
                if oldValue != newValue {
                    clearFocalLengthPreview()
                }
            }
            .onChange(of: isDialVisible) { _, visible in
                if !visible { centerCurrentZoom(using: proxy) }
            }
            .onChange(of: manager.currentZoomFactor) { _, current in
                guard !isDialVisible else { return }
                if let requestedZoom, abs(current - requestedZoom) < 0.05 {
                    self.requestedZoom = nil
                }
                guard let selectedLevel else {
                    centerCurrentZoom(using: proxy)
                    return
                }
                if isOneXAlternate(current, for: selectedLevel) { return }
                let upperBound = zoomLevels.first(where: { $0 > selectedLevel + 0.005 }) ?? manager.maxZoomFactor + 0.01
                if current < selectedLevel - 0.05 || current >= upperBound - 0.005 {
                    centerCurrentZoom(using: proxy)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: hapticTick)
    }
}

private struct ZoomStopButton: View {
    let level: CGFloat
    let isSelected: Bool
    let selectedZoom: CGFloat
    let focalLengthPreview: Int?
    let onDialDrag: (CGFloat, Bool) -> Void
    let action: () -> Void

    private var label: String {
        let value = isSelected ? selectedZoom : level
        let number = AGZoomDisplay.number(value)
        return isSelected ? "\(number)×" : number
    }

    @ViewBuilder
    var body: some View {
        let button = Button(action: action) {
            Group {
                if let focalLengthPreview {
                    VStack(spacing: -2) {
                        Text(focalLengthPreview.formatted())
                        Text("MM")
                            .scaleEffect(0.75)
                    }
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .id(focalLengthPreview)
                    .transition(.opacity)
                } else {
                    Text(label)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .transition(.opacity)
                }
            }
            .monospacedDigit()
            .foregroundStyle(isSelected ? .yellow : .white)
            .frame(width: 36, height: 36)
            .background(isSelected ? .black.opacity(0.55) : .clear, in: Circle())
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            focalLengthPreview.map { "\($0) millimeters" }
                ?? (isSelected ? "Current zoom \(label). Tap for alternate focal length" : "Zoom to \(label) times")
        )

        if isSelected {
            button.highPriorityGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { onDialDrag($0.translation.width, false) }
                    .onEnded { onDialDrag($0.translation.width, true) }
            )
        } else {
            button
        }
    }
}

// MARK: - Actions
private extension AGSZoomControlView {
    func isOneXAlternate(_ zoom: CGFloat, for selectedLevel: CGFloat) -> Bool {
        abs(selectedLevel - 1) < 0.005
            && (abs(zoom - 1.2) < 0.05 || abs(zoom - 1.5) < 0.05)
    }

    func selectZoom(_ level: CGFloat, using proxy: ScrollViewProxy) {
        if selectedLevel == level {
            withAnimation(.snappy(duration: 0.25)) {
                proxy.scrollTo(level, anchor: .center)
            }
            guard abs(level - 1) < 0.005 else { return }
            let current = requestedZoom ?? selectedZoom
            let next = AGZoomStops.nextOneXZoom(current: current, maximum: manager.maxZoomFactor)
            guard abs(next.factor - current) > 0.005 else { return }
            requestedZoom = next.factor
            showFocalLength(next.focalLength)
            onZoomChange(next.factor)
        } else {
            applyStop(level, using: proxy)
        }
    }

    func applyStop(_ level: CGFloat, using proxy: ScrollViewProxy) {
        clearFocalLengthPreview()
        requestedZoom = nil
        selectedLevel = level
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(level, anchor: .center)
        }
        onZoomChange(level)
    }

    func centerCurrentZoom(using proxy: ScrollViewProxy) {
        guard let closest = AGZoomDisplay.containingStop(for: manager.currentZoomFactor, in: zoomLevels) else { return }
        clearFocalLengthPreview()
        requestedZoom = nil
        selectedLevel = closest
        proxy.scrollTo(closest, anchor: .center)
    }

    func showFocalLength(_ millimeters: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            focalLengthPreview = millimeters
        }
    }

    func clearFocalLengthPreview() {
        withAnimation(.easeInOut(duration: 0.18)) {
            focalLengthPreview = nil
        }
    }

    func updateDial(translation: CGFloat, ended: Bool, using proxy: ScrollViewProxy) {
        if dialStartZoom == nil {
            dialDismissTask?.cancel()
            dialStartZoom = manager.currentZoomFactor
            dialZoom = manager.currentZoomFactor
            clearFocalLengthPreview()
            withAnimation(.easeOut(duration: 0.16)) {
                isDialVisible = true
            }
        }

        guard let dialStartZoom else { return }
        let target = AGZoomDialScale.zoom(
            from: dialStartZoom,
            translation: translation,
            minimum: manager.minZoomFactor,
            maximum: manager.maxZoomFactor
        )
        if AGZoomDialScale.crossesLandmark(
            from: dialZoom,
            to: target,
            minimum: manager.minZoomFactor,
            maximum: manager.maxZoomFactor
        ) {
            hapticTick += 1
        }
        dialZoom = target

        if ended || lastDialRequest.map({ abs($0 - target) >= 0.04 }) != false {
            lastDialRequest = target
            onZoomChange(target)
        }

        guard ended else { return }
        self.dialStartZoom = nil
        lastDialRequest = nil
        if let stop = AGZoomDisplay.containingStop(for: target, in: zoomLevels) {
            selectedLevel = stop
            withAnimation(.snappy(duration: 0.25)) {
                proxy.scrollTo(stop, anchor: .center)
            }
        }
        dialDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isDialVisible = false
            }
        }
    }
}

enum AGZoomDisplay {
    static func number(_ zoom: CGFloat) -> String {
        Double(zoom).formatted(
            .number
                .precision(.fractionLength(0...1))
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    static func containingStop(for zoom: CGFloat, in levels: [CGFloat]) -> CGFloat? {
        guard let first = levels.first else { return nil }
        return levels.last(where: { $0 <= zoom + 0.005 }) ?? first
    }
}
