import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CrispyVibes

/// Deterministic pixel fixtures for raster image editor tests.
enum RasterImageTestFixtures {
    /// Opaque RGBA colors used by the four-quadrant fixture (top-left, top-right, bottom-left, bottom-right).
    static let quadrantColors: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (255, 0, 0),
        (0, 255, 0),
        (0, 0, 255),
        (255, 255, 0)
    ]

    /// Builds a `width`×`height` sRGB image split into four solid quadrants (top-left origin).
    static func quadrantImage(width: Int, height: Int) -> CGImage {
        let context = makeContext(width: width, height: height)
        let halfW = width / 2
        let halfH = height / 2
        // CGContext is bottom-left origin: top rows live at high y.
        let rects: [CGRect] = [
            CGRect(x: 0, y: height - halfH, width: halfW, height: halfH),
            CGRect(x: halfW, y: height - halfH, width: width - halfW, height: halfH),
            CGRect(x: 0, y: 0, width: halfW, height: height - halfH),
            CGRect(x: halfW, y: 0, width: width - halfW, height: height - halfH)
        ]
        for (rect, color) in zip(rects, quadrantColors) {
            context.setFillColor(CGColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1))
            context.fill(rect)
        }
        return context.makeImage()!
    }

    static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// Wraps a CGImage as an NSImage whose point size equals its pixel size.
    static func nsImage(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Reads the RGB value at a top-left-origin pixel coordinate.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let context = makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * context.bytesPerRow + x * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    /// Returns the CGImage backing an NSImage.
    static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Whether `actual` is within `tolerance` of `expected` on every channel.
    static func matches(_ actual: (r: UInt8, g: UInt8, b: UInt8), _ expected: (r: UInt8, g: UInt8, b: UInt8), tolerance: Int = 40) -> Bool {
        abs(Int(actual.r) - Int(expected.r)) <= tolerance &&
            abs(Int(actual.g) - Int(expected.g)) <= tolerance &&
            abs(Int(actual.b) - Int(expected.b)) <= tolerance
    }

    /// Encodes `images` into a file of `type`, tagging frame 0 with `orientation`.
    @discardableResult
    static func write(
        _ images: [CGImage],
        type: UTType,
        to url: URL,
        orientation: UInt32 = 1
    ) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil) else {
            return false
        }
        for (index, image) in images.enumerated() {
            var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
            if index == 0 {
                properties[kCGImagePropertyOrientation] = orientation
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    /// Builds a 16-bit-per-channel RGB image.
    static func sixteenBitImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 16,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
