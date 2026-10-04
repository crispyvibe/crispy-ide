import Combine
import CoreGraphics
import Foundation

/// Main-actor owner of Screenshot Studio selection, memory-backed F009 editing, and delivery state.
@MainActor
final class ScreenshotStudioViewModel: ObservableObject {
    @Published private(set) var currentItem: ScreenshotStudioItem?
    @Published private(set) var historyEntries: [ScreenCaptureHistoryEntry] = []
    @Published private(set) var thumbnails: [UUID: ScreenCaptureHistoryImage] = [:]
    @Published private(set) var requestedSelectionID: UUID?
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var isWorking = false
    @Published private(set) var failure: ScreenshotStudioFailure?
    @Published private(set) var lastCopiedRevision: Int?
    @Published private(set) var isCopyAndDismissPending = false
    @Published private(set) var isClearConfirmationPresented = false

    let rasterViewModel: RasterImageEditorViewModel
    let repository: any ScreenCaptureHistoryRepository
    let delivery: ScreenCaptureDeliveryCoordinator
    var placement: ScreenCapturePlacementContext
    var historyTask: Task<Void, Never>?
    var selectionTask: Task<Void, Never>?
    var selectionRequest = UUID()
    var installedSession: RasterImageEditSession?
    var installationBaseline = 0
    var pendingDismissItemID: UUID?
    var pendingDismissRevision: Int?
    var isShutdown = false
    var onClose: (() -> Void)?

    init(
        rasterViewModel: RasterImageEditorViewModel,
        repository: any ScreenCaptureHistoryRepository,
        delivery: ScreenCaptureDeliveryCoordinator,
        placement: ScreenCapturePlacementContext
    ) {
        self.rasterViewModel = rasterViewModel
        self.repository = repository
        self.delivery = delivery
        self.placement = placement
        configureEditor()
        delivery.setEventHandler { [weak self] event in self?.handleDeliveryEvent(event) }
    }

    var selectedItemID: UUID? { currentItem?.id }
    var currentImage: CGImage? { currentItem?.image }
    var canCopy: Bool {
        currentItem != nil && installedSession != nil && !isWorking && !isCopyAndDismissPending
    }
    var canCopyAndDismiss: Bool { canCopy }
    var canDeleteCurrent: Bool { currentItem.map { historyEntries.containsID($0.id) } ?? false }

    /// Installs new capture pixels without starting side effects so presentation can happen first.
    func installNewCapture(_ capture: AcquiredScreenCapture) {
        guard !isShutdown else { return }
        let item = ScreenshotStudioItem(id: capture.id, capture: capture.image, source: .capture)
        install(item)
    }

    /// Starts eager raw clipboard and flattened-history delivery for the installed capture.
    func deliverCurrentCapture() {
        guard !isShutdown, let item = currentItem, item.source == .capture else { return }
        delivery.deliverInitial(item: item)
        refreshHistory()
    }

    /// Called by the memory host with the exact session that published the revision.
    func didChangeRevision(
        itemID: UUID,
        session: RasterImageEditSession,
        revision: Int,
        isDirty: Bool
    ) {
        guard currentItem?.id == itemID, !isShutdown else { return }
        if installedSession !== session {
            installedSession = session
            installationBaseline = revision
            return
        }
        guard isDirty, let item = currentItem else { return }
        delivery.revisionDidCommit(
            item: item,
            session: session,
            revision: revision,
            installationBaseline: installationBaseline
        )
    }

    /// Asks the owning panel controller to close without revealing the main IDE.
    func close() {
        consumeClose()
    }

    /// Cancels editor, loading, rendering, encoding, and persistence presentation work.
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        historyTask?.cancel()
        selectionTask?.cancel()
        historyTask = nil
        selectionTask = nil
        requestedSelectionID = nil
        isLoadingHistory = false
        isWorking = false
        clearPendingDismissState()
        installedSession = nil
        delivery.shutdown()
        rasterViewModel.shutdown()
        thumbnails.removeAll()
        historyEntries.removeAll()
        currentItem = nil
        onClose = nil
    }

    func install(_ item: ScreenshotStudioItem) {
        clearPendingDismissState()
        currentItem = item
        placement = item.capture.placement
        requestedSelectionID = nil
        installedSession = nil
        installationBaseline = 0
        failure = nil
        lastCopiedRevision = nil
        configureEditor()
        delivery.activate(itemID: item.id)
        if item.source == .history { delivery.registerHistoryItem(id: item.id) }
    }

    private func configureEditor() {
        rasterViewModel.selectMode(.markup)
        rasterViewModel.selectMarkupTool(.pen)
    }

    func beginPendingDismiss(itemID: UUID, revision: Int) {
        pendingDismissItemID = itemID
        pendingDismissRevision = revision
        isCopyAndDismissPending = true
    }

    func clearPendingDismissState() {
        pendingDismissItemID = nil
        pendingDismissRevision = nil
        isCopyAndDismissPending = false
    }

    func consumeClose() {
        let close = onClose
        onClose = nil
        close?()
    }

    func replaceHistoryEntries(_ entries: [ScreenCaptureHistoryEntry]) {
        historyEntries = entries
    }

    func replaceThumbnails(_ images: [UUID: ScreenCaptureHistoryImage]) {
        thumbnails = images
    }

    func setThumbnail(_ image: ScreenCaptureHistoryImage?, for id: UUID) {
        thumbnails[id] = image
    }

    func setRequestedSelection(_ id: UUID?) {
        requestedSelectionID = id
    }

    func setHistoryLoading(_ loading: Bool) {
        isLoadingHistory = loading
    }

    func setWorking(_ working: Bool) {
        isWorking = working
    }

    func setFailure(_ value: ScreenshotStudioFailure?) {
        failure = value
    }

    func setLastCopiedRevision(_ revision: Int?) {
        lastCopiedRevision = revision
    }

    func setClearConfirmationPresented(_ presented: Bool) {
        isClearConfirmationPresented = presented
    }

    func clearCurrentItem() {
        clearPendingDismissState()
        currentItem = nil
        installedSession = nil
    }
}

private extension Array where Element == ScreenCaptureHistoryEntry {
    func containsID(_ id: UUID) -> Bool { contains { $0.id == id } }
}
