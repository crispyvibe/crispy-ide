import AppKit

extension RasterImageMemoryPreview.Coordinator {
    func markInitialFitPending() {
        isInitialFitPending = true
    }

    func viewportDidLayout() {
        hasReceivedLayout = true
        if !applyPendingInitialFitIfPossible() {
            refreshCenteringInsets()
        }
    }

    func resetScrollPosition() { fitToWindow() }

    func fitToWindow() {
        guard applyFitToWindow() else { return }
        isInitialFitPending = false
    }

    @discardableResult
    func applyPendingInitialFitIfPossible() -> Bool {
        guard isInitialFitPending, hasReceivedLayout, !isApplyingInitialFit else { return false }
        isApplyingInitialFit = true
        defer { isApplyingInitialFit = false }
        guard applyFitToWindow() else { return false }
        isInitialFitPending = false
        return true
    }

    @discardableResult
    private func applyFitToWindow() -> Bool {
        guard let scrollView, scrollView.superview != nil,
          let size = canvas?.session?.canvasSize,
          let fit = RasterImageInitialFitPolicy.magnification(
            imageSize: size,
            viewportSize: scrollView.contentSize,
            minimum: scrollView.minMagnification,
            maximum: min(scrollView.maxMagnification, 1)
          )
        else { return false }
        scrollView.magnification = fit
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refreshCenteringInsets()
        publishZoom()
        return true
    }

    func zoomToActualSize() {
        guard let scrollView else { return }
        let scale = max(scrollView.window?.backingScaleFactor ?? 1, 1)
        let imageScale = max(canvas?.session?.document.exportScale ?? 1, 0.001)
        scrollView.magnification = min(
          scrollView.maxMagnification, max(scrollView.minMagnification, imageScale / scale))
        refreshCenteringInsets()
        publishZoom()
    }

    func zoom(by factor: CGFloat) {
        guard let scrollView else { return }
        scrollView.magnification = min(
          scrollView.maxMagnification,
          max(scrollView.minMagnification, scrollView.magnification * factor))
        refreshCenteringInsets()
        publishZoom()
    }

    private func refreshCenteringInsets() {
        guard let scrollView, let canvas else { return }
        let target = RasterImagePreviewGeometry.centeredInsets(
          viewportSize: scrollView.contentSize,
          imageSize: canvas.frame.size,
          magnification: scrollView.magnification
        )
        let current = scrollView.contentInsets
        if abs(current.left - target.left) > 0.5 || abs(current.right - target.right) > 0.5
          || abs(current.top - target.top) > 0.5 || abs(current.bottom - target.bottom) > 0.5
        {
          scrollView.contentInsets = target
        }
    }

    private func publishZoom() {
        guard let scrollView else { return }
        viewModel?.zoomPercent = Double(scrollView.magnification * 100)
    }
}
