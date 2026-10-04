import Combine
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenCaptureHistoryRepositoryRecoveryTests: XCTestCase {
    func test_retentionKeepsNewestFiftyEntries() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = ScreenCaptureHistoryTestClock(Date(timeIntervalSince1970: 50_000))
        let png = try ScreenCaptureHistoryTestFixture.png(width: 2, height: 2)
        let image = try await ScreenCaptureThumbnailService().decodePNG(png)
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: ScreenCaptureHistoryFastProcessor(image: image)
        )
        var ids: [UUID] = []
        for _ in 0..<52 {
            let id = UUID()
            ids.append(id)
            _ = try await repository.add(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
            clock.advance(1)
        }

        let loaded = try await repository.loadEntries()
        XCTAssertEqual(loaded.count, 50)
        XCTAssertEqual(loaded.map(\.id), Array(ids.suffix(50).reversed()))
        let firstRemovedURL = await repository.itemURL(ids[0])
        let secondRemovedURL = await repository.itemURL(ids[1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstRemovedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondRemovedURL.path))
    }

    func test_retentionRemovesEntriesOlderThanThirtyDays() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = ScreenCaptureHistoryTestClock(Date(timeIntervalSince1970: 100_000))
        let png = try ScreenCaptureHistoryTestFixture.png(width: 2, height: 2)
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let id = UUID()
        _ = try await repository.add(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        clock.advance((30 * 24 * 60 * 60) + 1)

        let loaded = try await repository.loadEntries()
        let expiredItemURL = await repository.itemURL(id)
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredItemURL.path))
    }

    func test_startupCleansInterruptedStagingOrphansAndIsolatesCorruptItems() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = ScreenCaptureHistoryTestClock(Date())
        let processor = ScreenCaptureThumbnailService()
        let firstRepository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: processor
        )
        let png = try ScreenCaptureHistoryTestFixture.png()
        let validID = UUID()
        let corruptID = UUID()
        let valid = try await firstRepository.add(
            id: validID,
            content: ScreenCaptureHistoryTestFixture.content(png)
        )
        _ = try await firstRepository.add(
            id: corruptID,
            content: ScreenCaptureHistoryTestFixture.content(png)
        )

        let abandoned = root.appendingPathComponent(".staging/abandoned", isDirectory: true)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: abandoned.appendingPathComponent("partial.png"))
        let validItem = await firstRepository.itemURL(validID)
        let orphanVersion = validItem.appendingPathComponent("versions/orphan.png")
        let orphanThumbnail = validItem.appendingPathComponent("thumbnails/orphan.png")
        try png.write(to: orphanVersion)
        try png.write(to: orphanThumbnail)
        let corruptItem = await firstRepository.itemURL(corruptID)
        try Data("{}".utf8).write(to: corruptItem.appendingPathComponent("current.json"), options: .atomic)

        let restarted = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: processor
        )
        let loaded = try await restarted.loadEntries()
        XCTAssertEqual(loaded, [valid])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptItem.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanVersion.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanThumbnail.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".staging"),
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    func test_deleteAndClearRetireItemsBeforePublishingEmptyDirectory() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let png = try ScreenCaptureHistoryTestFixture.png()
        let firstID = UUID()
        let secondID = UUID()
        _ = try await repository.add(id: firstID, content: ScreenCaptureHistoryTestFixture.content(png))
        _ = try await repository.add(id: secondID, content: ScreenCaptureHistoryTestFixture.content(png))

        try await repository.delete(id: firstID)
        let afterDelete = try await repository.loadEntries()
        let deletedItemURL = await repository.itemURL(firstID)
        XCTAssertEqual(afterDelete.map(\.id), [secondID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedItemURL.path))
        try await repository.clear()

        let afterClear = try await repository.loadEntries()
        XCTAssertTrue(afterClear.isEmpty)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("items").path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
    }
}


extension ScreenCaptureHistoryRepositoryRecoveryTests {
    func test_storeShutdownDuringBootstrapCancelsChildClearsOwnershipAndAllowsRetry() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = ScreenCaptureHistoryTestClock(Date())
        let png = try ScreenCaptureHistoryTestFixture.png(width: 8, height: 8)
        let seedRepository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let id = UUID()
        _ = try await seedRepository.add(
            id: id,
            content: ScreenCaptureHistoryTestFixture.content(png, width: 8, height: 8)
        )

        let processor = ScreenCaptureHistoryBlockingProcessor()
        await processor.setBlockingDecode()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: processor
        )
        let store = ScreenCaptureHistoryStore(repository: repository)
        var publishedNonemptySnapshot = false
        let observation = store.$entries.sink { entries in
            if !entries.isEmpty { publishedNonemptySnapshot = true }
        }

        store.load()
        await processor.waitUntilStarted()
        let hadPendingBootstrap = await repository.hasPendingBootstrap
        XCTAssertTrue(hadPendingBootstrap)

        store.shutdown()
        await processor.release()
        await processor.waitUntilCancellationObserved()
        await waitForStudioCondition { !(await repository.hasPendingBootstrap) }
        awaitStudioTurns(20)

        let pendingAfterShutdown = await repository.hasPendingBootstrap
        let retainedItemURL = await repository.itemURL(id)
        XCTAssertFalse(pendingAfterShutdown)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(store.failure)
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(publishedNonemptySnapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedItemURL.path))

        store.load()
        await store.waitForPendingOperation()

        let pendingAfterRetry = await repository.hasPendingBootstrap
        XCTAssertEqual(store.entries.map(\.id), [id])
        XCTAssertNil(store.failure)
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(pendingAfterRetry)
        withExtendedLifetime(observation) { }
    }
}

extension ScreenCaptureHistoryRepositoryRecoveryTests {
    func test_quarantineMoveFailureReportsWarningAndKeepsValidHistoryAvailable() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = ScreenCaptureHistoryTestClock(Date())
        let png = try ScreenCaptureHistoryTestFixture.png()
        let seed = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let validID = UUID()
        let corruptID = UUID()
        let valid = try await seed.add(
            id: validID,
            content: ScreenCaptureHistoryTestFixture.content(png)
        )
        _ = try await seed.add(
            id: corruptID,
            content: ScreenCaptureHistoryTestFixture.content(png)
        )
        let corruptItem = await seed.itemURL(corruptID)
        try Data("{}".utf8).write(
            to: corruptItem.appendingPathComponent("current.json"),
            options: .atomic
        )
        let warningRecorder = ScreenCaptureHistoryWarningRecorder()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: ScreenCaptureThumbnailService(),
            maintenanceWarningHandler: warningRecorder.record,
            quarantineMove: { _, _ in throw ScreenCaptureHistoryError.fileOperationFailed }
        )

        let loaded = try await repository.loadEntries()

        XCTAssertEqual(loaded, [valid])
        XCTAssertFalse(warningRecorder.warnings.isEmpty)
        XCTAssertTrue(warningRecorder.warnings.allSatisfy { $0 == .quarantineFailed })
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptItem.path))
    }

    func test_quarantineCancellationIsRethrown() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let corruptID = UUID()
        let png = try ScreenCaptureHistoryTestFixture.png()
        _ = try await seed.add(
            id: corruptID,
            content: ScreenCaptureHistoryTestFixture.content(png)
        )
        let corruptItem = await seed.itemURL(corruptID)
        try Data("{}".utf8).write(
            to: corruptItem.appendingPathComponent("current.json"),
            options: .atomic
        )
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService(),
            quarantineMove: { _, _ in throw CancellationError() }
        )

        var didCancel = false
        do {
            _ = try await repository.loadAndPruneEntries()

            XCTFail("Expected cancellation")
        } catch is CancellationError {
            didCancel = true
        }
        XCTAssertTrue(didCancel)
    }
}
