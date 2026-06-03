import Foundation

extension FolderExplorerViewModel {
    func setRootFolder(_ url: URL) {
        rootURL = url.standardizedFileURL
        activeSidebarTab = defaultSidebarTab
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
        isTreeRefreshInFlight = false
        queuedTreeRefreshTrigger = nil
        treeMutationRevision = 0
        changedDirectoryIDs = []
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
            self.isTreeRefreshInFlight = false
            self.queuedTreeRefreshTrigger = nil
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
            isTreeRefreshInFlight = false
            queuedTreeRefreshTrigger = nil
            return
        }

        if isTreeRefreshInFlight {
            if queuedTreeRefreshTrigger == nil || trigger == .manual {
                queuedTreeRefreshTrigger = trigger
            }
            return
        }

        isTreeRefreshInFlight = true
        let requestID = UUID()
        refreshRequestID = requestID
        workerStatus = .busy("Loading folders")

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isTreeRefreshInFlight = false
                if let queuedTrigger = self.queuedTreeRefreshTrigger {
                    self.queuedTreeRefreshTrigger = nil
                    self.refreshTree(trigger: queuedTrigger)
                }
            }

            do {
                let payload = try await self.worker.execute(
                    .listTree,
                    arguments: ["rootPath": rootURL.path],
                    timeout: self.treeLoadTimeout
                )
                guard self.refreshRequestID == requestID else { return }

                let decodedItems = try self.decodeFileItems(from: payload)
                let mergedItems = self.mergeRootItemsPreservingLoadedChildren(with: decodedItems)
                self.replaceRootItems(mergedItems)
                self.loadedDirectoryIDs = [rootURL.path]
                self.loadingDirectoryIDs.removeAll()
                self.workerStatus = .ready
                self.refreshGitStateIfNeeded(afterTreeRefresh: trigger)
            } catch {
                guard self.refreshRequestID == requestID else { return }
                self.userFacingError = "Failed to read \(rootURL.path): \(error.localizedDescription)"
                self.workerStatus = .unavailable("Explorer worker unavailable")
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
        let changedPaths = pendingExternalRefreshPaths
        let changedEvents = pendingExternalRefreshEvents
        pendingExternalRefreshPaths.removeAll()
        pendingExternalRefreshEvents.removeAll()

        if !changedPaths.isEmpty {
            // The owning ProjectSession posts `.fileSystemContentsDidChange`
            // (fast, for editor/docked reload). Here we only republish to
            // source control, which observes `observedFileSystemChanges`.
            observedFileSystemChanges.send(changedPaths)
        }

        guard activeSidebarTab == .files else {
            return
        }

        // The session starts watching at hydration, so events can arrive before
        // the explorer tree has ever been loaded (e.g. terminal-only board mode).
        // The change was already republished above; skip tree work until loaded
        // to preserve lazy tree loading.
        guard !loadedDirectoryIDs.isEmpty else { return }

        guard !changedPaths.isEmpty else {
            refreshTree(trigger: .watcher)
            return
        }

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
}
