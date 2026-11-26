public enum AGPhotoAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case fourThree
    case sixteenNine
    case square

    public var id: Self { self }

    public var title: String {
        switch self {
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        case .square: "1:1"
        }
    }

    public var landscapeRatio: Double {
        switch self {
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .square: 1.0
        }
    }
}
