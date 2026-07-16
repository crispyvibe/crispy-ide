import Foundation

extension FolderExplorerViewModel {
    func setRootFolder(_ url: URL) {
        rootURL = url.standardizedFileURL
        treeSessionID = UUID()
        selectedItemID = nil
        selectedFileURL = nil
        selectedFolderURL = rootURL
        openRequest = nil
        renamingItemID = nil
        renameText = ""
        expandedDirectoryIDs = []
        loadedDirectoryIDs = []
        loadingDirectoryIDs = []
        gitStatusItems = []
        gitBranchOptions = []
        gitState = .idle
        gitCurrentBranchName = nil
        gitMessage = nil
        gitCommitMessageDraft = ""
        gitOperationMessage = nil
        gitIsOperating = false
        gitHistoryEntries = []
        gitActiveHistoryScope = nil
        gitHistoryIsLoading = false
        pendingExternalRefreshWorkItem?.cancel()
        pendingExternalRefreshWorkItem = nil
        pendingExternalRefreshPaths.removeAll()
        pendingExternalRefreshEvents.removeAll()
        deferredTreeRefreshPaths.removeAll()
        deferredTreeRefreshEvents.removeAll()
        treeMutationRevision = 0
        changedDirectoryIDs = []
        activeSidebarTab = defaultSidebarTab
        refreshTree(trigger: .manual)
    }

    func restartWorker() {
        Task { [weak self] in
            guard let self else { return }
            await self.worker.restart()
            self.workerStatus = .ready
            self.loadedDirectoryIDs.removeAll()
            self.loadingDirectoryIDs.removeAll()
            self.gitStatusItems = []
            self.gitBranchOptions = []
            self.gitState = .idle
            self.gitCurrentBranchName = nil
            self.gitMessage = nil
            self.gitCommitMessageDraft = ""
            self.gitOperationMessage = nil
            self.gitIsOperating = false
            self.gitHistoryEntries = []
            self.gitActiveHistoryScope = nil
            self.gitHistoryIsLoading = false
            self.pendingExternalRefreshWorkItem?.cancel()
            self.pendingExternalRefreshWorkItem = nil
            self.pendingExternalRefreshPaths.removeAll()
            self.pendingExternalRefreshEvents.removeAll()
            self.deferredTreeRefreshPaths.removeAll()
            self.deferredTreeRefreshEvents.removeAll()
            self.treeSessionID = UUID()
            self.treeMutationRevision = 0
            self.changedDirectoryIDs = []
            self.refreshTree(trigger: .manual)
        }
    }

    func refreshTree(trigger: TreeRefreshTrigger = .manual) {
        guard let rootURL else {
            replaceRootItems([])
            gitStatusItems = []
            gitBranchOptions = []
            gitState = .idle
            gitCurrentBranchName = nil
            gitMessage = nil
            gitOperationMessage = nil
            gitHistoryEntries = []
            gitActiveHistoryScope = nil
            gitHistoryIsLoading = false
            return
        }

        if trigger == .manual {
            workerStatus = .busy("Loading folders")
        }

        Task { [weak self] in
            guard let self else { return }
            let refreshed = await self.refreshDirectoryContents(
                at: rootURL,
                showLoadingState: false
            )
            if refreshed {
                self.refreshGitStateIfNeeded(afterTreeRefresh: trigger)
            }
        }
    }

    func refreshGitStatus() {
        guard let rootURL else {
            gitStatusItems = []
            gitBranchOptions = []
            gitState = .idle
            gitCurrentBranchName = nil
            gitMessage = nil
            return
        }

        let requestID = UUID()
        gitRefreshRequestID = requestID
        gitState = .loading
        gitMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let payloadText = try await self.worker.execute(
                    .gitRepositorySnapshot,
                    arguments: ["rootPath": rootURL.path],
                    timeout: 12
                )

                guard self.gitRefreshRequestID == requestID else { return }
                let payload = try self.decodeGitRepositorySnapshotPayload(from: payloadText)

                if !payload.gitAvailable {
                    self.gitStatusItems = []
                    self.gitBranchOptions = []
                    self.gitState = .gitUnavailable
                    self.gitCurrentBranchName = nil
                    self.gitMessage = payload.message ?? "Git is not installed on this machine."
                    return
                }

                if !payload.repository {
                    self.gitStatusItems = []
                    self.gitBranchOptions = []
                    self.gitState = .notRepository
                    self.gitCurrentBranchName = nil
                    self.gitMessage = payload.message ?? "This folder is not a Git repository."
                    return
                }

                self.gitStatusItems = payload.entries.map(self.makeGitStatusItem(from:))
                self.gitBranchOptions = payload.branches.map(self.makeGitBranchOption(from:))
                self.gitCurrentBranchName = payload.currentBranch
                self.gitState = .ready
                self.gitMessage = nil
            } catch {
                guard self.gitRefreshRequestID == requestID else { return }
                self.gitStatusItems = []
                self.gitBranchOptions = []
                self.gitState = .error
                self.gitCurrentBranchName = nil
                self.gitMessage = "Unable to load Git status: \(error.localizedDescription)"
            }
        }
    }

    func refreshGitBranches() {
        guard let rootURL else {
            gitBranchOptions = []
            gitCurrentBranchName = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let payloadText = try await self.worker.execute(
                    .gitBranches,
                    arguments: ["rootPath": rootURL.path],
                    timeout: 10
                )
                let payload = try self.decodeGitBranchesPayload(from: payloadText)
                if !payload.gitAvailable || !payload.repository {
                    self.gitBranchOptions = []
                    self.gitCurrentBranchName = nil
                    return
                }

                self.gitBranchOptions = payload.branches.map(self.makeGitBranchOption(from:))
                self.gitCurrentBranchName = payload.currentBranch
            } catch {
                self.gitBranchOptions = []
                self.gitCurrentBranchName = nil
            }
        }
    }

    func scheduleExternalRefresh(
        changedPath: String? = nil,
        changedEvent: DirectoryWatcher.Event? = nil
    ) {
        guard let rootURL else { return }

        if let changedEvent {
            let normalizedPath = URL(fileURLWithPath: changedEvent.path).standardizedFileURL.path
            pendingExternalRefreshPaths.insert(normalizedPath)
            pendingExternalRefreshEvents[normalizedPath] = changedEvent
        }

        if let changedPath {
            pendingExternalRefreshPaths.insert(URL(fileURLWithPath: changedPath).standardizedFileURL.path)
        } else if changedEvent == nil {
            pendingExternalRefreshPaths.insert(rootURL.standardizedFileURL.path)
        }

        pendingExternalRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.consumeExternalRefreshQueue()
        }
        pendingExternalRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: workItem)
    }

    /// Ingests a filesystem event forwarded by the owning `ProjectSession`'s
    /// `DirectoryWatcher`. The session owns the watcher lifecycle (started in
    /// `activate()` at hydration); the explorer is purely a consumer that
    /// refreshes its tree and republishes the change.
    func ingestFileSystemEvent(_ event: DirectoryWatcher.Event) {
        scheduleExternalRefresh(changedEvent: event)
    }

    func consumeExternalRefreshQueue() {
        guard let rootURL else { return }
        let rootPath = rootURL.standardizedFileURL.path
        let newlyChangedPaths = pendingExternalRefreshPaths
        let newlyChangedEvents = pendingExternalRefreshEvents
        pendingExternalRefreshPaths.removeAll()
        pendingExternalRefreshEvents.removeAll()
        pendingExternalRefreshWorkItem = nil

        if !newlyChangedPaths.isEmpty {
            // The owning ProjectSession posts `.fileSystemContentsDidChange`
            // (fast, for editor/docked reload). Here we only republish to
            // source control, which observes `observedFileSystemChanges`.
            observedFileSystemChanges.send(newlyChangedPaths)
        }

        guard activeSidebarTab == .files else {
            deferredTreeRefreshPaths.formUnion(newlyChangedPaths)
            deferredTreeRefreshEvents.merge(newlyChangedEvents) { _, latest in latest }
            return
        }

        let changedPaths = deferredTreeRefreshPaths.union(newlyChangedPaths)
        var changedEvents = deferredTreeRefreshEvents
        changedEvents.merge(newlyChangedEvents) { _, latest in latest }
        deferredTreeRefreshPaths.removeAll()
        deferredTreeRefreshEvents.removeAll()

        // The session starts watching at hydration, so events can arrive before
        // the explorer tree has ever been loaded (e.g. terminal-only board mode).
        // Keep these paths dirty until the initial load completes so an older
        // in-flight root snapshot cannot make the new tree stale.
        guard !loadedDirectoryIDs.isEmpty else {
            deferredTreeRefreshPaths.formUnion(changedPaths)
            deferredTreeRefreshEvents.merge(changedEvents) { _, latest in latest }
            return
        }

        guard !changedPaths.isEmpty else { return }

        let directoryRefreshTargets = watcherRefreshTargetDirectoryPaths(
            for: changedPaths,
            changedEvents: changedEvents,
            rootPath: rootPath
        )

        guard !directoryRefreshTargets.isEmpty else {
            if changedPaths.contains(rootPath) {
                refreshTree(trigger: .watcher)
            }
            return
        }

        for directoryPath in directoryRefreshTargets {
            if directoryPath == rootPath {
                refreshRootDirectoryFromWatcher()
                continue
            }

            guard let item = findItem(withID: directoryPath), item.isDirectory else { continue }
            refreshChildren(of: item, showLoadingState: false)
        }
    }

    private func refreshGitStateIfNeeded(afterTreeRefresh _: TreeRefreshTrigger) {
        guard activeSidebarTab == .git else {
            return
        }
        refreshGitStatus()
    }

    func resumeDeferredTreeRefreshIfNeeded() {
        guard activeSidebarTab == .files else { return }
        guard !pendingExternalRefreshPaths.isEmpty || !deferredTreeRefreshPaths.isEmpty else { return }

        pendingExternalRefreshWorkItem?.cancel()
        pendingExternalRefreshWorkItem = nil
        Task { @MainActor [weak self] in
            self?.consumeExternalRefreshQueue()
        }
    }
}
