import Combine
import Foundation

@MainActor
final class FolderExplorerViewModel: ObservableObject {
    enum TreeRefreshTrigger {
        case manual
        case watcher
    }

    @Published var rootURL: URL?
    @Published var rootItems: [FileItem] = []
    @Published private(set) var displayedItems: [FileItem] = []
    @Published var activeSidebarTab: SidebarTab = .files {
        didSet {
            guard activeSidebarTab == .files, oldValue != .files else { return }
            resumeDeferredTreeRefreshIfNeeded()
        }
    }
    @Published var expandedDirectoryIDs: Set<String> = []
    @Published var searchQuery = ""
    @Published var selectedItemID: String?
    @Published var selectedFileURL: URL?
    @Published var selectedFolderURL: URL?
    @Published var openRequest: ExplorerOpenRequest?
    @Published var renamingItemID: String?
    @Published var renameText = ""
    @Published var userFacingError: String?
    @Published var workerStatus: PaneWorkerStatus = .ready
    @Published var loadingDirectoryIDs: Set<String> = []
    @Published var gitStatusItems: [GitStatusItem] = []
    @Published var gitBranchOptions: [GitBranchOption] = []
    @Published var gitState: GitState = .idle
    @Published var gitCurrentBranchName: String?
    @Published var gitMessage: String?
    @Published var gitCommitMessageDraft = ""
    @Published var gitOperationMessage: String?
    @Published var gitIsOperating = false
    @Published var gitHistoryEntries: [GitCommitEntry] = []
    @Published var gitActiveHistoryScope: GitHistoryScope?
    @Published var gitHistoryIsLoading = false
    @Published var treeMutationRevision = 0
    @Published var changedDirectoryIDs: Set<String> = []

    let defaultSidebarTab: SidebarTab
    let worker: any PaneWorkerExecuting
    let renameEvents = PassthroughSubject<ExplorerRenameEvent, Never>()
    let treeLoadTimeout: TimeInterval = 45
    let observedFileSystemChanges = PassthroughSubject<Set<String>, Never>()
    var gitRefreshRequestID = UUID()
    var treeSessionID = UUID()
    var loadedDirectoryIDs: Set<String> = []
    var pendingExternalRefreshWorkItem: DispatchWorkItem?
    var pendingExternalRefreshPaths: Set<String> = []
    var pendingExternalRefreshEvents: [String: DirectoryWatcher.Event] = [:]
    var deferredTreeRefreshPaths: Set<String> = []
    var deferredTreeRefreshEvents: [String: DirectoryWatcher.Event] = [:]
    var directoryRefreshInFlight: Set<String> = []
    var queuedDirectoryRefreshPaths: Set<String> = []
    var directoryRefreshWaiters: [String: [CheckedContinuation<Bool, Never>]] = [:]
    private var displayedItemsComputationTask: Task<Void, Never>?
    private var displayedItemsComputationRequestID = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var hasShutdown = false

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(worker: any PaneWorkerExecuting) {
        let environment = ProcessInfo.processInfo.environment
        if environment["CRISPYVIBES_UI_TEST_EXPLORER_TAB"] == SidebarTab.git.rawValue {
            defaultSidebarTab = .git
        } else {
            defaultSidebarTab = .files
        }
        self.worker = worker
        activeSidebarTab = defaultSidebarTab
        bindDisplayedItems()
    }

    deinit {
        pendingExternalRefreshWorkItem?.cancel()
        displayedItemsComputationTask?.cancel()
    }

    /// Explicit shutdown for the folder explorer's long-lived resources.
    /// Per the project's coding-guidelines memory rule (explicit `shutdown()`
    /// for types owning long-lived resources), callers (notably
    /// `ProjectSession.shutdown`) MUST invoke this when the owning project is
    /// removed or parked — `deinit` alone is not sufficient because SwiftUI
    /// may still hold `@ObservedObject` references mid-unmount, leaving the
    /// directory watcher and pending tasks running on the main actor and
    /// causing UI churn after the project has logically gone.
    ///
    /// Idempotent: safe to call multiple times. `deinit` calls the same
    /// teardown, but those calls are no-ops once `hasShutdown` is true.
    @MainActor
    func shutdown() {
        guard !hasShutdown else { return }
        hasShutdown = true
        pendingExternalRefreshWorkItem?.cancel()
        pendingExternalRefreshWorkItem = nil
        displayedItemsComputationTask?.cancel()
        displayedItemsComputationTask = nil
        treeSessionID = UUID()
    }

    private func bindDisplayedItems() {
        let normalizedSearchQuery = $searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)

        Publishers.CombineLatest($rootItems, normalizedSearchQuery)
            .sink { [weak self] rootItems, query in
                self?.refreshDisplayedItems(rootItems: rootItems, query: query)
            }
            .store(in: &subscriptions)
    }

    private func refreshDisplayedItems(rootItems: [FileItem], query: String) {
        displayedItemsComputationTask?.cancel()

        guard !query.isEmpty else {
            displayedItemsComputationRequestID = UUID()
            displayedItems = rootItems
            return
        }

        let requestID = UUID()
        displayedItemsComputationRequestID = requestID

        displayedItemsComputationTask = Task { [weak self] in
            let filteredItems = await Task.detached(priority: .userInitiated) {
                rootItems.compactMap { FolderExplorerViewModel.filterForSearch(item: $0, query: query) }
            }.value

            guard !Task.isCancelled, let self else { return }
            guard self.displayedItemsComputationRequestID == requestID else { return }
            self.displayedItems = filteredItems
        }
    }
}
