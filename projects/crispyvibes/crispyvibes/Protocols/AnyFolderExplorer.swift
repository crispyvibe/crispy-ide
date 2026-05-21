// AnyFolderExplorer.swift — SSH Remote Development
// Type-erased wrapper for FolderExploring. Forwards objectWillChange for SwiftUI.

import Combine
import Foundation

@MainActor
final class AnyFolderExplorer: ObservableObject {
    private let _wrapped: any FolderExploring
    private var cancellables = Set<AnyCancellable>()

    init<T: FolderExploring>(_ explorer: T) {
        self._wrapped = explorer
        explorer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - State

    var rootURL: URL? { _wrapped.rootURL }
    var rootItems: [FileItem] { _wrapped.rootItems }
    var displayedItems: [FileItem] { _wrapped.displayedItems }
    var activeSidebarTab: FolderExplorerViewModel.SidebarTab {
        get { _wrapped.activeSidebarTab }
        set { _wrapped.activeSidebarTab = newValue }
    }
    var expandedDirectoryIDs: Set<String> {
        get { _wrapped.expandedDirectoryIDs }
        set { _wrapped.expandedDirectoryIDs = newValue }
    }
    var searchQuery: String {
        get { _wrapped.searchQuery }
        set { _wrapped.searchQuery = newValue }
    }
    var selectedItemID: String? {
        get { _wrapped.selectedItemID }
        set { _wrapped.selectedItemID = newValue }
    }
    var selectedFileURL: URL? {
        get { _wrapped.selectedFileURL }
        set { _wrapped.selectedFileURL = newValue }
    }
    var selectedFolderURL: URL? {
        get { _wrapped.selectedFolderURL }
        set { _wrapped.selectedFolderURL = newValue }
    }
    var openRequest: ExplorerOpenRequest? {
        get { _wrapped.openRequest }
        set { _wrapped.openRequest = newValue }
    }
    var renamingItemID: String? {
        get { _wrapped.renamingItemID }
        set { _wrapped.renamingItemID = newValue }
    }
    var renameText: String {
        get { _wrapped.renameText }
        set { _wrapped.renameText = newValue }
    }
    var userFacingError: String? {
        get { _wrapped.userFacingError }
        set { _wrapped.userFacingError = newValue }
    }
    var workerStatus: PaneWorkerStatus { _wrapped.workerStatus }
    var loadingDirectoryIDs: Set<String> { _wrapped.loadingDirectoryIDs }
    var changedDirectoryIDs: Set<String> { _wrapped.changedDirectoryIDs }
    var treeMutationRevision: Int { _wrapped.treeMutationRevision }
    var supportsLiveWatching: Bool { _wrapped.supportsLiveWatching }

    // MARK: - Git State

    var gitStatusItems: [GitStatusItem] { _wrapped.gitStatusItems }
    var gitBranchOptions: [GitBranchOption] { _wrapped.gitBranchOptions }
    var gitCurrentBranchName: String? { _wrapped.gitCurrentBranchName }
    var gitState: FolderExplorerViewModel.GitState { _wrapped.gitState }
    var gitMessage: String? { _wrapped.gitMessage }
    var gitCommitMessageDraft: String {
        get { _wrapped.gitCommitMessageDraft }
        set { _wrapped.gitCommitMessageDraft = newValue }
    }
    var gitIsOperating: Bool { _wrapped.gitIsOperating }
    var gitOperationMessage: String? { _wrapped.gitOperationMessage }
    var gitHistoryEntries: [GitCommitEntry] { _wrapped.gitHistoryEntries }
    var gitActiveHistoryScope: GitHistoryScope? {
        get { _wrapped.gitActiveHistoryScope }
        set { _wrapped.gitActiveHistoryScope = newValue }
    }
    var gitHistoryIsLoading: Bool { _wrapped.gitHistoryIsLoading }

    // MARK: - Events

    var renameEvents: PassthroughSubject<ExplorerRenameEvent, Never> { _wrapped.renameEvents }
    var observedFileSystemChanges: PassthroughSubject<Set<String>, Never> { _wrapped.observedFileSystemChanges }

    // MARK: - Tree Operations

    func setRootFolder(_ url: URL) { _wrapped.setRootFolder(url) }
    func refreshTree(trigger: FolderExplorerViewModel.TreeRefreshTrigger) { _wrapped.refreshTree(trigger: trigger) }
    func toggleExpansion(for item: FileItem) { _wrapped.toggleExpansion(for: item) }
    func isDirectoryLoading(_ directoryID: String) -> Bool { _wrapped.isDirectoryLoading(directoryID) }

    // MARK: - File Operations

    func createNewFile(in item: FileItem?) { _wrapped.createNewFile(in: item) }
    func createNewFolder(in item: FileItem?) { _wrapped.createNewFolder(in: item) }
    func createNewFileAtSelection() { _wrapped.createNewFileAtSelection() }
    func createNewFolderAtSelection() { _wrapped.createNewFolderAtSelection() }
    func deleteItem(_ item: FileItem) { _wrapped.deleteItem(item) }
    func startRenaming(item: FileItem) { _wrapped.startRenaming(item: item) }
    func startRenamingSelectedItem() { _wrapped.startRenamingSelectedItem() }
    func commitRename() { _wrapped.commitRename() }
    func cancelRename() { _wrapped.cancelRename() }
    func clearError() { _wrapped.clearError() }

    // MARK: - Selection

    func select(_ item: FileItem) { _wrapped.select(item) }
    func openInTab(_ item: FileItem) { _wrapped.openInTab(item) }
    func openInWindow(_ item: FileItem) { _wrapped.openInWindow(item) }
    func openInSplitHorizontal(_ item: FileItem) { _wrapped.openInSplitHorizontal(item) }
    func openInSplitVertical(_ item: FileItem) { _wrapped.openInSplitVertical(item) }
    func selectGitStatusItem(_ item: GitStatusItem) { _wrapped.selectGitStatusItem(item) }

    // MARK: - Git Operations

    func stageGitItem(_ item: GitStatusItem) { _wrapped.stageGitItem(item) }
    func unstageGitItem(_ item: GitStatusItem) { _wrapped.unstageGitItem(item) }
    func stageAllGitChanges() { _wrapped.stageAllGitChanges() }
    func commitGitChanges() { _wrapped.commitGitChanges() }
    func pushGitChanges() { _wrapped.pushGitChanges() }
    func checkoutGitBranch(_ branch: GitBranchOption) { _wrapped.checkoutGitBranch(branch) }
    func refreshGitStatus() { _wrapped.refreshGitStatus() }
    func refreshGitBranches() { _wrapped.refreshGitBranches() }
    func openGitHistory(scope: GitHistoryScope) { _wrapped.openGitHistory(scope: scope) }
    func dismissGitHistory() { _wrapped.dismissGitHistory() }

    // MARK: - Transfer

    func transferItems(using plans: [ExplorerItemTransferPlan]) { _wrapped.transferItems(using: plans) }
}
