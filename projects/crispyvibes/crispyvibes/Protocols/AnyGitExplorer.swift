// AnyGitExplorer.swift — SSH Remote Development
// Type-erased wrapper for GitExploring. Forwards objectWillChange for SwiftUI.

import Combine
import Foundation

@MainActor
final class AnyGitExplorer: ObservableObject {
    private let _wrapped: any GitExploring
    private var cancellables = Set<AnyCancellable>()

    init<T: GitExploring>(_ explorer: T) {
        self._wrapped = explorer
        explorer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var commandExecutor: any CommandExecuting { _wrapped.commandExecutor }
    var isAvailable: Bool { _wrapped.isAvailable }
    var statusItems: [GitStatusItem] { _wrapped.statusItems }
    var branchOptions: [GitBranchOption] { _wrapped.branchOptions }
    var currentBranchName: String? { _wrapped.currentBranchName }
    var gitState: FolderExplorerViewModel.GitState { _wrapped.gitState }
    var commitMessageDraft: String {
        get { _wrapped.commitMessageDraft }
        set { _wrapped.commitMessageDraft = newValue }
    }
    var isOperating: Bool { _wrapped.isOperating }
    var operationMessage: String? { _wrapped.operationMessage }
    var historyEntries: [GitCommitEntry] { _wrapped.historyEntries }
    var isHistoryLoading: Bool { _wrapped.isHistoryLoading }
    var activeHistoryScope: GitHistoryScope? {
        get { _wrapped.activeHistoryScope }
        set { _wrapped.activeHistoryScope = newValue }
    }

    func discoverRepositories(at rootPath: String) async throws -> WorkerGitRepositoryDiscoveryPayload {
        try await _wrapped.discoverRepositories(at: rootPath)
    }
    func loadStatus(for rootPath: String) async throws { try await _wrapped.loadStatus(for: rootPath) }
    func stage(files: [String], in rootPath: String) async throws { try await _wrapped.stage(files: files, in: rootPath) }
    func unstage(files: [String], in rootPath: String) async throws { try await _wrapped.unstage(files: files, in: rootPath) }
    func commit(message: String, in rootPath: String) async throws { try await _wrapped.commit(message: message, in: rootPath) }
    func checkout(branch: String, isRemoteBranch: Bool, in rootPath: String) async throws {
        try await _wrapped.checkout(branch: branch, isRemoteBranch: isRemoteBranch, in: rootPath)
    }
    func loadBranches(for rootPath: String) async throws { try await _wrapped.loadBranches(for: rootPath) }
    func loadDiff(relativePath: String, in rootPath: String) async throws -> String {
        try await _wrapped.loadDiff(relativePath: relativePath, in: rootPath)
    }
    func loadHistory(for rootPath: String, scope: GitHistoryScope?) async throws {
        try await _wrapped.loadHistory(for: rootPath, scope: scope)
    }
}
