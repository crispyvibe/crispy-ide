import Foundation

extension LocalScreenCaptureHistoryRepository {
    /// Shares one bootstrap child. Cancellation by any owning waiter cancels that shared child;
    /// concurrent waiters observe cancellation and a later call creates a fresh retry.
    func prepareIfNeeded() async throws {
        try Task.checkCancellation()
        if isReady { return }

        let task: Task<Void, Error>
        let taskID: UUID
        if let bootstrapTask, let bootstrapTaskID {
            task = bootstrapTask
            taskID = bootstrapTaskID
        } else {
            taskID = UUID()
            task = Task { [weak self] in
                guard let self else { throw ScreenCaptureHistoryError.cancelled }
                try await self.performBootstrap()
            }
            bootstrapTask = task
            bootstrapTaskID = taskID
        }

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            if bootstrapTaskID == taskID {
                isReady = true
                bootstrapTask = nil
                bootstrapTaskID = nil
            }
        } catch {
            if bootstrapTaskID == taskID {
                bootstrapTask = nil
                bootstrapTaskID = nil
            }
            throw mapped(error)
        }
    }

    func performBootstrap() async throws {
        try Task.checkCancellation()
        guard rootURL.isFileURL, maximumEntryCount > 0, maximumAge >= 0 else {
            throw ScreenCaptureHistoryError.invalidRoot
        }
        try Task.checkCancellation()
        try createDirectory(rootURL)
        try Task.checkCancellation()
        try excludeRootFromBackup()
        try Task.checkCancellation()
        try createDirectory(itemsURL)
        try Task.checkCancellation()
        try createDirectory(stagingURL)
        try Task.checkCancellation()
        try createDirectory(trashURL)
        try Task.checkCancellation()
        try removeContents(of: stagingURL)
        try Task.checkCancellation()
        try removeContents(of: trashURL)
        try Task.checkCancellation()
        _ = try await loadAndPruneEntries()
        try Task.checkCancellation()
    }

    func loadAndPruneEntries() async throws -> [ScreenCaptureHistoryEntry] {
        try Task.checkCancellation()
        let epoch = clearEpoch
        let urls = try directoryContentsIncludingHidden(itemsURL)
        var entries: [ScreenCaptureHistoryEntry] = []
        for url in urls {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      let id = UUID(uuidString: url.lastPathComponent) else {
                    try Task.checkCancellation()
                    try quarantineCorruptItem(url)
                    continue
                }
                let entry = try await readValidatedEntry(at: url, expectedID: id, validateImages: true)
                try Task.checkCancellation()
                try removeOrphans(in: url, current: entry)
                entries.append(entry)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ScreenCaptureHistoryError where error == .cancelled {
                throw error
            } catch {
                try Task.checkCancellation()
                if epoch == clearEpoch {
                    try quarantineCorruptItem(url)
                }
            }
        }
        try Task.checkCancellation()
        guard epoch == clearEpoch else {
            let entries = try await loadAndPruneEntries()
            try Task.checkCancellation()
            return entries
        }

        entries.sort {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString > $1.id.uuidString }
            return $0.updatedAt > $1.updatedAt
        }
        let cutoff = clock.now.addingTimeInterval(-maximumAge)
        let retained = Array(entries.filter { $0.createdAt >= cutoff }.prefix(maximumEntryCount))
        let retainedIDs = Set(retained.map(\.id))
        for entry in entries where !retainedIDs.contains(entry.id) {
            try Task.checkCancellation()
            try atomicallyDelete(id: entry.id, requireExisting: false)
        }
        try Task.checkCancellation()
        return retained
    }

    func readValidatedEntry(
        at item: URL,
        expectedID: UUID,
        validateImages: Bool
    ) async throws -> ScreenCaptureHistoryEntry {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: item.path) else {
            throw ScreenCaptureHistoryError.itemNotFound
        }
        let entry = try decodeMetadata(at: currentMetadataURL(in: item))
        guard entry.id == expectedID else { throw ScreenCaptureHistoryError.corruptItem }
        let flattened = flattenedURL(for: entry, in: item)
        let thumbnail = thumbnailURL(for: entry, in: item)
        guard isRegularNonSymbolicFile(flattened), isRegularNonSymbolicFile(thumbnail) else {
            throw ScreenCaptureHistoryError.corruptItem
        }
        if validateImages {
            do {
                try Task.checkCancellation()
                _ = try await imageProcessor.decodePNG(Data(contentsOf: flattened, options: .mappedIfSafe))
                try Task.checkCancellation()
                _ = try await imageProcessor.decodePNG(Data(contentsOf: thumbnail, options: .mappedIfSafe))
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ScreenCaptureHistoryError where error == .cancelled {
                throw error
            } catch {
                throw ScreenCaptureHistoryError.corruptItem
            }
        }
        try Task.checkCancellation()
        return entry
    }

    func decodedImage(for id: UUID, thumbnail: Bool) async throws -> ScreenCaptureHistoryImage {
        try await prepareIfNeeded()
        try Task.checkCancellation()
        let epoch = clearEpoch
        let generation = generations[id, default: 0]
        let item = itemURL(id)
        let entry = try await readValidatedEntry(at: item, expectedID: id, validateImages: false)
        try Task.checkCancellation()
        let url = thumbnail ? thumbnailURL(for: entry, in: item) : flattenedURL(for: entry, in: item)
        let data: Data
        do {
            try Task.checkCancellation()
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ScreenCaptureHistoryError.corruptItem
        }
        let image = try await imageProcessor.decodePNG(data)
        try Task.checkCancellation()
        try checkCurrent(id: id, generation: generation, epoch: epoch, requiresExistingItem: true)
        return image
    }

    func atomicallyDelete(id: UUID, requireExisting: Bool) throws {
        try Task.checkCancellation()
        generations[id, default: 0] &+= 1
        tombstones.insert(id)
        let source = itemURL(id)
        guard fileManager.fileExists(atPath: source.path) else {
            if requireExisting { throw ScreenCaptureHistoryError.itemNotFound }
            return
        }
        let retired = trashURL.appendingPathComponent("item-\(UUID().uuidString)", isDirectory: true)
        try Task.checkCancellation()
        try fileOperation { try fileManager.moveItem(at: source, to: retired) }
        try Task.checkCancellation()
        try? fileManager.removeItem(at: retired)
    }

    func checkCurrent(
        id: UUID,
        generation: UInt64,
        epoch: UInt64,
        requiresExistingItem: Bool
    ) throws {
        guard clearEpoch == epoch,
              generations[id, default: 0] == generation,
              !tombstones.contains(id),
              !requiresExistingItem || fileManager.fileExists(atPath: itemURL(id).path),
              requiresExistingItem || !fileManager.fileExists(atPath: itemURL(id).path) else {
            throw ScreenCaptureHistoryError.staleOperation
        }
    }

    func quarantineCorruptItem(_ url: URL) throws {
        do {
            try quarantine(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScreenCaptureHistoryError where error == .cancelled {
            throw error
        } catch {
            maintenanceWarningHandler(.quarantineFailed)
        }
    }

    func quarantine(_ url: URL) throws {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: url.path) else { return }
        let retired = trashURL.appendingPathComponent("corrupt-\(UUID().uuidString)", isDirectory: true)
        if let quarantineMove {
            try quarantineMove(url, retired)
        } else {
            try fileOperation { try fileManager.moveItem(at: url, to: retired) }
        }
        try Task.checkCancellation()
        do {
            try fileManager.removeItem(at: retired)
        } catch {
            maintenanceWarningHandler(.quarantineCleanupFailed)
        }
    }

    func removeOrphans(in item: URL, current: ScreenCaptureHistoryEntry) throws {
        let versions = item.appendingPathComponent("versions", isDirectory: true)
        let thumbnails = item.appendingPathComponent("thumbnails", isDirectory: true)
        for url in try directoryContentsIncludingHidden(versions)
            where url.lastPathComponent != current.flattenedFileIdentifier {
            try Task.checkCancellation()
            try fileOperation { try fileManager.removeItem(at: url) }
        }
        for url in try directoryContentsIncludingHidden(thumbnails)
            where url.lastPathComponent != current.thumbnailFileIdentifier {
            try Task.checkCancellation()
            try fileOperation { try fileManager.removeItem(at: url) }
        }
    }
}
