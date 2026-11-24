public enum AGLivePhotoMode: CaseIterable, Identifiable, Sendable {
    case off
    case on
    case auto

    public var id: Self { self }

    public var title: String {
        switch self {
        case .off: "Off"
        case .on: "On"
        case .auto: "Auto"
        }
    }
}
