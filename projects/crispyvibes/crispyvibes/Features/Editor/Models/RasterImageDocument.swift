import CoreGraphics
import Foundation

/// Where full-resolution pixels for export come from.
enum RasterImageSource: @unchecked Sendable {
    /// Pixels held in memory (standalone canvas use and tests). `CGImage` is immutable.
    case memory(CGImage)
    /// Pixels decoded on demand from a file, normalized to upright orientation.
    case file(URL)
}

/// Non-destructive raster document: an immutable source plus an ordered operation list.
///
/// Canvas units: the editor's point space. For file sources this equals oriented source pixels
/// (`exportScale == 1`); for in-memory `NSImage` sources it equals the image's point size.
struct RasterImageDocument: @unchecked Sendable {
    let source: RasterImageSource
    /// Canvas size of the unedited source.
    let baseCanvasSize: CGSize
    /// Export pixels per canvas unit.
    let exportScale: CGFloat
    private(set) var operations: [ImageEditOperation] = []
    /// Increments on every change; used to discard stale async results.
    private(set) var revision = 0

    init(source: RasterImageSource, baseCanvasSize: CGSize, exportScale: CGFloat) {
        self.source = source
        self.baseCanvasSize = baseCanvasSize
        self.exportScale = exportScale
    }

    /// Canvas size after replaying every operation.
    var canvasSize: CGSize {
        operations.reduce(baseCanvasSize) { $1.resultingCanvasSize(from: $0) }
    }

    /// Index just past the last geometric operation; operations before it are flattened.
    var flattenedPrefixCount: Int {
        (operations.lastIndex(where: \.isGeometric)).map { $0 + 1 } ?? 0
    }

    /// Non-geometric operations drawn live on top of the flattened base.
    var overlayOperations: ArraySlice<ImageEditOperation> {
        operations[flattenedPrefixCount...]
    }

    mutating func replaceOperations(_ newOperations: [ImageEditOperation]) {
        operations = newOperations
        revision += 1
    }
}

/// Undo/redo stack over a document's operation list.
///
/// Appends (the common case) are stored as a count, not a snapshot, so long sessions retain
/// O(limit) entries rather than O(limit × operations). Only non-append changes (Revert) store
/// a full snapshot.
struct RasterImageEditHistory {
    /// How to get from one operation list to another.
    enum Entry {
        /// Drop the last `count` operations.
        case removeLast(Int)
        /// Append these operations.
        case append([ImageEditOperation])
        /// Replace the whole list.
        case replace([ImageEditOperation])
        /// Set the operation at an index.
        case set(Int, ImageEditOperation)
        /// Insert an operation at an index.
        case insert(Int, ImageEditOperation)
        /// Remove the operation at an index.
        case remove(Int)

        /// Applies the entry to `current`, returning the result and the inverse entry.
        func apply(to current: [ImageEditOperation]) -> (operations: [ImageEditOperation], inverse: Entry) {
            switch self {
            case .removeLast(let count):
                let count = min(count, current.count)
                return (Array(current.dropLast(count)), .append(Array(current.suffix(count))))
            case .append(let operations):
                return (current + operations, .removeLast(operations.count))
            case .replace(let operations):
                return (operations, .replace(current))
            case let .set(index, operation):
                guard current.indices.contains(index) else { return (current, .replace(current)) }
                var result = current
                let old = result[index]
                result[index] = operation
                return (result, .set(index, old))
            case let .insert(index, operation):
                var result = current
                result.insert(operation, at: min(max(index, 0), result.count))
                return (result, .remove(min(max(index, 0), current.count)))
            case .remove(let index):
                guard current.indices.contains(index) else { return (current, .replace(current)) }
                var result = current
                let removed = result.remove(at: index)
                return (result, .insert(index, removed))
            }
        }
    }

    /// Maximum retained undo steps.
    var limit = 200
    private(set) var undoStack: [Entry] = []
    private(set) var redoStack: [Entry] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var lastCoalescingKey: String?
    private var lastCoalescingDate = Date.distantPast
    /// Changes with the same key further apart than this start a new undo step.
    var coalescingWindow: TimeInterval = 1.0

    /// Records a single appended operation.
    mutating func recordAppend() {
        push(.removeLast(1))
    }

    /// Records replacing the operation at `index` (whose prior value was `previous`). Consecutive
    /// calls with the same non-nil `coalescingKey` keep only the first prior value.
    mutating func recordSet(index: Int, previous: ImageEditOperation, coalescingKey: String?, now: Date = Date()) {
        defer { lastCoalescingDate = now }
        if let coalescingKey, coalescingKey == lastCoalescingKey,
           now.timeIntervalSince(lastCoalescingDate) <= coalescingWindow,
           case .set(index, _)? = undoStack.last {
            redoStack.removeAll()
            return
        }
        push(.set(index, previous))
        lastCoalescingKey = coalescingKey
    }

    /// Ends any coalescing run so the next change starts a new undo step.
    mutating func endCoalescing() {
        lastCoalescingKey = nil
    }

    /// Records removing `removed` from `index`.
    mutating func recordRemove(index: Int, removed: ImageEditOperation) {
        push(.insert(index, removed))
    }

    /// Records an arbitrary change whose prior state was `previous`.
    mutating func record(previous: [ImageEditOperation]) {
        push(.replace(previous))
    }

    /// Returns the operations to restore, pushing the inverse onto the redo stack.
    mutating func undo(current: [ImageEditOperation]) -> [ImageEditOperation]? {
        lastCoalescingKey = nil
        guard let entry = undoStack.popLast() else { return nil }
        let result = entry.apply(to: current)
        redoStack.append(result.inverse)
        return result.operations
    }

    /// Returns the operations to restore, pushing the inverse onto the undo stack.
    mutating func redo(current: [ImageEditOperation]) -> [ImageEditOperation]? {
        guard let entry = redoStack.popLast() else { return nil }
        let result = entry.apply(to: current)
        undoStack.append(result.inverse)
        return result.operations
    }

    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastCoalescingKey = nil
    }

    private mutating func push(_ entry: Entry) {
        lastCoalescingKey = nil
        undoStack.append(entry)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }
}
