import Foundation

/// Runtime-inferred git worktree info for a project folder. Projects sharing a
/// `commonDir` are worktrees of the same repository and get clubbed together.
struct ProjectWorktreeInfo: Equatable, Sendable {
    let commonDir: String
    let branch: String?
}

/// One worktree of a repository (added or not), from `git worktree list`.
struct WorktreeEntry: Equatable, Identifiable, Sendable {
    let path: String
    let branch: String?
    var id: String { path }
    var displayName: String { branch ?? URL(fileURLWithPath: path).lastPathComponent }
}

/// Result of probing a vibespace's projects: repo identity + branch per added
/// project, and the full worktree list per repository (for clubbing + the
/// "Other worktrees" group).
struct WorktreeProbeResult: Sendable {
    var infoByProject: [String: ProjectWorktreeInfo] = [:]
    var worktreesByCommonDir: [String: [WorktreeEntry]] = [:]
}

/// A unified-sidebar node's backing group: one project, or several worktrees
/// of the same repository clubbed together, plus any of the repo's worktrees
/// that haven't been added as projects yet (F052/F053).
struct UnifiedProjectGroup: Identifiable {
    let id: UUID
    let addedProjects: [AnyProjectSession]
    let title: String
    let otherWorktrees: [WorktreeEntry]
    /// Absolute path of the repo's primary/main worktree (the repo root), used
    /// to forbid deleting the main worktree. Nil for non-repo single projects.
    let primaryPath: String?
}
