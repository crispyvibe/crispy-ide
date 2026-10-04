import Foundation

extension ScreenshotStudioViewModel {
    /// Performs explicit Copy immediately and leaves Screenshot Studio open.
    func copy() {
        guard canCopy, let item = currentItem, let session = installedSession, !isShutdown else { return }
        setFailure(nil)
        delivery.copyNow(item: item, session: session)
    }

    /// Delivers the selected revision immediately and closes only after clipboard and history commit.
    func copyAndDismiss() {
        guard canCopyAndDismiss,
              let item = currentItem,
              let session = installedSession,
              !isShutdown else { return }
        setFailure(nil)
        beginPendingDismiss(itemID: item.id, revision: session.revision)
        delivery.copyNow(item: item, session: session)
    }

    /// Retries copy failures through the identical full-resolution pipeline; otherwise refreshes history.
    func retryLastFailure() {
        guard let failure else { return }
        if failure.stage.supportsCopyRetry {
            copy()
        } else {
            refreshHistory()
        }
    }

    func handleDeliveryEvent(_ event: ScreenCaptureDeliveryEvent) {
        guard !isShutdown else { return }
        switch event {
        case let .working(id, working):
            if currentItem?.id == id { setWorking(working) }
        case let .clipboardUpdated(id, revision):
            guard currentItem?.id == id else { return }
            setLastCopiedRevision(revision)
            if failure?.stage.supportsCopyRetry == true { setFailure(nil) }
        case let .deliveryCompleted(id, revision):
            guard pendingDismissItemID == id,
                  let requestedRevision = pendingDismissRevision,
                  revision >= requestedRevision,
                  currentItem?.id == id else { return }
            clearPendingDismissState()
            consumeClose()
        case let .historyChanged(entries, id, thumbnail):
            replaceHistoryEntries(entries)
            if let thumbnail { setThumbnail(thumbnail, for: id) }
        case let .deleted(id, entries):
            replaceHistoryEntries(entries)
            setThumbnail(nil, for: id)
            if currentItem?.id == id {
                if let replacement = entries.first {
                    selectHistoryItem(id: replacement.id)
                } else {
                    clearCurrentItem()
                }
            }
        case .cleared:
            replaceHistoryEntries([])
            replaceThumbnails([:])
        case .failed(let failure):
            if failure.itemID == pendingDismissItemID { clearPendingDismissState() }
            setFailure(failure)
            if failure.itemID == currentItem?.id { setWorking(false) }
        }
    }
}
