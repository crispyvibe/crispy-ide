import Foundation

/// Commands the editor view model sends to the canvas adapter.
@MainActor
protocol RasterImageCanvasControlling: AnyObject {
    var isInteractionLocked: Bool { get set }
    var state: RasterImageCanvasState { get }
    var session: RasterImageEditSession? { get }
    func applyCropSelection() -> RasterImageCropResult
    func cancelCropSelection() -> Bool
    func clearEdits() -> Bool
    /// Applies `change` to the selected markup item; returns `false` when nothing is selected.
    @discardableResult
    func updateSelectedMarkup(coalescingKey: String?, _ change: (RasterMarkupItem) -> RasterMarkupItem) -> Bool
    /// Deletes the selected markup item.
    func deleteSelectedMarkup() -> Bool
}

/// File-level operations owned by the preview's loading/observation layer.
@MainActor
protocol RasterImageFileSessionControlling: AnyObject {
    /// Re-decodes the file from disk, discarding canvas edits.
    func reloadFromDisk()
    /// Records the current on-disk state as the known baseline (after save or Keep My Edits).
    func markFileStateCurrent()
    /// `true` when the file on disk no longer matches what was loaded or last saved.
    func hasExternalChangeSinceLoad() -> Bool
    /// Scrolls the canvas back to its origin (after a crop changes the image size).
    func resetScrollPosition()
}

/// Zoom / framing commands for the scroll view hosting the canvas.
@MainActor
protocol RasterImageViewportControlling: AnyObject {
    /// Fits the whole image in the viewport (never enlarging beyond actual size).
    func fitToWindow()
    /// Shows one image pixel per device pixel.
    func zoomToActualSize()
    /// Multiplies the current zoom by `factor`, keeping the viewport center fixed.
    func zoom(by factor: CGFloat)
}

extension EditableRasterImageCanvasView: RasterImageCanvasControlling {}

/// Write sink for encoded image data; completion may be called on any thread.
typealias RasterImageSaveDataHandler = (URL, Data, @escaping (Result<Void, Error>) -> Void) -> Void
