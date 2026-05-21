// GitExploring.swift — SSH Remote Development

import Combine
import Foundation

/// Abstraction over git operations for a project.
/// Both local and remote use the same GitOutputParser; only the CommandExecuting differs.
@MainActor
protocol GitExploring: ObservableObject {
    var commandExecutor: any CommandExecuting { get }
    var isAvailable: Bool { get }
    var statusItems: [GitStatusItem] { get }
    var branchOptions: [GitBranchOption] { get }
    var currentBranchName: String? { get }
    var gitState: FolderExplorerViewModel.GitState { get }
    var commitMessageDraft: String { get set }
    var isOperating: Bool { get }
    var operationMessage: String? { get }
    var historyEntries: [GitCommitEntry] { get }
    var isHistoryLoading: Bool { get }
    var activeHistoryScope: GitHistoryScope? { get set }

    func discoverRepositories(at rootPath: String) async throws -> WorkerGitRepositoryDiscoveryPayload
    func loadStatus(for rootPath: String) async throws
    func stage(files: [String], in rootPath: String) async throws
    func unstage(files: [String], in rootPath: String) async throws
    func commit(message: String, in rootPath: String) async throws
    func checkout(branch: String, isRemoteBranch: Bool, in rootPath: String) async throws
    func loadBranches(for rootPath: String) async throws
    func loadDiff(relativePath: String, in rootPath: String) async throws -> String
    func loadHistory(for rootPath: String, scope: GitHistoryScope?) async throws
}
