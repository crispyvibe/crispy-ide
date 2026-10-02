import AppKit
import Foundation

/// Viewport framing for the raster preview.
extension RasterImageFilePreviewCoordinator: RasterImageViewportControlling {
    /// Canvas units per device pixel is `1 / backingScale` at actual size.
    var backingScale: CGFloat {
        max(scrollView?.crispyvibesBackingScaleFactor() ?? 1, 1)
    }

    /// Fits the whole image in the viewport (never enlarging beyond actual size).
    func fitToWindow() {
        guard let scrollView, let canvasView, canvasView.hasRenderableImage else { return }
        let viewport = scrollView.contentSize
        let imageSize = canvasView.frame.size
        guard viewport.width > 0, viewport.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            scrollView.magnification = 1
            return
        }
        let actualSize = (canvasView.session?.document.exportScale ?? 1) / backingScale
        let fit = min(actualSize, min(viewport.width / imageSize.width, viewport.height / imageSize.height))
        scrollView.magnification = min(max(fit, scrollView.minMagnification), scrollView.maxMagnification)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refreshCenteringInsets()
        reportZoom()
    }

    func zoomToActualSize() {
        guard let scrollView, let canvasView, canvasView.hasRenderableImage else { return }
        setMagnification((canvasView.session?.document.exportScale ?? 1) / backingScale, in: scrollView)
    }

    func zoom(by factor: CGFloat) {
        guard let scrollView else { return }
        setMagnification(scrollView.magnification * factor, in: scrollView)
    }

    /// Zoom where 100% shows one export pixel per device pixel.
    var zoomPercent: Double {
        guard let scrollView else { return 100 }
        let exportScale = canvasView?.session?.document.exportScale ?? 1
        return Double(scrollView.magnification * backingScale / max(exportScale, 0.0001) * 100)
    }

    func reportZoom() {
        let percent = zoomPercent
        DispatchQueue.main.async { [weak self] in
            self?.viewModelForViewport?.viewportDidChange(zoomPercent: percent)
        }
    }

    private func setMagnification(_ magnification: CGFloat, in scrollView: NSScrollView) {
        let clamped = min(max(magnification, scrollView.minMagnification), scrollView.maxMagnification)
        let visible = scrollView.contentView.bounds
        scrollView.setMagnification(clamped, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
        refreshCenteringInsets()
        reportZoom()
    }

    func refreshCenteringInsets() {
        guard let scrollView, let canvasView, canvasView.hasRenderableImage else { return }
        let imageSize = canvasView.frame.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let targetInsets = RasterImagePreviewGeometry.centeredInsets(
            viewportSize: scrollView.contentSize,
            imageSize: imageSize,
            magnification: scrollView.magnification
        )
        let current = scrollView.contentInsets
        if abs(current.left - targetInsets.left) > 0.5 ||
            abs(current.right - targetInsets.right) > 0.5 ||
            abs(current.top - targetInsets.top) > 0.5 ||
            abs(current.bottom - targetInsets.bottom) > 0.5 {
            scrollView.contentInsets = targetInsets
        }
    }

    func captureViewportContext() -> ViewportContext? {
        guard let scrollView, let canvasView, canvasView.hasRenderableImage else { return nil }
        let visibleRect = scrollView.contentView.bounds
        let horizontalRange = max(0, canvasView.bounds.width - visibleRect.width)
        let verticalRange = max(0, canvasView.bounds.height - visibleRect.height)
        let horizontalFraction = horizontalRange > 0 ? visibleRect.origin.x / horizontalRange : 0
        let verticalFraction = verticalRange > 0 ? visibleRect.origin.y / verticalRange : 0
        return ViewportContext(
            magnification: scrollView.magnification,
            horizontalFraction: min(max(horizontalFraction, 0), 1),
            verticalFraction: min(max(verticalFraction, 0), 1)
        )
    }

    func restoreViewportContext(_ context: ViewportContext) {
        guard let scrollView, let canvasView, canvasView.hasRenderableImage else { return }
        scrollView.magnification = min(max(context.magnification, scrollView.minMagnification), scrollView.maxMagnification)
        let visibleRect = scrollView.contentView.bounds
        let horizontalRange = max(0, canvasView.bounds.width - visibleRect.width)
        let verticalRange = max(0, canvasView.bounds.height - visibleRect.height)
        scrollView.contentView.scroll(to: CGPoint(
            x: horizontalRange * context.horizontalFraction,
            y: verticalRange * context.verticalFraction
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
