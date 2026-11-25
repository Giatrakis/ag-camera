import Photos
import PhotosUI
import SwiftUI

public struct AGLivePhotoView: View {
    public let capture: AGLivePhotoCapture

    @State private var livePhoto: PHLivePhoto?
    @State private var placeholderImage: UIImage?
    @State private var requestID: PHLivePhotoRequestID?
    @State private var stillFileURL: URL?
    @State private var requestToken = UUID()

    public init(capture: AGLivePhotoCapture) {
        self.capture = capture
    }

    public var body: some View {
        Group {
            if let livePhoto {
                LivePhotoPlayer(livePhoto: livePhoto)
            } else if let placeholderImage {
                Image(uiImage: placeholderImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }
        }
        .task(id: capture.pairedVideoURL) {
            loadLivePhoto()
        }
        .onDisappear {
            cancelLoading()
        }
    }

    private func loadLivePhoto() {
        cancelLoading()
        let token = UUID()
        requestToken = token
        placeholderImage = UIImage(data: capture.photoData)
        guard let photoFileExtension = capture.photoFileExtension else { return }
        let stillURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(photoFileExtension)
        do {
            try capture.photoData.write(to: stillURL)
            stillFileURL = stillURL
        } catch {
            return
        }
        requestID = PHLivePhoto.request(
            withResourceFileURLs: [stillURL, capture.pairedVideoURL],
            placeholderImage: placeholderImage,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit
        ) { result, info in
            guard info[PHLivePhotoInfoCancelledKey] as? Bool != true,
                  let result else { return }
            Task { @MainActor in
                guard requestToken == token else { return }
                livePhoto = result
            }
        }
    }

    private func cancelLoading() {
        requestToken = UUID()
        if let requestID {
            PHLivePhoto.cancelRequest(withRequestID: requestID)
            self.requestID = nil
        }
        if let stillFileURL {
            try? FileManager.default.removeItem(at: stillFileURL)
            self.stillFileURL = nil
        }
    }
}

private struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        guard uiView.livePhoto !== livePhoto else { return }
        uiView.livePhoto = livePhoto
        uiView.startPlayback(with: .hint)
    }
}
