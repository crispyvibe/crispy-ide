import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F009 Phase 1: document model, history, canvas transform, and file identity.
@MainActor
final class RasterImageDocumentTests: XCTestCase {
    private let stroke = ImageEditOperation.stroke(RasterStroke(points: [.zero, CGPoint(x: 1, y: 1)]))

    func test_document_derivesCanvasSizeAndOverlaySegment() {
        var document = RasterImageDocument(source: .memory(RasterImageTestFixtures.quadrantImage(width: 10, height: 10)), baseCanvasSize: CGSize(width: 100, height: 60), exportScale: 1)
        document.replaceOperations([stroke, .crop(CGRect(x: 0, y: 0, width: 40, height: 30)), stroke])
        XCTAssertEqual(document.canvasSize, CGSize(width: 40, height: 30))
        XCTAssertEqual(document.flattenedPrefixCount, 2)
        XCTAssertEqual(Array(document.overlayOperations), [stroke])
        XCTAssertEqual(document.revision, 1)
    }

    func test_history_undoRedo_andRedoInvalidation() {
        var history = RasterImageEditHistory()
        history.record(previous: [])
        let afterUndo = history.undo(current: [stroke])
        XCTAssertEqual(afterUndo, [])
        XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.redo(current: []), [stroke])
        history.record(previous: [stroke])
        XCTAssertFalse(history.canRedo, "a new edit invalidates redo")
    }

    func test_history_isBounded() {
        var history = RasterImageEditHistory()
        history.limit = 3
        for _ in 0..<10 { history.record(previous: []) }
        XCTAssertEqual(history.undoStack.count, 3)
    }

    func test_transform_snapsSelectionToExportPixels() {
        let retina = RasterImageCanvasTransform(canvasSize: CGSize(width: 50, height: 50), scale: 2)
        XCTAssertEqual(retina.snappedCropRect(forSelection: CGRect(x: 10.3, y: 10.3, width: 5, height: 5)), CGRect(x: 10, y: 10, width: 5.5, height: 5.5))
        XCTAssertEqual(retina.pixelSize.width, 100)
        XCTAssertEqual(retina.pixelRect(forCanvasRect: CGRect(x: 10, y: 10, width: 5.5, height: 5.5)), CGRect(x: 20, y: 20, width: 11, height: 11))
        XCTAssertNil(retina.snappedCropRect(forSelection: CGRect(x: 1, y: 1, width: 0.2, height: 0.2)))
    }

    func test_transform_roundTripsPoints() {
        let transform = RasterImageCanvasTransform(canvasSize: CGSize(width: 300, height: 200), scale: 0.37)
        let point = CGPoint(x: 123.4, y: 56.7)
        let back = transform.canvasPoint(fromPixel: transform.pixelPoint(point))
        XCTAssertEqual(back.x, point.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, point.y, accuracy: 0.0001)
    }

    func test_session_rebaseAfterSave_clearsHistoryAndKeepsOutput() throws {
        let session = RasterImageEditSession.inMemory(RasterImageTestFixtures.quadrantImage(width: 100, height: 60), canvasSize: CGSize(width: 100, height: 60))
        XCTAssertEqual(session.applyCrop(selection: CGRect(x: 0, y: 0, width: 50, height: 30)), .success)
        let output = try RasterImageExportService.run(
            session.makeExportJob(destinationURL: nil), handle: nil,
            decoder: RasterImageDecoder(), renderer: RasterImageRenderer(), encoder: RasterImageEncoder()
        ).get()
        session.rebase(afterSaving: output)
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.canUndo)
        XCTAssertEqual(session.canvasSize, CGSize(width: 50, height: 30))
        XCTAssertFalse(session.revert())
    }

    func test_fileState_detectsSameSizeReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RasterFileState-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.png")
        try Data([1, 2, 3]).write(to: url)
        let before = RasterImageFileState.capture(for: url)
        XCTAssertEqual(before, RasterImageFileState.capture(for: url))

        let modificationDate = try XCTUnwrap(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try Data([4, 5, 6]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
        XCTAssertNotEqual(before, RasterImageFileState.capture(for: url), "atomic replacement changes file identity even with equal size/date")
    }

    func test_history_appendEntriesDoNotSnapshotOperations() {
        var history = RasterImageEditHistory()
        var operations: [ImageEditOperation] = []
        for _ in 0..<50 {
            history.recordAppend()
            operations.append(stroke)
        }
        XCTAssertTrue(history.undoStack.allSatisfy {
            if case .removeLast(1) = $0 { return true }
            return false
        })
        let back = history.undo(current: operations)
        XCTAssertEqual(back?.count, 49)
        XCTAssertEqual(history.redo(current: back ?? [])?.count, 50)
    }

    func test_undo_whenTargetFailsToRender_leavesStateUntouched() throws {
        struct FailingAfterFirst: RasterImageRendering {
            let counter: Counter
            final class Counter: @unchecked Sendable { var calls = 0 }
            func render(base: CGImage, baseCanvasSize: CGSize, operations: [ImageEditOperation]) -> CGImage? {
                counter.calls += 1
                return counter.calls <= 2 ? RasterImageRenderer().render(base: base, baseCanvasSize: baseCanvasSize, operations: operations) : nil
            }
            func applyAdjustments(_ adjustments: RasterImageAdjustments, to image: CGImage) -> CGImage? { image }
        }
        let renderer = FailingAfterFirst(counter: .init())
        let session = RasterImageEditSession.inMemory(RasterImageTestFixtures.quadrantImage(width: 100, height: 60),
                                                      canvasSize: CGSize(width: 100, height: 60), renderer: renderer)
        XCTAssertTrue(session.commit(.crop(CGRect(x: 0, y: 0, width: 50, height: 30))))
        XCTAssertTrue(session.commit(.crop(CGRect(x: 0, y: 0, width: 20, height: 20))))
        XCTAssertFalse(session.undo(), "re-rendering the first crop fails")
        XCTAssertEqual(session.canvasSize, CGSize(width: 20, height: 20))
        XCTAssertEqual(session.flattenedDisplayImage.width, 20)
        XCTAssertTrue(session.canUndo, "history is restored after a failed undo")
    }

    func test_coalescing_endsAfterWindowOrExplicitBoundary() {
        var history = RasterImageEditHistory()
        let start = Date()
        history.recordSet(index: 0, previous: stroke, coalescingKey: "k", now: start)
        history.recordSet(index: 0, previous: stroke, coalescingKey: "k", now: start.addingTimeInterval(0.5))
        XCTAssertEqual(history.undoStack.count, 1, "rapid same-key edits coalesce")
        history.recordSet(index: 0, previous: stroke, coalescingKey: "k", now: start.addingTimeInterval(5))
        XCTAssertEqual(history.undoStack.count, 2, "a later edit to the same property is its own step")
        history.endCoalescing()
        history.recordSet(index: 0, previous: stroke, coalescingKey: "k", now: start.addingTimeInterval(5.1))
        XCTAssertEqual(history.undoStack.count, 3)
    }
}
