import AppKit
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenshotStudioViewModelTests: XCTestCase {
    func test_newCaptureBecomesCurrentBeforeSideEffectsAndStartsMarkupPen() throws {
        let fixture = try ScreenshotStudioFixture(output: SuspendedOutput())
        let capture = fixture.capture()
        defer { fixture.viewModel.shutdown() }

        fixture.viewModel.installNewCapture(capture)

        XCTAssertEqual(fixture.viewModel.selectedItemID, capture.id)
        XCTAssertTrue(fixture.viewModel.currentImage === capture.image.cgImage)
        XCTAssertEqual(fixture.editor.editingMode, .markup)
        XCTAssertEqual(fixture.editor.markupTool, .pen)
        XCTAssertTrue(fixture.clipboard.values.isEmpty)
    }

    func test_historySelectionLatestWinsAndFailurePreservesCurrentEditor() async throws {
        let repository = try ControlledRepository()
        let fixture = try ScreenshotStudioFixture(repository: repository)
        let current = fixture.item(id: UUID())
        fixture.viewModel.install(current)
        let a = UUID(), b = UUID(), failing = UUID()
        await repository.seed(ids: [a, b, failing])
        fixture.viewModel.refreshHistory()
        await waitForStudioCondition { fixture.viewModel.historyEntries.count == 3 }
        await repository.suspendSource(id: a)
        await repository.suspendSource(id: b)

        fixture.viewModel.selectHistoryItem(id: a)
        await waitForStudioCondition { await repository.isSourcePending(id: a) }
        fixture.viewModel.selectHistoryItem(id: b)
        await waitForStudioCondition { await repository.isSourcePending(id: b) }
        await repository.resumeSource(id: b)
        await waitForStudioCondition { fixture.viewModel.selectedItemID == b }
        await repository.resumeSource(id: a)
        awaitStudioTurns()
        XCTAssertEqual(fixture.viewModel.selectedItemID, b)

        await repository.failSource(id: failing)
        let retainedImage = fixture.viewModel.currentImage
        fixture.viewModel.selectHistoryItem(id: failing)
        await waitForStudioCondition { fixture.viewModel.failure?.stage == .historySelection }
        XCTAssertEqual(fixture.viewModel.selectedItemID, b)
        XCTAssertTrue(fixture.viewModel.currentImage === retainedImage)
    }

    func test_clipboardFailurePreservesCurrentItemAndExposesCopyRetry() async throws {
        let clipboard = RecordingClipboard(failures: 1)
        let fixture = try ScreenshotStudioFixture(clipboard: clipboard)
        let capture = fixture.capture()
        fixture.viewModel.installNewCapture(capture)
        fixture.viewModel.deliverCurrentCapture()
        await waitForStudioCondition { fixture.viewModel.failure?.stage == .clipboard }

        XCTAssertEqual(fixture.viewModel.selectedItemID, capture.id)
        XCTAssertTrue(fixture.viewModel.currentImage === capture.image.cgImage)
        XCTAssertTrue(try XCTUnwrap(fixture.viewModel.failure).stage.supportsCopyRetry)
    }
}


extension ScreenshotStudioViewModelTests {
    func test_shutdownDuringPendingHistorySelectionHasNoLateCurrentOrHistoryMutation() async throws {
        let repository = try ControlledRepository()
        let fixture = try ScreenshotStudioFixture(repository: repository)
        let selectedID = UUID()
        await repository.seed(ids: [selectedID])
        fixture.viewModel.refreshHistory()
        await waitForStudioCondition { fixture.viewModel.historyEntries.count == 1 }
        await repository.suspendSource(id: selectedID)
        fixture.viewModel.selectHistoryItem(id: selectedID)
        await waitForStudioCondition { await repository.isSourcePending(id: selectedID) }

        fixture.viewModel.shutdown()
        await repository.resumeSource(id: selectedID)
        awaitStudioTurns(50)

        XCTAssertNil(fixture.viewModel.currentItem)
        XCTAssertTrue(fixture.viewModel.historyEntries.isEmpty)
        XCTAssertTrue(fixture.viewModel.thumbnails.isEmpty)
        XCTAssertNil(fixture.viewModel.requestedSelectionID)
    }
}

extension ScreenshotStudioViewModelTests {
    func test_copyAndDismissCancelsPendingDebounceCommitsRequestedRevisionAndClosesOnce() async throws {
        let scheduler = ManualScheduler()
        let fixture = try ScreenshotStudioFixture(scheduler: scheduler)
        defer { fixture.viewModel.shutdown() }
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        fixture.viewModel.install(item)
        fixture.viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 7, y: 7)]))))
        fixture.viewModel.didChangeRevision(itemID: item.id, session: session, revision: 1, isDirty: true)
        await waitForStudioCondition { await scheduler.waiterCount == 1 }
        var closeCount = 0
        fixture.viewModel.onClose = { closeCount += 1 }

        fixture.viewModel.copyAndDismiss()

        await waitForStudioCondition { closeCount == 1 }
        XCTAssertEqual(fixture.exporter.revisions, [1])
        XCTAssertEqual(fixture.clipboard.values.count, 1)
        let addCount = await fixture.repository.addCount
        XCTAssertEqual(addCount, 1)
        XCTAssertFalse(fixture.viewModel.isCopyAndDismissPending)
        XCTAssertNil(fixture.viewModel.onClose)
        await scheduler.releaseAll()
        awaitStudioTurns(50)
        XCTAssertEqual(fixture.exporter.count, 1)
        XCTAssertEqual(closeCount, 1)
    }

    func test_copyAndDismissClipboardFailurePersistsButStaysOpenAndRetryable() async throws {
        let clipboard = RecordingClipboard(failures: 1)
        let fixture = try ScreenshotStudioFixture(clipboard: clipboard)
        defer { fixture.viewModel.shutdown() }
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        fixture.viewModel.install(item)
        fixture.viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        var closeCount = 0
        fixture.viewModel.onClose = { closeCount += 1 }

        fixture.viewModel.copyAndDismiss()
        await waitForStudioCondition { await fixture.repository.addCount == 1 }

        XCTAssertEqual(fixture.viewModel.failure?.stage, .clipboard)
        XCTAssertFalse(fixture.viewModel.isCopyAndDismissPending)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(fixture.viewModel.canCopyAndDismiss)

        fixture.viewModel.copyAndDismiss()
        await waitForStudioCondition { closeCount == 1 }
        let updateCount = await fixture.repository.updateCount
        XCTAssertEqual(updateCount, 1)
        XCTAssertEqual(clipboard.values.count, 1)
    }

    func test_copyAndDismissHistoryAddFailureAfterClipboardStaysOpenWithRetry() async throws {
        let repository = try ControlledRepository()
        await repository.failNextAdd()
        let fixture = try ScreenshotStudioFixture(repository: repository)
        defer { fixture.viewModel.shutdown() }
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        fixture.viewModel.install(item)
        fixture.viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        var closeCount = 0
        fixture.viewModel.onClose = { closeCount += 1 }

        fixture.viewModel.copyAndDismiss()
        await waitForStudioCondition { fixture.viewModel.failure?.stage == .historyAdd }

        XCTAssertEqual(fixture.clipboard.values.count, 1)
        XCTAssertEqual(closeCount, 0)
        XCTAssertFalse(fixture.viewModel.isCopyAndDismissPending)
        XCTAssertTrue(try XCTUnwrap(fixture.viewModel.failure).stage.supportsCopyRetry)

        fixture.viewModel.copyAndDismiss()
        await waitForStudioCondition { closeCount == 1 }
        let addCount = await repository.addCount
        XCTAssertEqual(addCount, 2)
    }

    func test_copyAndDismissHistoryUpdateFailureAfterClipboardStaysOpen() async throws {
        let repository = try ControlledRepository()
        let itemID = UUID()
        await repository.seed(ids: [itemID])
        await repository.failNextUpdate()
        let fixture = try ScreenshotStudioFixture(repository: repository)
        defer { fixture.viewModel.shutdown() }
        let item = fixture.item(id: itemID, source: .history)
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        fixture.viewModel.install(item)
        fixture.viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        var closeCount = 0
        fixture.viewModel.onClose = { closeCount += 1 }

        fixture.viewModel.copyAndDismiss()
        await waitForStudioCondition { fixture.viewModel.failure?.stage == .historyUpdate }

        XCTAssertEqual(fixture.clipboard.values.count, 1)
        XCTAssertEqual(closeCount, 0)
        XCTAssertFalse(fixture.viewModel.isCopyAndDismissPending)
    }

    func test_staleCompletionDifferentSelectionAndShutdownCannotCloseReplacement() throws {
        let fixture = try ScreenshotStudioFixture(output: SuspendedOutput())
        let first = fixture.item()
        let firstSession = RasterImageEditSession.inMemory(first.image, canvasSize: first.canvasSize)
        fixture.viewModel.install(first)
        fixture.viewModel.didChangeRevision(itemID: first.id, session: firstSession, revision: 0, isDirty: false)
        XCTAssertTrue(firstSession.commit(.stroke(.init(points: [.zero, CGPoint(x: 7, y: 7)]))))
        fixture.viewModel.didChangeRevision(itemID: first.id, session: firstSession, revision: 1, isDirty: true)
        var closeCount = 0
        fixture.viewModel.onClose = { closeCount += 1 }
        fixture.viewModel.copyAndDismiss()

        fixture.viewModel.handleDeliveryEvent(.deliveryCompleted(first.id, 0))
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(fixture.viewModel.isCopyAndDismissPending)

        let replacement = fixture.item(id: UUID())
        fixture.viewModel.install(replacement)
        fixture.viewModel.handleDeliveryEvent(.deliveryCompleted(first.id, 1))
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(fixture.viewModel.selectedItemID, replacement.id)
        XCTAssertFalse(fixture.viewModel.isCopyAndDismissPending)

        fixture.viewModel.shutdown()
        fixture.viewModel.handleDeliveryEvent(.deliveryCompleted(replacement.id, 99))
        XCTAssertEqual(closeCount, 0)
    }

    func test_plainCopyPersistsAndStaysOpen() async throws {
        let fixture = try ScreenshotStudioFixture()
        defer { fixture.viewModel.shutdown() }
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        fixture.viewModel.install(item)
        fixture.viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        var closeCount = 0
        fixture.viewModel.onClose = { closeCount += 1 }

        fixture.viewModel.copy()
        await waitForStudioCondition { await fixture.repository.addCount == 1 }

        XCTAssertEqual(closeCount, 0)
        XCTAssertNotNil(fixture.viewModel.onClose)
        XCTAssertFalse(fixture.viewModel.isCopyAndDismissPending)
    }

    func test_deliveryCompletionNilsCloseOwnershipBeforeExactlyOneCallback() throws {
        let fixture = try ScreenshotStudioFixture(output: SuspendedOutput())
        defer { fixture.viewModel.shutdown() }
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        fixture.viewModel.install(item)
        fixture.viewModel.didChangeRevision(itemID: item.id, session: session, revision: 0, isDirty: false)
        var closeCount = 0
        fixture.viewModel.onClose = {
            XCTAssertNil(fixture.viewModel.onClose)
            XCTAssertFalse(fixture.viewModel.isCopyAndDismissPending)
            closeCount += 1
        }

        fixture.viewModel.copyAndDismiss()
        fixture.viewModel.handleDeliveryEvent(.deliveryCompleted(item.id, 0))
        fixture.viewModel.handleDeliveryEvent(.deliveryCompleted(item.id, 0))

        XCTAssertEqual(closeCount, 1)
    }
}
