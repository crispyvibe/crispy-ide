import CoreGraphics
import Foundation

/// Display composites, export jobs, and post-save rebasing.
extension RasterImageEditSession {
    /// Display-scale composite of every operation (for legacy copy/save and tests).
    func compositeDisplayImage() -> CGImage? {
        let overlays = Array(overlayOperations)
        guard !overlays.isEmpty else { return flattenedDisplayImage }
        return renderer.render(base: flattenedDisplayImage, baseCanvasSize: canvasSize, operations: overlays)
    }

    /// Inputs for an off-main display composite with optional adjustment override
    /// (live slider preview, before/after compare).
    func displayCompositeJob(adjustments override: RasterImageAdjustments?) -> RasterImageExportJob {
        var operations = document.operations
        if let override { operations.append(.adjust(override)) }
        return RasterImageExportJob(
            source: .memory(displaySource),
            baseCanvasSize: document.baseCanvasSize,
            operations: operations,
            revision: document.revision,
            destinationURL: nil
        )
    }

    func makeExportJob(destinationURL: URL?) -> RasterImageExportJob {
        RasterImageExportJob(
            source: document.source,
            baseCanvasSize: document.baseCanvasSize,
            operations: document.operations,
            revision: document.revision,
            destinationURL: destinationURL
        )
    }

    /// Makes the saved output the new unedited baseline and clears history.
    func rebase(afterSaving result: RasterImageExportResult) {
        let newCanvasSize = canvasSize
        let newSource: RasterImageSource
        let newDisplay: CGImage
        switch document.source {
        case .memory:
            newSource = .memory(result.image)
            newDisplay = result.image
        case .file(let url):
            newSource = .file(url)
            newDisplay = compositeDisplayImage() ?? result.image
        }
        document = RasterImageDocument(source: newSource, baseCanvasSize: newCanvasSize, exportScale: document.exportScale)
        displaySource = newDisplay
        flattenedDisplayImage = newDisplay
        flattenedPrefix = []
        flattenedAdjustments = .identity
        history.reset()
        if let info = sourceInfo {
            sourceInfo = RasterImageSourceInfo(
                pixelWidth: result.image.width,
                pixelHeight: result.image.height,
                exifOrientation: 1,
                frameCount: 1,
                bitDepth: min(info.bitDepth, 8),
                hasGainMap: false
            )
        }
        onChange?()
    }
}

/// Editing of individual markup items.
extension RasterImageEditSession {
    /// Replaces the markup item with `id`. Successive changes with the same non-nil
    /// `coalescingKey` (e.g. typing, nudging, slider drags) collapse into one undo step.
    @discardableResult
    func updateMarkup(id: UUID, to item: RasterMarkupItem, coalescingKey: String? = nil) -> Bool {
        guard let index = markupEntries.first(where: { $0.item.id == id })?.index,
              document.operations[index] != .markup(item) else { return false }
        var operations = document.operations
        let previous = operations[index]
        operations[index] = .markup(item)
        document.replaceOperations(operations)
        history.recordSet(index: index, previous: previous, coalescingKey: coalescingKey.map { "\($0)-\(id)" })
        onChange?()
        return true
    }

    /// Ends any coalescing run (e.g. when the selection changes) so the next edit is its own undo step.
    func endCoalescing() {
        history.endCoalescing()
    }

    /// Removes the markup item with `id` (undoable).
    @discardableResult
    func deleteMarkup(id: UUID) -> Bool {
        guard let index = markupEntries.first(where: { $0.item.id == id })?.index else { return false }
        var operations = document.operations
        let removed = operations.remove(at: index)
        document.replaceOperations(operations)
        history.recordRemove(index: index, removed: removed)
        onChange?()
        return true
    }
}
