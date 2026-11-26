import SwiftUI

public struct AGInputPickerButton: View {
    @Binding private var outputType: AGOutputType
    private let moreControlsNamespace: Namespace.ID?
    private let onInteractionChanged: (Bool) -> Void
    private let stopWidth: CGFloat = 80
    private let collapsedWidth: CGFloat = 206
    private let controlHeight: CGFloat = 44
    private let edgeFadeWidth: CGFloat = 15

    @State private var centeredMode: Mode = .photo
    @State private var scrollOffset: CGFloat = 0
    @State private var isExpanded = false
    @State private var didUserScroll = false

    public init(outputType: Binding<AGOutputType>) {
        self._outputType = outputType
        self.moreControlsNamespace = nil
        self.onInteractionChanged = { _ in }
    }

    init(
        outputType: Binding<AGOutputType>,
        moreControlsNamespace: Namespace.ID,
        onInteractionChanged: @escaping (Bool) -> Void
    ) {
        self._outputType = outputType
        self.moreControlsNamespace = moreControlsNamespace
        self.onInteractionChanged = onInteractionChanged
    }

    public var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                let visibleWidth = isExpanded ? geometry.size.width : collapsedWidth
                let fadeFraction = edgeFadeWidth / visibleWidth

                ZStack {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(width: collapsedWidth, height: controlHeight)
                        .opacity(isExpanded ? 0 : 1)

                    selectedCapsule

                    ZStack {
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach([Mode.video, .photo]) { mode in
                                    modeLabel(mode)
                                        .frame(width: stopWidth, height: controlHeight)
                                        .id(mode)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, max(0, (geometry.size.width - stopWidth) / 2))
                        }
                        .scrollIndicators(.hidden)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in setExpanded(true) }
                                .onEnded { _ in
                                    if !didUserScroll { setExpanded(false) }
                                }
                        )
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.contentOffset.x
                        } action: { _, offset in
                            guard offset.isFinite else { return }
                            scrollOffset = offset
                            let mode = Mode.nearest(to: offset, step: stopWidth)
                            if centeredMode != mode { centeredMode = mode }
                        }
                        .onScrollPhaseChange { _, phase, context in
                            switch phase {
                            case .interacting, .decelerating:
                                didUserScroll = true
                                setExpanded(true)
                            case .idle:
                                guard didUserScroll else { return }
                                didUserScroll = false
                                let mode = Mode.nearest(to: context.geometry.contentOffset.x, step: stopWidth)
                                if let type = mode.outputType { outputType = type }
                                withAnimation(.smooth(duration: 0.22)) {
                                    proxy.scrollTo(mode, anchor: .center)
                                }
                                setExpanded(false)
                            default:
                                break
                            }
                        }

                        ForEach(Mode.allCases.filter { $0.outputType == nil }) { mode in
                            Text(mode.title)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.38))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(width: stopWidth, height: controlHeight)
                                .position(
                                    x: geometry.size.width / 2
                                        + CGFloat(mode.rawValue - Mode.video.rawValue) * stopWidth
                                        - scrollOffset,
                                    y: controlHeight / 2
                                )
                                .allowsHitTesting(false)
                                .accessibilityLabel("\(mode.title), unavailable")
                        }
                    }
                    .mask {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white, location: fadeFraction),
                                        .init(color: .white, location: 1 - fadeFraction),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: visibleWidth, height: controlHeight)
                    }
                }
                .frame(width: geometry.size.width, height: controlHeight)
                .animation(.smooth(duration: 0.2), value: isExpanded)
            }
            .frame(height: controlHeight)
            .onAppear {
                let mode = Mode(outputType: outputType)
                centeredMode = mode
                proxy.scrollTo(mode, anchor: .center)
            }
            .onChange(of: outputType) { _, newValue in
                let mode = Mode(outputType: newValue)
                withAnimation(.smooth(duration: 0.22)) {
                    centeredMode = mode
                    proxy.scrollTo(mode, anchor: .center)
                }
            }
            .onDisappear { setExpanded(false) }
        }
        .sensoryFeedback(.selection, trigger: centeredMode)
        .accessibilityLabel("Camera mode")
    }

    @ViewBuilder
    private var selectedCapsule: some View {
        let capsule = Text(centeredMode.title)
            .font(.footnote)
            .foregroundStyle(.clear)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 20)
            .frame(height: controlHeight - 4)
            .background(.white.opacity(0.07), in: Capsule())
            .agCameraGlassCapsule()
            .overlay(Capsule().strokeBorder(.white.opacity(0.24)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        if let moreControlsNamespace {
            capsule.matchedTransitionSource(id: "moreControls", in: moreControlsNamespace)
        } else {
            capsule
        }
    }

    private func modeLabel(_ mode: Mode) -> some View {
        Button {
            if let type = mode.outputType { outputType = type }
        } label: {
            Text(mode.title)
                .font(.footnote)
                .foregroundStyle(mode == centeredMode ? .yellow : .white.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == centeredMode ? .isSelected : [])
    }
}

// MARK: - Actions
private extension AGInputPickerButton {
    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        onInteractionChanged(expanded)
    }
}

private extension AGInputPickerButton {
    enum Mode: Int, CaseIterable, Identifiable {
        case timeLapse
        case slowMotion
        case cinematic
        case video
        case photo
        case portrait
        case spatial
        case panorama

        var id: Self { self }

        var title: String {
            switch self {
            case .timeLapse: "TIME-LAPSE"
            case .slowMotion: "SLO-MO"
            case .cinematic: "CINEMATIC"
            case .video: "VIDEO"
            case .photo: "PHOTO"
            case .portrait: "PORTRAIT"
            case .spatial: "SPATIAL"
            case .panorama: "PANO"
            }
        }

        var outputType: AGOutputType? {
            switch self {
            case .video: .video
            case .photo: .photo
            default: nil
            }
        }

        init(outputType: AGOutputType) {
            self = outputType == .video ? .video : .photo
        }

        static func nearest(to offset: CGFloat, step: CGFloat) -> Self {
            guard offset.isFinite, step > 0 else { return .photo }
            return offset < step / 2 ? .video : .photo
        }
    }
}
