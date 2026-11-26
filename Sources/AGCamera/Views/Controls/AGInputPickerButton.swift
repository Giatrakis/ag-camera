import SwiftUI

public struct AGInputPickerButton: View {
    @Binding private var outputType: AGOutputType
    private let moreControlsNamespace: Namespace.ID?
    private let stopWidth: CGFloat = 88
    private let controlHeight: CGFloat = 42

    @State private var didUserScroll = false

    public init(outputType: Binding<AGOutputType>) {
        self._outputType = outputType
        self.moreControlsNamespace = nil
    }

    init(outputType: Binding<AGOutputType>, moreControlsNamespace: Namespace.ID) {
        self._outputType = outputType
        self.moreControlsNamespace = moreControlsNamespace
    }

    public var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        modeButton(.video)
                        modeButton(.photo)
                        Text("PORTRAIT")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: stopWidth, height: controlHeight)
                            .offset(x: outputType == .photo ? 22 : 0)
                            .accessibilityLabel("Portrait mode unavailable")
                    }
                    .padding(.horizontal, max(0, (geometry.size.width - stopWidth) / 2))
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(AGCameraModePagingBehavior(step: stopWidth))
                .onScrollPhaseChange { _, phase, context in
                    switch phase {
                    case .interacting, .decelerating:
                        didUserScroll = true
                    case .idle:
                        guard didUserScroll else { return }
                        didUserScroll = false
                        let offset = context.geometry.contentOffset.x
                        guard offset.isFinite else { return }
                        let selected: AGOutputType = offset < stopWidth / 2 ? .video : .photo
                        select(selected)
                        withAnimation(.smooth(duration: 0.25)) {
                            proxy.scrollTo(selected, anchor: .center)
                        }
                    default:
                        break
                    }
                }
            }
            .frame(height: controlHeight)
            .agCameraGlassCapsule()
            .overlay {
                selectedCapsule
            }
            .onAppear { proxy.scrollTo(outputType, anchor: .center) }
            .onChange(of: outputType) { _, newValue in
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: outputType)
        .accessibilityLabel("Camera mode")
    }

    @ViewBuilder
    private var selectedCapsule: some View {
        let capsule = Text(outputType.title.uppercased())
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.yellow)
            .frame(width: stopWidth, height: controlHeight)
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

    private func modeButton(_ mode: AGOutputType) -> some View {
        Button {
            select(mode)
        } label: {
            Text(mode.title.uppercased())
                .font(.subheadline)
                .foregroundStyle(mode == outputType ? .clear : .white.opacity(0.8))
                .frame(width: stopWidth, height: controlHeight)
                .offset(x: mode == .video && outputType == .photo ? 29 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == outputType ? .isSelected : [])
        .id(mode)
    }

    private func select(_ mode: AGOutputType) {
        outputType = mode
    }
}

private struct AGCameraModePagingBehavior: ScrollTargetBehavior {
    let step: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard step > 0 else { return }
        let maximumOffset = max(0, context.contentSize.width - context.containerSize.width)
        target.rect.origin.x = min(maximumOffset, max(0, (target.rect.origin.x / step).rounded() * step))
    }
}
