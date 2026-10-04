import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO-backed processor that emits metadata-free canonical and thumbnail PNGs off-main.
struct ScreenCaptureThumbnailService: ScreenCaptureHistoryImageProcessing {
    func prepare(
        pngData: Data,
        maximumThumbnailPixelSize: Int
    ) async throws -> ScreenCaptureHistoryPreparedImages {
        let child = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard maximumThumbnailPixelSize > 0,
                  let image = Self.decode(pngData) else {
                throw ScreenCaptureHistoryError.decodingFailed
            }
            try Task.checkCancellation()
            let canonicalPNG = try Self.encode(image)
            try Task.checkCancellation()
            let thumbnail = try Self.makeThumbnail(image, maximumPixelSize: maximumThumbnailPixelSize)
            try Task.checkCancellation()
            let thumbnailPNG = try Self.encode(thumbnail)
            try Task.checkCancellation()
            return ScreenCaptureHistoryPreparedImages(
                canonicalPNG: canonicalPNG,
                thumbnailPNG: thumbnailPNG,
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        }
        return try await withTaskCancellationHandler {
            try await child.value
        } onCancel: {
            child.cancel()
        }
    }

    func decodePNG(_ data: Data) async throws -> ScreenCaptureHistoryImage {
        let child = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard let image = Self.decode(data) else {
                throw ScreenCaptureHistoryError.decodingFailed
            }
            try Task.checkCancellation()
            return ScreenCaptureHistoryImage(cgImage: image)
        }
        return try await withTaskCancellationHandler {
            try await child.value
        } onCancel: {
            child.cancel()
        }
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1 else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func makeThumbnail(_ image: CGImage, maximumPixelSize: Int) throws -> CGImage {
        let scale = min(
            1,
            Double(maximumPixelSize) / Double(max(image.width, image.height))
        )
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ScreenCaptureHistoryError.encodingFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage() else {
            throw ScreenCaptureHistoryError.encodingFailed
        }
        return thumbnail
    }

    private static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureHistoryError.encodingFailed
        }
        // A decoded CGImage has no source metadata. Supplying no properties prevents metadata copying.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), !data.isEmpty else {
            throw ScreenCaptureHistoryError.encodingFailed
        }
        return data as Data
    }
}
