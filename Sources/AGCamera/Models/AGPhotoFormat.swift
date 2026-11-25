import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum AGPhotoFormat: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case jpeg
    case heif

    public var id: Self { self }

    public var fileType: AVFileType? {
        switch self {
        case .automatic: nil
        case .jpeg: .jpg
        case .heif: .heic
        }
    }

    public var codec: AVVideoCodecType? {
        switch self {
        case .automatic: nil
        case .jpeg: .jpeg
        case .heif: .hevc
        }
    }

    public static func fileExtension(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { return nil }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "heic" }
        if type.conforms(to: .jpeg) { return "jpg" }
        return nil
    }
}
