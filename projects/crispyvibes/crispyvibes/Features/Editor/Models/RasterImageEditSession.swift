import CoreGraphics
import Foundation

/// Owns one open raster document: operations, undo/redo history, and the display rendering.
///
/// The display bitmap may be a downsampled proxy; it is never used for export. Full-resolution
/// output is produced by replaying the same operations through `RasterImageExporting`.
@MainActor
final class RasterImageEditSession {
    var document: RasterImageDocument
    var sourceInfo: RasterImageSourceInfo?
    var history = RasterImageEditHistory()
    let renderer: any RasterImageRendering
    /// Unadjusted display bitmap of the source (may be a proxy).
    var displaySource: CGImage
    var flattenedPrefix: [ImageEditOperation] = []
    var flattenedAdjustments = RasterImageAdjustments.identity
    /// Display-scale bitmap of the source with every operation up to the last geometric one applied.
    var flattenedDisplayImage: CGImage
    /// Called after every document change.
    var onChange: (() -> Void)?

    init(
        document: RasterImageDocument,
        displayImage: CGImage,
        sourceInfo: RasterImageSourceInfo?,
        renderer: any RasterImageRendering
    ) {
        self.document = document
        self.displaySource = displayImage
        self.flattenedDisplayImage = displayImage
        self.sourceInfo = sourceInfo
        self.renderer = renderer
    }

    /// Session over in-memory pixels whose canvas size is `canvasSize` (e.g. an `NSImage` point size).
    static func inMemory(
        _ image: CGImage,
        canvasSize: CGSize,
        renderer: any RasterImageRendering = RasterImageRenderer()
    ) -> RasterImageEditSession {
        let scale = canvasSize.width > 0 ? CGFloat(image.width) / canvasSize.width : 1
        return RasterImageEditSession(
            document: RasterImageDocument(source: .memory(image), baseCanvasSize: canvasSize, exportScale: scale),
            displayImage: image,
            sourceInfo: nil,
            renderer: renderer
        )
    }

    var canvasSize: CGSize { document.canvasSize }
    var overlayOperations: ArraySlice<ImageEditOperation> { document.overlayOperations }
    var isDirty: Bool { !document.operations.isEmpty }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var revision: Int { document.revision }
    var effectiveAdjustments: RasterImageAdjustments { document.operations.effectiveAdjustments }
    /// The renderer used for display composites (shared with async preview work).
    var displayRenderer: any RasterImageRendering { renderer }

    /// Editable markup items (those after the last geometric edit), with their operation index.
    var markupEntries: [(index: Int, item: RasterMarkupItem)] {
        let start = document.flattenedPrefixCount
        return document.operations.enumerated().compactMap { offset, operation in
            guard offset >= start, let item = operation.markupItem else { return nil }
            return (offset, item)
        }
    }

    func markupItem(id: UUID) -> RasterMarkupItem? {
        markupEntries.first { $0.item.id == id }?.item
    }

    /// Maps canvas units to export pixels; crop rectangles are snapped through it.
    var exportTransform: RasterImageCanvasTransform {
        RasterImageCanvasTransform(canvasSize: canvasSize, scale: document.exportScale)
    }

    // MARK: - Editing

    /// Commits an operation. Geometric operations are pre-rendered against the display bitmap and
    /// rejected (returning `false`) if rendering fails, so the document never holds an unrenderable op.
    @discardableResult
    func commit(_ newOperation: ImageEditOperation) -> Bool {
        let operation = newOperation.canonicalized(for: canvasSize, exportScale: document.exportScale)
        if case .adjust = operation {
            // Only the last `.adjust` counts, so keep a single node: replace it in place (undoable
            // as a `.set`) or append the first one. Adjustments change the base, so re-render.
            var operations = document.operations
            if let index = operations.lastIndex(where: { if case .adjust = $0 { return true } else { return false } }) {
                let previous = operations[index]
                operations[index] = operation
                guard apply(operations) else { return false }
                history.recordSet(index: index, previous: previous, coalescingKey: nil)
            } else {
                guard apply(operations + [operation]) else { return false }
                history.recordAppend()
            }
            return true
        }
        guard operation.isGeometric else {
            history.recordAppend()
            document.replaceOperations(document.operations + [operation])
            onChange?()
            return true
        }
        // Incremental: flatten only the overlays since the last geometric op, plus the new op.
        let delta = Array(overlayOperations) + [operation]
        guard let rendered = renderer.render(base: flattenedDisplayImage, baseCanvasSize: canvasSize, operations: delta) else {
            return false
        }
        let candidate = document.operations + [operation]
        history.recordAppend()
        document.replaceOperations(candidate)
        flattenedDisplayImage = rendered
        flattenedPrefix = candidate
        onChange?()
        return true
    }

    /// Selection snapped outward to whole export pixels, or `nil` when too small.
    func snappedCropRect(forSelection selection: CGRect) -> CGRect? {
        exportTransform.snappedCropRect(forSelection: selection)
    }

    /// `true` when `selection` snaps to the entire canvas (cropping would change nothing).
    func isFullCanvasSelection(_ selection: CGRect) -> Bool {
        guard let snapped = snappedCropRect(forSelection: selection) else { return false }
        let full = CGRect(origin: .zero, size: canvasSize)
        let tolerance = 0.5 / max(document.exportScale, 0.0001)
        return abs(snapped.minX - full.minX) < tolerance && abs(snapped.minY - full.minY) < tolerance &&
            abs(snapped.maxX - full.maxX) < tolerance && abs(snapped.maxY - full.maxY) < tolerance
    }

    func applyCrop(selection: CGRect?) -> RasterImageCropResult {
        guard let selection else { return .noSelection }
        guard let rect = snappedCropRect(forSelection: selection), !isFullCanvasSelection(selection) else {
            return .invalidSelection
        }
        return commit(.crop(rect)) ? .success : .cropFailure
    }

    /// Steps back one edit. Returns `false` (leaving state untouched) if nothing can be undone or
    /// the target state fails to render.
    @discardableResult
    func undo() -> Bool {
        guard let previous = history.undo(current: document.operations) else { return false }
        guard apply(previous) else {
            _ = history.redo(current: previous)
            return false
        }
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = history.redo(current: document.operations) else { return false }
        guard apply(next) else {
            _ = history.undo(current: next)
            return false
        }
        return true
    }

    /// Discards every unsaved operation (undoable).
    @discardableResult
    func revert() -> Bool {
        guard isDirty else { return false }
        replaceOperations([])
        return true
    }

    // MARK: - Private

    private func replaceOperations(_ operations: [ImageEditOperation]) {
        let previous = document.operations
        guard apply(operations) else { return }
        history.record(previous: previous)
    }

    /// Installs `operations` only if their flattened prefix renders; returns `false` otherwise.
    private func apply(_ operations: [ImageEditOperation]) -> Bool {
        let prefixCount = (operations.lastIndex(where: \.isGeometric)).map { $0 + 1 } ?? 0
        let prefix = Array(operations.prefix(prefixCount))
        let adjustments = operations.effectiveAdjustments
        if prefix != flattenedPrefix || adjustments != flattenedAdjustments {
            let base = adjustments.isIdentity ? displaySource : renderer.applyAdjustments(adjustments, to: displaySource)
            guard let base else { return false }
            if prefix.isEmpty {
                flattenedDisplayImage = base
            } else if let rendered = renderer.render(base: base, baseCanvasSize: document.baseCanvasSize, operations: prefix) {
                flattenedDisplayImage = rendered
            } else {
                return false
            }
            flattenedPrefix = prefix
            flattenedAdjustments = adjustments
        }
        document.replaceOperations(operations)
        onChange?()
        return true
    }
}
