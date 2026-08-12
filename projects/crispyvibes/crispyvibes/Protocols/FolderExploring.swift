// FolderExploring.swift — SSH Remote Development

import Combine
import Foundation

/// Abstraction over the file explorer sidebar.
/// Local: backed by FolderExplorerViewModel (existing). Remote: backed by RemoteFolderExplorer (SFTP).
/// Views consume this protocol via AnyFolderExplorer type-erased wrapper.
@MainActor
protocol FolderExploring: ObservableObject {

    // MARK: - Tree State

    var rootURL: URL? { get }
    var rootItems: [FileItem] { get }
    var displayedItems: [FileItem] { get }
    var activeSidebarTab: FolderExplorerViewModel.SidebarTab { get set }
    var expandedDirectoryIDs: Set<String> { get set }
    var searchQuery: String { get set }
    var selectedItemID: String? { get set }
    var selectedFileURL: URL? { get set }
    var selectedFolderURL: URL? { get set }
    var openRequest: ExplorerOpenRequest? { get set }
    var renamingItemID: String? { get set }
    var renameText: String { get set }
    var userFacingError: String? { get set }
    var workerStatus: PaneWorkerStatus { get }
    var loadingDirectoryIDs: Set<String> { get }
    var changedDirectoryIDs: Set<String> { get }
    var treeMutationRevision: Int { get }

    /// false for remote → views show a manual refresh button instead of live updates.
    var supportsLiveWatching: Bool { get }

    /// false when drag payloads cannot safely prove project and host identity.
    var supportsFileTransfers: Bool { get }

    // MARK: - Git State

    var gitStatusItems: [GitStatusItem] { get }
    var gitBranchOptions: [GitBranchOption] { get }
    var gitCurrentBranchName: String? { get }
    var gitState: FolderExplorerViewModel.GitState { get }
    var gitMessage: String? { get }
    var gitCommitMessageDraft: String { get set }
    var gitIsOperating: Bool { get }
    var gitOperationMessage: String? { get }
    var gitHistoryEntries: [GitCommitEntry] { get }
    var gitActiveHistoryScope: GitHistoryScope? { get set }
    var gitHistoryIsLoading: Bool { get }

    // MARK: - Events

    var renameEvents: PassthroughSubject<ExplorerRenameEvent, Never> { get }
    var observedFileSystemChanges: PassthroughSubject<Set<String>, Never> { get }

    // MARK: - Tree Operations

    func setRootFolder(_ url: URL)
    func refreshTree(trigger: FolderExplorerViewModel.TreeRefreshTrigger)
    func toggleExpansion(for item: FileItem)
    func isDirectoryLoading(_ directoryID: String) -> Bool

    // MARK: - File Operations

    func createNewFile(in item: FileItem?)
    func createNewFolder(in item: FileItem?)
    func createNewFileAtSelection()
    func createNewFolderAtSelection()
    func deleteItem(_ item: FileItem)
    func startRenaming(item: FileItem)
    func startRenamingSelectedItem()
    func commitRename()
    func cancelRename()
    func clearError()

    // MARK: - Selection

    func select(_ item: FileItem)
    func openInTab(_ item: FileItem)
    func openInWindow(_ item: FileItem)
    func openInSplitHorizontal(_ item: FileItem)
    func openInSplitVertical(_ item: FileItem)
    func selectGitStatusItem(_ item: GitStatusItem)

    // MARK: - Git Operations

    func stageGitItem(_ item: GitStatusItem)
    func unstageGitItem(_ item: GitStatusItem)
    func stageAllGitChanges()
    func commitGitChanges()
    func pushGitChanges()
    func checkoutGitBranch(_ branch: GitBranchOption)
    func refreshGitStatus()
    func refreshGitBranches()
    func openGitHistory(scope: GitHistoryScope)
    func dismissGitHistory()

    // MARK: - Transfer

    func transferItems(using plans: [ExplorerItemTransferPlan])
}
