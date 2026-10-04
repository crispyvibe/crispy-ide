import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenCaptureHistoryRepositoryConcurrencyTests: XCTestCase {
    func test_addIsInvisibleUntilStagedItemIsValidatedAndRenamed() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let processor = ScreenCaptureHistoryBlockingProcessor()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: processor
        )
        let initialEntries = try await repository.loadEntries()
        XCTAssertTrue(initialEntries.isEmpty)
        await processor.setBlocking(true)
        let png = try ScreenCaptureHistoryTestFixture.png()
        let id = UUID()
        let addTask = Task {
            try await repository.add(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        }
        await processor.waitUntilStarted()

        let entriesWhileStaged = try await repository.loadEntries()
        XCTAssertTrue(entriesWhileStaged.isEmpty)
        let visibleItems = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("items"),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(visibleItems.isEmpty)

        await processor.release()
        _ = try await addTask.value
        let committedEntries = try await repository.loadEntries()
        XCTAssertEqual(committedEntries.map(\.id), [id])
    }

    func test_updateCannotResurrectEntryDeletedWhileImageWorkWasPending() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let processor = ScreenCaptureHistoryBlockingProcessor()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: processor
        )
        let id = UUID()
        let png = try ScreenCaptureHistoryTestFixture.png()
        _ = try await repository.add(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        await processor.setBlocking(true)
        let updateTask = Task {
            try await repository.update(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        }
        await processor.waitUntilStarted()

        try await repository.delete(id: id)
        await processor.release()
        do {
            _ = try await updateTask.value
            XCTFail("Expected stale update rejection")
        } catch {
            XCTAssertEqual(error as? ScreenCaptureHistoryError, .staleOperation)
        }
        let remainingEntries = try await repository.loadEntries()
        XCTAssertTrue(remainingEntries.isEmpty)
    }

    func test_updateCannotResurrectEntryClearedWhileImageWorkWasPending() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let processor = ScreenCaptureHistoryBlockingProcessor()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: processor
        )
        let id = UUID()
        let png = try ScreenCaptureHistoryTestFixture.png()
        _ = try await repository.add(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        await processor.setBlocking(true)
        let updateTask = Task {
            try await repository.update(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        }
        await processor.waitUntilStarted()

        try await repository.clear()
        await processor.release()
        do {
            _ = try await updateTask.value
            XCTFail("Expected stale update rejection")
        } catch {
            XCTAssertEqual(error as? ScreenCaptureHistoryError, .staleOperation)
        }
        let remainingEntries = try await repository.loadEntries()
        XCTAssertTrue(remainingEntries.isEmpty)
    }
}


extension ScreenCaptureHistoryRepositoryConcurrencyTests {
    func test_cancelledPendingAddRemovesStagingAndPublishesNoItem() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let processor = ScreenCaptureHistoryBlockingProcessor()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: processor
        )
        _ = try await repository.loadEntries()
        await processor.setBlocking(true)
        let id = UUID()
        let png = try ScreenCaptureHistoryTestFixture.png()
        let addTask = Task {
            try await repository.add(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        }
        await processor.waitUntilStarted()

        addTask.cancel()
        await processor.release()
        do {
            _ = try await addTask.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ScreenCaptureHistoryError, .cancelled)
        }

        let entriesAfterCancellation = try await repository.loadEntries()
        XCTAssertTrue(entriesAfterCancellation.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("items"),
            includingPropertiesForKeys: nil
        ).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".staging"),
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    func test_cancelledPendingUpdatePreservesPriorVersionAndCurrentMetadata() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let processor = ScreenCaptureHistoryBlockingProcessor()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: processor
        )
        let id = UUID()
        let initialPNG = try ScreenCaptureHistoryTestFixture.png(width: 24, height: 12)
        let original = try await repository.add(
            id: id,
            content: ScreenCaptureHistoryTestFixture.content(initialPNG)
        )
        let item = root.appendingPathComponent("items/\(id.uuidString.lowercased())", isDirectory: true)
        let metadataURL = item.appendingPathComponent("current.json")
        let originalMetadata = try Data(contentsOf: metadataURL)
        await processor.setBlocking(true)
        let replacementPNG = try ScreenCaptureHistoryTestFixture.png(width: 48, height: 24)
        let updateTask = Task {
            try await repository.update(
                id: id,
                content: ScreenCaptureHistoryTestFixture.content(replacementPNG, width: 48, height: 24)
            )
        }
        await processor.waitUntilStarted()

        updateTask.cancel()
        await processor.release()
        do {
            _ = try await updateTask.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ScreenCaptureHistoryError, .cancelled)
        }

        let entriesAfterCancellation = try await repository.loadEntries()
        let retained = try XCTUnwrap(entriesAfterCancellation.first)
        XCTAssertEqual(retained.currentVersionID, original.currentVersionID)
        XCTAssertEqual(try Data(contentsOf: metadataURL), originalMetadata)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            at: item.appendingPathComponent("versions"),
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent), [original.flattenedFileIdentifier])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            at: item.appendingPathComponent("thumbnails"),
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent), [original.thumbnailFileIdentifier])
    }
}
