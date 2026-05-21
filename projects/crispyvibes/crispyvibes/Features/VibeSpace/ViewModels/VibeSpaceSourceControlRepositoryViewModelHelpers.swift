import Foundation

extension VibeSpaceSourceControlRepositoryViewModel {
    func refreshViaGitExplorer(_ gitExplorer: AnyGitExplorer) async {
        do {
            try await gitExplorer.loadStatus(for: repositoryRootURL.path)
            try await gitExplorer.loadBranches(for: repositoryRootURL.path)

            applyStatusItems(gitExplorer.statusItems.map(makeStatusItem(from:)))
            branchName = gitExplorer.currentBranchName
            branchOptions = gitExplorer.branchOptions
            loadState = .ready
            message = nil
        } catch {
            handleRefreshFailure("Unable to load repository status: \(error.localizedDescription)")
        }
    }

    func runMutation(
        activityMessage: String,
        method: PaneWorkerMethod,
        arguments: [String: String],
        onSuccess: (() -> Void)? = nil
    ) {
        activeMutationTask?.cancel()
        isOperating = true
        operationMessage = activityMessage
        message = nil

        activeMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.worker.execute(
                    method,
                    arguments: arguments,
                    timeout: 12
                )
                onSuccess?()
                self.isOperating = false
                self.operationMessage = nil
                await self.refresh()
            } catch {
                self.isOperating = false
                self.operationMessage = nil
                self.message = "Git operation failed: \(error.localizedDescription)"
            }
        }
    }

    func runGitExplorerMutation(
        activityMessage: String,
        operation: @escaping () async throws -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        activeMutationTask?.cancel()
        isOperating = true
        operationMessage = activityMessage
        message = nil

        activeMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
                onSuccess?()
                self.isOperating = false
                self.operationMessage = nil
                await self.refresh()
            } catch {
                self.isOperating = false
                self.operationMessage = nil
                self.message = "Git operation failed: \(error.localizedDescription)"
            }
        }
    }

    func applyStatusItems(_ items: [VibeSpaceSourceControlStatusItem]) {
        statusItems = items
        stagedItems = items.filter(\.isStaged)
        changeItems = items.filter { $0.hasUnstagedChanges || !$0.isStaged }
    }

    func makeLocationLabel() -> String? {
        guard attachedProjects.count == 1, let project = attachedProjects.first else {
            return nil
        }

        let repositoryPath = repositoryRootURL.path
        let projectPath = project.rootURL.path

        if repositoryPath == projectPath {
            return nil
        }

        if pathContains(projectPath, candidatePath: repositoryPath) {
            return relativePath(from: project.rootURL, to: repositoryRootURL)
        }

        if pathContains(repositoryPath, candidatePath: projectPath) {
            return project.title
        }

        return nil
    }

    func relativePath(from baseURL: URL, to targetURL: URL) -> String? {
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents
        guard targetComponents.count >= baseComponents.count,
              Array(targetComponents.prefix(baseComponents.count)) == baseComponents else {
            return nil
        }

        let relativeComponents = targetComponents.dropFirst(baseComponents.count)
        let relativePath = relativeComponents.joined(separator: "/")
        return relativePath.isEmpty ? nil : relativePath
    }

    func pathContains(_ rootPath: String, candidatePath: String) -> Bool {
        if rootPath == candidatePath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    func decodeGitStatusPayload(from payload: String?) throws -> WorkerGitStatusPayload {
        guard let payload,
              let data = payload.data(using: .utf8) else {
            return WorkerGitStatusPayload(gitAvailable: true, repository: true, entries: [], message: nil)
        }
        return try JSONDecoder().decode(WorkerGitStatusPayload.self, from: data)
    }

    func decodeGitBranchesPayload(from payload: String?) throws -> WorkerGitBranchesPayload {
        guard let payload,
              let data = payload.data(using: .utf8) else {
            return WorkerGitBranchesPayload(
                gitAvailable: true,
                repository: true,
                currentBranch: nil,
                branches: [],
                message: nil
            )
        }
        return try JSONDecoder().decode(WorkerGitBranchesPayload.self, from: data)
    }

    func decodeGitRepositorySnapshotPayload(from payload: String?) throws -> WorkerGitRepositorySnapshotPayload {
        guard let payload,
              let data = payload.data(using: .utf8) else {
            return WorkerGitRepositorySnapshotPayload(
                gitAvailable: true,
                repository: true,
                entries: [],
                currentBranch: nil,
                branches: [],
                message: nil
            )
        }
        return try JSONDecoder().decode(WorkerGitRepositorySnapshotPayload.self, from: data)
    }

    func decodeGitHistoryPayload(from payload: String?) throws -> WorkerGitHistoryPayload {
        guard let payload,
              let data = payload.data(using: .utf8) else {
            return WorkerGitHistoryPayload(entries: [])
        }
        return try JSONDecoder().decode(WorkerGitHistoryPayload.self, from: data)
    }

    func makeStatusItem(from node: WorkerGitStatusNode) -> VibeSpaceSourceControlStatusItem {
        VibeSpaceSourceControlStatusItem(
            repositoryRootURL: repositoryRootURL,
            code: node.code,
            indexStatus: node.indexStatus,
            workTreeStatus: node.workTreeStatus,
            relativePath: node.relativePath,
            url: URL(fileURLWithPath: node.path).standardizedFileURL
        )
    }

    func makeStatusItem(from item: GitStatusItem) -> VibeSpaceSourceControlStatusItem {
        VibeSpaceSourceControlStatusItem(
            repositoryRootURL: repositoryRootURL,
            code: item.code,
            indexStatus: item.indexStatus,
            workTreeStatus: item.workTreeStatus,
            relativePath: item.relativePath,
            url: item.url.standardizedFileURL
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

    func makeGitCommitEntry(from entry: WorkerGitHistoryEntry) -> GitCommitEntry {
        GitCommitEntry(
            hash: entry.hash,
            shortHash: entry.shortHash,
            authorName: entry.authorName,
            authoredDate: entry.authoredDate,
            subject: entry.subject
        )
    }
}
