import Foundation

/// Pure, testable parsing of `git worktree list --porcelain` output. Kept
/// separate from IO so it can be unit-tested without git.
enum WorktreeParser {
    /// Parses porcelain output into worktree entries, skipping prunable ones
    /// and (via `pathExists`) worktrees whose directory is gone.
    static func parse(
        porcelain: String,
        pathExists: (String) -> Bool = WorktreeParser.directoryExists,
        resolve: (String) -> String = WorktreeParser.resolveCanonical
    ) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var currentPath: String?
        var currentBranch: String?
        var prunable = false

        func flush() {
            defer { currentPath = nil; currentBranch = nil; prunable = false }
            guard let raw = currentPath, !prunable else { return }
            let normalized = URL(fileURLWithPath: raw).standardizedFileURL.path
            guard pathExists(normalized) else { return }
            entries.append(WorktreeEntry(path: normalized, branch: currentBranch, canonicalPath: resolve(normalized)))
        }

        for rawLine in porcelain.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                flush()
                currentPath = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                currentBranch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "detached" {
                currentBranch = nil
            } else if line.hasPrefix("prunable") {
                prunable = true
            } else if line.isEmpty {
                flush()
            }
        }
        flush()
        return entries
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Symlink-resolved, standardized real path — matches the path git reports
    /// for a worktree even when the project was opened via a symlinked path.
    /// Touches the filesystem, so it runs in the service (off the main actor),
    /// never in a SwiftUI body.
    static func resolveCanonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// Git-backed `WorktreeServicing`. Git IO goes through an injectable `runGit`
/// closure (defaults to `PaneWorkerExecutor`); porcelain parsing is the pure
/// `WorktreeParser`. Runs off the main actor.
struct WorktreeService: WorktreeServicing {
    /// Runs a git command → (status, stdout, stderr), or nil if it couldn't
    /// run. Injectable so tests can supply canned git output.
    typealias GitRunner = @Sendable ([String]) -> (status: Int32, stdout: Data, stderr: Data)?

    private let runGit: GitRunner

    init(runGit: @escaping GitRunner = WorktreeService.defaultRunGit) {
        self.runGit = runGit
    }

    static let defaultRunGit: GitRunner = { args in
        guard let result = try? PaneWorkerExecutor.runGitCommand(arguments: args) else { return nil }
        return (result.terminationStatus, result.stdoutData, result.stderrData)
    }

    func probe(paths: [String]) async -> WorktreeProbeResult {
        let run = runGit
        return await Task.detached(priority: .utility) {
            var result = WorktreeProbeResult()
            for path in paths where !path.hasPrefix("ssh://") {
                guard let common = Self.output(run, ["-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"]),
                      let topLevel = Self.output(run, ["-C", path, "rev-parse", "--show-toplevel"]) else {
                    continue
                }
                let commonDir = URL(fileURLWithPath: common).standardizedFileURL.path
                // The worktree this project lives in (its root), resolved the
                // same way porcelain paths are so identity matching is robust.
                let worktreeRoot = WorktreeParser.resolveCanonical(topLevel)
                let projectCanonical = WorktreeParser.resolveCanonical(path)
                result.placementByProject[path] = ProjectGitPlacement(
                    commonDir: commonDir,
                    worktreeRoot: worktreeRoot,
                    relativeSubpath: Self.relativeSubpath(root: worktreeRoot, project: projectCanonical)
                )
                if result.worktreesByCommonDir[commonDir] == nil,
                   let list = Self.output(run, ["-C", path, "worktree", "list", "--porcelain"]) {
                    result.worktreesByCommonDir[commonDir] = WorktreeParser.parse(porcelain: list)
                }
            }
            return result
        }.value
    }

    /// Path of `project` relative to its worktree `root` (both canonical), or
    /// "" when the project IS the worktree root. Comparison is case-insensitive
    /// because the default macOS APFS volume is case-insensitive (git-reported
    /// and on-disk casing can differ). Anomalous non-descendant paths fall back
    /// to the project's own folder name so they stay standalone rather than
    /// masquerading as a worktree root.
    private static func relativeSubpath(root: String, project: String) -> String {
        if project.compare(root, options: .caseInsensitive) == .orderedSame { return "" }
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        if project.range(of: rootPrefix, options: [.caseInsensitive, .anchored]) != nil {
            return String(project.dropFirst(rootPrefix.count))
        }
        return URL(fileURLWithPath: project).lastPathComponent
    }

    func addWorktree(repoRoot: String, worktreePath: String, branch: String) async -> (path: String?, error: String?) {
        let run = runGit
        return await Task.detached(priority: .userInitiated) {
            guard let result = run(["-C", repoRoot, "worktree", "add", "-b", branch, worktreePath]) else {
                return (nil, "git failed to run.")
            }
            if result.status == 0 {
                return (URL(fileURLWithPath: worktreePath).standardizedFileURL.path, nil)
            }
            return (nil, Self.errorText(result.stderr) ?? "git worktree add failed.")
        }.value
    }

    func removeWorktree(path: String, force: Bool) async -> String? {
        let run = runGit
        return await Task.detached(priority: .userInitiated) {
            guard let common = Self.output(run, ["-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"]) else {
                return "Not a git worktree."
            }
            let mainRoot = URL(fileURLWithPath: common).standardizedFileURL.deletingLastPathComponent().path
            var args = ["-C", mainRoot, "worktree", "remove"]
            if force { args.append("--force") }
            args.append(path)
            guard let result = run(args) else { return "git failed to run." }
            if result.status == 0 { return nil }
            return Self.errorText(result.stderr) ?? "git worktree remove failed."
        }.value
    }

    private static func output(_ run: GitRunner, _ args: [String]) -> String? {
        guard let result = run(args), result.status == 0,
              let text = String(data: result.stdout, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func errorText(_ data: Data) -> String? {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }
}
