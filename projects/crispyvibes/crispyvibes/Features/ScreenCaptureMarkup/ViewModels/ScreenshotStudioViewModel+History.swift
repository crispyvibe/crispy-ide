import CoreGraphics
import Foundation

extension ScreenshotStudioViewModel {
    /// Reloads newest-first metadata and decoded thumbnails without replacing the editor image.
    func refreshHistory() {
        guard !isShutdown else { return }
        historyTask?.cancel()
        setHistoryLoading(true)
        setFailure(nil)
        let repository = repository
        historyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let entries = try await repository.loadEntries()
                guard !Task.isCancelled else { return }
                self.replaceHistoryEntries(entries)
                await self.loadThumbnails(for: entries)
                guard !Task.isCancelled else { return }
                self.setHistoryLoading(false)
                self.historyTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.setHistoryLoading(false)
                self.historyTask = nil
                self.setFailure(Self.failure(for: error, itemID: nil, stage: .historyLoad))
            }
        }
    }

    /// Loads flattened history pixels off-main and installs only the latest requested item.
    func selectHistoryItem(id: UUID) {
        guard !isShutdown, id != currentItem?.id,
              let entry = historyEntries.first(where: { $0.id == id }) else { return }
        selectionTask?.cancel()
        clearPendingDismissState()
        selectionRequest = UUID()
        let request = selectionRequest
        setRequestedSelection(id)
        setFailure(nil)
        delivery.activate(itemID: id)
        let repository = repository
        let retainedItemID = currentItem?.id
        selectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await repository.flattenedSource(for: id)
                guard !Task.isCancelled, request == self.selectionRequest else { return }
                let capture = CapturedScreenImage(
                    cgImage: image.cgImage,
                    canvasSize: CGSize(width: entry.canvasWidth, height: entry.canvasHeight),
                    exportScale: CGFloat(entry.exportScale),
                    nativePixelSize: CGSize(width: entry.pixelWidth, height: entry.pixelHeight),
                    colorSpaceName: image.cgImage.colorSpace?.name.map { $0 as String },
                    placement: self.placement
                )
                self.install(.init(id: id, capture: capture, source: .history))
                self.selectionTask = nil
            } catch {
                guard !Task.isCancelled, request == self.selectionRequest else { return }
                self.setRequestedSelection(nil)
                self.selectionTask = nil
                self.setFailure(Self.failure(for: error, itemID: id, stage: .historySelection))
                if let retainedItemID { self.delivery.activate(itemID: retainedItemID) }
            }
        }
    }

    /// Deletes an item after delivery tokens have been invalidated.
    func deleteItem(id: UUID) {
        guard historyEntries.contains(where: { $0.id == id }) else { return }
        setFailure(nil)
        delivery.delete(id: id)
    }

    /// Deletes the current persisted item, if any.
    func deleteCurrent() {
        guard let id = currentItem?.id, canDeleteCurrent else { return }
        deleteItem(id: id)
    }

    /// Presents Clear History confirmation without mutating state from the view.
    func requestClearHistory() {
        setClearConfirmationPresented(true)
    }

    /// Dismisses Clear History confirmation.
    func cancelClearHistory() {
        setClearConfirmationPresented(false)
    }

    /// Clears persisted history after confirmation and invalidates pending output first.
    func confirmClearHistory() {
        clearHistory()
    }

    /// Clears history after invalidating Studio output, including Settings-initiated clears.
    func clearHistory() {
        setClearConfirmationPresented(false)
        setFailure(nil)
        delivery.clear()
    }

    func loadThumbnails(for entries: [ScreenCaptureHistoryEntry]) async {
        let repository = repository
        let validIDs = Set(entries.map(\.id))
        replaceThumbnails(thumbnails.filter { validIDs.contains($0.key) })
        await withTaskGroup(of: (UUID, ScreenCaptureHistoryImage?).self) { group in
            for entry in entries where thumbnails[entry.id] == nil {
                group.addTask {
                    (entry.id, try? await repository.thumbnail(for: entry.id))
                }
            }
            for await (id, image) in group {
                guard !Task.isCancelled else { return }
                if let image {
                    setThumbnail(image, for: id)
                } else if failure == nil {
                    setFailure(ScreenshotStudioFailure(
                        itemID: id,
                        stage: .historyLoad,
                        reason: .history(.decodingFailed)
                    ))
                }
            }
        }
    }

    static func failure(
        for error: Error,
        itemID: UUID?,
        stage: ScreenshotStudioFailureStage
    ) -> ScreenshotStudioFailure {
        let reason: ScreenshotStudioFailure.Reason
        if let historyError = error as? ScreenCaptureHistoryError {
            reason = .history(historyError)
        } else if let captureError = error as? ScreenCaptureError {
            reason = .capture(captureError)
        } else {
            reason = stage == .historySelection || stage == .historyLoad
                ? .history(.fileOperationFailed) : .capture(.encodingFailed)
        }
        return .init(itemID: itemID, stage: stage, reason: reason)
    }
}
