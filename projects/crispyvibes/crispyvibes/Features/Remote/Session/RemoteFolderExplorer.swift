// RemoteFolderExplorer.swift — SSH Remote Development
//
// Remote FolderExploring implementation backed by SFTP.
// Lazy directory loading, polling watcher, manual refresh.

import Combine
import Foundation

@MainActor
final class RemoteFolderExplorer: ObservableObject, FolderExploring {

    // MARK: - Published State

    @Published var rootURL: URL?
    @Published var rootItems: [FileItem] = []
    @Published private(set) var displayedItems: [FileItem] = []
    @Published var activeSidebarTab: FolderExplorerViewModel.SidebarTab = .files
    @Published var expandedDirectoryIDs: Set<String> = []
    @Published var searchQuery: String = ""
    @Published var selectedItemID: String?
    @Published var selectedFileURL: URL?
    @Published var selectedFolderURL: URL?
    @Published var openRequest: ExplorerOpenRequest?
    @Published var renamingItemID: String?
    @Published var renameText: String = ""
    @Published var userFacingError: String?
    @Published var workerStatus: PaneWorkerStatus = .ready
    @Published var loadingDirectoryIDs: Set<String> = []
    @Published var changedDirectoryIDs: Set<String> = []
    @Published var treeMutationRevision: Int = 0

    // Git state (delegated to RemoteGitExplorer via RemoteProjectSession)
    @Published var gitStatusItems: [GitStatusItem] = []
    @Published var gitBranchOptions: [GitBranchOption] = []
    @Published var gitCurrentBranchName: String?
    @Published var gitState: FolderExplorerViewModel.GitState = .idle
    @Published var gitMessage: String?
    @Published var gitCommitMessageDraft: String = ""
    @Published var gitIsOperating: Bool = false
    @Published var gitOperationMessage: String?
    @Published var gitHistoryEntries: [GitCommitEntry] = []
    @Published var gitActiveHistoryScope: GitHistoryScope?
    @Published var gitHistoryIsLoading: Bool = false

    let supportsLiveWatching = false
    let renameEvents = PassthroughSubject<ExplorerRenameEvent, Never>()
    let observedFileSystemChanges = PassthroughSubject<Set<String>, Never>()

    private let fileSystem: any FileSystemProviding
    private let watcher: any DirectoryWatching
    private let remotePath: String
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var refreshRequestID = UUID()

    init(remotePath: String, fileSystem: any FileSystemProviding, watcher: any DirectoryWatching) {
        self.remotePath = remotePath
        self.fileSystem = fileSystem
        self.watcher = watcher
        bindSearch()

        // Wire watcher output to observedFileSystemChanges and trigger refresh
        watcher.onPathsChanged = { [weak self] changedPaths in
            self?.observedFileSystemChanges.send(changedPaths)
            self?.refresh()
        }
    }

    // MARK: - Tree Operations

    func setRootFolder(_ url: URL) {
        AppDiagnostics.record(
            category: .remote,
            level: .info,
            event: "remote_explorer_set_root",
            metadata: ["url_path": url.path, "remote_path": remotePath]
        )
        rootURL = url
        watcher.watch(paths: [url.path])
        refresh()
    }

    func refreshTree(trigger: FolderExplorerViewModel.TreeRefreshTrigger) { refresh() }

    func toggleExpansion(for item: FileItem) {
        if expandedDirectoryIDs.contains(item.id) {
            expandedDirectoryIDs.remove(item.id)
        } else {
            expandedDirectoryIDs.insert(item.id)
            loadChildren(for: item)
        }
    }

    func isDirectoryLoading(_ directoryID: String) -> Bool { loadingDirectoryIDs.contains(directoryID) }

    // MARK: - File Operations

    func createNewFile(in item: FileItem?) {
        let dir = item?.isDirectory == true ? item!.url.path : (rootURL?.path ?? remotePath)
        Task {
            do {
                try await fileSystem.createFile(at: (dir as NSString).appendingPathComponent("untitled"), contents: nil)
                refresh()
            } catch { userFacingError = error.localizedDescription }
        }
    }

    func createNewFolder(in item: FileItem?) {
        let dir = item?.isDirectory == true ? item!.url.path : (rootURL?.path ?? remotePath)
        Task {
            do {
                try await fileSystem.createDirectory(at: (dir as NSString).appendingPathComponent("New Folder"))
                refresh()
            } catch { userFacingError = error.localizedDescription }
        }
    }

    func createNewFileAtSelection() { createNewFile(in: nil) }
    func createNewFolderAtSelection() { createNewFolder(in: nil) }

    func deleteItem(_ item: FileItem) {
        Task {
            do { try await fileSystem.removeItem(at: item.url.path); refresh() }
            catch { userFacingError = error.localizedDescription }
        }
    }

    func startRenaming(item: FileItem) { renamingItemID = item.id; renameText = item.url.lastPathComponent }
    func startRenamingSelectedItem() {
        guard let id = selectedItemID else { return }
        renamingItemID = id; renameText = URL(fileURLWithPath: id).lastPathComponent
    }

    func commitRename() {
        guard let renamingID = renamingItemID else { return }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()
        guard !newName.isEmpty else { return }
        let newPath = (renamingID as NSString).deletingLastPathComponent + "/" + newName
        Task {
            do {
                try await fileSystem.moveItem(from: renamingID, to: newPath)
                renameEvents.send(ExplorerRenameEvent(oldURL: URL(fileURLWithPath: renamingID), newURL: URL(fileURLWithPath: newPath)))
                refresh()
            } catch { userFacingError = error.localizedDescription }
        }
    }

    func cancelRename() { renamingItemID = nil; renameText = "" }
    func clearError() { userFacingError = nil }

    // MARK: - Selection

    func select(_ item: FileItem) {
        selectedItemID = item.id
        if item.isDirectory { selectedFolderURL = item.url } else { selectedFileURL = item.url }
    }

    func openInTab(_ item: FileItem) {
        guard !item.isDirectory else { return }
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openTab)
    }

    func openInWindow(_ item: FileItem) { openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openWindow) }
    func openInSplitHorizontal(_ item: FileItem) { openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openInSplitHorizontal) }
    func openInSplitVertical(_ item: FileItem) { openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openInSplitVertical) }
    func selectGitStatusItem(_ item: GitStatusItem) { selectedItemID = item.url.path; selectedFileURL = item.url }

    // MARK: - Git (no-op stubs — git handled by RemoteGitExplorer)

    func stageGitItem(_ item: GitStatusItem) {}
    func unstageGitItem(_ item: GitStatusItem) {}
    func stageAllGitChanges() {}
    func commitGitChanges() {}
    func pushGitChanges() {}
    func checkoutGitBranch(_ branch: GitBranchOption) {}
    func refreshGitStatus() {}
    func refreshGitBranches() {}
    func openGitHistory(scope: GitHistoryScope) {}
    func dismissGitHistory() {}
    func transferItems(using plans: [ExplorerItemTransferPlan]) {}

    func stopWatching() {
        watcher.stop()
        refreshRequestID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        workerStatus = .ready
    }

    // MARK: - Private

    private func refresh() {
        let path = rootURL?.path ?? remotePath
        let requestID = UUID()
        refreshRequestID = requestID
        workerStatus = .busy("Loading")
        refreshTask?.cancel()
        AppDiagnostics.record(
            category: .remote,
            level: .info,
            event: "remote_explorer_refresh_start",
            metadata: [
                "path": path,
                "root_url_set": rootURL != nil ? "true" : "false",
                "request_id": requestID.uuidString
            ]
        )
        refreshTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    guard let self, self.refreshRequestID == requestID else { return }
                    self.refreshTask = nil
                }
            }
            guard let self else { return }
            do {
                let items = try await self.fileSystem.contentsOfDirectory(at: path)
                guard !Task.isCancelled else {
                    AppDiagnostics.record(
                        category: .remote,
                        level: .info,
                        event: "remote_explorer_refresh_cancelled",
                        metadata: ["path": path, "request_id": requestID.uuidString]
                    )
                    return
                }
                // Preserve previously-loaded children for items that still
                // exist at the same path. The polling watcher fires periodic
                // refreshes which would otherwise clear out lazily-loaded
                // sub-trees (FileItem.children populated by loadChildren),
                // making expanded directories appear empty until re-expanded.
                let cachedChildrenByID: [String: [FileItem]] = Dictionary(
                    uniqueKeysWithValues: self.rootItems.compactMap { item in
                        guard let children = item.children else { return nil }
                        return (item.id, children)
                    }
                )
                let newRootItems: [FileItem] = items
                    .map { descriptor -> FileItem in
                        let url = URL(fileURLWithPath: descriptor.path)
                        return FileItem(
                            url: url,
                            isDirectory: descriptor.isDirectory,
                            isHidden: descriptor.isHidden,
                            children: cachedChildrenByID[url.path]
                        )
                    }
                    .sorted { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
                self.rootItems = newRootItems
                self.refreshDisplayedItems()
                self.workerStatus = .ready
                AppDiagnostics.record(
                    category: .remote,
                    level: .info,
                    event: "remote_explorer_refresh_ok",
                    metadata: [
                        "path": path,
                        "descriptor_count": String(items.count),
                        "root_items_count": String(newRootItems.count),
                        "request_id": requestID.uuidString
                    ]
                )
            } catch {
                guard !Task.isCancelled else { return }
                if !Self.shouldSuppressConnectionReadinessError(error) {
                    self.userFacingError = error.localizedDescription
                }
                self.workerStatus = .ready
                AppDiagnostics.record(
                    category: .remote,
                    level: .error,
                    event: "remote_explorer_refresh_failed",
                    metadata: [
                        "path": path,
                        "error": String(error.localizedDescription.prefix(300)),
                        "request_id": requestID.uuidString
                    ]
                )
            }
        }
    }

    private func loadChildren(for item: FileItem) {
        loadingDirectoryIDs.insert(item.id)
        Task {
            defer { loadingDirectoryIDs.remove(item.id) }
            do {
                let descriptors = try await fileSystem.contentsOfDirectory(at: item.url.path)
                let children = descriptors.map {
                    FileItem(url: URL(fileURLWithPath: $0.path), isDirectory: $0.isDirectory, isHidden: $0.isHidden)
                }.sorted { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
                rootItems = rootItems.map { updateItem($0, parentID: item.id, children: children) }
                refreshDisplayedItems()
                // Tell AppKitTreeView that this directory's children changed.
                // rootItemsMatch deliberately ignores children for diff cost
                // reasons, so without bumping the revision the NSOutlineView
                // never re-queries its data source and the new children stay
                // invisible until the user manually collapses + re-expands.
                recordTreeMutation(changedDirectoryIDs: [item.id])
            } catch { userFacingError = "Failed to load directory: \(error.localizedDescription)" }
        }
    }

    private func recordTreeMutation(changedDirectoryIDs: Set<String>) {
        self.changedDirectoryIDs = changedDirectoryIDs
        self.treeMutationRevision += 1
    }

    private func updateItem(_ item: FileItem, parentID: String, children: [FileItem]) -> FileItem {
        if item.id == parentID { var updated = item; updated.children = children; return updated }
        guard let existing = item.children else { return item }
        var updated = item
        updated.children = existing.map { updateItem($0, parentID: parentID, children: children) }
        return updated
    }

    private func bindSearch() {
        // Observe only the search query. `displayedItems` is updated
        // synchronously when `rootItems` changes (see refresh / loadChildren),
        // because Combine delivery via RunLoop.main introduces a brief async
        // gap where rootItems is non-empty but displayedItems still is, and
        // SwiftUI's conditional rendering can snapshot the empty state into a
        // freshly-created AppKitTreeView whose NSOutlineView never repaints.
        $searchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshDisplayedItems() }
            .store(in: &subscriptions)
    }

    private func refreshDisplayedItems() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newDisplayed: [FileItem]
        if trimmed.isEmpty {
            newDisplayed = rootItems
        } else {
            newDisplayed = rootItems.compactMap {
                FolderExplorerViewModel.filterForSearch(item: $0, query: trimmed)
            }
        }
        displayedItems = newDisplayed
        AppDiagnostics.record(
            category: .remote,
            level: .info,
            event: "remote_explorer_displayed_items_updated",
            metadata: [
                "root_items_count": String(rootItems.count),
                "displayed_items_count": String(newDisplayed.count),
                "query_present": trimmed.isEmpty ? "false" : "true"
            ]
        )
    }

    private static func shouldSuppressConnectionReadinessError(_ error: Error) -> Bool {
        false // System ssh connections are ready immediately once ControlMaster is up
    }
}
