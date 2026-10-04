import AppKit
import XCTest
@testable import CrispyVibes

/// F062-S18 persistence lifecycle coverage across delivery and the local repository.
@MainActor
final class ScreenCaptureDeliveryCancellationTests: XCTestCase {
    func test_shutdownDuringPendingAddPublishesNoItemOrLateSideEffect() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let processor = ScreenCaptureHistoryBlockingProcessor()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: processor
        )
        _ = try await repository.loadEntries()
        let png = try ScreenCaptureHistoryTestFixture.png(width: 8, height: 8)
        let clipboard = RecordingClipboard()
        let historyStore = ScreenCaptureHistoryStore(repository: repository)
        let delivery = ScreenCaptureDeliveryCoordinator(
            exporter: ImmediateRasterExporter(),
            encoder: FixedScreenCaptureOutput(png: png),
            clipboard: clipboard,
            repository: repository,
            historyStore: historyStore
        )
        let item = try ScreenshotStudioFixture().item()
        var events: [ScreenCaptureDeliveryEvent] = []
        delivery.setEventHandler { events.append($0) }
        await processor.setBlocking(true)
        delivery.deliverInitial(item: item)
        await processor.waitUntilStarted()
        let clipboardCountAtShutdown = clipboard.values.count
        let eventCountAtShutdown = events.count

        delivery.shutdown()
        await processor.release()
        let entriesAfterShutdown = try await repository.loadEntries()
        XCTAssertTrue(entriesAfterShutdown.isEmpty)
        awaitStudioTurns(50)

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("items"),
            includingPropertiesForKeys: nil
        ).isEmpty)
        XCTAssertTrue(historyStore.entries.isEmpty)
        XCTAssertEqual(clipboard.values.count, clipboardCountAtShutdown)
        XCTAssertEqual(events.count, eventCountAtShutdown)
    }

    func test_shutdownDuringPendingUpdatePreservesCommittedVersionAndMetadata() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let processor = ScreenCaptureHistoryBlockingProcessor()
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: processor
        )
        let id = UUID()
        let png = try ScreenCaptureHistoryTestFixture.png(width: 8, height: 8)
        let original = try await repository.add(
            id: id,
            content: ScreenCaptureHistoryTestFixture.content(png, width: 8, height: 8)
        )
        let itemURL = root.appendingPathComponent("items/\(id.uuidString.lowercased())", isDirectory: true)
        let metadataURL = itemURL.appendingPathComponent("current.json")
        let originalMetadata = try Data(contentsOf: metadataURL)
        let clipboard = RecordingClipboard()
        let historyStore = ScreenCaptureHistoryStore(repository: repository)
        historyStore.synchronize(entries: [original])
        let delivery = ScreenCaptureDeliveryCoordinator(
            exporter: ImmediateRasterExporter(),
            encoder: FixedScreenCaptureOutput(png: png),
            clipboard: clipboard,
            repository: repository,
            historyStore: historyStore
        )
        let capture = try ScreenshotStudioFixture().item(id: id, source: .history)
        delivery.registerHistoryItem(id: id)
        delivery.activate(itemID: id)
        var events: [ScreenCaptureDeliveryEvent] = []
        delivery.setEventHandler { events.append($0) }
        await processor.setBlocking(true)
        delivery.copyNow(
            item: capture,
            session: .inMemory(capture.image, canvasSize: capture.canvasSize)
        )
        await processor.waitUntilStarted()
        let clipboardCountAtShutdown = clipboard.values.count
        let eventCountAtShutdown = events.count

        delivery.shutdown()
        await processor.release()
        let entriesAfterShutdown = try await repository.loadEntries()
        let retained = try XCTUnwrap(entriesAfterShutdown.first)
        awaitStudioTurns(50)

        XCTAssertEqual(retained.currentVersionID, original.currentVersionID)
        XCTAssertEqual(try Data(contentsOf: metadataURL), originalMetadata)
        XCTAssertEqual(historyStore.entries.first?.currentVersionID, original.currentVersionID)
        XCTAssertEqual(clipboard.values.count, clipboardCountAtShutdown)
        XCTAssertEqual(events.count, eventCountAtShutdown)
    }
}

actor FixedScreenCaptureOutput: ScreenCaptureOutputEncoding {
    let png: Data

    init(png: Data) {
        self.png = png
    }

    func encode(_ image: CapturedScreenImage) async throws -> EncodedScreenCapture {
        EncodedScreenCapture(png: png, tiff: png)
    }
}


extension ScreenCaptureDeliveryCancellationTests {
    func test_shutdownAfterCommittedAddDuringPostCommitLoadPublishesNothingLate() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        _ = try await base.loadEntries()
        let repository = ScreenCaptureHistoryPostCommitGateRepository(base: base)
        await repository.arm(.loadEntries)
        let png = try ScreenCaptureHistoryTestFixture.png(width: 8, height: 8)
        let clipboard = RecordingClipboard()
        let historyStore = ScreenCaptureHistoryStore(repository: repository)
        let delivery = ScreenCaptureDeliveryCoordinator(
            exporter: ImmediateRasterExporter(),
            encoder: FixedScreenCaptureOutput(png: png),
            clipboard: clipboard,
            repository: repository,
            historyStore: historyStore
        )
        let image = try ScreenshotStudioFixture.makeImage()
        let item = ScreenshotStudioItem(
            id: UUID(),
            capture: CapturedScreenImage(
                cgImage: image,
                canvasSize: CGSize(width: image.width, height: image.height),
                exportScale: 1,
                nativePixelSize: CGSize(width: image.width, height: image.height),
                colorSpaceName: nil,
                placement: .init(displayID: 1, visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
            ),
            source: .capture
        )
        var events: [ScreenCaptureDeliveryEvent] = []
        delivery.setEventHandler { events.append($0) }

        delivery.deliverInitial(item: item)
        await repository.waitUntilBlocked()
        let itemURL = await base.itemURL(item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemURL.path), "Add must already be committed")
        let clipboardCountAtShutdown = clipboard.values.count
        let eventCountAtShutdown = events.count

        delivery.shutdown()
        historyStore.shutdown()
        await repository.release()
        awaitStudioTurns(50)

        let committedIDs = try await base.loadEntries().map(\.id)
        XCTAssertEqual(committedIDs, [item.id], "Committed files remain on disk")
        XCTAssertTrue(historyStore.entries.isEmpty)
        XCTAssertEqual(clipboard.values.count, clipboardCountAtShutdown)
        XCTAssertEqual(events.count, eventCountAtShutdown)
        XCTAssertFalse(events.contains { event in
            if case .historyChanged = event { return true }
            return false
        })
    }

    func test_studioShutdownAfterCommittedUpdateDuringThumbnailPublishesNothingLate() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = ScreenCaptureHistoryTestClock(Date())
        let base = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let id = UUID()
        let png = try ScreenCaptureHistoryTestFixture.png(width: 8, height: 8)
        let original = try await base.add(
            id: id,
            content: ScreenCaptureHistoryTestFixture.content(png, width: 8, height: 8)
        )
        let itemURL = await base.itemURL(id)
        let metadataURL = itemURL.appendingPathComponent("current.json")
        let originalMetadata = try Data(contentsOf: metadataURL)
        clock.advance(1)

        let repository = ScreenCaptureHistoryPostCommitGateRepository(base: base)
        await repository.arm(.thumbnail)
        let historyStore = ScreenCaptureHistoryStore(repository: repository)
        historyStore.synchronize(entries: [original])
        let clipboard = RecordingClipboard()
        let delivery = ScreenCaptureDeliveryCoordinator(
            exporter: ImmediateRasterExporter(),
            encoder: FixedScreenCaptureOutput(png: png),
            clipboard: clipboard,
            repository: repository,
            historyStore: historyStore
        )
        let editor = RasterImageEditorViewModel(services: .makeDefault())
        let viewModel = ScreenshotStudioViewModel(
            rasterViewModel: editor,
            repository: repository,
            delivery: delivery,
            placement: .init(displayID: 1, visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
        )
        let image = try ScreenshotStudioFixture.makeImage()
        let capture = CapturedScreenImage(
            cgImage: image,
            canvasSize: CGSize(width: image.width, height: image.height),
            exportScale: 1,
            nativePixelSize: CGSize(width: image.width, height: image.height),
            colorSpaceName: nil,
            placement: viewModel.placement
        )
        let item = ScreenshotStudioItem(id: id, capture: capture, source: .history)
        let session = RasterImageEditSession.inMemory(image, canvasSize: capture.canvasSize)
        var events: [ScreenCaptureDeliveryEvent] = []
        delivery.setEventHandler { [weak viewModel] event in
            events.append(event)
            viewModel?.handleDeliveryEvent(event)
        }
        viewModel.install(item)
        viewModel.didChangeRevision(itemID: id, session: session, revision: 0, isDirty: false)

        viewModel.copy()
        await repository.waitUntilBlocked()
        XCTAssertNotEqual(try Data(contentsOf: metadataURL), originalMetadata, "Update must already be committed")
        let clipboardCountAtShutdown = clipboard.values.count
        let eventCountAtShutdown = events.count

        viewModel.shutdown()
        historyStore.shutdown()
        await repository.release()
        awaitStudioTurns(50)

        let committedEntries = try await base.loadEntries()
        let committed = try XCTUnwrap(committedEntries.first)
        XCTAssertNotEqual(committed.currentVersionID, original.currentVersionID)
        XCTAssertTrue(historyStore.entries.isEmpty)
        XCTAssertTrue(viewModel.historyEntries.isEmpty)
        XCTAssertTrue(viewModel.thumbnails.isEmpty)
        XCTAssertNil(viewModel.currentItem)
        XCTAssertEqual(clipboard.values.count, clipboardCountAtShutdown)
        XCTAssertEqual(events.count, eventCountAtShutdown)
        XCTAssertFalse(events.contains { event in
            if case .historyChanged = event { return true }
            return false
        })
    }
}
