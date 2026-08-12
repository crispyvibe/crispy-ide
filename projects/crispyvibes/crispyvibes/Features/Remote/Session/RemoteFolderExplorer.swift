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
    let supportsFileTransfers = false
    let renameEvents = PassthroughSubject<ExplorerRenameEvent, Never>()
    let observedFileSystemChanges = PassthroughSubject<Set<String>, Never>()

    private struct DirectoryRefreshOperation {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private let fileSystem: any FileSystemProviding
    private let watcher: any DirectoryWatching
    private let remotePath: String
    private let enhancedMode: Bool
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var refreshRequestID = UUID()
    private var treeGeneration = UUID()
    private var directoryRefreshOperations: [String: DirectoryRefreshOperation] = [:]
    private var queuedDirectoryRefreshPaths: Set<String> = []

    init(
        remotePath: String,
        fileSystem: any FileSystemProviding,
        watcher: any DirectoryWatching,
        enhancedMode: Bool = false
    ) {
        self.remotePath = remotePath
        self.fileSystem = fileSystem
        self.watcher = watcher
        self.enhancedMode = enhancedMode
        bindSearch()

        watcher.onPathsChanged = { [weak self] changedPaths in
            guard let self else { return }
            self.observedFileSystemChanges.send(changedPaths)
            if self.enhancedMode {
                self.refreshChangedDirectories(changedPaths)
            } else {
                self.refreshLegacyRoot()
            }
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
        treeGeneration = UUID()
        cancelDirectoryRefreshes()
        rootURL = url.standardizedFileURL
        if enhancedMode {
            synchronizeWatchedPaths()
            refreshEnhancedTree()
        } else {
            watcher.watch(paths: [url.path])
            refreshLegacyRoot()
        }
    }

    func refreshTree(trigger: FolderExplorerViewModel.TreeRefreshTrigger) {
        if enhancedMode {
            refreshEnhancedTree()
        } else {
            refreshLegacyRoot()
        }
    }

    func toggleExpansion(for item: FileItem) {
        guard item.isDirectory, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if expandedDirectoryIDs.contains(item.id) {
            expandedDirectoryIDs.remove(item.id)
            expandedDirectoryIDs = Set(
                expandedDirectoryIDs.filter { !Self.isDescendantPath($0, of: item.id) }
            )
            if enhancedMode {
                synchronizeWatchedPaths()
            }
        } else {
            expandedDirectoryIDs.insert(item.id)
            if enhancedMode {
                synchronizeWatchedPaths()
                if findItem(withID: item.id)?.children == nil {
                    loadChildrenEnhanced(for: item)
                }
            } else {
                loadChildrenLegacy(for: item)
            }
        }
    }

    func isDirectoryLoading(_ directoryID: String) -> Bool {
        loadingDirectoryIDs.contains(directoryID)
    }

    // MARK: - File Operations

    func createNewFile(in item: FileItem?) {
        createItem(proposedName: "untitled", isFolder: false, in: item)
    }

    func createNewFolder(in item: FileItem?) {
        createItem(proposedName: "New Folder", isFolder: true, in: item)
    }

    func createNewFileAtSelection() {
        if enhancedMode {
            createItem(
                proposedName: "untitled",
                isFolder: false,
                inDirectory: creationDirectoryAtSelection()
            )
        } else {
            createNewFile(in: nil)
        }
    }

    func createNewFolderAtSelection() {
        if enhancedMode {
            createItem(
                proposedName: "New Folder",
                isFolder: true,
                inDirectory: creationDirectoryAtSelection()
            )
        } else {
            createNewFolder(in: nil)
        }
    }

    func deleteItem(_ item: FileItem) {
        if !enhancedMode {
            let mutationGeneration = treeGeneration
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.fileSystem.removeItem(at: item.url.path)
                    guard self.treeGeneration == mutationGeneration else { return }
                    self.refreshLegacyRoot()
                } catch {
                    guard self.treeGeneration == mutationGeneration else { return }
                    self.userFacingError = error.localizedDescription
                }
            }
            return
        }

        let mutationGeneration = treeGeneration
        workerStatus = .busy("Deleting")
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fileSystem.removeItem(at: item.url.path)
                guard self.treeGeneration == mutationGeneration else { return }
                self.clearSelections(under: item.url.path)
                self.expandedDirectoryIDs = Set(self.expandedDirectoryIDs.filter {
                    $0 != item.id && !Self.isDescendantPath($0, of: item.id)
                })
                _ = await self.refreshDirectoryContents(at: item.url.deletingLastPathComponent().path)
                guard self.treeGeneration == mutationGeneration else { return }
                self.synchronizeWatchedPaths()
                self.workerStatus = .ready
            } catch {
                guard self.treeGeneration == mutationGeneration else { return }
                self.userFacingError = "Delete failed: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Remote explorer unavailable")
            }
        }
    }

    func startRenaming(item: FileItem) {
        renamingItemID = item.id
        renameText = item.url.lastPathComponent
        if enhancedMode {
            let selectionIsRenamedItemOrDescendant = selectedItemID.map {
                $0 == item.id || Self.isDescendantPath($0, of: item.id)
            } ?? false
            if !selectionIsRenamedItemOrDescendant {
                selectedItemID = item.id
            }
        }
    }

    func startRenamingSelectedItem() {
        guard let id = selectedItemID else { return }
        if enhancedMode {
            guard let item = findItem(withID: id) else { return }
            startRenaming(item: item)
        } else {
            renamingItemID = id
            renameText = URL(fileURLWithPath: id).lastPathComponent
        }
    }

    func commitRename() {
        guard let renamingID = renamingItemID else { return }
        let proposedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !enhancedMode {
            cancelRename()
            guard !proposedName.isEmpty else { return }
            let newPath = (renamingID as NSString).deletingLastPathComponent + "/" + proposedName
            let mutationGeneration = treeGeneration
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.fileSystem.moveItem(from: renamingID, to: newPath)
                    guard self.treeGeneration == mutationGeneration else { return }
                    self.renameEvents.send(
                        ExplorerRenameEvent(
                            oldURL: URL(fileURLWithPath: renamingID),
                            newURL: URL(fileURLWithPath: newPath)
                        )
                    )
                    self.refreshLegacyRoot()
                } catch {
                    guard self.treeGeneration == mutationGeneration else { return }
                    self.userFacingError = error.localizedDescription
                }
            }
            return
        }

        guard Self.isValidPathComponent(proposedName) else {
            userFacingError = "Rename failed: enter a name without path separators."
            return
        }

        let oldURL = URL(fileURLWithPath: renamingID).standardizedFileURL
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(proposedName).standardizedFileURL
        cancelRename()
        guard oldURL.path != newURL.path else { return }
        let renamedItem = findItem(withID: oldURL.path)
        let renamedItemWasDirectory = renamedItem?.isDirectory == true
        let mutationGeneration = treeGeneration
        workerStatus = .busy("Renaming")

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fileSystem.moveItem(from: oldURL.path, to: newURL.path)
                guard self.treeGeneration == mutationGeneration else { return }
                if renamedItemWasDirectory {
                    self.rootItems = self.rootItems.map {
                        Self.remapItemTree($0, from: oldURL.path, to: newURL.path)
                    }
                    self.refreshDisplayedItems()
                }
                self.remapSelections(from: oldURL.path, to: newURL.path)
                if renamedItemWasDirectory {
                    self.remapExpandedDirectories(from: oldURL.path, to: newURL.path)
                }
                self.renameEvents.send(ExplorerRenameEvent(oldURL: oldURL, newURL: newURL))
                _ = await self.refreshDirectoryContents(at: oldURL.deletingLastPathComponent().path)
                guard self.treeGeneration == mutationGeneration else { return }

                if renamedItemWasDirectory {
                    let renamedExpandedPaths = self.expandedDirectoryIDs
                        .filter { $0 == newURL.path || Self.isDescendantPath($0, of: newURL.path) }
                        .sorted { Self.pathDepth($0) < Self.pathDepth($1) }
                    for path in renamedExpandedPaths {
                        _ = await self.refreshDirectoryContents(at: path)
                        guard self.treeGeneration == mutationGeneration else { return }
                    }
                }
                self.synchronizeWatchedPaths()
                self.workerStatus = .ready
            } catch {
                guard self.treeGeneration == mutationGeneration else { return }
                self.userFacingError = "Rename failed: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Remote explorer unavailable")
            }
        }
    }

    func cancelRename() {
        renamingItemID = nil
        renameText = ""
    }

    func clearError() {
        userFacingError = nil
    }

    // MARK: - Selection

    func select(_ item: FileItem) {
        selectedItemID = item.id
        if item.isDirectory {
            selectedFolderURL = item.url
            if enhancedMode {
                selectedFileURL = nil
            }
        } else {
            selectedFileURL = item.url
            if enhancedMode {
                selectedFolderURL = item.url.deletingLastPathComponent()
                openRequest = ExplorerOpenRequest(fileURL: item.url, action: .preview)
            }
        }
    }

    func openInTab(_ item: FileItem) {
        guard !item.isDirectory else {
            if enhancedMode { select(item) }
            return
        }
        updateFileSelection(for: item)
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openTab)
    }

    func openInWindow(_ item: FileItem) {
        guard !item.isDirectory else { return }
        updateFileSelection(for: item)
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openWindow)
    }

    func openInSplitHorizontal(_ item: FileItem) {
        guard !item.isDirectory else { return }
        updateFileSelection(for: item)
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openInSplitHorizontal)
    }

    func openInSplitVertical(_ item: FileItem) {
        guard !item.isDirectory else { return }
        updateFileSelection(for: item)
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openInSplitVertical)
    }

    func selectGitStatusItem(_ item: GitStatusItem) {
        selectedItemID = item.url.path
        selectedFileURL = item.url
    }

    // MARK: - Git (handled by RemoteGitExplorer)

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

    func transferItems(using plans: [ExplorerItemTransferPlan]) {
        guard enhancedMode, !plans.isEmpty else { return }
        userFacingError = "Remote drag and drop is unavailable until project and host identity can be verified."
    }

    func stopWatching() {
        treeGeneration = UUID()
        watcher.stop()
        refreshRequestID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        cancelDirectoryRefreshes()
        loadingDirectoryIDs.removeAll()
        workerStatus = .ready
    }

    // MARK: - Enhanced Refresh

    private func refreshEnhancedTree() {
        let rootPath = normalizedRootPath
        let expandedPaths = expandedDirectoryIDs
            .filter { Self.isPath($0, within: rootPath) }
            .sorted { Self.pathDepth($0) < Self.pathDepth($1) }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshDirectoryContents(at: rootPath)
            guard !Task.isCancelled else { return }
            for path in expandedPaths where self.findItem(withID: path)?.isDirectory == true {
                _ = await self.refreshDirectoryContents(at: path)
                guard !Task.isCancelled else { return }
            }
            self.synchronizeWatchedPaths()
            self.refreshTask = nil
        }
    }

    private func refreshChangedDirectories(_ changedPaths: Set<String>) {
        Task { [weak self] in
            guard let self else { return }
            for path in changedPaths.map(Self.normalizePath).sorted() {
                guard Self.isPath(path, within: self.normalizedRootPath) else { continue }
                if path == self.normalizedRootPath || self.findItem(withID: path)?.isDirectory == true {
                    _ = await self.refreshDirectoryContents(at: path)
                } else {
                    _ = await self.refreshDirectoryContents(
                        at: URL(fileURLWithPath: path).deletingLastPathComponent().path
                    )
                }
            }
        }
    }

    private func loadChildrenEnhanced(for item: FileItem) {
        Task { [weak self] in
            _ = await self?.refreshDirectoryContents(at: item.url.path)
        }
    }

    private func refreshDirectoryContents(at rawPath: String) async -> Bool {
        let path = Self.normalizePath(rawPath)
        queuedDirectoryRefreshPaths.insert(path)

        if let operation = directoryRefreshOperations[path] {
            let result = await operation.task.value
            if queuedDirectoryRefreshPaths.remove(path) != nil {
                directoryRefreshOperations.removeValue(forKey: path)
                return await refreshDirectoryContents(at: path)
            }
            return result
        }

        let operationID = UUID()
        let operationGeneration = treeGeneration
        let task = Task { [weak self] in
            guard let self else { return false }
            var result = false
            repeat {
                self.queuedDirectoryRefreshPaths.remove(path)
                result = await self.performDirectoryRefresh(
                    at: path,
                    generation: operationGeneration
                )
            } while self.queuedDirectoryRefreshPaths.contains(path)
                && self.treeGeneration == operationGeneration
                && !Task.isCancelled
            return result
        }
        directoryRefreshOperations[path] = DirectoryRefreshOperation(id: operationID, task: task)
        let result = await task.value
        if directoryRefreshOperations[path]?.id == operationID {
            directoryRefreshOperations.removeValue(forKey: path)
        }
        if queuedDirectoryRefreshPaths.remove(path) != nil {
            return await refreshDirectoryContents(at: path)
        }
        return result
    }

    private func performDirectoryRefresh(at path: String, generation: UUID) async -> Bool {
        guard generation == treeGeneration else { return false }
        let isRoot = path == normalizedRootPath
        if isRoot {
            workerStatus = .busy("Loading")
        } else {
            loadingDirectoryIDs.insert(path)
        }
        defer {
            if isRoot {
                workerStatus = .ready
            } else {
                loadingDirectoryIDs.remove(path)
            }
        }

        do {
            let descriptors = try await fileSystem.contentsOfDirectory(at: path)
            guard generation == treeGeneration, !Task.isCancelled else { return false }

            if isRoot {
                rootItems = makeItems(from: descriptors, preserving: rootItems)
            } else {
                guard let directory = findItem(withID: path), directory.isDirectory else { return false }
                let children = makeItems(from: descriptors, preserving: directory.children ?? [])
                rootItems = rootItems.map { updateItem($0, parentID: path, children: children) }
                recordTreeMutation(changedDirectoryIDs: [path])
            }
            reconcileTreeState(afterRefreshing: path)
            refreshDisplayedItems()
            userFacingError = nil
            return true
        } catch {
            guard generation == treeGeneration, !Task.isCancelled else { return false }
            if !Self.shouldSuppressConnectionReadinessError(error) {
                let displayName = isRoot ? path : URL(fileURLWithPath: path).lastPathComponent
                userFacingError = "Failed to load \(displayName): \(error.localizedDescription)"
            }
            return false
        }
    }

    private func makeItems(
        from descriptors: [FileItemDescriptor],
        preserving existingItems: [FileItem]
    ) -> [FileItem] {
        let existingByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        return descriptors.map { descriptor in
            let url = URL(fileURLWithPath: descriptor.path).standardizedFileURL
            return FileItem(
                url: url,
                isDirectory: descriptor.isDirectory,
                isHidden: descriptor.isHidden,
                children: existingByID[url.path]?.children
            )
        }.sorted(by: Self.sortItems)
    }

    private func synchronizeWatchedPaths() {
        guard enhancedMode, rootURL != nil else { return }
        let rootPath = normalizedRootPath
        var paths = expandedDirectoryIDs
            .filter { Self.isPath($0, within: rootPath) }
            .sorted {
                let lhsDepth = Self.pathDepth($0)
                let rhsDepth = Self.pathDepth($1)
                return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
            }
        paths.insert(rootPath, at: 0)
        watcher.watch(paths: Array(paths.prefix(256)))
    }

    private func cancelDirectoryRefreshes() {
        for operation in directoryRefreshOperations.values {
            operation.task.cancel()
        }
        directoryRefreshOperations.removeAll()
        queuedDirectoryRefreshPaths.removeAll()
    }

    // MARK: - Legacy Refresh

    private func refreshLegacyRoot() {
        let path = rootURL?.path ?? remotePath
        let requestID = UUID()
        refreshRequestID = requestID
        workerStatus = .busy("Loading")
        refreshTask?.cancel()
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
                guard !Task.isCancelled, self.refreshRequestID == requestID else { return }
                let cachedChildrenByID = Dictionary(
                    uniqueKeysWithValues: self.rootItems.compactMap { item -> (String, [FileItem])? in
                        guard let children = item.children else { return nil }
                        return (item.id, children)
                    }
                )
                self.rootItems = items.map { descriptor in
                    let url = URL(fileURLWithPath: descriptor.path)
                    return FileItem(
                        url: url,
                        isDirectory: descriptor.isDirectory,
                        isHidden: descriptor.isHidden,
                        children: cachedChildrenByID[url.path]
                    )
                }.sorted {
                    $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent)
                        == .orderedAscending
                }
                self.refreshDisplayedItems()
                self.workerStatus = .ready
            } catch {
                guard !Task.isCancelled, self.refreshRequestID == requestID else { return }
                if !Self.shouldSuppressConnectionReadinessError(error) {
                    self.userFacingError = error.localizedDescription
                }
                self.workerStatus = .ready
            }
        }
    }

    private func loadChildrenLegacy(for item: FileItem) {
        loadingDirectoryIDs.insert(item.id)
        Task { [weak self] in
            guard let self else { return }
            defer { self.loadingDirectoryIDs.remove(item.id) }
            do {
                let descriptors = try await self.fileSystem.contentsOfDirectory(at: item.url.path)
                let children = descriptors.map {
                    FileItem(
                        url: URL(fileURLWithPath: $0.path),
                        isDirectory: $0.isDirectory,
                        isHidden: $0.isHidden
                    )
                }.sorted {
                    $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent)
                        == .orderedAscending
                }
                self.rootItems = self.rootItems.map {
                    self.updateItem($0, parentID: item.id, children: children)
                }
                self.refreshDisplayedItems()
                self.recordTreeMutation(changedDirectoryIDs: [item.id])
            } catch {
                self.userFacingError = "Failed to load directory: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Mutation Helpers

    private func createItem(proposedName: String, isFolder: Bool, in item: FileItem?) {
        let directory = targetDirectory(for: item)
        createItem(proposedName: proposedName, isFolder: isFolder, inDirectory: directory)
    }

    private func createItem(proposedName: String, isFolder: Bool, inDirectory directory: URL?) {
        guard let directory else {
            userFacingError = "Select a folder first."
            return
        }

        if !enhancedMode {
            let path = directory.appendingPathComponent(proposedName).path
            let mutationGeneration = treeGeneration
            Task { [weak self] in
                guard let self else { return }
                do {
                    if isFolder {
                        try await self.fileSystem.createDirectory(at: path)
                    } else {
                        try await self.fileSystem.createFile(at: path, contents: nil)
                    }
                    guard self.treeGeneration == mutationGeneration else { return }
                    self.refreshLegacyRoot()
                } catch {
                    guard self.treeGeneration == mutationGeneration else { return }
                    self.userFacingError = error.localizedDescription
                }
            }
            return
        }

        let mutationGeneration = treeGeneration
        workerStatus = .busy("Creating")
        Task { [weak self] in
            guard let self else { return }
            do {
                let descriptors = try await self.fileSystem.contentsOfDirectory(at: directory.path)
                guard self.treeGeneration == mutationGeneration else { return }
                let name = Self.uniqueName(
                    proposedName,
                    existingNames: Set(descriptors.map(\.name))
                )
                let newURL = directory.appendingPathComponent(name).standardizedFileURL
                if isFolder {
                    try await self.fileSystem.createDirectory(at: newURL.path)
                } else {
                    try await self.fileSystem.createFile(at: newURL.path, contents: nil)
                }
                guard self.treeGeneration == mutationGeneration else { return }

                self.expandedDirectoryIDs.insert(directory.standardizedFileURL.path)
                let refreshed = await self.refreshDirectoryContents(at: directory.path)
                guard self.treeGeneration == mutationGeneration else { return }
                guard refreshed, self.findItem(withID: newURL.path) != nil else {
                    self.userFacingError = "Created \(name), but could not refresh its folder."
                    self.workerStatus = .ready
                    return
                }

                self.selectedItemID = newURL.path
                self.renamingItemID = newURL.path
                self.renameText = name
                if isFolder {
                    self.selectedFolderURL = newURL
                    self.selectedFileURL = nil
                } else {
                    self.selectedFileURL = newURL
                    self.selectedFolderURL = directory.standardizedFileURL
                    self.openRequest = ExplorerOpenRequest(fileURL: newURL, action: .preview)
                }
                self.synchronizeWatchedPaths()
                self.workerStatus = .ready
            } catch {
                guard self.treeGeneration == mutationGeneration else { return }
                self.userFacingError = "Creation failed: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Remote explorer unavailable")
            }
        }
    }

    private func targetDirectory(for item: FileItem?) -> URL? {
        guard let rootURL else { return nil }
        guard let item else { return rootURL }
        return item.isDirectory ? item.url : item.url.deletingLastPathComponent()
    }

    private func creationDirectoryAtSelection() -> URL? {
        guard let rootURL = rootURL?.standardizedFileURL else { return nil }
        var candidate = (selectedFolderURL ?? rootURL).standardizedFileURL
        guard Self.isPath(candidate.path, within: rootURL.path) else { return rootURL }

        while candidate.path != rootURL.path {
            if findItem(withID: candidate.path)?.isDirectory == true {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        return rootURL
    }

    private func updateFileSelection(for item: FileItem) {
        selectedItemID = item.id
        selectedFileURL = item.url
        if enhancedMode {
            selectedFolderURL = item.url.deletingLastPathComponent()
        }
    }

    private func clearSelections(under path: String) {
        if let selectedItemID,
           selectedItemID == path || Self.isDescendantPath(selectedItemID, of: path) {
            self.selectedItemID = nil
        }
        if let selectedFileURL,
           selectedFileURL.path == path || Self.isDescendantPath(selectedFileURL.path, of: path) {
            self.selectedFileURL = nil
        }
        if let selectedFolderURL,
           selectedFolderURL.path == path || Self.isDescendantPath(selectedFolderURL.path, of: path) {
            self.selectedFolderURL = rootURL
        }
        if let renamingItemID,
           renamingItemID == path || Self.isDescendantPath(renamingItemID, of: path) {
            cancelRename()
        }
    }

    private func remapSelections(from oldPath: String, to newPath: String) {
        selectedItemID = selectedItemID.map { Self.remapPath($0, from: oldPath, to: newPath) }
        selectedFileURL = selectedFileURL.map {
            URL(fileURLWithPath: Self.remapPath($0.path, from: oldPath, to: newPath))
        }
        selectedFolderURL = selectedFolderURL.map {
            URL(fileURLWithPath: Self.remapPath($0.path, from: oldPath, to: newPath))
        }
    }

    private func remapExpandedDirectories(from oldPath: String, to newPath: String) {
        expandedDirectoryIDs = Set(
            expandedDirectoryIDs.map { Self.remapPath($0, from: oldPath, to: newPath) }
        )
    }

    private func reconcileTreeState(afterRefreshing directoryPath: String) {
        if let selectedItemID,
           Self.isPath(selectedItemID, within: directoryPath),
           findItem(withID: selectedItemID) == nil {
            self.selectedItemID = nil
        }
        if let selectedFileURL,
           Self.isPath(selectedFileURL.path, within: directoryPath),
           findItem(withID: selectedFileURL.path) == nil {
            self.selectedFileURL = nil
        }
        if let selectedFolderURL,
           selectedFolderURL.path != normalizedRootPath,
           Self.isPath(selectedFolderURL.path, within: directoryPath),
           findItem(withID: selectedFolderURL.path)?.isDirectory != true {
            self.selectedFolderURL = URL(fileURLWithPath: directoryPath)
        }
        if let renamingItemID,
           Self.isPath(renamingItemID, within: directoryPath),
           findItem(withID: renamingItemID) == nil {
            cancelRename()
        }
        expandedDirectoryIDs = Set(expandedDirectoryIDs.filter {
            $0 == normalizedRootPath || findItem(withID: $0)?.isDirectory == true
        })
    }

    // MARK: - Tree Helpers

    private var normalizedRootPath: String {
        Self.normalizePath(rootURL?.path ?? remotePath)
    }

    private func findItem(withID id: String) -> FileItem? {
        func find(in items: [FileItem]) -> FileItem? {
            for item in items {
                if item.id == id { return item }
                if let children = item.children, let found = find(in: children) {
                    return found
                }
            }
            return nil
        }
        return find(in: rootItems)
    }

    private func updateItem(_ item: FileItem, parentID: String, children: [FileItem]) -> FileItem {
        if item.id == parentID {
            var updated = item
            updated.children = children
            return updated
        }
        guard let existing = item.children else { return item }
        var updated = item
        updated.children = existing.map { updateItem($0, parentID: parentID, children: children) }
        return updated
    }

    private func recordTreeMutation(changedDirectoryIDs: Set<String>) {
        self.changedDirectoryIDs = changedDirectoryIDs
        treeMutationRevision += 1
    }

    private func bindSearch() {
        $searchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshDisplayedItems() }
            .store(in: &subscriptions)
    }

    private func refreshDisplayedItems() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            displayedItems = rootItems
        } else {
            displayedItems = rootItems.compactMap {
                FolderExplorerViewModel.filterForSearch(item: $0, query: trimmed)
            }
        }
    }

    private static func remapItemTree(
        _ item: FileItem,
        from oldPath: String,
        to newPath: String
    ) -> FileItem {
        let remappedPath = remapPath(item.id, from: oldPath, to: newPath)
        return FileItem(
            url: URL(fileURLWithPath: remappedPath),
            isDirectory: item.isDirectory,
            isHidden: item.isHidden,
            isGitIgnored: item.isGitIgnored,
            children: item.children?.map {
                remapItemTree($0, from: oldPath, to: newPath)
            }
        )
    }

    private static func sortItems(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }
        return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
            == .orderedAscending
    }

    private static func uniqueName(_ proposedName: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(proposedName) else { return proposedName }
        let baseName = (proposedName as NSString).deletingPathExtension
        let pathExtension = (proposedName as NSString).pathExtension
        var counter = 1
        while true {
            let candidate = pathExtension.isEmpty
                ? "\(baseName) \(counter)"
                : "\(baseName) \(counter).\(pathExtension)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    private static func isValidPathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func pathDepth(_ path: String) -> Int {
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents.count
    }

    private static func isPath(_ candidate: String, within ancestor: String) -> Bool {
        let candidate = normalizePath(candidate)
        let ancestor = normalizePath(ancestor)
        return candidate == ancestor || isDescendantPath(candidate, of: ancestor)
    }

    private static func isDescendantPath(_ candidate: String, of ancestor: String) -> Bool {
        let ancestor = normalizePath(ancestor)
        let candidate = normalizePath(candidate)
        let prefix = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return candidate.hasPrefix(prefix)
    }

    private static func remapPath(_ path: String, from oldPath: String, to newPath: String) -> String {
        if path == oldPath { return newPath }
        guard isDescendantPath(path, of: oldPath) else { return path }
        return newPath + String(path.dropFirst(oldPath.count))
    }

    private static func shouldSuppressConnectionReadinessError(_ error: Error) -> Bool {
        false
    }
}
