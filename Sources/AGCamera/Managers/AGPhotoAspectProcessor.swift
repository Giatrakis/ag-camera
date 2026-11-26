import CoreGraphics
import Foundation
import ImageIO

enum AGPhotoAspectProcessor {
    static func crop(_ data: Data, to aspectRatio: AGPhotoAspectRatio) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let type = CGImageSourceGetType(source) else {
            throw CameraError.captureFailed
        }

        let width = image.width
        let height = image.height
        let targetRatio = width >= height
            ? aspectRatio.landscapeRatio
            : 1.0 / aspectRatio.landscapeRatio
        let currentRatio = Double(width) / Double(height)
        guard abs(currentRatio - targetRatio) > 0.001 else { return data }

        let cropWidth = currentRatio > targetRatio
            ? Int((Double(height) * targetRatio).rounded(.down)) : width
        let cropHeight = currentRatio > targetRatio
            ? height : Int((Double(width) / targetRatio).rounded(.down))
        let rect = CGRect(
            x: (width - cropWidth) / 2,
            y: (height - cropHeight) / 2,
            width: cropWidth,
            height: cropHeight
        )
        guard let cropped = image.cropping(to: rect) else {
            throw CameraError.captureFailed
        }

        let output = NSMutableData()
        guard let imageDestination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            throw CameraError.captureFailed
        }
        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        properties[kCGImagePropertyPixelWidth as String] = cropWidth
        properties[kCGImagePropertyPixelHeight as String] = cropHeight
        properties[kCGImageDestinationLossyCompressionQuality as String] = 1.0
        if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = cropWidth
            exif[kCGImagePropertyExifPixelYDimension as String] = cropHeight
            properties[kCGImagePropertyExifDictionary as String] = exif
        }
        CGImageDestinationAddImage(imageDestination, cropped, properties as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw CameraError.captureFailed
        }
        return output as Data
    }
}
