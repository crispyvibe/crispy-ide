import Combine
import Foundation

@MainActor
final class VibeSpaceSourceControlRepositoryViewModel: ObservableObject, Identifiable {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case error
    }

    let id: String
    let repositoryRootURL: URL
    let worker: any PaneWorkerExecuting
    let gitExplorer: AnyGitExplorer?

    @Published var attachedProjects: [VibeSpaceSourceControlProjectReference] = []
    @Published var branchName: String?
    @Published var branchOptions: [GitBranchOption] = []
    @Published var statusItems: [VibeSpaceSourceControlStatusItem] = []
    @Published var stagedItems: [VibeSpaceSourceControlStatusItem] = []
    @Published var changeItems: [VibeSpaceSourceControlStatusItem] = []
    @Published var loadState: LoadState = .idle
    @Published var message: String?
    @Published var isExpanded = true
    @Published var commitDraft = ""
    @Published var operationMessage: String?
    @Published var isOperating = false
    @Published var historyEntries: [GitCommitEntry] = []
    @Published var activeHistoryScope: VibeSpaceSourceControlHistoryScope?
    @Published var historyIsLoading = false
    @Published var locationLabel: String?

    private var refreshInFlight = false
    private var refreshQueued = false
    var activeMutationTask: Task<Void, Never>?
    var activeHistoryTask: Task<Void, Never>?

    init(
        id: String? = nil,
        repositoryRootURL: URL,
        worker: any PaneWorkerExecuting,
        gitExplorer: AnyGitExplorer? = nil
    ) {
        self.id = id ?? repositoryRootURL.standardizedFileURL.path
        self.repositoryRootURL = repositoryRootURL.standardizedFileURL
        self.worker = worker
        self.gitExplorer = gitExplorer
    }

    var displayName: String {
        let name = repositoryRootURL.lastPathComponent
        return name.isEmpty ? repositoryRootURL.path : name
    }

    var pendingChangeCount: Int {
        statusItems.count
    }

    var hasDiscardableChanges: Bool {
        statusItems.contains(where: \.canDiscardChanges)
    }

    var hasSnapshotData: Bool {
        !statusItems.isEmpty || branchName != nil || !branchOptions.isEmpty
    }

    func configure(attachedProjects: [VibeSpaceSourceControlProjectReference]) {
        self.attachedProjects = attachedProjects.sorted { lhs, rhs in
            lhs.orderIndex < rhs.orderIndex
        }
        locationLabel = makeLocationLabel()
    }

    func refresh() async {
        guard !refreshInFlight else {
            refreshQueued = true
            return
        }

        refreshInFlight = true
        defer { refreshInFlight = false }

        repeat {
            refreshQueued = false
            await performRefresh()
        } while refreshQueued
    }

    private func performRefresh() async {
        if !hasSnapshotData {
            loadState = .loading
        }

        if let gitExplorer {
            await refreshViaGitExplorer(gitExplorer)
            return
        }

        do {
            let snapshotPayloadText = try await worker.execute(
                .gitRepositorySnapshot,
                arguments: ["rootPath": repositoryRootURL.path],
                timeout: 12
            )
            let snapshotPayload = try decodeGitRepositorySnapshotPayload(from: snapshotPayloadText)

            guard snapshotPayload.gitAvailable else {
                handleRefreshFailure(snapshotPayload.message ?? "Git is not installed on this machine.")
                return
            }

            guard snapshotPayload.repository else {
                handleRefreshFailure(snapshotPayload.message ?? "This repository is no longer available.")
                return
            }

            applyStatusItems(snapshotPayload.entries.map(makeStatusItem(from:)))
            branchName = snapshotPayload.currentBranch
            branchOptions = snapshotPayload.branches.map(makeGitBranchOption(from:))
            loadState = .ready
            message = nil
        } catch {
            handleRefreshFailure("Unable to load repository status: \(error.localizedDescription)")
        }
    }

    func handleRefreshFailure(_ failureMessage: String) {
        message = failureMessage
        if hasSnapshotData {
            loadState = .ready
        } else {
            loadState = .error
            applyStatusItems([])
            branchName = nil
            branchOptions = []
        }
    }

    func stage(_ item: VibeSpaceSourceControlStatusItem) {
        if let gitExplorer {
            runGitExplorerMutation(activityMessage: "Staging \(item.relativePath)") {
                try await gitExplorer.stage(files: [item.relativePath], in: self.repositoryRootURL.path)
            }
            return
        }
        runMutation(
            activityMessage: "Staging \(item.relativePath)",
            method: .gitStage,
            arguments: [
                "rootPath": repositoryRootURL.path,
                "relativePath": item.relativePath
            ]
        )
    }

    func unstage(_ item: VibeSpaceSourceControlStatusItem) {
        if let gitExplorer {
            runGitExplorerMutation(activityMessage: "Unstaging \(item.relativePath)") {
                try await gitExplorer.unstage(files: [item.relativePath], in: self.repositoryRootURL.path)
            }
            return
        }
        runMutation(
            activityMessage: "Unstaging \(item.relativePath)",
            method: .gitUnstage,
            arguments: [
                "rootPath": repositoryRootURL.path,
                "relativePath": item.relativePath
            ]
        )
    }

    func stageAll() {
        if let gitExplorer {
            let allPaths = statusItems.map(\.relativePath)
            runGitExplorerMutation(activityMessage: "Staging all changes") {
                try await gitExplorer.stage(files: allPaths, in: self.repositoryRootURL.path)
            }
            return
        }
        runMutation(
            activityMessage: "Staging all changes",
            method: .gitStageAll,
            arguments: ["rootPath": repositoryRootURL.path]
        )
    }

    func unstageAll() {
        if let gitExplorer {
            let stagedPaths = stagedItems.map(\.relativePath)
            runGitExplorerMutation(activityMessage: "Unstaging all changes") {
                try await gitExplorer.unstage(files: stagedPaths, in: self.repositoryRootURL.path)
            }
            return
        }
        runMutation(
            activityMessage: "Unstaging all changes",
            method: .gitUnstageAll,
            arguments: ["rootPath": repositoryRootURL.path]
        )
    }

    func discard(_ item: VibeSpaceSourceControlStatusItem) {
        if gitExplorer != nil {
            message = "Discard is not yet available for remote repositories."
            return
        }
        runMutation(
            activityMessage: "Discarding changes in \(item.relativePath)",
            method: .gitDiscard,
            arguments: [
                "rootPath": repositoryRootURL.path,
                "relativePath": item.relativePath
            ]
        )
    }

    func discardAllChanges() {
        if gitExplorer != nil {
            message = "Discard is not yet available for remote repositories."
            return
        }
        runMutation(
            activityMessage: "Discarding all unstaged changes",
            method: .gitDiscardAll,
            arguments: ["rootPath": repositoryRootURL.path]
        )
    }

    func commit() {
        let trimmedMessage = commitDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            message = "Commit message cannot be empty."
            return
        }

        if let gitExplorer {
            runGitExplorerMutation(activityMessage: "Creating commit") {
                try await gitExplorer.commit(message: trimmedMessage, in: self.repositoryRootURL.path)
            } onSuccess: { [weak self] in
                self?.commitDraft = ""
            }
            return
        }

        runMutation(
            activityMessage: "Creating commit",
            method: .gitCommit,
            arguments: [
                "rootPath": repositoryRootURL.path,
                "message": trimmedMessage
            ],
            onSuccess: { [weak self] in
                self?.commitDraft = ""
            }
        )
    }

    func push() {
        if let gitExplorer {
            runGitExplorerMutation(activityMessage: "Pushing branch") {
                let rootPath = self.repositoryRootURL.path
                _ = try await gitExplorer.commandExecutor.execute(
                    tool: "git",
                    arguments: ["-C", rootPath, "push"],
                    stdinData: nil,
                    timeout: 30
                )
                try await gitExplorer.loadStatus(for: rootPath)
                try await gitExplorer.loadBranches(for: rootPath)
            }
            return
        }
        runMutation(
            activityMessage: "Pushing branch",
            method: .gitPush,
            arguments: ["rootPath": repositoryRootURL.path]
        )
    }

    func pull() {
        if let gitExplorer {
            runGitExplorerMutation(activityMessage: "Pulling changes") {
                let rootPath = self.repositoryRootURL.path
                _ = try await gitExplorer.commandExecutor.execute(
                    tool: "git",
                    arguments: ["-C", rootPath, "pull"],
                    stdinData: nil,
                    timeout: 30
                )
                try await gitExplorer.loadStatus(for: rootPath)
                try await gitExplorer.loadBranches(for: rootPath)
            }
            return
        }
        runMutation(
            activityMessage: "Pulling changes",
            method: .gitPull,
            arguments: ["rootPath": repositoryRootURL.path]
        )
    }

    func fetch() {
        if let gitExplorer {
            runGitExplorerMutation(activityMessage: "Fetching remote") {
                let rootPath = self.repositoryRootURL.path
                _ = try await gitExplorer.commandExecutor.execute(
                    tool: "git",
                    arguments: ["-C", rootPath, "fetch"],
                    stdinData: nil,
                    timeout: 30
                )
                try await gitExplorer.loadBranches(for: rootPath)
            }
            return
        }
        runMutation(
            activityMessage: "Fetching remote",
            method: .gitFetch,
            arguments: ["rootPath": repositoryRootURL.path]
        )
    }

    func checkout(_ branch: GitBranchOption) {
        if let gitExplorer {
            runGitExplorerMutation(activityMessage: "Checking out \(branch.displayName)") {
                try await gitExplorer.checkout(
                    branch: branch.name,
                    isRemoteBranch: branch.isRemote,
                    in: self.repositoryRootURL.path
                )
                try await gitExplorer.loadStatus(for: self.repositoryRootURL.path)
            }
            return
        }
        runMutation(
            activityMessage: "Checking out \(branch.displayName)",
            method: .gitCheckoutBranch,
            arguments: [
                "rootPath": repositoryRootURL.path,
                "branch": branch.name,
                "isRemote": branch.isRemote ? "1" : "0"
            ]
        )
    }

    func openHistory(scope: VibeSpaceSourceControlHistoryScope) {
        activeHistoryTask?.cancel()
        historyEntries = []
        activeHistoryScope = scope
        historyIsLoading = true

        if let gitExplorer {
            activeHistoryTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let gitScope: GitHistoryScope = switch scope {
                    case .repository:
                        .repository
                    case let .file(relativePath):
                        .file(relativePath: relativePath)
                    }
                    try await gitExplorer.loadHistory(for: self.repositoryRootURL.path, scope: gitScope)
                    self.historyEntries = gitExplorer.historyEntries
                    self.historyIsLoading = false
                } catch {
                    self.historyEntries = []
                    self.historyIsLoading = false
                    self.message = "Unable to load Git history: \(error.localizedDescription)"
                }
            }
            return
        }

        activeHistoryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let method: PaneWorkerMethod
                var arguments: [String: String] = [
                    "rootPath": self.repositoryRootURL.path,
                    "limit": "100"
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
                self.historyEntries = payload.entries.map(self.makeGitCommitEntry(from:))
                self.historyIsLoading = false
            } catch {
                self.historyEntries = []
                self.historyIsLoading = false
                self.message = "Unable to load Git history: \(error.localizedDescription)"
            }
        }
    }

    func dismissHistory() {
        activeHistoryTask?.cancel()
        activeHistoryScope = nil
        historyEntries = []
        historyIsLoading = false
    }

    func containsPath(_ path: String) -> Bool {
        let normalizedRepositoryPath = repositoryRootURL.path
        if path == normalizedRepositoryPath {
            return true
        }
        let prefix = normalizedRepositoryPath.hasSuffix("/") ? normalizedRepositoryPath : normalizedRepositoryPath + "/"
        return path.hasPrefix(prefix)
    }
}
