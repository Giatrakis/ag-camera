import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
#if canImport(AGCamera)
@testable import AGCamera
#else
@testable import ag_camera
#endif

@MainActor
struct AGPhotoAspectProcessorTests {
    @Test(arguments: [
        (AGPhotoAspectRatio.fourThree, 400, 300),
        (.sixteenNine, 400, 225),
        (.square, 300, 300)
    ])
    func cropsLandscapePhotoToSelectedAspect(
        aspect: AGPhotoAspectRatio,
        expectedWidth: Int,
        expectedHeight: Int
    ) throws {
        let source = try makePhoto(width: 400, height: 300)
        let cropped = try AGPhotoAspectProcessor.crop(source, to: aspect)
        let imageSource = try #require(CGImageSourceCreateWithData(cropped as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])

        #expect(image.width == expectedWidth)
        #expect(image.height == expectedHeight)
        #expect(properties[kCGImagePropertyOrientation as String] as? Int == 6)
        #expect(AGPhotoFormat.fileExtension(for: cropped) == "jpg")
    }

    @Test
    func aspectSelectionUpdatesConfiguration() {
        let manager = AGCameraManager()
        manager.setPhotoAspectRatio(.square)

        #expect(manager.photoAspectRatio == .square)
        #expect(manager.configuration.photoAspectRatio == .square)
    }

    @Test
    func cropsPortraitPhotoWithoutChangingOrientation() throws {
        let source = try makePhoto(width: 300, height: 400)
        let cropped = try AGPhotoAspectProcessor.crop(source, to: .sixteenNine)
        let imageSource = try #require(CGImageSourceCreateWithData(cropped as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any])

        #expect(image.width == 225)
        #expect(image.height == 400)
        #expect(properties[kCGImagePropertyOrientation as String] as? Int == 6)
    }

    private func makePhoto(width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cgImage = try #require(image.cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImagePropertyOrientation: 6
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
