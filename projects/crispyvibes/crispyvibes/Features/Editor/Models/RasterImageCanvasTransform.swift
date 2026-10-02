import CoreGraphics

/// The single coordinate model shared by the canvas, the renderer, and export.
///
/// Canvas units use a top-left origin. A transform pairs a canvas size with a pixel scale
/// (pixels per canvas unit) for one concrete bitmap — the display proxy or the export image.
struct RasterImageCanvasTransform: Equatable, Sendable {
    let canvasSize: CGSize
    let scale: CGFloat

    /// Integral pixel dimensions of a bitmap covering the canvas at this scale.
    var pixelSize: (width: Int, height: Int) {
        (max(Int((canvasSize.width * scale).rounded()), 1), max(Int((canvasSize.height * scale).rounded()), 1))
    }

    func pixelPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    func canvasPoint(fromPixel point: CGPoint) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(x: point.x / scale, y: point.y / scale)
    }

    /// Snaps a canvas-space selection outward to whole pixels and returns it in canvas units.
    /// - Returns: `nil` if the snapped rectangle is smaller than the minimum crop edge.
    func snappedCropRect(forSelection selection: CGRect) -> CGRect? {
        let pixels = pixelSize
        guard let pixelRect = RasterImageCropGeometry.pixelRect(
            forSelection: selection,
            imagePointSize: canvasSize,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height
        ) else {
            return nil
        }
        return RasterImageCropGeometry.pointRect(
            forPixelRect: pixelRect,
            imagePointSize: canvasSize,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height
        )
    }

    /// Integral pixel rectangle (top-left origin) for a canvas rectangle, clamped to the bitmap.
    func pixelRect(forCanvasRect rect: CGRect) -> CGRect {
        let pixels = pixelSize
        return RasterImageCropGeometry.coveringPixelRect(
            forCanvasRect: rect,
            canvasSize: canvasSize,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height
        ) ?? .zero
    }
}
