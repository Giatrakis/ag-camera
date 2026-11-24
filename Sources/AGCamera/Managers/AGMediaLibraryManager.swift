//
//  AGMediaLibraryManager.swift
//  ag-camera
//

import Photos
import UIKit

@MainActor
class AGMediaLibraryManager {

    private let permissionManager: AGPermissionManager

    init(permissionManager: AGPermissionManager) {
        self.permissionManager = permissionManager
    }

    func savePhotoToLibrary(_ data: Data) async throws {
        guard await permissionManager.requestPhotoLibraryPermission() else {
            throw CameraError.permissionDenied
        }

        guard let image = UIImage(data: data) else {
            throw CameraError.captureFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAsset(from: image)
        }
    }

    func saveVideoToLibrary(url: URL) async throws {
        guard await permissionManager.requestPhotoLibraryPermission() else {
            throw CameraError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }

        try? FileManager.default.removeItem(at: url)
    }
}
