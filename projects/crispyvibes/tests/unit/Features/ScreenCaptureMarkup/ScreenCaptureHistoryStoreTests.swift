import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenCaptureHistoryStoreTests: XCTestCase {
    func test_thumbnailServiceCreatesBoundedAspectFitPNG() async throws {
        let service = ScreenCaptureThumbnailService()
        let source = try ScreenCaptureHistoryTestFixture.png(width: 800, height: 400)
        let prepared = try await service.prepare(pngData: source, maximumThumbnailPixelSize: 320)
        let canonical = try await service.decodePNG(prepared.canonicalPNG)
        let thumbnail = try await service.decodePNG(prepared.thumbnailPNG)

        XCTAssertEqual(canonical.pixelWidth, 800)
        XCTAssertEqual(canonical.pixelHeight, 400)
        XCTAssertEqual(thumbnail.pixelWidth, 320)
        XCTAssertEqual(thumbnail.pixelHeight, 160)
    }

    func test_storeNamedOperationsPublishEntriesAndStructuredErrors() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let store = ScreenCaptureHistoryStore(repository: repository)
        let png = try ScreenCaptureHistoryTestFixture.png()
        let id = UUID()

        store.load()
        await store.waitForPendingOperation()
        XCTAssertTrue(store.entries.isEmpty)
        store.add(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        await store.waitForPendingOperation()
        XCTAssertEqual(store.entries.map(\.id), [id])
        store.update(id: id, content: ScreenCaptureHistoryTestFixture.content(png))
        await store.waitForPendingOperation()
        XCTAssertEqual(store.entries.map(\.id), [id])
        store.delete(id: id)
        await store.waitForPendingOperation()
        XCTAssertTrue(store.entries.isEmpty)

        store.delete(id: UUID())
        await store.waitForPendingOperation()
        XCTAssertEqual(
            store.failure,
            ScreenCaptureHistoryStoreFailure(operation: .delete, error: .itemNotFound)
        )
        store.add(id: UUID(), content: ScreenCaptureHistoryTestFixture.content(png))
        await store.waitForPendingOperation()
        store.clear()
        await store.waitForPendingOperation()
        XCTAssertTrue(store.entries.isEmpty)
        store.shutdown()
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(store.failure)
    }
}
