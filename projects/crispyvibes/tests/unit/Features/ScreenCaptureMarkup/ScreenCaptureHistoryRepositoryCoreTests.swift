import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ScreenCaptureHistoryRepositoryCoreTests: XCTestCase {
    func test_addLoadUpdateAndSeparateDecodedImages() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = ScreenCaptureHistoryTestClock(Date(timeIntervalSince1970: 10_000))
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: clock,
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let id = UUID()
        let firstPNG = try ScreenCaptureHistoryTestFixture.png(width: 40, height: 20)
        let first = try await repository.add(
            id: id,
            content: ScreenCaptureHistoryTestFixture.content(firstPNG, width: 20, height: 10)
        )

        let loaded = try await repository.loadEntries()
        XCTAssertEqual(loaded, [first])
        let source = try await repository.flattenedSource(for: id)
        let thumbnail = try await repository.thumbnail(for: id)
        XCTAssertEqual(source.pixelWidth, 40)
        XCTAssertEqual(source.pixelHeight, 20)
        XCTAssertLessThanOrEqual(max(thumbnail.pixelWidth, thumbnail.pixelHeight), 320)

        let item = await repository.itemURL(id)
        let oldFlattened = await repository.flattenedURL(for: first, in: item)
        let oldThumbnail = await repository.thumbnailURL(for: first, in: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldFlattened.path))
        clock.advance(10)
        let secondPNG = try ScreenCaptureHistoryTestFixture.png(width: 80, height: 30)
        let updated = try await repository.update(
            id: id,
            content: ScreenCaptureHistoryTestFixture.content(secondPNG, width: 40, height: 15)
        )

        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.createdAt, first.createdAt)
        XCTAssertGreaterThan(updated.updatedAt, first.updatedAt)
        XCTAssertNotEqual(updated.currentVersionID, first.currentVersionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFlattened.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldThumbnail.path))
        let updatedSource = try await repository.flattenedSource(for: id)
        XCTAssertEqual(updatedSource.pixelWidth, 80)
    }

    func test_metadataUsesExactPrivacyWhitelistAndPNGMetadataIsStripped() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let forbiddenValue = "private-window-title-origin-app-selection-annotation-path"
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date(timeIntervalSince1970: 20_000)),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        let id = UUID()
        let source = try ScreenCaptureHistoryTestFixture.png(metadataValue: forbiddenValue)
        let entry = try await repository.add(
            id: id,
            content: ScreenCaptureHistoryTestFixture.content(source)
        )
        let item = await repository.itemURL(id)
        let metadataURL = await repository.currentMetadataURL(in: item)
        let metadata = try Data(contentsOf: metadataURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        let expected: Set<String> = [
            "schemaVersion", "id", "createdAt", "updatedAt", "currentVersionID",
            "flattenedFileIdentifier", "thumbnailFileIdentifier", "canvasWidth",
            "canvasHeight", "exportScale", "pixelWidth", "pixelHeight"
        ]
        XCTAssertEqual(Set(object.keys), expected)

        let prohibitedKeys = ["app", "window", "display", "selection", "origin", "path", "title", "annotation"]
        let loweredKeys = object.keys.map { $0.lowercased() }
        for prohibited in prohibitedKeys {
            XCTAssertFalse(loweredKeys.contains { $0.contains(prohibited) })
        }
        let forbiddenBytes = Data(forbiddenValue.utf8)
        let flattened = await repository.flattenedURL(for: entry, in: item)
        let thumbnail = await repository.thumbnailURL(for: entry, in: item)
        XCTAssertNil(try Data(contentsOf: flattened).range(of: forbiddenBytes))
        XCTAssertNil(try Data(contentsOf: thumbnail).range(of: forbiddenBytes))
    }

    func test_rootIsExcludedFromBackup() async throws {
        let root = try ScreenCaptureHistoryTestFixture.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScreenCaptureHistoryRepository(
            rootURL: root,
            clock: ScreenCaptureHistoryTestClock(Date()),
            imageProcessor: ScreenCaptureThumbnailService()
        )
        _ = try await repository.loadEntries()
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
