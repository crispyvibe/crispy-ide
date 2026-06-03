import Foundation

extension FolderExplorerViewModel {
    func selectGitStatusItem(_ item: GitStatusItem) {
        let fileURL = item.url
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
        let allowsMissingFile = item.code.contains("D") || item.code.contains("R") || item.code.contains("C")
        if !fileExists && !allowsMissingFile {
            userFacingError = "File does not exist on disk: \(item.relativePath)"
            return
        }

        selectedFileURL = (fileExists && !isDirectory.boolValue) ? fileURL : nil
        selectedFolderURL = fileURL.deletingLastPathComponent()
        selectedItemID = fileURL.path
        openRequest = ExplorerOpenRequest(
            fileURL: fileURL,
            action: .compareGitStatus(code: item.code, relativePath: item.relativePath)
        )
    }

    func select(_ item: FileItem) {
        selectedItemID = item.id
        if item.isDirectory {
            selectedFolderURL = item.url
            selectedFileURL = nil
        } else {
            selectedFileURL = item.url
            selectedFolderURL = item.url.deletingLastPathComponent()
            openRequest = ExplorerOpenRequest(fileURL: item.url, action: .preview)
        }
    }

    func openInTab(_ item: FileItem) {
        guard !item.isDirectory else {
            select(item)
            return
        }
        selectedItemID = item.id
        selectedFileURL = item.url
        selectedFolderURL = item.url.deletingLastPathComponent()
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openTab)
    }

    func openInWindow(_ item: FileItem) {
        guard !item.isDirectory else { return }
        selectedItemID = item.id
        selectedFileURL = item.url
        selectedFolderURL = item.url.deletingLastPathComponent()
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openWindow)
    }

    func openInSplitHorizontal(_ item: FileItem) {
        guard !item.isDirectory else { return }
        selectedItemID = item.id
        selectedFileURL = item.url
        selectedFolderURL = item.url.deletingLastPathComponent()
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openInSplitHorizontal)
    }

    func openInSplitVertical(_ item: FileItem) {
        guard !item.isDirectory else { return }
        selectedItemID = item.id
        selectedFileURL = item.url
        selectedFolderURL = item.url.deletingLastPathComponent()
        openRequest = ExplorerOpenRequest(fileURL: item.url, action: .openInSplitVertical)
    }

    func toggleExpansion(for item: FileItem) {
        guard item.isDirectory, !isSearching else { return }

        if expandedDirectoryIDs.contains(item.id) {
            let descendantDirectoryIDs = self.expandedDescendantDirectoryIDs(ofPath: item.id)
            expandedDirectoryIDs.remove(item.id)
            expandedDirectoryIDs.subtract(descendantDirectoryIDs)
            return
        }

        expandedDirectoryIDs.insert(item.id)
        loadChildrenIfNeeded(of: item)
    }

    func isDirectoryLoading(_ directoryID: String) -> Bool {
        loadingDirectoryIDs.contains(directoryID)
    }

    func createNewFile(in item: FileItem?) {
        createItem(named: "untitled", isFolder: false, in: item)
    }

    func createNewFolder(in item: FileItem?) {
        createItem(named: "New Folder", isFolder: true, in: item)
    }

    func createNewFileAtSelection() {
        createItem(named: "untitled", isFolder: false, inDirectoryURL: selectedFolderURL ?? rootURL)
    }

    func createNewFolderAtSelection() {
        createItem(named: "New Folder", isFolder: true, inDirectoryURL: selectedFolderURL ?? rootURL)
    }

    func startRenaming(item: FileItem) {
        renamingItemID = item.id
        renameText = item.displayName
        selectedItemID = item.id
    }

    func startRenamingSelectedItem() {
        guard let selectedItemID,
              let item = findItem(withID: selectedItemID) else { return }
        startRenaming(item: item)
    }

    func cancelRename() {
        renamingItemID = nil
        renameText = ""
    }

    func commitRename() {
        guard let renamingItemID else { return }
        let oldURL = URL(fileURLWithPath: renamingItemID)
        let trimmedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)

        cancelRename()

        guard !trimmedName.isEmpty else { return }

        workerStatus = .busy("Renaming")

        Task { [weak self] in
            guard let self else { return }
            do {
                let renamedPath = try await self.worker.execute(
                    .renameItem,
                    arguments: [
                        "itemPath": oldURL.path,
                        "newName": trimmedName
                    ],
                    timeout: 10
                )

                guard let renamedPath, !renamedPath.isEmpty else {
                    throw PaneWorkerError.invalidResponse
                }

                let destinationURL = URL(fileURLWithPath: renamedPath)
                self.updateSelections(afterMoving: oldURL, to: destinationURL)
                self.renameEvents.send(
                    ExplorerRenameEvent(
                        oldURL: oldURL.standardizedFileURL,
                        newURL: destinationURL.standardizedFileURL
                    )
                )
                self.refreshTree()
            } catch {
                self.userFacingError = "Rename failed: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Explorer worker unavailable")
            }
        }
    }

    func deleteItem(_ item: FileItem) {
        workerStatus = .busy("Deleting")

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.worker.execute(
                    .deleteItem,
                    arguments: ["itemPath": item.url.path],
                    timeout: 10
                )

                if self.isSamePathOrDescendant(self.selectedFileURL, of: item.url) {
                    self.selectedFileURL = nil
                }
                if self.isSamePathOrDescendant(self.selectedFolderURL, of: item.url) {
                    self.selectedFolderURL = self.rootURL
                }
                if let selectedID = self.selectedItemID,
                   self.isSamePathOrDescendant(URL(fileURLWithPath: selectedID), of: item.url) {
                    self.selectedItemID = nil
                }

                self.refreshTree()
            } catch {
                self.userFacingError = "Delete failed: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Explorer worker unavailable")
            }
        }
    }

    func clearError() {
        userFacingError = nil
    }

    func stageGitItem(_ item: GitStatusItem) {
        runGitMutation(
            activityMessage: "Staging \(item.relativePath)",
            method: .gitStage,
            arguments: { rootPath in
                [
                    "rootPath": rootPath,
                    "relativePath": item.relativePath
                ]
            }
        )
    }

    func unstageGitItem(_ item: GitStatusItem) {
        runGitMutation(
            activityMessage: "Unstaging \(item.relativePath)",
            method: .gitUnstage,
            arguments: { rootPath in
                [
                    "rootPath": rootPath,
                    "relativePath": item.relativePath
                ]
            }
        )
    }

    func stageAllGitChanges() {
        runGitMutation(
            activityMessage: "Staging all changes",
            method: .gitStageAll,
            arguments: { rootPath in ["rootPath": rootPath] }
        )
    }

    func commitGitChanges() {
        let message = gitCommitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            userFacingError = "Commit message cannot be empty."
            return
        }

        runGitMutation(
            activityMessage: "Creating commit",
            method: .gitCommit,
            arguments: { rootPath in
                [
                    "rootPath": rootPath,
                    "message": message
                ]
            },
            onSuccess: { [weak self] in
                self?.gitCommitMessageDraft = ""
            }
        )
    }

    func pushGitChanges() {
        runGitMutation(
            activityMessage: "Pushing commits",
            method: .gitPush,
            arguments: { rootPath in ["rootPath": rootPath] }
        )
    }

    func pullGitChanges() {
        runGitMutation(
            activityMessage: "Pulling changes",
            method: .gitPull,
            arguments: { rootPath in ["rootPath": rootPath] }
        )
    }

    func fetchGitChanges() {
        runGitMutation(
            activityMessage: "Fetching remote",
            method: .gitFetch,
            arguments: { rootPath in ["rootPath": rootPath] }
        )
    }

    func checkoutGitBranch(_ branch: GitBranchOption) {
        runGitMutation(
            activityMessage: "Checking out \(branch.displayName)",
            method: .gitCheckoutBranch,
            arguments: { rootPath in
                [
                    "rootPath": rootPath,
                    "branch": branch.name,
                    "isRemote": branch.isRemote ? "1" : "0"
                ]
            }
        )
    }

    func openGitHistory(scope: GitHistoryScope) {
        guard let rootURL else {
            userFacingError = "Select a folder first."
            return
        }

        gitActiveHistoryScope = scope
        gitHistoryEntries = []
        gitHistoryIsLoading = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let method: PaneWorkerMethod
                var arguments: [String: String] = [
                    "rootPath": rootURL.path,
                    "limit": "120"
                ]
                switch scope {
                case .repository:
                    method = .gitCommitHistory
                case let .file(relativePath):
                    method = .gitFileHistory
                    arguments["relativePath"] = relativePath
                }

                let payloadText = try await self.worker.execute(
                    method,
                    arguments: arguments,
                    timeout: 12
                )
                let payload = try self.decodeGitHistoryPayload(from: payloadText)
                self.gitHistoryEntries = self.makeGitCommitEntries(from: payload)
                self.gitHistoryIsLoading = false
            } catch {
                self.gitHistoryEntries = []
                self.gitHistoryIsLoading = false
                self.userFacingError = "Unable to load history: \(error.localizedDescription)"
            }
        }
    }

    func dismissGitHistory() {
        gitActiveHistoryScope = nil
        gitHistoryEntries = []
        gitHistoryIsLoading = false
    }

    private func runGitMutation(
        activityMessage: String,
        method: PaneWorkerMethod,
        arguments: @escaping (_ rootPath: String) -> [String: String],
        onSuccess: (() -> Void)? = nil
    ) {
        guard let rootURL else {
            userFacingError = "Select a folder first."
            return
        }

        gitIsOperating = true
        gitOperationMessage = activityMessage

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.worker.execute(
                    method,
                    arguments: arguments(rootURL.path),
                    timeout: 15
                )
                onSuccess?()
                self.gitOperationMessage = nil
                self.gitIsOperating = false
                self.refreshGitStatus()
                self.refreshGitBranches()
            } catch {
                self.gitIsOperating = false
                self.gitOperationMessage = nil
                self.userFacingError = "Git operation failed: \(error.localizedDescription)"
            }
        }
    }
}
