import AppKit
import CoreGraphics

/// Replays `ImageEditOperation`s over a base bitmap at whatever pixel scale the base carries.
///
/// Thread-safe: draws only into private bitmap contexts, so it runs on the main thread for the
/// display proxy and on a background queue for full-resolution export.
struct RasterImageRenderer: RasterImageRendering {
    let effects: RasterImageEffects

    init(effects: RasterImageEffects = RasterImageEffects()) {
        self.effects = effects
    }

    /// Applies color adjustments to a base bitmap (callers do this before replaying operations;
    /// `render` itself ignores `.adjust` operations).
    func applyAdjustments(_ adjustments: RasterImageAdjustments, to image: CGImage) -> CGImage? {
        effects.apply(adjustments, to: image)
    }

    func render(
        base: CGImage,
        baseCanvasSize: CGSize,
        operations: [ImageEditOperation]
    ) -> CGImage? {
        var image = base
        var canvasSize = baseCanvasSize
        var pending: [ImageEditOperation] = []
        // Pixels per canvas unit, fixed for the whole replay so rounding never compounds.
        var scale = PixelScale(
            x: CGFloat(base.width) / max(baseCanvasSize.width, 0.0001),
            y: CGFloat(base.height) / max(baseCanvasSize.height, 0.0001)
        )

        for operation in operations {
            guard operation.isGeometric else {
                pending.append(operation)
                continue
            }
            if !pending.isEmpty {
                guard let flattened = flatten(image, canvasSize: canvasSize, overlays: pending) else { return nil }
                image = flattened
                pending.removeAll()
            }
            guard let transformed = apply(operation, to: image, canvasSize: canvasSize, scale: scale) else { return nil }
            image = transformed
            canvasSize = operation.resultingCanvasSize(from: canvasSize)
            if case .rotate(let turns) = operation, abs(turns) % 2 == 1 {
                scale = PixelScale(x: scale.y, y: scale.x)
            }
        }
        if !pending.isEmpty {
            return flatten(image, canvasSize: canvasSize, overlays: pending)
        }
        return image
    }

    private struct PixelScale {
        var x: CGFloat
        var y: CGFloat
    }

    private func apply(_ operation: ImageEditOperation, to image: CGImage, canvasSize: CGSize, scale: PixelScale) -> CGImage? {
        switch operation {
        case .stroke, .annotation, .markup, .adjust:
            return image
        case .removeBackground(let mask):
            guard let context = makeContext(width: image.width, height: image.height, like: image) else { return nil }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.interpolationQuality = .high
            // Grayscale image mask: white keeps pixels, black makes them transparent.
            context.clip(to: rect, mask: mask.image)
            context.draw(image, in: rect)
            return context.makeImage()
        case .crop(let rect):
            // Map through the bitmap's actual per-axis scale: proxies round width and height independently.
            guard let pixelRect = RasterImageCropGeometry.coveringPixelRect(
                forCanvasRect: rect,
                canvasSize: canvasSize,
                pixelWidth: image.width,
                pixelHeight: image.height
            ), pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
            return image.cropping(to: pixelRect)
        case .rotate(let quarterTurns):
            let swaps = abs(quarterTurns) % 2 == 1
            return resample(image, canvasSize: canvasSize, operation: operation,
                            pixelSize: swaps ? (image.height, image.width) : (image.width, image.height),
                            interpolation: .none)
        case .flip:
            return resample(image, canvasSize: canvasSize, operation: operation,
                            pixelSize: (image.width, image.height), interpolation: .none)
        case .straighten, .resize:
            let output = operation.resultingCanvasSize(from: canvasSize)
            let pixelSize = (max(Int((output.width * scale.x).rounded()), 1), max(Int((output.height * scale.y).rounded()), 1))
            return resample(image, canvasSize: canvasSize, operation: operation, pixelSize: pixelSize, interpolation: .high)
        }
    }

    /// Draws `image` plus vector `overlays` into a new bitmap of the same pixel size.
    func flatten(_ image: CGImage, canvasSize: CGSize, overlays: [ImageEditOperation]) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, canvasSize.width > 0, canvasSize.height > 0,
              let context = makeContext(width: width, height: height, like: image) else {
            return nil
        }
        context.interpolationQuality = .high
        // Base pixels are drawn in CoreGraphics' native bottom-left space, so they stay upright.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Overlays use a flipped, canvas-unit space that matches the on-screen canvas.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / canvasSize.width, y: -CGFloat(height) / canvasSize.height)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.shouldAntialias = true
        for overlay in overlays {
            if let item = overlay.markupItem, item.isPixelEffect {
                graphicsContext.flushGraphics()
                applyPixelEffect(item, in: context, canvasSize: canvasSize, pixelWidth: width, pixelHeight: height)
            } else {
                RasterImageOverlayPainter.draw(overlay, canvasSize: canvasSize)
            }
        }
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    func makeContext(width: Int, height: Int, like image: CGImage) -> CGContext? {
        guard width > 0, height > 0, let colorSpace = Self.workingColorSpace(for: image) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func workingColorSpace(for image: CGImage) -> CGColorSpace? {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB)
    }
}
