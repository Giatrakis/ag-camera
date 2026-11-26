import AVKit
import SwiftUI

struct AGRecentCapture: Identifiable {
    enum Content {
        case photo(UIImage)
        case live(AGLivePhotoCapture)
        case video(URL)
    }

    let id = UUID()
    let content: Content
    let thumbnail: UIImage?
}

struct AGRecentCaptureView: View {
    let capture: AGRecentCapture

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch capture.content {
                case .photo(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                case .live(let live):
                    if FileManager.default.fileExists(atPath: live.pairedVideoURL.path) {
                        AGLivePhotoView(capture: live)
                    } else if let thumbnail = capture.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                    }
                case .video(let url):
                    VideoPlayer(player: AVPlayer(url: url))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle("Recent Capture")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
