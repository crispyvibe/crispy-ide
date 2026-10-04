import AppKit
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenCaptureDeliveryCoordinatorTests: XCTestCase {
    func test_debounceCoalescesRevisionsAndRevisionZeroDoesNotLoop() async throws {
        let scheduler = ManualScheduler()
        let fixture = try ScreenshotStudioFixture(scheduler: scheduler)
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        fixture.delivery.activate(itemID: item.id)

        fixture.delivery.revisionDidCommit(item: item, session: session, revision: 0, installationBaseline: 0)
        XCTAssertEqual(fixture.exporter.count, 0)
        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 1, y: 1)]))))
        fixture.delivery.revisionDidCommit(item: item, session: session, revision: 1, installationBaseline: 0)
        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 2, y: 2)]))))
        fixture.delivery.revisionDidCommit(item: item, session: session, revision: 2, installationBaseline: 0)
        await waitForStudioCondition { await scheduler.waiterCount >= 1 }
        await scheduler.releaseAll()
        await waitForStudioCondition { fixture.clipboard.values.count == 1 }

        XCTAssertEqual(fixture.exporter.count, 1)
        XCTAssertEqual(fixture.exporter.revisions, [2])
    }

    func test_initialAutoCopyThenAnnotatedRevisionRefreshesClipboardAndHistory() async throws {
        let scheduler = ManualScheduler()
        let fixture = try ScreenshotStudioFixture(scheduler: scheduler)
        let item = fixture.item()
        fixture.delivery.deliverInitial(item: item)
        await waitForStudioCondition { fixture.clipboard.values.count == 1 }
        await waitForStudioCondition { await fixture.repository.addCount == 1 }
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 1, y: 1)]))))

        fixture.delivery.revisionDidCommit(item: item, session: session, revision: 1, installationBaseline: 0)
        await waitForStudioCondition { await scheduler.waiterCount >= 1 }
        await scheduler.releaseAll()
        await waitForStudioCondition { fixture.clipboard.values.count == 2 }
        await waitForStudioCondition { await fixture.repository.updateCount == 1 }

        XCTAssertEqual(fixture.exporter.count, 1)
        XCTAssertEqual(fixture.clipboard.values.last?.png, Data([1]))
    }

    func test_manualCopyCancelsDebounceAndUsesSamePipeline() async throws {
        let scheduler = ManualScheduler()
        let fixture = try ScreenshotStudioFixture(scheduler: scheduler)
        let item = fixture.item(source: .history)
        fixture.delivery.registerHistoryItem(id: item.id)
        fixture.delivery.activate(itemID: item.id)
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 1, y: 1)]))))
        fixture.delivery.revisionDidCommit(item: item, session: session, revision: 1, installationBaseline: 0)

        fixture.delivery.copyNow(item: item, session: session)
        await waitForStudioCondition { fixture.clipboard.values.count == 1 }
        await scheduler.releaseAll()
        awaitStudioTurns()

        XCTAssertEqual(fixture.exporter.count, 1)
        let updateCount = await fixture.repository.updateCount
        XCTAssertEqual(updateCount, 1)
    }

    func test_itemACompletionCannotOverwriteClipboardAfterItemBActivation() async throws {
        let exporter = ControlledRasterExporter()
        let fixture = try ScreenshotStudioFixture(exporter: exporter)
        let a = fixture.item(id: UUID(), source: .history)
        let b = fixture.item(id: UUID(), source: .history)
        let sessionA = RasterImageEditSession.inMemory(a.image, canvasSize: a.canvasSize)
        let sessionB = RasterImageEditSession.inMemory(b.image, canvasSize: b.canvasSize)
        fixture.delivery.registerHistoryItem(id: a.id)
        fixture.delivery.registerHistoryItem(id: b.id)
        fixture.delivery.activate(itemID: a.id)
        fixture.delivery.copyNow(item: a, session: sessionA)
        fixture.delivery.activate(itemID: b.id)
        fixture.delivery.copyNow(item: b, session: sessionB)

        exporter.complete(index: 0)
        awaitStudioTurns()
        XCTAssertTrue(fixture.clipboard.values.isEmpty)
        exporter.complete(index: 1)
        await waitForStudioCondition { fixture.clipboard.values.count == 1 }
        XCTAssertEqual(fixture.clipboard.values.count, 1)
    }

    func test_deleteAndClearInvalidatePendingOutputBeforeRepositoryMutation() async throws {
        let exporter = ControlledRasterExporter()
        let fixture = try ScreenshotStudioFixture(exporter: exporter)
        let item = fixture.item(source: .history)
        fixture.delivery.registerHistoryItem(id: item.id)
        fixture.delivery.activate(itemID: item.id)
        fixture.delivery.copyNow(
            item: item,
            session: .inMemory(item.image, canvasSize: item.canvasSize)
        )

        fixture.delivery.delete(id: item.id)
        exporter.complete(index: 0)
        await waitForStudioCondition { await fixture.repository.deleteCount == 1 }
        XCTAssertTrue(fixture.clipboard.values.isEmpty)

        let second = fixture.item(id: UUID(), source: .history)
        fixture.delivery.registerHistoryItem(id: second.id)
        fixture.delivery.activate(itemID: second.id)
        fixture.delivery.copyNow(
            item: second,
            session: .inMemory(second.image, canvasSize: second.canvasSize)
        )
        fixture.delivery.clear()
        exporter.complete(index: 1)
        await waitForStudioCondition { await fixture.repository.clearCount == 1 }
        XCTAssertTrue(fixture.clipboard.values.isEmpty)
    }
}


extension ScreenCaptureDeliveryCoordinatorTests {
    func test_shutdownDuringPendingEncodeHasNoLateClipboardEventOrHistoryMutation() async throws {
        let output = BlockingOutput()
        let fixture = try ScreenshotStudioFixture(output: output)
        let item = fixture.item()
        var events: [ScreenCaptureDeliveryEvent] = []
        fixture.delivery.setEventHandler { events.append($0) }
        fixture.delivery.deliverInitial(item: item)
        await output.waitUntilStarted()
        let eventCountAtShutdown = events.count

        fixture.delivery.shutdown()
        await output.release()
        awaitStudioTurns(50)

        let addCount = await fixture.repository.addCount
        let updateCount = await fixture.repository.updateCount
        XCTAssertTrue(fixture.clipboard.values.isEmpty)
        XCTAssertEqual(addCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(events.count, eventCountAtShutdown)
    }
}

extension ScreenCaptureDeliveryCoordinatorTests {
    func test_cancelledDebounceDoesNotClearReplacementOwnership() async throws {
        let scheduler = ManualScheduler()
        let fixture = try ScreenshotStudioFixture(scheduler: scheduler)
        let item = fixture.item(source: .history)
        fixture.delivery.registerHistoryItem(id: item.id)
        fixture.delivery.activate(itemID: item.id)
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)

        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 1, y: 1)]))))
        fixture.delivery.revisionDidCommit(
            item: item,
            session: session,
            revision: 1,
            installationBaseline: 0
        )
        await waitForStudioCondition { await scheduler.waiterCount == 1 }

        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 2, y: 2)]))))
        fixture.delivery.revisionDidCommit(
            item: item,
            session: session,
            revision: 2,
            installationBaseline: 0
        )
        await waitForStudioCondition { await scheduler.waiterCount == 2 }
        XCTAssertTrue(fixture.delivery.hasPendingDebounce(for: item.id))

        await scheduler.releaseAll()
        await waitForStudioCondition { fixture.exporter.count == 1 }
        await waitForStudioCondition { !fixture.delivery.hasPendingDebounce(for: item.id) }

        XCTAssertEqual(fixture.exporter.revisions, [2])
    }

    func test_unexpectedDebounceFailureClearsOwnershipAndPublishesStructuredFailure() async throws {
        let fixture = try ScreenshotStudioFixture(scheduler: FailingScheduler())
        let item = fixture.item(source: .history)
        fixture.delivery.registerHistoryItem(id: item.id)
        fixture.delivery.activate(itemID: item.id)
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        var failures: [ScreenshotStudioFailure] = []
        fixture.delivery.setEventHandler { event in
            if case .failed(let failure) = event { failures.append(failure) }
        }

        XCTAssertTrue(session.commit(.stroke(.init(points: [.zero, CGPoint(x: 1, y: 1)]))))
        fixture.delivery.revisionDidCommit(
            item: item,
            session: session,
            revision: 1,
            installationBaseline: 0
        )
        await waitForStudioCondition { !failures.isEmpty }

        XCTAssertFalse(fixture.delivery.hasPendingDebounce(for: item.id))
        XCTAssertEqual(failures.first?.itemID, item.id)
        XCTAssertEqual(failures.first?.stage, .render)
        XCTAssertEqual(fixture.exporter.count, 0)
    }
}

extension ScreenCaptureDeliveryCoordinatorTests {
    func test_deliveryCompletionFollowsClipboardAndHistoryPublication() async throws {
        let fixture = try ScreenshotStudioFixture()
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        var eventKinds: [String] = []
        fixture.delivery.setEventHandler { event in
            switch event {
            case .clipboardUpdated: eventKinds.append("clipboard")
            case .historyChanged: eventKinds.append("history")
            case .deliveryCompleted: eventKinds.append("completed")
            default: break
            }
        }
        fixture.delivery.activate(itemID: item.id)

        fixture.delivery.copyNow(item: item, session: session)
        await waitForStudioCondition { eventKinds.contains("completed") }

        XCTAssertEqual(eventKinds, ["clipboard", "history", "completed"])
        XCTAssertEqual(fixture.clipboard.values.count, 1)
        let addCount = await fixture.repository.addCount
        XCTAssertEqual(addCount, 1)
    }
}

extension ScreenCaptureDeliveryCoordinatorTests {
    func test_clipboardFailurePersistsButEmitsNoDeliveryCompletion() async throws {
        let clipboard = RecordingClipboard(failures: 1)
        let fixture = try ScreenshotStudioFixture(clipboard: clipboard)
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        var events: [ScreenCaptureDeliveryEvent] = []
        fixture.delivery.setEventHandler { events.append($0) }
        fixture.delivery.activate(itemID: item.id)

        fixture.delivery.copyNow(item: item, session: session)
        await waitForStudioCondition { await fixture.repository.addCount == 1 }

        XCTAssertTrue(events.contains { event in
            if case .failed(let failure) = event { return failure.stage == .clipboard }
            return false
        })
        XCTAssertFalse(events.contains { event in
            if case .deliveryCompleted = event { return true }
            return false
        })
    }

    func test_historyFailureAfterClipboardEmitsNoDeliveryCompletion() async throws {
        let repository = try ControlledRepository()
        await repository.failNextAdd()
        let fixture = try ScreenshotStudioFixture(repository: repository)
        let item = fixture.item()
        let session = RasterImageEditSession.inMemory(item.image, canvasSize: item.canvasSize)
        var events: [ScreenCaptureDeliveryEvent] = []
        fixture.delivery.setEventHandler { events.append($0) }
        fixture.delivery.activate(itemID: item.id)

        fixture.delivery.copyNow(item: item, session: session)
        await waitForStudioCondition {
            events.contains { event in
                if case .failed(let failure) = event { return failure.stage == .historyAdd }
                return false
            }
        }

        XCTAssertEqual(fixture.clipboard.values.count, 1)
        XCTAssertFalse(events.contains { event in
            if case .deliveryCompleted = event { return true }
            return false
        })
    }
}
