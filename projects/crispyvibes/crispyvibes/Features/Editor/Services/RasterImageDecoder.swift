import CoreGraphics
import Foundation
import ImageIO

/// Result of decoding an editable raster image.
struct RasterImageDecodeResult: @unchecked Sendable {
    /// Upright pixels (EXIF orientation already applied).
    let image: CGImage
    /// Facts about the on-disk source.
    let sourceInfo: RasterImageSourceInfo

    /// `true` when `image` holds every source pixel (not a downsampled proxy).
    var isFullResolution: Bool {
        image.width >= sourceInfo.pixelWidth && image.height >= sourceInfo.pixelHeight
    }
}

/// Decodes raster images into canonical upright pixels on every code path.
///
/// Both the downsampled-proxy path and the full-resolution path apply EXIF orientation
/// exactly once, so the editor always operates on the same visual orientation and exports
/// can write orientation 1.
struct RasterImageDecoder: RasterImageDecoding {
    /// Sources whose longest oriented edge is at or below this limit are decoded at full
    /// resolution so they remain safely saveable.
    var fullResolutionEdgeLimit: Int = 4096

    /// Reads source facts without decoding pixels.
    func sourceInfo(for source: CGImageSource) -> RasterImageSourceInfo? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              rawWidth > 0, rawHeight > 0 else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let swapsAxes = (5...8).contains(orientation)
        return RasterImageSourceInfo(
            pixelWidth: swapsAxes ? rawHeight : rawWidth,
            pixelHeight: swapsAxes ? rawWidth : rawHeight,
            exifOrientation: (1...8).contains(orientation) ? orientation : 1,
            frameCount: max(CGImageSourceGetCount(source), 1),
            bitDepth: (properties[kCGImagePropertyDepth] as? Int) ?? 8,
            hasGainMap: Self.hasGainMap(in: source)
        )
    }

    /// Decodes `url` into upright pixels, preferring full resolution when the source is small
    /// enough, otherwise a proxy whose longest edge is at most `maxPixelSize`.
    func decode(contentsOf url: URL, maxPixelSize: Int) -> RasterImageDecodeResult? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let info = sourceInfo(for: source) else {
            return nil
        }
        let limit = max(maxPixelSize, fullResolutionEdgeLimit)
        if info.longestEdge <= limit, let full = fullResolutionImage(from: source, info: info) {
            return RasterImageDecodeResult(image: full, sourceInfo: info)
        }
        if let proxy = proxyImage(from: source, maxPixelSize: maxPixelSize) {
            return RasterImageDecodeResult(image: proxy, sourceInfo: info)
        }
        if let full = fullResolutionImage(from: source, info: info) {
            return RasterImageDecodeResult(image: full, sourceInfo: info)
        }
        return nil
    }

    /// Decodes every pixel of `url` upright, for export.
    func fullResolutionImage(contentsOf url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let info = sourceInfo(for: source) else {
            return nil
        }
        return fullResolutionImage(from: source, info: info)
    }

    /// Decodes every source pixel and applies EXIF orientation.
    func fullResolutionImage(from source: CGImageSource, info: RasterImageSourceInfo) -> CGImage? {
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            return nil
        }
        let orientation = CGImagePropertyOrientation(rawValue: info.exifOrientation) ?? .up
        return RasterImageOrientation.upright(raw, orientation: orientation)
    }

    /// Decodes a downsampled, EXIF-transformed proxy.
    func proxyImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func hasGainMap(in source: CGImageSource) -> Bool {
        let types: [CFString] = [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap]
        return types.contains { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }
    }
}

/// Applies EXIF orientation to raw decoded pixels.
enum RasterImageOrientation {
    /// Returns `image` redrawn upright. Orientation `.up` returns the input unchanged.
    static func upright(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        guard orientation != .up else { return image }
        let rawWidth = CGFloat(image.width)
        let rawHeight = CGFloat(image.height)
        let swapsAxes = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let outWidth = swapsAxes ? rawHeight : rawWidth
        let outHeight = swapsAxes ? rawWidth : rawHeight

        let bitsPerComponent = image.bitsPerComponent == 16 ? 16 : 8
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace,
              let context = CGContext(
                  data: nil,
                  width: Int(outWidth),
                  height: Int(outHeight),
                  bitsPerComponent: bitsPerComponent,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.concatenate(transform(for: orientation, outWidth: outWidth, outHeight: outHeight))
        context.draw(image, in: CGRect(x: 0, y: 0, width: rawWidth, height: rawHeight))
        return context.makeImage()
    }

    /// Bottom-left-origin transform that maps raw pixels into the upright output canvas.
    static func transform(
        for orientation: CGImagePropertyOrientation,
        outWidth: CGFloat,
        outHeight: CGFloat
    ) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        switch orientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: outWidth, y: outHeight).rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: outWidth, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: outHeight).rotated(by: -.pi / 2)
        default:
            break
        }
        switch orientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: outWidth, y: 0).scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: outHeight, y: 0).scaledBy(x: -1, y: 1)
        default:
            break
        }
        return transform
    }
}
