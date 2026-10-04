import Foundation

extension ScreenCaptureDeliveryCoordinator {
    /// Invalidates output before atomically deleting the repository item.
    func delete(id: UUID) {
        invalidate(itemID: id)
        let repository = repository
        let taskID = UUID()
        mutationTasks[taskID] = Task { [weak self] in
            do {
                try await repository.delete(id: id)
                guard !Task.isCancelled else { return }
                let entries = try await repository.loadEntries()
                guard !Task.isCancelled else { return }
                self?.historyItemIDs.remove(id)
                self?.historyStore?.synchronize(entries: entries)
                self?.eventHandler?(.deleted(id, entries))
            } catch {
                guard !Task.isCancelled else { return }
                self?.report(error, itemID: id, stage: .delete)
            }
            self?.mutationTasks[taskID] = nil
        }
    }

    /// Invalidates every pending output before atomically clearing history.
    func clear() {
        invalidateAllItems()
        let repository = repository
        let taskID = UUID()
        mutationTasks[taskID] = Task { [weak self] in
            do {
                try await repository.clear()
                guard !Task.isCancelled else { return }
                self?.historyItemIDs.removeAll()
                self?.historyStore?.synchronize(entries: [])
                self?.eventHandler?(.cleared)
            } catch {
                guard !Task.isCancelled else { return }
                self?.report(error, itemID: nil, stage: .clear)
            }
            self?.mutationTasks[taskID] = nil
        }
    }

    func enqueuePersistence(
        kind: PersistenceKind,
        itemID: UUID,
        revision: Int,
        clipboardCommitted: Bool,
        generation: UInt64,
        token: UInt64,
        png: Data,
        capture: CapturedScreenImage
    ) {
        let previous = persistenceTails[itemID]
        let repository = repository
        let content = ScreenCaptureHistoryContent(
            pngData: png,
            canvasWidth: capture.canvasSize.width,
            canvasHeight: capture.canvasSize.height,
            exportScale: capture.exportScale
        )
        let requestedKind = kind
        let task = Task { [weak self] in
            await previous?.value
            var effectiveKind = requestedKind
            do {
                try Task.checkCancellation()
                guard let self,
                      self.canPublishPersistence(
                        itemID: itemID,
                        generation: generation,
                        token: token
                      ) else { return }
                effectiveKind = self.historyItemIDs.contains(itemID) ? .update : requestedKind
                switch effectiveKind {
                case .add:
                    do {
                        _ = try await repository.add(id: itemID, content: content)
                    } catch let error as ScreenCaptureHistoryError where error == .itemAlreadyExists {
                        try Task.checkCancellation()
                        guard self.canPublishPersistence(
                            itemID: itemID,
                            generation: generation,
                            token: token
                        ) else { return }
                        effectiveKind = .update
                        _ = try await repository.update(id: itemID, content: content)
                    }
                case .update:
                    _ = try await repository.update(id: itemID, content: content)
                }
                try Task.checkCancellation()
                guard self.canPublishPersistence(
                    itemID: itemID,
                    generation: generation,
                    token: token
                ) else { return }
                self.historyItemIDs.insert(itemID)

                let entries = try await repository.loadEntries()
                try Task.checkCancellation()
                guard self.canPublishPersistence(
                    itemID: itemID,
                    generation: generation,
                    token: token
                ) else { return }

                var thumbnail: ScreenCaptureHistoryImage?
                var thumbnailPublicationSucceeded = true
                do {
                    thumbnail = try await repository.thumbnail(for: itemID)
                    try Task.checkCancellation()
                    guard self.canPublishPersistence(
                        itemID: itemID,
                        generation: generation,
                        token: token
                    ) else { return }
                } catch is CancellationError {
                    return
                } catch let error as ScreenCaptureHistoryError where error == .cancelled {
                    return
                } catch {
                    try Task.checkCancellation()
                    guard self.canPublishPersistence(
                        itemID: itemID,
                        generation: generation,
                        token: token
                    ) else { return }
                    thumbnailPublicationSucceeded = false
                    thumbnail = nil
                    self.report(error, itemID: itemID, stage: .historyLoad)
                }

                try Task.checkCancellation()
                guard self.canPublishPersistence(
                    itemID: itemID,
                    generation: generation,
                    token: token
                ) else { return }
                self.historyItemIDs.insert(itemID)
                self.historyStore?.synchronize(entries: entries)
                self.eventHandler?(.historyChanged(entries, itemID, thumbnail))
                if clipboardCommitted, thumbnailPublicationSucceeded {
                    self.eventHandler?(.deliveryCompleted(itemID, revision))
                }
            } catch is CancellationError {
                return
            } catch let error as ScreenCaptureHistoryError where error == .cancelled {
                return
            } catch {
                guard let self,
                      self.canPublishPersistence(
                        itemID: itemID,
                        generation: generation,
                        token: token
                      ) else { return }
                let stage: ScreenshotStudioFailureStage = effectiveKind == .add
                    ? .historyAdd : .historyUpdate
                self.report(error, itemID: itemID, stage: stage)
            }
        }
        persistenceTails[itemID] = task
    }
}
