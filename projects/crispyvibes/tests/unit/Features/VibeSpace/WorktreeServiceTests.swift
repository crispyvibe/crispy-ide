import Foundation
import XCTest
@testable import CrispyVibes

/// F055: unit coverage for git-worktree porcelain parsing and the worktree
/// service's git wiring (via an injected runner — no real git needed).
@MainActor
final class WorktreeServiceTests: XCTestCase {

    // MARK: - WorktreeParser (pure)

    func testParseParsesPathsAndBranches() {
        let porcelain = """
        worktree /repo/main
        HEAD aaa
        branch refs/heads/main

        worktree /repo/feature
        HEAD bbb
        branch refs/heads/feature/login
        """
        let entries = WorktreeParser.parse(porcelain: porcelain, pathExists: { _ in true })
        XCTAssertEqual(entries.map(\.path), ["/repo/main", "/repo/feature"])
        XCTAssertEqual(entries.map(\.branch), ["main", "feature/login"])
    }

    func testParseSkipsPrunableEntries() {
        let porcelain = """
        worktree /repo/main
        branch refs/heads/main

        worktree /repo/stale
        branch refs/heads/x
        prunable gitdir points to a non-existent location
        """
        let entries = WorktreeParser.parse(porcelain: porcelain, pathExists: { _ in true })
        XCTAssertEqual(entries.map(\.branch), ["main"])
    }

    func testParseDetachedHasNilBranch() {
        let porcelain = "worktree /repo/det\nHEAD abc\ndetached\n"
        let entries = WorktreeParser.parse(porcelain: porcelain, pathExists: { _ in true })
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].branch)
    }

    func testParseSkipsMissingDirectories() {
        let porcelain = "worktree /repo/gone\nbranch refs/heads/x\n"
        let entries = WorktreeParser.parse(porcelain: porcelain, pathExists: { _ in false })
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Canonical (symlink-resolved) path dedup (F056)

    func testParseAppliesCanonicalResolver() {
        let porcelain = "worktree /repo/linked\nbranch refs/heads/feat\n"
        let entries = WorktreeParser.parse(
            porcelain: porcelain,
            pathExists: { _ in true },
            resolve: { _ in "/canonical/real" }
        )
        XCTAssertEqual(entries.first?.path, "/repo/linked")
        XCTAssertEqual(entries.first?.canonicalPath, "/canonical/real")
    }

    func testParseDefaultCanonicalEqualsPathWhenNoSymlinks() {
        let porcelain = "worktree /repo/main\nbranch refs/heads/main\n"
        let entries = WorktreeParser.parse(porcelain: porcelain, pathExists: { _ in true })
        XCTAssertEqual(entries.first?.canonicalPath, entries.first?.path)
    }

    /// A project opened via a symlinked path (`/var/...`) must still dedup
    /// against the resolved real path git reports (`/private/var/...`), so the
    /// active worktree does NOT repeat in "Other worktrees".
    func testNotOpenedDedupsSymlinkedProjectPath() {
        // git reports resolved real paths; parser keeps them (resolve is a no-op here).
        let porcelain = """
        worktree /private/var/repo-main
        branch refs/heads/main

        worktree /private/var/repo-feat
        branch refs/heads/feat
        """
        let entries = WorktreeParser.parse(porcelain: porcelain, pathExists: { _ in true }, resolve: { $0 })

        // Project opened via the symlink form; canonicalized the same way the service does.
        let realByLink = ["/var/repo-main": "/private/var/repo-main"]
        let resolve: (String) -> String = { realByLink[$0] ?? $0 }
        let openedCanonical = Set(["/var/repo-main"].map(resolve))

        let other = WorktreeEntry.notOpened(entries, openedCanonicalPaths: openedCanonical)
        XCTAssertEqual(other.map(\.path), ["/private/var/repo-feat"], "main worktree should be excluded despite symlink form")

        // Regression guard: comparing the raw (non-canonical) path fails to dedup.
        let rawOther = WorktreeEntry.notOpened(entries, openedCanonicalPaths: ["/var/repo-main"])
        XCTAssertEqual(rawOther.count, 2, "raw path compare would repeat the active worktree")
    }

    /// On a case-insensitive APFS volume, a worktree opened with different
    /// casing than git reports must still dedup out of "Other worktrees".
    func testNotOpenedDedupsCaseInsensitively() {
        let porcelain = "worktree /private/var/Repo-Main\nbranch refs/heads/main\n"
        let entries = WorktreeParser.parse(porcelain: porcelain, pathExists: { _ in true }, resolve: { $0 })
        let opened = Set(["/private/var/repo-main"]) // lower-cased form
        let other = WorktreeEntry.notOpened(entries, openedCanonicalPaths: opened)
        XCTAssertTrue(other.isEmpty, "case-only path difference must still dedup")
    }

    // MARK: - WorktreeService (injected git runner)

    func testProbeBuildsWorktreeRootPlacement() async {
        let tempDir = NSTemporaryDirectory() + "wt-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let runner: WorktreeService.GitRunner = { args in
            func ok(_ s: String) -> (Int32, Data, Data) { (0, Data(s.utf8), Data()) }
            if args.contains("--git-common-dir") { return ok("/repo/.git") }
            if args.contains("--show-toplevel") { return ok(tempDir) }
            if args.contains("list") { return ok("worktree \(tempDir)\nbranch refs/heads/main\n") }
            return (1, Data(), Data())
        }

        let result = await WorktreeService(runGit: runner).probe(paths: [tempDir])
        let placement = result.placementByProject[tempDir]
        XCTAssertEqual(placement?.commonDir, "/repo/.git")
        XCTAssertEqual(placement?.worktreeRoot, WorktreeParser.resolveCanonical(tempDir))
        XCTAssertEqual(placement?.relativeSubpath, "")
        XCTAssertEqual(placement?.isWorktreeRoot, true)
        XCTAssertEqual(result.worktreesByCommonDir["/repo/.git"]?.count, 1)
    }

    /// The reported bug: a subdirectory opened as its own project shares the
    /// repo's common-dir and branch, but is NOT the worktree root, so it must
    /// be flagged `isWorktreeRoot == false` (→ standalone node, no duplicate
    /// branch-labeled worktree, not counted among the repo's worktrees).
    func testProbeSubdirectoryProjectIsNotWorktreeRoot() async {
        let root = NSTemporaryDirectory() + "wt-\(UUID().uuidString)"
        let sub = root + "/book-manuscript"
        try? FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let runner: WorktreeService.GitRunner = { args in
            func ok(_ s: String) -> (Int32, Data, Data) { (0, Data(s.utf8), Data()) }
            if args.contains("--git-common-dir") { return ok("/repo/.git") }
            // git reports the containing worktree root for a subdirectory.
            if args.contains("--show-toplevel") { return ok(root) }
            if args.contains("list") { return ok("worktree \(root)\nbranch refs/heads/whiteboard\n") }
            return (1, Data(), Data())
        }

        let result = await WorktreeService(runGit: runner).probe(paths: [sub])
        let placement = result.placementByProject[sub]
        XCTAssertEqual(placement?.worktreeRoot, WorktreeParser.resolveCanonical(root))
        XCTAssertEqual(placement?.relativeSubpath, "book-manuscript")
        XCTAssertEqual(placement?.isWorktreeRoot, false, "a subdirectory project must not be treated as a worktree root")
    }

    func testProbeSkipsProjectsThatAreNotGitRepos() async {
        // No --show-toplevel (rev-parse fails outside a repo) → no placement.
        let runner: WorktreeService.GitRunner = { args in
            if args.contains("--git-common-dir") { return (0, Data("/repo/.git".utf8), Data()) }
            return (128, Data(), Data("fatal: not a git repository".utf8))
        }
        let result = await WorktreeService(runGit: runner).probe(paths: ["/tmp/plain-folder"])
        XCTAssertTrue(result.placementByProject.isEmpty)
    }

    func testProbeSkipsSSHPaths() async {
        let result = await WorktreeService(runGit: { _ in (0, Data(), Data()) })
            .probe(paths: ["ssh://host/repo"])
        XCTAssertTrue(result.placementByProject.isEmpty)
    }

    func testAddWorktreeSuccessReturnsPath() async {
        let result = await WorktreeService(runGit: { _ in (0, Data(), Data()) })
            .addWorktree(repoRoot: "/repo", worktreePath: "/repo-feat", branch: "feat")
        XCTAssertEqual(result.path, "/repo-feat")
        XCTAssertNil(result.error)
    }

    func testAddWorktreeFailureReturnsStderr() async {
        let runner: WorktreeService.GitRunner = { _ in (1, Data(), Data("fatal: already exists".utf8)) }
        let result = await WorktreeService(runGit: runner).addWorktree(repoRoot: "/repo", worktreePath: "/x", branch: "b")
        XCTAssertNil(result.path)
        XCTAssertEqual(result.error, "fatal: already exists")
    }

    func testRemoveWorktreeFailureReturnsStderr() async {
        let runner: WorktreeService.GitRunner = { args in
            if args.contains("--git-common-dir") { return (0, Data("/repo/.git".utf8), Data()) }
            return (1, Data(), Data("fatal: contains modified or untracked files".utf8))
        }
        let error = await WorktreeService(runGit: runner).removeWorktree(path: "/repo-feat", force: false)
        XCTAssertEqual(error, "fatal: contains modified or untracked files")
    }

    func testRemoveWorktreeSuccessReturnsNil() async {
        let runner: WorktreeService.GitRunner = { args in
            if args.contains("--git-common-dir") { return (0, Data("/repo/.git".utf8), Data()) }
            return (0, Data(), Data())
        }
        let error = await WorktreeService(runGit: runner).removeWorktree(path: "/repo-feat", force: true)
        XCTAssertNil(error)
    }
}
