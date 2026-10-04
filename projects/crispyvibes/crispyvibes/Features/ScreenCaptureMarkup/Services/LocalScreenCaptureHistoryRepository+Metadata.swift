import Foundation

extension LocalScreenCaptureHistoryRepository {
    var itemsURL: URL { rootURL.appendingPathComponent("items", isDirectory: true) }
    var stagingURL: URL { rootURL.appendingPathComponent(".staging", isDirectory: true) }
    var trashURL: URL { rootURL.appendingPathComponent(".trash", isDirectory: true) }

    func itemURL(_ id: UUID) -> URL {
        itemsURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    func currentMetadataURL(in item: URL) -> URL {
        item.appendingPathComponent("current.json", isDirectory: false)
    }

    func flattenedURL(for entry: ScreenCaptureHistoryEntry, in item: URL) -> URL {
        item.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(entry.flattenedFileIdentifier, isDirectory: false)
    }

    func thumbnailURL(for entry: ScreenCaptureHistoryEntry, in item: URL) -> URL {
        item.appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent(entry.thumbnailFileIdentifier, isDirectory: false)
    }

    func makeEntry(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        versionID: UUID,
        content: ScreenCaptureHistoryContent,
        prepared: ScreenCaptureHistoryPreparedImages
    ) -> ScreenCaptureHistoryEntry {
        let version = versionID.uuidString.lowercased()
        let canonicalCreatedAt = canonicalTimestamp(createdAt)
        let canonicalUpdatedAt = canonicalTimestamp(updatedAt)
        return ScreenCaptureHistoryEntry(
            schemaVersion: ScreenCaptureHistoryEntry.currentSchemaVersion,
            id: id,
            createdAt: canonicalCreatedAt,
            updatedAt: canonicalUpdatedAt,
            currentVersionID: versionID,
            flattenedFileIdentifier: "\(version).png",
            thumbnailFileIdentifier: "\(version).png",
            canvasWidth: content.canvasWidth,
            canvasHeight: content.canvasHeight,
            exportScale: content.exportScale,
            pixelWidth: prepared.pixelWidth,
            pixelHeight: prepared.pixelHeight
        )
    }

    func writeMetadata(_ entry: ScreenCaptureHistoryEntry, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        do {
            try encoder.encode(entry).write(to: url, options: .atomic)
        } catch {
            throw ScreenCaptureHistoryError.fileOperationFailed
        }
    }

    func decodeMetadata(at url: URL) throws -> ScreenCaptureHistoryEntry {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ScreenCaptureHistoryError.corruptItem
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Self.metadataKeys else {
            throw ScreenCaptureHistoryError.corruptItem
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let entry = try? decoder.decode(ScreenCaptureHistoryEntry.self, from: data) else {
            throw ScreenCaptureHistoryError.corruptItem
        }
        try validate(entry)
        return entry
    }

    func validate(_ content: ScreenCaptureHistoryContent) throws {
        guard !content.pngData.isEmpty,
              content.canvasWidth.isFinite, content.canvasWidth > 0,
              content.canvasHeight.isFinite, content.canvasHeight > 0,
              content.exportScale.isFinite, content.exportScale > 0 else {
            throw ScreenCaptureHistoryError.invalidContent
        }
    }

    func validate(_ entry: ScreenCaptureHistoryEntry) throws {
        let expectedFileIdentifier = "\(entry.currentVersionID.uuidString.lowercased()).png"
        guard entry.schemaVersion == ScreenCaptureHistoryEntry.currentSchemaVersion,
              entry.flattenedFileIdentifier == expectedFileIdentifier,
              entry.thumbnailFileIdentifier == expectedFileIdentifier,
              entry.canvasWidth.isFinite, entry.canvasWidth > 0,
              entry.canvasHeight.isFinite, entry.canvasHeight > 0,
              entry.exportScale.isFinite, entry.exportScale > 0,
              entry.pixelWidth > 0, entry.pixelHeight > 0 else {
            throw ScreenCaptureHistoryError.corruptItem
        }
    }

    func canonicalTimestamp(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.down)
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    static let metadataKeys: Set<String> = [
        "schemaVersion", "id", "createdAt", "updatedAt", "currentVersionID",
        "flattenedFileIdentifier", "thumbnailFileIdentifier", "canvasWidth",
        "canvasHeight", "exportScale", "pixelWidth", "pixelHeight"
    ]
}
