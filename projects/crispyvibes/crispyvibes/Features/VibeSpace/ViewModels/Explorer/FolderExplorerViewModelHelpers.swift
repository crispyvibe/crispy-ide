import Foundation

struct VibeSpaceSidebarVisibleRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case item(FileItem)
        case loading(parentDirectoryID: String)
    }

    let kind: Kind
    let depth: Int
    let isExpanded: Bool

    var id: String {
        switch kind {
        case .item(let item):
            return item.id
        case .loading(let parentDirectoryID):
            return "loading:\(parentDirectoryID)"
        }
    }
}

extension FolderExplorerViewModel {
    func revealInSidebar(_ targetURL: URL) {
        let normalizedTargetURL = targetURL.standardizedFileURL
        guard let rootURL = rootURL?.standardizedFileURL else { return }
        guard normalizedTargetURL.path == rootURL.path || normalizedTargetURL.path.hasPrefix(rootURL.path + "/") else {
            return
        }

        activeSidebarTab = .files
        Task { @MainActor [weak self] in
            await self?.revealInSidebarAsync(normalizedTargetURL, rootURL: rootURL)
        }
    }

    func loadChildrenIfNeeded(of item: FileItem) {
        refreshChildren(of: item, showLoadingState: true)
    }

    func refreshChildren(of item: FileItem, showLoadingState: Bool) {
        guard item.isDirectory else { return }
        if showLoadingState {
            guard !loadedDirectoryIDs.contains(item.id), !loadingDirectoryIDs.contains(item.id) else { return }
            loadingDirectoryIDs.insert(item.id)
        } else {
            guard !loadingDirectoryIDs.contains(item.id) else { return }
        }

        let directoryPath = item.url.path

        Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.worker.execute(
                    .listTree,
                    arguments: ["rootPath": directoryPath],
                    timeout: self.treeLoadTimeout
                )

                let children = try self.decodeFileItems(from: payload)
                self.replaceChildren(ofPath: directoryPath, with: children)
                self.loadedDirectoryIDs.insert(item.id)
                if showLoadingState {
                    self.loadingDirectoryIDs.remove(item.id)
                }
                self.workerStatus = .ready
            } catch {
                if showLoadingState {
                    self.loadingDirectoryIDs.remove(item.id)
                }
                self.workerStatus = .unavailable("Explorer worker unavailable")
                self.userFacingError = "Failed to load \(item.displayName): \(error.localizedDescription)"
            }
        }
    }

    func createItem(named proposedName: String, isFolder: Bool, in item: FileItem?) {
        createItem(named: proposedName, isFolder: isFolder, inDirectoryURL: targetDirectory(for: item))
    }

    func createItem(named proposedName: String, isFolder: Bool, inDirectoryURL directoryURL: URL?) {
        guard let directoryURL else {
            userFacingError = "Select a folder first."
            return
        }

        workerStatus = .busy("Creating")

        Task { [weak self] in
            guard let self else { return }
            do {
                let method: PaneWorkerMethod = isFolder ? .createFolder : .createFile
                let createdPath = try await self.worker.execute(
                    method,
                    arguments: [
                        "directoryPath": directoryURL.path,
                        "name": proposedName
                    ],
                    timeout: 10
                )

                guard let createdPath, !createdPath.isEmpty else {
                    throw PaneWorkerError.invalidResponse
                }

                let newURL = URL(fileURLWithPath: createdPath)
                self.refreshTree()
                self.renamingItemID = newURL.path
                self.renameText = newURL.lastPathComponent
                self.selectedItemID = newURL.path

                if isFolder {
                    self.selectedFolderURL = newURL
                    self.selectedFileURL = nil
                } else {
                    self.selectedFileURL = newURL
                    self.selectedFolderURL = directoryURL
                    self.openRequest = ExplorerOpenRequest(fileURL: newURL, action: .preview)
                }
            } catch {
                self.userFacingError = "Creation failed: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Explorer worker unavailable")
            }
        }
    }

    func targetDirectory(for item: FileItem?) -> URL? {
        guard let rootURL else { return nil }
        guard let item else { return rootURL }

        if item.isDirectory {
            return item.url
        }
        return item.url.deletingLastPathComponent()
    }

    func filter(item: FileItem, query: String) -> FileItem? {
        Self.filterForSearch(item: item, query: query)
    }

    nonisolated static func filterForSearch(item: FileItem, query: String) -> FileItem? {
        let matches = item.displayName.lowercased().contains(query)
        if item.isDirectory {
            let matchingChildren = item.children?.compactMap { filterForSearch(item: $0, query: query) } ?? []
            if matches || !matchingChildren.isEmpty {
                var result = item
                result.children = matchingChildren
                return result
            }
            return nil
        }

        return matches ? item : nil
    }

    func findItem(withID id: String) -> FileItem? {
        findItem(withID: id, in: rootItems)
    }

    func directoryDescendantIDs(of item: FileItem) -> Set<String> {
        var descendantIDs: Set<String> = []

        func appendDescendants(from items: [FileItem]?) {
            guard let items else { return }

            for child in items where child.isDirectory {
                descendantIDs.insert(child.id)
                appendDescendants(from: child.children)
            }
        }

        appendDescendants(from: item.children)
        return descendantIDs
    }

    func expandedDescendantDirectoryIDs(ofPath directoryPath: String) -> Set<String> {
        expandedDirectoryIDs.filter { candidatePath in
            isDescendantPath(candidatePath, ofDirectoryPath: directoryPath)
        }
    }

    func expandedDirectoryItemsAffected(by changedPaths: Set<String>) -> [FileItem] {
        let affectedDirectoryIDs = expandedDirectoryIDs
            .filter { directoryPath in
                changedPaths.contains { changedPath in
                    pathAffectsDirectory(changedPath, directoryPath: directoryPath)
                }
            }
            .sorted()

        return affectedDirectoryIDs.compactMap { directoryID in
            guard let item = findItem(withID: directoryID), item.isDirectory else { return nil }
            return item
        }
    }

    @discardableResult
    func replaceChildren(
        ofPath targetPath: String,
        with children: [FileItem],
        shouldRecordMutation: Bool = true
    ) -> Bool {
        var updatedRootItems = rootItems
        guard replaceChildren(in: &updatedRootItems, targetPath: targetPath, with: children) else { return false }
        rootItems = updatedRootItems
        if shouldRecordMutation {
            recordTreeMutation(changedDirectoryIDs: [targetPath])
        }
        return true
    }

    func replaceRootItems(_ items: [FileItem]) {
        rootItems = items
    }

    func vibespaceSidebarVisibleRows() -> [VibeSpaceSidebarVisibleRow] {
        Self.makeVibeSpaceSidebarVisibleRows(
            displayedItems: displayedItems,
            expandedDirectoryIDs: expandedDirectoryIDs,
            loadingDirectoryIDs: loadingDirectoryIDs,
            isSearching: isSearching
        )
    }

    nonisolated static func makeVibeSpaceSidebarVisibleRows(
        displayedItems: [FileItem],
        expandedDirectoryIDs: Set<String>,
        loadingDirectoryIDs: Set<String>,
        isSearching: Bool
    ) -> [VibeSpaceSidebarVisibleRow] {
        var rows: [VibeSpaceSidebarVisibleRow] = []
        rows.reserveCapacity(displayedItems.count)

        func appendRows(for items: [FileItem], depth: Int) {
            for item in items {
                rows.append(
                    VibeSpaceSidebarVisibleRow(
                        kind: .item(item),
                        depth: depth,
                        isExpanded: isSearching || expandedDirectoryIDs.contains(item.id)
                    )
                )

                guard item.isDirectory else { continue }
                let shouldShowChildren = isSearching || expandedDirectoryIDs.contains(item.id)
                guard shouldShowChildren else { continue }

                if loadingDirectoryIDs.contains(item.id) {
                    rows.append(
                        VibeSpaceSidebarVisibleRow(
                            kind: .loading(parentDirectoryID: item.id),
                            depth: depth + 1,
                            isExpanded: false
                        )
                    )
                    continue
                }

                guard let children = item.children, !children.isEmpty else { continue }
                appendRows(for: children, depth: depth + 1)
            }
        }

        appendRows(for: displayedItems, depth: 0)
        return rows
    }

    func mergeRootItemsPreservingLoadedChildren(with freshRootItems: [FileItem]) -> [FileItem] {
        guard !rootItems.isEmpty else { return freshRootItems }
        let existingByID = Dictionary(uniqueKeysWithValues: rootItems.map { ($0.id, $0) })

        return freshRootItems.map { incomingItem in
            guard incomingItem.isDirectory,
                  let existingItem = existingByID[incomingItem.id],
                  let existingChildren = existingItem.children,
                  expandedDirectoryIDs.contains(incomingItem.id) || loadedDirectoryIDs.contains(incomingItem.id) else {
                return incomingItem
            }

            var merged = incomingItem
            merged.children = existingChildren
            return merged
        }
    }

    private func findItem(withID id: String, in items: [FileItem]) -> FileItem? {
        for item in items {
            if item.id == id {
                return item
            }
            if let children = item.children,
               let match = findItem(withID: id, in: children) {
                return match
            }
        }
        return nil
    }

    func watcherRefreshTargetDirectoryPaths(
        for changedPaths: Set<String>,
        changedEvents: [String: DirectoryWatcher.Event],
        rootPath: String
    ) -> [String] {
        var targetPaths: Set<String> = []

        for changedPath in changedPaths {
            let normalizedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.path
            let event = changedEvents[normalizedPath]
            let resolvedKind = event?.kind ?? .unknown
            let isDirectory = event?.isDirectory ?? existingDirectoryPath(for: normalizedPath)

            if normalizedPath == rootPath {
                targetPaths.insert(rootPath)
                continue
            }

            let parentPath = URL(fileURLWithPath: normalizedPath)
                .deletingLastPathComponent()
                .standardizedFileURL
                .path

            if isDirectory {
                if resolvedKind == .modified {
                    if isVisibleDirectoryPath(normalizedPath, rootPath: rootPath) {
                        targetPaths.insert(normalizedPath)
                    } else if isVisibleDirectoryPath(parentPath, rootPath: rootPath) {
                        targetPaths.insert(parentPath)
                    }
                } else {
                    if isVisibleDirectoryPath(parentPath, rootPath: rootPath) {
                        targetPaths.insert(parentPath)
                    }
                    if isVisibleDirectoryPath(normalizedPath, rootPath: rootPath) {
                        targetPaths.insert(normalizedPath)
                    }
                }
                continue
            }

            if isVisibleDirectoryPath(parentPath, rootPath: rootPath) {
                targetPaths.insert(parentPath)
            }
        }

        return targetPaths.sorted()
    }

    func refreshRootDirectoryFromWatcher() {
        guard let rootURL else { return }
        let rootPath = rootURL.standardizedFileURL.path

        Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.worker.execute(
                    .listTree,
                    arguments: ["rootPath": rootPath],
                    timeout: self.treeLoadTimeout
                )

                let decodedItems = try self.decodeFileItems(from: payload)
                let mergedItems = self.mergeRootItemsPreservingLoadedChildren(with: decodedItems)
                guard self.rootItems != mergedItems else { return }
                self.replaceRootItems(mergedItems)
                self.loadedDirectoryIDs.insert(rootPath)
                self.recordTreeMutation(changedDirectoryIDs: [rootPath])
            } catch {
                self.workerStatus = .unavailable("Explorer worker unavailable")
                self.userFacingError = "Failed to read \(rootPath): \(error.localizedDescription)"
            }
        }
    }

    func recordTreeMutation(changedDirectoryIDs: Set<String>) {
        self.changedDirectoryIDs = changedDirectoryIDs
        treeMutationRevision += 1
    }

    private func isDescendantPath(_ candidatePath: String, ofDirectoryPath directoryPath: String) -> Bool {
        guard candidatePath != directoryPath else { return false }

        let normalizedDirectoryPath = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return candidatePath.hasPrefix(normalizedDirectoryPath)
    }

    private func pathAffectsDirectory(_ changedPath: String, directoryPath: String) -> Bool {
        if changedPath == directoryPath {
            return true
        }

        let normalizedDirectoryPath = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return changedPath.hasPrefix(normalizedDirectoryPath)
    }

    private func existingDirectoryPath(for path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func isVisibleDirectoryPath(_ directoryPath: String, rootPath: String) -> Bool {
        if directoryPath == rootPath {
            return true
        }
        return expandedDirectoryIDs.contains(directoryPath) || loadedDirectoryIDs.contains(directoryPath)
    }

    private func replaceChildren(
        in items: inout [FileItem],
        targetPath: String,
        with children: [FileItem]
    ) -> Bool {
        for index in items.indices {
            if items[index].id == targetPath {
                if let existing = items[index].children, existing == children, existing.count == children.count {
                    return false
                }
                items[index].children = children
                return true
            }
            guard items[index].children != nil else { continue }
            var nestedChildren = items[index].children ?? []
            if replaceChildren(in: &nestedChildren, targetPath: targetPath, with: children) {
                items[index].children = nestedChildren
                return true
            }
        }
        return false
    }

    func updateSelections(afterMoving oldURL: URL, to newURL: URL) {
        if let mappedFileURL = mapPathAfterMove(selectedFileURL, from: oldURL, to: newURL) {
            selectedFileURL = mappedFileURL
        } else if pathsReferToSameLocation(selectedFileURL, as: oldURL) {
            selectedFileURL = newURL.standardizedFileURL
        }
        if let mappedFolderURL = mapPathAfterMove(selectedFolderURL, from: oldURL, to: newURL) {
            selectedFolderURL = mappedFolderURL
        } else if pathsReferToSameLocation(selectedFolderURL, as: oldURL) {
            selectedFolderURL = newURL.standardizedFileURL
        }
        if let selectedID = selectedItemID,
           let mappedItemURL = mapPathAfterMove(URL(fileURLWithPath: selectedID), from: oldURL, to: newURL) {
            selectedItemID = mappedItemURL.path
        } else if let selectedID = selectedItemID,
                  pathsReferToSameLocation(URL(fileURLWithPath: selectedID), as: oldURL) {
            selectedItemID = newURL.standardizedFileURL.path
        }
    }

    func isSamePathOrDescendant(_ candidate: URL?, of container: URL) -> Bool {
        guard let candidate else { return false }
        return mapPathAfterMove(candidate, from: container, to: container) != nil
    }

    func mapPathAfterMove(_ candidate: URL?, from oldURL: URL, to newURL: URL) -> URL? {
        guard let candidate else { return nil }

        let oldPathVariants = normalizedPathVariants(for: oldURL)
        let candidatePathVariants = normalizedPathVariants(for: candidate)

        for candidatePath in candidatePathVariants {
            for oldPath in oldPathVariants {
                if candidatePath == oldPath {
                    return newURL.standardizedFileURL
                }

                let oldPrefix = oldPath.hasSuffix("/") ? oldPath : oldPath + "/"
                guard candidatePath.hasPrefix(oldPrefix) else { continue }

                let relativeSuffix = String(candidatePath.dropFirst(oldPrefix.count))
                return newURL.standardizedFileURL.appendingPathComponent(relativeSuffix)
            }
        }

        return nil
    }

    func normalizedPathVariants(for url: URL) -> Set<String> {
        let standardizedPath = url.standardizedFileURL.path
        let resolvedPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return [standardizedPath, resolvedPath]
    }

    func pathsReferToSameLocation(_ lhs: URL?, as rhs: URL) -> Bool {
        guard let lhs else { return false }
        return !normalizedPathVariants(for: lhs).isDisjoint(with: normalizedPathVariants(for: rhs))
    }

    func decodeFileItems(from payload: String?) throws -> [FileItem] {
        guard let payload, !payload.isEmpty else { return [] }
        let data = Data(payload.utf8)
        let nodes = try JSONDecoder().decode([WorkerFileNode].self, from: data)
        return nodes.map(makeFileItem(from:))
    }

    func decodeGitPayload(from payload: String?) throws -> WorkerGitStatusPayload {
        guard let payload, !payload.isEmpty else {
            return WorkerGitStatusPayload(gitAvailable: true, repository: true, entries: [], message: nil)
        }
        let data = Data(payload.utf8)
        return try JSONDecoder().decode(WorkerGitStatusPayload.self, from: data)
    }

    func decodeGitBranchesPayload(from payload: String?) throws -> WorkerGitBranchesPayload {
        guard let payload, !payload.isEmpty else {
            return WorkerGitBranchesPayload(
                gitAvailable: true,
                repository: true,
                currentBranch: nil,
                branches: [],
                message: nil
            )
        }
        let data = Data(payload.utf8)
        return try JSONDecoder().decode(WorkerGitBranchesPayload.self, from: data)
    }

    func decodeGitRepositorySnapshotPayload(from payload: String?) throws -> WorkerGitRepositorySnapshotPayload {
        guard let payload, !payload.isEmpty else {
            return WorkerGitRepositorySnapshotPayload(
                gitAvailable: true,
                repository: true,
                entries: [],
                currentBranch: nil,
                branches: [],
                message: nil
            )
        }
        let data = Data(payload.utf8)
        return try JSONDecoder().decode(WorkerGitRepositorySnapshotPayload.self, from: data)
    }

    func decodeGitHistoryPayload(from payload: String?) throws -> WorkerGitHistoryPayload {
        guard let payload, !payload.isEmpty else {
            return WorkerGitHistoryPayload(entries: [])
        }
        let data = Data(payload.utf8)
        return try JSONDecoder().decode(WorkerGitHistoryPayload.self, from: data)
    }

    func makeFileItem(from node: WorkerFileNode) -> FileItem {
        let children = node.children?.map(makeFileItem(from:))
        return FileItem(
            url: URL(fileURLWithPath: node.path),
            isDirectory: node.isDirectory,
            isHidden: node.isHidden,
            isGitIgnored: node.isGitIgnored,
            children: children
        )
    }

    func makeGitStatusItem(from node: WorkerGitStatusNode) -> GitStatusItem {
        GitStatusItem(
            code: node.code,
            indexStatus: node.indexStatus,
            workTreeStatus: node.workTreeStatus,
            relativePath: node.relativePath,
            url: URL(fileURLWithPath: node.path)
        )
    }

    func makeGitBranchOption(from node: WorkerGitBranchNode) -> GitBranchOption {
        GitBranchOption(
            name: node.name,
            displayName: node.displayName,
            isCurrent: node.isCurrent,
            isRemote: node.isRemote
        )
    }

    func makeGitCommitEntries(from payload: WorkerGitHistoryPayload) -> [GitCommitEntry] {
        payload.entries.map { entry in
            GitCommitEntry(
                hash: entry.hash,
                shortHash: entry.shortHash,
                authorName: entry.authorName,
                authoredDate: entry.authoredDate,
                subject: entry.subject
            )
        }
    }

    private func revealInSidebarAsync(_ targetURL: URL, rootURL: URL) async {
        let directoryURL = targetURL.hasDirectoryPath ? targetURL : targetURL.deletingLastPathComponent()
        let ancestorPaths = directoryAncestorPaths(for: directoryURL, rootURL: rootURL)

        _ = await waitForDirectoryContents(rootURL.path)
        for ancestorPath in ancestorPaths.dropFirst() {
            guard let item = await waitForItem(withID: ancestorPath) else { continue }
            expandedDirectoryIDs.insert(item.id)
            loadChildrenIfNeeded(of: item)
            _ = await waitForDirectoryContents(item.id)
        }

        selectedItemID = targetURL.path
        if targetURL.hasDirectoryPath {
            selectedFolderURL = targetURL
            selectedFileURL = nil
        } else {
            selectedFolderURL = directoryURL
            selectedFileURL = targetURL
        }
    }

    private func waitForItem(withID id: String, timeout: TimeInterval = 2) async -> FileItem? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let item = findItem(withID: id) {
                return item
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return findItem(withID: id)
    }

    private func waitForDirectoryContents(_ directoryID: String, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if loadedDirectoryIDs.contains(directoryID) || !loadingDirectoryIDs.contains(directoryID) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return loadedDirectoryIDs.contains(directoryID)
    }

    private func directoryAncestorPaths(for directoryURL: URL, rootURL: URL) -> [String] {
        guard directoryURL.path == rootURL.path || directoryURL.path.hasPrefix(rootURL.path + "/") else {
            return [rootURL.path]
        }

        var currentPath = rootURL.path
        var paths = [currentPath]
        let relativePath = directoryURL.path == rootURL.path
            ? ""
            : String(directoryURL.path.dropFirst(rootURL.path.count + 1))
        for component in relativePath.split(separator: "/") {
            currentPath = URL(fileURLWithPath: currentPath)
                .appendingPathComponent(String(component), isDirectory: true)
                .path
            paths.append(currentPath)
        }
        return paths
    }
}
