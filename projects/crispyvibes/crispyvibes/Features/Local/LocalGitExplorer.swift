// LocalGitExplorer.swift — SSH Remote Development
//
// GitExploring implementation that uses CommandExecuting for git operations.
// Local projects: delegates to FolderExplorerViewModel for UI state, uses
//   LocalCommandExecutor for discovery.
// Remote projects: runs all git commands via RemoteCommandExecutor over SSH.

import Combine
import Foundation

@MainActor
final class LocalGitExplorer: ObservableObject, GitExploring {
    let commandExecutor: any CommandExecuting
    private let explorer: any FolderExploring
    private var cancellables = Set<AnyCancellable>()
    private let isRemote: Bool

    @Published private var _isAvailable = false
    @Published private var _statusItems: [GitStatusItem] = []
    @Published private var _branchOptions: [GitBranchOption] = []
    @Published private var _currentBranchName: String?
    @Published private var _gitState: FolderExplorerViewModel.GitState = .idle
    @Published var commitMessageDraft: String = ""
    @Published private var _isOperating = false
    @Published private var _operationMessage: String?
    @Published private var _historyEntries: [GitCommitEntry] = []
    @Published private var _isHistoryLoading = false
    @Published var activeHistoryScope: GitHistoryScope?

    init<T: FolderExploring>(explorer: T, commandExecutor: any CommandExecuting = LocalCommandExecutor()) {
        self.explorer = explorer
        self.commandExecutor = commandExecutor
        self.isRemote = commandExecutor is RemoteCommandExecutor

        if !isRemote {
            // Local: forward state from FolderExplorerViewModel
            explorer.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    // MARK: - State (remote uses own state, local forwards from explorer)

    var isAvailable: Bool { isRemote ? _isAvailable : explorerGitAvailable }
    var statusItems: [GitStatusItem] { isRemote ? _statusItems : explorer.gitStatusItems }
    var branchOptions: [GitBranchOption] { isRemote ? _branchOptions : explorer.gitBranchOptions }
    var currentBranchName: String? { isRemote ? _currentBranchName : explorer.gitCurrentBranchName }
    var gitState: FolderExplorerViewModel.GitState { isRemote ? _gitState : explorer.gitState }
    var isOperating: Bool { isRemote ? _isOperating : explorer.gitIsOperating }
    var operationMessage: String? { isRemote ? _operationMessage : explorer.gitOperationMessage }
    var historyEntries: [GitCommitEntry] { isRemote ? _historyEntries : explorer.gitHistoryEntries }
    var isHistoryLoading: Bool { isRemote ? _isHistoryLoading : explorer.gitHistoryIsLoading }

    private var explorerGitAvailable: Bool {
        switch explorer.gitState {
        case .ready, .loading: return true
        default: return false
        }
    }

    // MARK: - Operations

    func discoverRepositories(at rootPath: String) async throws -> WorkerGitRepositoryDiscoveryPayload {
        if !isRemote {
            return WorkerGitRepositoryDiscoveryPayload(gitAvailable: explorerGitAvailable, repositories: [], message: nil)
        }
        let versionResult = try await commandExecutor.execute(
            tool: "git",
            arguments: ["--version"],
            stdinData: nil,
            timeout: 15
        )
        guard versionResult.terminationStatus == 0 else {
            let stderr = String(data: versionResult.stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            _isAvailable = false
            _gitState = .gitUnavailable
            return WorkerGitRepositoryDiscoveryPayload(
                gitAvailable: false,
                repositories: [],
                message: stderr?.isEmpty == false ? stderr : "Git is not available on the remote host."
            )
        }

        let result = try await commandExecutor.execute(
            tool: "git",
            arguments: ["-C", rootPath, "rev-parse", "--show-toplevel"],
            stdinData: nil,
            timeout: 15
        )
        _isAvailable = true

        if result.terminationStatus == 0 {
            let stdout = String(data: result.stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let repositoryRootPath = stdout.isEmpty ? rootPath : stdout
            _gitState = .ready
            return WorkerGitRepositoryDiscoveryPayload(
                gitAvailable: true,
                repositories: [WorkerGitRepositoryNode(repositoryRootPath: repositoryRootPath)],
                message: nil
            )
        }

        let stderr = String(data: result.stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _gitState = .ready
        return WorkerGitRepositoryDiscoveryPayload(
            gitAvailable: true,
            repositories: [],
            message: stderr.isEmpty ? "This folder is not a Git repository." : stderr
        )
    }

    func loadStatus(for rootPath: String) async throws {
        if !isRemote { explorer.refreshGitStatus(); return }
        _gitState = .loading
        let result = try await commandExecutor.execute(
            tool: "git", arguments: ["-C", rootPath, "status", "--porcelain=v1", "-z"], stdinData: nil, timeout: 30
        )
        let nodes = GitOutputParser.parseStatus(from: result.stdoutData, rootURL: URL(fileURLWithPath: rootPath))
        _statusItems = nodes.map { node in
            GitStatusItem(code: node.code, indexStatus: node.indexStatus, workTreeStatus: node.workTreeStatus, relativePath: node.relativePath, url: URL(fileURLWithPath: node.path))
        }
        _gitState = .ready
    }

    func stage(files: [String], in rootPath: String) async throws {
        if !isRemote { files.forEach { f in explorer.gitStatusItems.first { $0.relativePath == f }.map { explorer.stageGitItem($0) } }; return }
        _isOperating = true
        _ = try await commandExecutor.execute(tool: "git", arguments: ["-C", rootPath, "add"] + files, stdinData: nil, timeout: 15)
        _isOperating = false
        try await loadStatus(for: rootPath)
    }

    func unstage(files: [String], in rootPath: String) async throws {
        if !isRemote { files.forEach { f in explorer.gitStatusItems.first { $0.relativePath == f }.map { explorer.unstageGitItem($0) } }; return }
        _isOperating = true
        _ = try await commandExecutor.execute(tool: "git", arguments: ["-C", rootPath, "restore", "--staged"] + files, stdinData: nil, timeout: 15)
        _isOperating = false
        try await loadStatus(for: rootPath)
    }

    func commit(message: String, in rootPath: String) async throws {
        if !isRemote { explorer.gitCommitMessageDraft = message; explorer.commitGitChanges(); return }
        _isOperating = true; _operationMessage = "Committing…"
        _ = try await commandExecutor.execute(tool: "git", arguments: ["-C", rootPath, "commit", "-m", message], stdinData: nil, timeout: 30)
        _isOperating = false; _operationMessage = nil
        try await loadStatus(for: rootPath)
    }

    func checkout(branch: String, isRemoteBranch: Bool, in rootPath: String) async throws {
        if !isRemote { explorer.gitBranchOptions.first { $0.name == branch }.map { explorer.checkoutGitBranch($0) }; return }
        _isOperating = true
        var args = ["-C", rootPath, "checkout"]
        if isRemoteBranch { args += ["-b", branch.replacingOccurrences(of: "origin/", with: ""), branch] }
        else { args.append(branch) }
        _ = try await commandExecutor.execute(tool: "git", arguments: args, stdinData: nil, timeout: 15)
        _isOperating = false
        try await loadBranches(for: rootPath)
    }

    func loadBranches(for rootPath: String) async throws {
        if !isRemote { explorer.refreshGitBranches(); return }
        let localResult = try await commandExecutor.execute(
            tool: "git", arguments: ["-C", rootPath, "for-each-ref", "--format=%(refname:short)\t%(HEAD)", "refs/heads/"], stdinData: nil, timeout: 15
        )
        let remoteResult = try await commandExecutor.execute(
            tool: "git", arguments: ["-C", rootPath, "for-each-ref", "--format=%(refname:short)", "refs/remotes/"], stdinData: nil, timeout: 15
        )
        let local = GitOutputParser.parseLocalBranches(from: String(data: localResult.stdoutData, encoding: .utf8) ?? "")
        let remote = GitOutputParser.parseRemoteBranches(from: String(data: remoteResult.stdoutData, encoding: .utf8) ?? "")
        _branchOptions = GitOutputParser.sortBranches(local + remote).map {
            GitBranchOption(name: $0.name, displayName: $0.displayName, isCurrent: $0.isCurrent, isRemote: $0.isRemote)
        }
        _currentBranchName = _branchOptions.first(where: \.isCurrent)?.name
    }

    func loadDiff(relativePath: String, in rootPath: String) async throws -> String {
        if !isRemote { return "" }
        let result = try await commandExecutor.execute(
            tool: "git", arguments: ["-C", rootPath, "diff", "--", relativePath], stdinData: nil, timeout: 15
        )
        return String(data: result.stdoutData, encoding: .utf8) ?? ""
    }

    func loadHistory(for rootPath: String, scope: GitHistoryScope?) async throws {
        if !isRemote { if let scope { explorer.openGitHistory(scope: scope) }; return }
        _isHistoryLoading = true
        var args = ["-C", rootPath, "log", "--format=\u{1E}%H\u{1F}%h\u{1F}%an\u{1F}%aI\u{1F}%s", "-50"]
        if case .file(let path) = scope { args += ["--", path] }
        let result = try await commandExecutor.execute(tool: "git", arguments: args, stdinData: nil, timeout: 30)
        let entries = GitOutputParser.parseHistoryEntries(from: result.stdoutData)
        _historyEntries = entries.map { GitCommitEntry(hash: $0.hash, shortHash: $0.shortHash, authorName: $0.authorName, authoredDate: $0.authoredDate, subject: $0.subject) }
        _isHistoryLoading = false
    }
}
