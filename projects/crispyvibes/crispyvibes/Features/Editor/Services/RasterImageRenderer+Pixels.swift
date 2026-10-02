import AppKit
import CoreGraphics

/// Bitmap resampling and in-place pixel effects for `RasterImageRenderer`.
extension RasterImageRenderer {
    /// Redraws `image` through the operation's top-left canvas transform into a new bitmap.
    func resample(
        _ image: CGImage,
        canvasSize: CGSize,
        operation: ImageEditOperation,
        pixelSize: (width: Int, height: Int),
        interpolation: CGInterpolationQuality
    ) -> CGImage? {
        let geometry = operation.geometry(for: canvasSize)
        guard canvasSize.width > 0, canvasSize.height > 0, geometry.size.width > 0, geometry.size.height > 0,
              let context = makeContext(width: pixelSize.width, height: pixelSize.height, like: image) else {
            return nil
        }
        let oldHeight = CGFloat(image.height)
        let newHeight = CGFloat(pixelSize.height)
        // Bottom-left source pixels → top-left source pixels → canvas → transformed canvas → top-left
        // destination pixels → bottom-left destination pixels.
        let flipOld = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: oldHeight)
        let pixelsToCanvas = CGAffineTransform(scaleX: canvasSize.width / CGFloat(image.width), y: canvasSize.height / oldHeight)
        let canvasToPixels = CGAffineTransform(
            scaleX: CGFloat(pixelSize.width) / geometry.size.width,
            y: newHeight / geometry.size.height
        )
        let flipNew = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: newHeight)
        let transform = flipOld
            .concatenating(pixelsToCanvas)
            .concatenating(geometry.transform)
            .concatenating(canvasToPixels)
            .concatenating(flipNew)
        context.interpolationQuality = interpolation
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Blurs or pixelates the already-composited pixels under `item`, in place.
    func applyPixelEffect(_ item: RasterMarkupItem, in context: CGContext, canvasSize: CGSize, pixelWidth: Int, pixelHeight: Int) {
        guard let rect = item.rect?.standardized,
              let pixelRect = RasterImageCropGeometry.coveringPixelRect(
                  forCanvasRect: rect, canvasSize: canvasSize, pixelWidth: pixelWidth, pixelHeight: pixelHeight
              ), pixelRect.width >= 1, pixelRect.height >= 1,
              let snapshot = context.makeImage(),
              let region = snapshot.cropping(to: pixelRect) else {
            return
        }
        let strength = item.effectStrength * CGFloat(pixelWidth) / max(canvasSize.width, 0.0001)
        let processed: CGImage?
        switch item.kind {
        case .blur: processed = effects.blur(region, radius: strength)
        case .pixelate: processed = effects.pixelate(region, cellSize: strength)
        default: processed = nil
        }
        guard let processed else { return }
        // Draw in raw bottom-left pixel space, bypassing the flipped canvas transform.
        context.saveGState()
        context.concatenate(context.ctm.inverted())
        context.interpolationQuality = .none
        context.draw(processed, in: CGRect(
            x: pixelRect.minX,
            y: CGFloat(pixelHeight) - pixelRect.maxY,
            width: pixelRect.width,
            height: pixelRect.height
        ))
        context.restoreGState()
    }
}
