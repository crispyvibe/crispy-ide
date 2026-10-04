import Foundation

/// Content-free maintenance conditions safe to report without screenshot identifiers or paths.
enum ScreenCaptureHistoryMaintenanceWarning: Equatable, Sendable {
    case quarantineFailed
    case quarantineCleanupFailed
}

/// Actor-confined, bounded local repository for flattened screenshot history.
actor LocalScreenCaptureHistoryRepository: ScreenCaptureHistoryRepository {
    let rootURL: URL
    let fileManager: FileManager
    let clock: any ScreenCaptureHistoryClock
    let imageProcessor: any ScreenCaptureHistoryImageProcessing
    let maximumEntryCount: Int
    let maximumAge: TimeInterval
    let maximumThumbnailPixelSize: Int
    let maintenanceWarningHandler: @Sendable (ScreenCaptureHistoryMaintenanceWarning) -> Void
    let quarantineMove: (@Sendable (URL, URL) throws -> Void)?

    var isReady = false
    var bootstrapTask: Task<Void, Error>?
    var bootstrapTaskID: UUID?
    var hasPendingBootstrap: Bool { bootstrapTask != nil }
    var clearEpoch: UInt64 = 0
    var generations: [UUID: UInt64] = [:]
    var tombstones: Set<UUID> = []

    init(
        rootURL: URL,
        fileManager: FileManager = FileManager(),
        clock: any ScreenCaptureHistoryClock,
        imageProcessor: any ScreenCaptureHistoryImageProcessing,
        maximumEntryCount: Int = 50,
        maximumAge: TimeInterval = 30 * 24 * 60 * 60,
        maximumThumbnailPixelSize: Int = 320,
        maintenanceWarningHandler: @escaping @Sendable (ScreenCaptureHistoryMaintenanceWarning) -> Void = { _ in },
        quarantineMove: (@Sendable (URL, URL) throws -> Void)? = nil
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.clock = clock
        self.imageProcessor = imageProcessor
        self.maximumEntryCount = maximumEntryCount
        self.maximumAge = maximumAge
        self.maximumThumbnailPixelSize = maximumThumbnailPixelSize
        self.maintenanceWarningHandler = maintenanceWarningHandler
        self.quarantineMove = quarantineMove
    }

    func loadEntries() async throws -> [ScreenCaptureHistoryEntry] {
        try await prepareIfNeeded()
        try Task.checkCancellation()
        return try await loadAndPruneEntries()
    }

    func add(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        try await prepareIfNeeded()
        try Task.checkCancellation()
        try validate(content)
        guard !tombstones.contains(id), !fileManager.fileExists(atPath: itemURL(id).path) else {
            throw ScreenCaptureHistoryError.itemAlreadyExists
        }
        let epoch = clearEpoch
        let prepared: ScreenCaptureHistoryPreparedImages
        do {
            prepared = try await imageProcessor.prepare(
                pngData: content.pngData,
                maximumThumbnailPixelSize: maximumThumbnailPixelSize
            )
            try Task.checkCancellation()
        } catch {
            throw mapped(error)
        }
        try checkCurrent(id: id, generation: 0, epoch: epoch, requiresExistingItem: false)

        let versionID = UUID()
        let entry = makeEntry(
            id: id,
            createdAt: clock.now,
            updatedAt: clock.now,
            versionID: versionID,
            content: content,
            prepared: prepared
        )
        let stageURL = stagingURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try createItemDirectories(at: stageURL)
            try write(prepared.canonicalPNG, to: flattenedURL(for: entry, in: stageURL))
            try write(prepared.thumbnailPNG, to: thumbnailURL(for: entry, in: stageURL))
            try writeMetadata(entry, to: currentMetadataURL(in: stageURL))
            _ = try await readValidatedEntry(at: stageURL, expectedID: id, validateImages: true)
            try Task.checkCancellation()
            try checkCurrent(id: id, generation: 0, epoch: epoch, requiresExistingItem: false)
            try Task.checkCancellation()
            try fileOperation { try fileManager.moveItem(at: stageURL, to: itemURL(id)) }
        } catch {
            try? fileManager.removeItem(at: stageURL)
            throw mapped(error)
        }
        generations[id] = 0
        _ = try await loadAndPruneEntries()
        return entry
    }

    func update(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        try await prepareIfNeeded()
        try Task.checkCancellation()
        try validate(content)
        let generation = generations[id, default: 0]
        let epoch = clearEpoch
        let item = itemURL(id)
        let previous = try await readValidatedEntry(at: item, expectedID: id, validateImages: true)
        try Task.checkCancellation()
        try checkCurrent(id: id, generation: generation, epoch: epoch, requiresExistingItem: true)
        let prepared: ScreenCaptureHistoryPreparedImages
        do {
            prepared = try await imageProcessor.prepare(
                pngData: content.pngData,
                maximumThumbnailPixelSize: maximumThumbnailPixelSize
            )
            try Task.checkCancellation()
        } catch {
            throw mapped(error)
        }
        try checkCurrent(id: id, generation: generation, epoch: epoch, requiresExistingItem: true)

        let updated = makeEntry(
            id: id,
            createdAt: previous.createdAt,
            updatedAt: clock.now,
            versionID: UUID(),
            content: content,
            prepared: prepared
        )
        let newFlattenedURL = flattenedURL(for: updated, in: item)
        let newThumbnailURL = thumbnailURL(for: updated, in: item)
        do {
            try write(prepared.canonicalPNG, to: newFlattenedURL)
            try write(prepared.thumbnailPNG, to: newThumbnailURL)
            _ = try await imageProcessor.decodePNG(prepared.canonicalPNG)
            try Task.checkCancellation()
            _ = try await imageProcessor.decodePNG(prepared.thumbnailPNG)
            try Task.checkCancellation()
            try checkCurrent(id: id, generation: generation, epoch: epoch, requiresExistingItem: true)
            try Task.checkCancellation()
            try writeMetadata(updated, to: currentMetadataURL(in: item))
            try? fileManager.removeItem(at: flattenedURL(for: previous, in: item))
            try? fileManager.removeItem(at: thumbnailURL(for: previous, in: item))
        } catch {
            try? fileManager.removeItem(at: newFlattenedURL)
            try? fileManager.removeItem(at: newThumbnailURL)
            throw mapped(error)
        }
        _ = try await loadAndPruneEntries()
        return updated
    }

    func thumbnail(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        try await decodedImage(for: id, thumbnail: true)
    }

    func flattenedSource(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        try await decodedImage(for: id, thumbnail: false)
    }

    func delete(id: UUID) async throws {
        try await prepareIfNeeded()
        try Task.checkCancellation()
        try atomicallyDelete(id: id, requireExisting: true)
    }

    func clear() async throws {
        try await prepareIfNeeded()
        try Task.checkCancellation()
        clearEpoch &+= 1
        let retiredURL = trashURL.appendingPathComponent("clear-\(UUID().uuidString)", isDirectory: true)
        do {
            try Task.checkCancellation()
            try fileOperation { try fileManager.moveItem(at: itemsURL, to: retiredURL) }
            do {
                try createDirectory(itemsURL)
            } catch {
                try? fileManager.moveItem(at: retiredURL, to: itemsURL)
                throw error
            }
            generations.removeAll()
            tombstones.removeAll()
            try? fileManager.removeItem(at: retiredURL)
        } catch {
            throw mapped(error)
        }
    }
}
