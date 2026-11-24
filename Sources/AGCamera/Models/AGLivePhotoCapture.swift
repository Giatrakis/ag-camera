import Foundation

public struct AGLivePhotoCapture: Equatable, Sendable {
    public let photoData: Data
    public let pairedVideoURL: URL

    public init(photoData: Data, pairedVideoURL: URL) {
        self.photoData = photoData
        self.pairedVideoURL = pairedVideoURL
    }
}

public enum AGPhotoCaptureResult: Equatable, Sendable {
    case still(Data)
    case live(AGLivePhotoCapture)
}
