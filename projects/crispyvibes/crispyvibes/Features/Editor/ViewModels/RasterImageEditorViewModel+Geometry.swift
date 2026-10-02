import CoreGraphics
import Foundation

/// Rotate, flip, straighten, resize, crop-ratio, and zoom commands.
extension RasterImageEditorViewModel {
    /// Rotates 90° clockwise (`clockwise == true`) or counter-clockwise.
    func rotate(clockwise: Bool) {
        commitGeometry(.rotate(quarterTurns: clockwise ? 1 : 3))
    }

    func flip(horizontal: Bool) {
        commitGeometry(.flip(horizontal: horizontal))
    }

    /// Live preview while the straighten slider moves.
    func previewStraighten(degrees: Double) {
        straightenDegrees = min(max(degrees, -45), 45)
    }

    /// Commits the previewed straighten angle (no-op at 0°) and resets the slider.
    func commitStraighten() {
        let degrees = straightenDegrees
        straightenDegrees = 0
        guard abs(degrees) >= 0.05 else { return }
        commitGeometry(.straighten(radians: degrees * .pi / 180))
    }

    /// Resamples to `width`×`height` export pixels.
    func resize(toPixelWidth width: Int, height: Int) {
        guard let session = canvas?.session, width > 0, height > 0 else { return }
        let current = session.exportTransform.pixelSize
        guard width != current.width || height != current.height else {
            isResizeSheetPresented = false
            return
        }
        guard width <= Self.maximumPixelEdge, height <= Self.maximumPixelEdge else {
            actionStatus = AppStrings.ImageEditor.statusResizeTooLarge(Self.maximumPixelEdge)
            return
        }
        let scale = max(session.document.exportScale, 0.0001)
        commitGeometry(.resize(CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)))
        isResizeSheetPresented = false
    }

    /// Largest edge Resize accepts, bounding export memory.
    static let maximumPixelEdge = 16_384

    func selectCropAspectRatio(_ ratio: RasterImageCropAspectRatio) {
        cropAspectRatio = ratio
        if editingMode != .crop { selectMode(.crop) }
    }

    func toggleCropOrientation() {
        isCropPortrait.toggle()
    }

    func presentResize() {
        guard canEditGeometry else { return }
        isResizeSheetPresented = true
    }

    func presentExport() {
        guard canExport else { return }
        if let ext = fileURL?.pathExtension, let format = RasterImageExportFormat(fileExtension: ext) {
            exportOptions.format = format
        }
        isExportSheetPresented = true
    }

    // MARK: - Viewport

    func fitToWindow() { viewport?.fitToWindow() }
    func zoomToActualSize() { viewport?.zoomToActualSize() }
    func zoomIn() { viewport?.zoom(by: 1.25) }
    func zoomOut() { viewport?.zoom(by: 0.8) }

    /// Called by the viewport when magnification changes.
    func viewportDidChange(zoomPercent: Double) {
        guard abs(self.zoomPercent - zoomPercent) > 0.5 else { return }
        self.zoomPercent = zoomPercent
    }

    // MARK: - Private

    private func commitGeometry(_ operation: ImageEditOperation) {
        guard canEditGeometry, let canvas, let session = canvas.session else { return }
        guard session.commit(operation) else {
            actionStatus = AppStrings.ImageEditor.statusTransformFailed
            return
        }
        canvasState = canvas.state
        actionStatus = nil
        fileSession?.resetScrollPosition()
    }
}
