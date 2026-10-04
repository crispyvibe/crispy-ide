import Foundation

extension ScreenCaptureDeliveryCoordinator {
    /// Eagerly encodes and copies a new raw capture, then adds its flattened PNG to history.
    func deliverInitial(item: ScreenshotStudioItem) {
        guard !isShutdown else { return }
        activate(itemID: item.id)
        let generation = bumpGeneration(for: item.id)
        let token = clipboardToken
        eventHandler?(.working(item.id, true))
        outputTask = Task { [weak self] in
            guard let self else { return }
            do {
                let representations = try await self.encoder.encode(item.capture)
                guard !Task.isCancelled else { return }
                self.finishEncoded(
                    representations,
                    renderedCapture: item.capture,
                    itemID: item.id,
                    revision: 0,
                    generation: generation,
                    token: token,
                    persistence: .add
                )
            } catch {
                guard token == self.clipboardToken,
                      generation == self.itemGenerations[item.id],
                      self.activeItemID == item.id else { return }
                self.report(error, itemID: item.id, stage: .encode)
                self.eventHandler?(.working(item.id, false))
            }
        }
    }

    /// Debounces a genuine revision and invalidates any older render immediately.
    func revisionDidCommit(
        item: ScreenshotStudioItem,
        session: RasterImageEditSession,
        revision: Int,
        installationBaseline: Int
    ) {
        guard !isShutdown, revision > installationBaseline, session.isDirty else { return }
        invalidateClipboardOutput()
        debounceTasks[item.id]?.cancel()
        let generation = bumpGeneration(for: item.id)
        let taskID = UUID()
        debounceTaskIDs[item.id] = taskID
        debounceTasks[item.id] = Task { [weak self, weak session] in
            guard let self else { return }
            defer { self.finishDebounce(itemID: item.id, taskID: taskID) }
            do {
                try await self.scheduler.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                guard let session else { return }
                self.startRenderedDelivery(
                    item: item,
                    session: session,
                    revision: revision,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                guard !self.isShutdown,
                      self.debounceTaskIDs[item.id] == taskID,
                      generation == self.itemGenerations[item.id],
                      self.activeItemID == item.id else { return }
                self.report(error, itemID: item.id, stage: .render)
            }
        }
    }

    /// Cancels pending debounce and immediately runs the same render/copy/persist pipeline.
    func copyNow(item: ScreenshotStudioItem, session: RasterImageEditSession) {
        guard !isShutdown else { return }
        debounceTasks[item.id]?.cancel()
        debounceTasks[item.id] = nil
        debounceTaskIDs[item.id] = nil
        invalidateClipboardOutput()
        let generation = bumpGeneration(for: item.id)
        startRenderedDelivery(
            item: item,
            session: session,
            revision: session.revision,
            generation: generation
        )
    }

    @discardableResult
    func finishDebounce(itemID: UUID, taskID: UUID) -> Bool {
        guard debounceTaskIDs[itemID] == taskID else { return false }
        debounceTaskIDs[itemID] = nil
        debounceTasks[itemID] = nil
        return true
    }

    func hasPendingDebounce(for itemID: UUID) -> Bool {
        debounceTaskIDs[itemID] != nil && debounceTasks[itemID] != nil
    }
}
