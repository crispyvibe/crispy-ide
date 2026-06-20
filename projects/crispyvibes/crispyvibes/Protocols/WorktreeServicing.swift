import Foundation

/// Discovers git worktrees for a vibespace's projects and performs worktree
/// mutations. Concrete implementation: `WorktreeService`. Injected via
/// `AppContainer` so views/coordinators don't shell out to git directly (F055).
protocol WorktreeServicing: Sendable {
    /// Per added project: repo identity (shared git-common-dir) + current
    /// branch; plus every worktree per repository (for clubbing + discovery).
    func probe(paths: [String]) async -> WorktreeProbeResult

    /// Creates a worktree on a new branch. Returns the created path on success,
    /// or an error string on failure.
    func addWorktree(repoRoot: String, worktreePath: String, branch: String) async -> (path: String?, error: String?)

    /// Removes a worktree. Returns nil on success, or the git error text.
    func removeWorktree(path: String, force: Bool) async -> String?
}
