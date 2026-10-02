import CoreGraphics

/// Pure crop math for the raster image editor.
///
/// All rectangles use a **top-left origin** in both point space (the flipped canvas) and pixel
/// space (`CGImage.cropping(to:)`), so no vertical inversion is ever applied.
enum RasterImageCropGeometry {
    /// Smallest crop edge, in pixels, that the editor accepts.
    static let minimumPixelEdge: CGFloat = 2

    /// Maps a point-space selection to an integral, clamped pixel rectangle.
    ///
    /// Each edge is converted to pixels first, then rounded outward (`floor` for min edges,
    /// `ceil` for max edges) so the result always covers every pixel the selection touches.
    /// - Returns: `nil` when inputs are degenerate or the clamped result is below the minimum edge.
    static func pixelRect(
        forSelection selection: CGRect,
        imagePointSize: CGSize,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGRect? {
        guard !selection.isNull, !selection.isInfinite,
              let rect = coveringPixelRect(
                  forCanvasRect: selection,
                  canvasSize: imagePointSize,
                  pixelWidth: pixelWidth,
                  pixelHeight: pixelHeight
              ),
              rect.width >= minimumPixelEdge, rect.height >= minimumPixelEdge else {
            return nil
        }
        return rect
    }

    /// Maps a canvas rectangle onto a `pixelWidth`×`pixelHeight` bitmap that covers `canvasSize`,
    /// using independent X/Y scales and rounding each edge outward.
    ///
    /// Edges within `tolerance` pixels of a whole pixel snap to it, so rectangles that were
    /// already pixel-aligned never grow by a row or column from floating-point error.
    static func coveringPixelRect(
        forCanvasRect rect: CGRect,
        canvasSize: CGSize,
        pixelWidth: Int,
        pixelHeight: Int,
        tolerance: CGFloat = 1e-6
    ) -> CGRect? {
        guard canvasSize.width > 0, canvasSize.height > 0, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }
        let normalized = rect.standardized
        let scaleX = CGFloat(pixelWidth) / canvasSize.width
        let scaleY = CGFloat(pixelHeight) / canvasSize.height
        let maxWidth = CGFloat(pixelWidth)
        let maxHeight = CGFloat(pixelHeight)

        func edge(_ value: CGFloat, roundingUp: Bool, upperBound: CGFloat) -> CGFloat {
            let nearest = value.rounded()
            let snapped = abs(value - nearest) <= tolerance ? nearest : (roundingUp ? ceil(value) : floor(value))
            return min(max(snapped, 0), upperBound)
        }

        let minX = edge(normalized.minX * scaleX, roundingUp: false, upperBound: maxWidth)
        let minY = edge(normalized.minY * scaleY, roundingUp: false, upperBound: maxHeight)
        let maxX = edge(normalized.maxX * scaleX, roundingUp: true, upperBound: maxWidth)
        let maxY = edge(normalized.maxY * scaleY, roundingUp: true, upperBound: maxHeight)
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }

    /// Converts a pixel rectangle back into the point space of an image with the given sizes.
    static func pointRect(
        forPixelRect pixelRect: CGRect,
        imagePointSize: CGSize,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGRect {
        let scaleX = imagePointSize.width / CGFloat(max(pixelWidth, 1))
        let scaleY = imagePointSize.height / CGFloat(max(pixelHeight, 1))
        return CGRect(
            x: pixelRect.minX * scaleX,
            y: pixelRect.minY * scaleY,
            width: pixelRect.width * scaleX,
            height: pixelRect.height * scaleY
        )
    }
}
