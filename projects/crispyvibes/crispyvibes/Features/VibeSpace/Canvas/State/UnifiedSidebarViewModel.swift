import Foundation

/// F053: mediates the unified sidebar's data + git-worktree/conversation IO so
/// the views never call services directly. Owns the worktree probe results and
/// per-project conversation threads; the panel observes its published state.
@MainActor
final class UnifiedSidebarViewModel: ObservableObject {
    @Published private(set) var worktreeInfoByProject: [String: ProjectWorktreeInfo] = [:]
    @Published private(set) var worktreesByCommonDir: [String: [WorktreeEntry]] = [:]
    @Published private(set) var threadsByProject: [String: [ConversationThreadSummary]] = [:]

    private var worktreeService: (any WorktreeServicing)?
    private weak var conversationStore: AgentConversationStore?

    /// Injects dependencies once (called from the view's `.task`; the view owns
    /// the VM via `@StateObject` so it can't pass these through `init`).
    func configure(worktreeService: any WorktreeServicing, conversationStore: AgentConversationStore) {
        if self.worktreeService == nil { self.worktreeService = worktreeService }
        if self.conversationStore == nil { self.conversationStore = conversationStore }
    }

    /// Reloads conversation threads + git worktree discovery for the vibespace.
    func reload(projectPaths: [String], vibespaceID: UUID?) async {
        await loadThreads(vibespaceID: vibespaceID)
        guard let worktreeService else { return }
        let probe = await worktreeService.probe(paths: projectPaths)
        worktreeInfoByProject = probe.infoByProject
        worktreesByCommonDir = probe.worktreesByCommonDir
    }

    /// Creates a worktree on a new branch. Returns the created path or an error.
    func addWorktree(repoRoot: String, worktreePath: String, branch: String) async -> (path: String?, error: String?) {
        guard let worktreeService else { return (nil, "Worktree service unavailable.") }
        return await worktreeService.addWorktree(repoRoot: repoRoot, worktreePath: worktreePath, branch: branch)
    }

    /// Removes a worktree. Returns nil on success, or the git error text.
    func removeWorktree(path: String, force: Bool) async -> String? {
        guard let worktreeService else { return "Worktree service unavailable." }
        return await worktreeService.removeWorktree(path: path, force: force)
    }

    private func loadThreads(vibespaceID: UUID?) async {
        guard let store = conversationStore, case .ready = store.state else { return }
        var params: [String: Any] = ["limit": 200]
        if let vibespaceID { params["vibespaceId"] = vibespaceID.uuidString }
        let result = await store.send(method: "thread.list", params: params)
        guard let list = result?.value?["threads"] as? [[String: Any]] else {
            threadsByProject = [:]
            return
        }
        let summaries = list.compactMap { ConversationThreadSummary(json: $0) }
        threadsByProject = Dictionary(grouping: summaries) {
            VibeSpaceState.normalizedPath(from: $0.projectPath)
        }
    }
}
