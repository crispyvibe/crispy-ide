import Foundation
import XCTest
@testable import CrispyVibes

/// F052: unit coverage for git-worktree porcelain parsing and the worktree
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

    // MARK: - WorktreeService (injected git runner)

    func testProbeResolvesCommonDirAndBranch() async {
        let tempDir = NSTemporaryDirectory() + "wt-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let runner: WorktreeService.GitRunner = { args in
            func ok(_ s: String) -> (Int32, Data, Data) { (0, Data(s.utf8), Data()) }
            if args.contains("--git-common-dir") { return ok("/repo/.git") }
            if args.contains("--abbrev-ref") { return ok("main") }
            if args.contains("list") { return ok("worktree \(tempDir)\nbranch refs/heads/main\n") }
            return (1, Data(), Data())
        }

        let result = await WorktreeService(runGit: runner).probe(paths: ["/repo"])
        XCTAssertEqual(result.infoByProject["/repo"]?.commonDir, "/repo/.git")
        XCTAssertEqual(result.infoByProject["/repo"]?.branch, "main")
        XCTAssertEqual(result.worktreesByCommonDir["/repo/.git"]?.count, 1)
    }

    func testProbeSkipsSSHPaths() async {
        let result = await WorktreeService(runGit: { _ in (0, Data(), Data()) })
            .probe(paths: ["ssh://host/repo"])
        XCTAssertTrue(result.infoByProject.isEmpty)
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
