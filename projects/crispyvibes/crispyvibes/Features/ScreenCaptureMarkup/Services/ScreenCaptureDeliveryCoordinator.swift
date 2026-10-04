import CoreGraphics
import Foundation

/// Renders, eagerly encodes, copies, and persists flattened Screenshot Studio output.
@MainActor
final class ScreenCaptureDeliveryCoordinator {
    enum PersistenceKind { case add, update }

    let exporter: any RasterImageExporting
    let encoder: any ScreenCaptureOutputEncoding
    let clipboard: any ScreenCaptureClipboardDelivering
    let repository: any ScreenCaptureHistoryRepository
    let historyStore: ScreenCaptureHistoryStore?
    let scheduler: any ScreenCaptureScheduling

    var eventHandler: ((ScreenCaptureDeliveryEvent) -> Void)?
    var activeItemID: UUID?
    var clipboardToken: UInt64 = 0
    var itemGenerations: [UUID: UInt64] = [:]
    var historyItemIDs: Set<UUID> = []
    var debounceTasks: [UUID: Task<Void, Never>] = [:]
    var debounceTaskIDs: [UUID: UUID] = [:]
    var mutationTasks: [UUID: Task<Void, Never>] = [:]
    var outputTask: Task<Void, Never>?
    var renderHandle: RasterImageWorkHandle?
    var persistenceTails: [UUID: Task<Void, Never>] = [:]
    var isShutdown = false

    init(
        exporter: any RasterImageExporting,
        encoder: any ScreenCaptureOutputEncoding,
        clipboard: any ScreenCaptureClipboardDelivering,
        repository: any ScreenCaptureHistoryRepository,
        historyStore: ScreenCaptureHistoryStore? = nil,
        scheduler: any ScreenCaptureScheduling = ContinuousScreenCaptureScheduler()
    ) {
        self.exporter = exporter
        self.encoder = encoder
        self.clipboard = clipboard
        self.repository = repository
        self.historyStore = historyStore
        self.scheduler = scheduler
    }

    /// Installs the presentation callback. The closure is cleared during shutdown.
    func setEventHandler(_ handler: @escaping (ScreenCaptureDeliveryEvent) -> Void) {
        eventHandler = handler
    }

    /// Makes `itemID` the only item allowed to replace the clipboard.
    func activate(itemID: UUID) {
        guard !isShutdown else { return }
        activeItemID = itemID
        invalidateClipboardOutput()
    }

    /// Marks a repository-backed item so future flattened writes are updates.
    func registerHistoryItem(id: UUID) {
        historyItemIDs.insert(id)
        itemGenerations[id, default: 0] &+= 1
    }

    /// Cancels every task and render handle and disconnects presentation callbacks.
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        invalidateAllItems()
        persistenceTails.values.forEach { $0.cancel() }
        persistenceTails.removeAll()
        mutationTasks.values.forEach { $0.cancel() }
        mutationTasks.removeAll()
        eventHandler = nil
    }

    func canPublishPersistence(
        itemID: UUID,
        generation: UInt64,
        token: UInt64
    ) -> Bool {
        !isShutdown
            && token == clipboardToken
            && generation == itemGenerations[itemID]
            && activeItemID == itemID
    }

    @discardableResult
    func bumpGeneration(for itemID: UUID) -> UInt64 {
        itemGenerations[itemID, default: 0] &+= 1
        return itemGenerations[itemID, default: 0]
    }

    func invalidate(itemID: UUID) {
        _ = bumpGeneration(for: itemID)
        debounceTasks.removeValue(forKey: itemID)?.cancel()
        debounceTaskIDs.removeValue(forKey: itemID)
        persistenceTails.removeValue(forKey: itemID)?.cancel()
        if activeItemID == itemID {
            activeItemID = nil
            invalidateClipboardOutput()
        }
    }

    func invalidateAllItems() {
        itemGenerations.keys.forEach { itemGenerations[$0, default: 0] &+= 1 }
        debounceTasks.values.forEach { $0.cancel() }
        debounceTasks.removeAll()
        debounceTaskIDs.removeAll()
        outputTask?.cancel()
        outputTask = nil
        renderHandle?.cancel()
        renderHandle = nil
        clipboardToken &+= 1
        activeItemID = nil
    }

    func invalidateClipboardOutput() {
        clipboardToken &+= 1
        outputTask?.cancel()
        outputTask = nil
        renderHandle?.cancel()
        renderHandle = nil
    }

    func report(_ error: Error, itemID: UUID?, stage: ScreenshotStudioFailureStage) {
        let reason: ScreenshotStudioFailure.Reason
        if let error = error as? ScreenCaptureHistoryError {
            reason = .history(error)
        } else if let error = error as? ScreenCaptureError {
            reason = .capture(error)
        } else if stage == .render {
            reason = .rendering
        } else {
            reason = .capture(stage == .clipboard ? .clipboardFailed : .encodingFailed)
        }
        eventHandler?(.failed(.init(itemID: itemID, stage: stage, reason: reason)))
    }
}
