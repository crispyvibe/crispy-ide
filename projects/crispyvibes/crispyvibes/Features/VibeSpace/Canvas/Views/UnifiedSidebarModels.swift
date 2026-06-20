import Foundation

/// Where an opened project sits in git: which repository (`commonDir`), which
/// worktree (`worktreeRoot`, the symlink-resolved `--show-toplevel`), and where
/// inside that worktree the project folder is (`relativeSubpath`, empty when
/// the project IS the worktree root).
///
/// This is the unit of identity for the unified sidebar: a project is treated
/// as a worktree only when `isWorktreeRoot`. A subdirectory opened as its own
/// project shares the repo's `commonDir` but is NOT a worktree, so it must not
/// be clubbed with — or mislabeled as — the worktree it lives in. The branch is
/// intentionally absent here: it is read from the authoritative porcelain
/// `WorktreeEntry` for `worktreeRoot`, never from a separate per-project query.
struct ProjectGitPlacement: Equatable, Sendable {
    let commonDir: String
    let worktreeRoot: String
    let relativeSubpath: String

    /// True when the opened project folder is exactly the worktree's root.
    var isWorktreeRoot: Bool { relativeSubpath.isEmpty }
}

/// One worktree of a repository (added or not), from `git worktree list`.
struct WorktreeEntry: Equatable, Identifiable, Sendable {
    let path: String
    let branch: String?
    /// Symlink-resolved real path used for identity matching (dedup against
    /// opened projects). Equals `path` when no path component is a symlink.
    /// Resolved once in the service/parser — never in the SwiftUI render path.
    let canonicalPath: String
    var id: String { path }
    var displayName: String { branch ?? URL(fileURLWithPath: path).lastPathComponent }

    init(path: String, branch: String?, canonicalPath: String? = nil) {
        self.path = path
        self.branch = branch
        self.canonicalPath = canonicalPath ?? path
    }

    /// Filters `entries` down to worktrees that are NOT opened as projects,
    /// matching by canonical (symlink-resolved) path so a project opened via a
    /// symlinked path still dedups against its git-reported real path. Matching
    /// is case-insensitive to match the default case-insensitive APFS volume
    /// (git-reported and on-disk casing can differ). Pure.
    static func notOpened(_ entries: [WorktreeEntry], openedCanonicalPaths: Set<String>) -> [WorktreeEntry] {
        let opened = Set(openedCanonicalPaths.map { $0.lowercased() })
        return entries.filter { !opened.contains($0.canonicalPath.lowercased()) }
    }
}

/// Result of probing a vibespace's projects: each opened project's git
/// placement (repo + worktree + subpath) and the full worktree list per
/// repository (the source of truth for branches, clubbing, and the "Other
/// worktrees" group).
struct WorktreeProbeResult: Sendable {
    var placementByProject: [String: ProjectGitPlacement] = [:]
    var worktreesByCommonDir: [String: [WorktreeEntry]] = [:]
}

/// A unified-sidebar node's backing group: one project, or several worktrees
/// of the same repository clubbed together, plus any of the repo's worktrees
/// that haven't been added as projects yet (F055/F056).
struct UnifiedProjectGroup: Identifiable {
    let id: UUID
    let addedProjects: [AnyProjectSession]
    let title: String
    let otherWorktrees: [WorktreeEntry]
    /// Absolute path of the repo's primary/main worktree (the repo root), used
    /// to forbid deleting the main worktree. Nil for non-repo single projects.
    let primaryPath: String?
}
