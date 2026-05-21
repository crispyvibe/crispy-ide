import AppKit
import Darwin
import Foundation
import XCTest
@testable import CrispyVibes

final class PaneWorkerExecutorTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-worker-unit")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testPingForAllWorkerKindsReturnsValue() {
        for pane in [PaneWorkerKind.explorer, .sourceControl, .editor, .terminal] {
            let response = PaneWorkerExecutor.execute(
                pane: pane,
                request: PaneWorkerRequest(method: .ping, arguments: [:])
            )
            XCTAssertTrue(response.success)
            XCTAssertNotNil(response.value)
        }
    }

    func testListTreeSortsAndIncludesHiddenItems() throws {
        let folderA = tempRoot.appendingPathComponent("afolder", isDirectory: true)
        let folderB = tempRoot.appendingPathComponent("BFolder", isDirectory: true)
        let fileA = tempRoot.appendingPathComponent("a.txt")
        let fileZ = tempRoot.appendingPathComponent("z.txt")
        let hidden = tempRoot.appendingPathComponent(".secret")

        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: fileA)
        try Data("z".utf8).write(to: fileZ)
        try Data("h".utf8).write(to: hidden)

        let response = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(method: .listTree, arguments: ["rootPath": tempRoot.path])
        )
        XCTAssertTrue(response.success)

        let nodes: [WorkerFileNode] = try decodeJSON(response.value)
        let names = nodes.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names, ["afolder", "BFolder", ".secret", "a.txt", "z.txt"])
        XCTAssertTrue(names.contains(".secret"))
        let hiddenNode = try XCTUnwrap(nodes.first(where: { URL(fileURLWithPath: $0.path).lastPathComponent == ".secret" }))
        XCTAssertTrue(hiddenNode.isHidden)
        XCTAssertFalse(hiddenNode.isGitIgnored)
    }

    func testExplorerCreateRenameDeleteWorkflow() throws {
        let createFileResponse = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .createFile,
                arguments: ["directoryPath": tempRoot.path, "name": "note.txt"]
            )
        )
        XCTAssertTrue(createFileResponse.success)
        let createdPath = try XCTUnwrap(createFileResponse.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdPath))

        let createDuplicateResponse = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .createFile,
                arguments: ["directoryPath": tempRoot.path, "name": "note.txt"]
            )
        )
        XCTAssertTrue(createDuplicateResponse.success)
        let duplicatePath = try XCTUnwrap(createDuplicateResponse.value)
        XCTAssertTrue(duplicatePath.hasSuffix("note 1.txt"))

        let renameResponse = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .renameItem,
                arguments: ["itemPath": createdPath, "newName": "renamed.txt"]
            )
        )
        XCTAssertTrue(renameResponse.success)
        let renamedPath = try XCTUnwrap(renameResponse.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdPath))

        let deleteResponse = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .deleteItem,
                arguments: ["itemPath": renamedPath]
            )
        )
        XCTAssertTrue(deleteResponse.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedPath))
    }

    func testExplorerMoveItemMovesFileBetweenDirectories() throws {
        let sourceDirectory = tempRoot.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = tempRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceFile = sourceDirectory.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: sourceFile)

        let response = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .moveItem,
                arguments: [
                    "sourcePath": sourceFile.path,
                    "destinationDirectoryPath": destinationDirectory.path
                ]
            )
        )
        XCTAssertTrue(response.success)
        let movedPath = try XCTUnwrap(response.value)
        XCTAssertEqual(movedPath, destinationDirectory.appendingPathComponent("note.txt").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    func testExplorerCopyItemCopiesFileBetweenDirectories() throws {
        let sourceDirectory = tempRoot.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = tempRoot.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceFile = sourceDirectory.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: sourceFile)

        let response = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .copyItem,
                arguments: [
                    "sourcePath": sourceFile.path,
                    "destinationDirectoryPath": destinationDirectory.path
                ]
            )
        )
        XCTAssertTrue(response.success)
        let copiedPath = try XCTUnwrap(response.value)
        XCTAssertEqual(copiedPath, destinationDirectory.appendingPathComponent("note.txt").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    func testEditorWriteThenReadRoundTrip() throws {
        let fileURL = tempRoot.appendingPathComponent("doc.md")
        let writeResponse = PaneWorkerExecutor.execute(
            pane: .editor,
            request: PaneWorkerRequest(
                method: .writeFile,
                arguments: [
                    "filePath": fileURL.path,
                    "content": "# Hello"
                ]
            )
        )
        XCTAssertTrue(writeResponse.success)

        let readResponse = PaneWorkerExecutor.execute(
            pane: .editor,
            request: PaneWorkerRequest(
                method: .readFile,
                arguments: ["filePath": fileURL.path]
            )
        )
        XCTAssertTrue(readResponse.success)
        XCTAssertEqual(readResponse.value, "# Hello")
    }

    func testGitStatusForNonRepository() throws {
        let response = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(method: .gitStatus, arguments: ["rootPath": tempRoot.path])
        )
        XCTAssertTrue(response.success)
        let payload: WorkerGitStatusPayload = try decodeJSON(response.value)
        if payload.gitAvailable {
            XCTAssertFalse(payload.repository)
            XCTAssertNotNil(payload.message)
        } else {
            XCTAssertFalse(payload.repository)
        }
    }

    func testGitStatusForRepositoryIncludesEntries() throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repo = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: repo)
        try Data("hello".utf8).write(to: repo.appendingPathComponent("tracked.txt"))

        let response = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(method: .gitStatus, arguments: ["rootPath": repo.path])
        )
        XCTAssertTrue(response.success)

        let payload: WorkerGitStatusPayload = try decodeJSON(response.value)
        if !payload.gitAvailable {
            throw XCTSkip("Git command was unavailable at runtime.")
        }

        XCTAssertTrue(payload.repository)
        XCTAssertTrue(payload.entries.contains(where: { $0.relativePath == "tracked.txt" }))
    }

    func testGitRepositorySnapshotReturnsStatusAndBranchState() throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repo = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try initializeGitRepository(at: repo)
        try configureGitIdentity(at: repo)
        let baselineFile = repo.appendingPathComponent("baseline.txt")
        try Data("baseline\n".utf8).write(to: baselineFile)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "baseline.txt"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "initial"], workingDirectory: repo)
        try Data("hello".utf8).write(to: repo.appendingPathComponent("tracked.txt"))

        let response = PaneWorkerExecutor.execute(
            pane: .sourceControl,
            request: PaneWorkerRequest(method: .gitRepositorySnapshot, arguments: ["rootPath": repo.path])
        )
        XCTAssertTrue(response.success)

        let payload: WorkerGitRepositorySnapshotPayload = try decodeJSON(response.value)
        if !payload.gitAvailable {
            throw XCTSkip("Git command was unavailable at runtime.")
        }

        XCTAssertTrue(payload.repository)
        XCTAssertTrue(payload.entries.contains(where: { $0.relativePath == "tracked.txt" }))
        XCTAssertNotNil(payload.currentBranch)
        XCTAssertFalse(payload.branches.isEmpty)
    }

    func testDiscoverGitRepositoriesBatchReturnsPerProjectPayloads() throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        let secondProjectURL = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: secondProjectURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: tempRoot)

        let payload = try PaneWorkerExecutor.discoverGitRepositoriesBatch(
            for: [tempRoot, secondProjectURL]
        )
        let payloadsByPath = Dictionary(uniqueKeysWithValues: payload.results.map { ($0.projectRootPath, $0.payload) })

        XCTAssertEqual(payload.results.count, 2)
        XCTAssertTrue(payloadsByPath[tempRoot.standardizedFileURL.path]?.repositories.contains(where: {
            $0.repositoryRootPath == tempRoot.standardizedFileURL.path
        }) == true)
        XCTAssertEqual(
            payloadsByPath[secondProjectURL.standardizedFileURL.path]?.repositories.first?.repositoryRootPath,
            tempRoot.standardizedFileURL.path
        )
    }

    func testGitBranchPayloadAndCheckoutFlow() throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repo = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "unit@test.local"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Unit Test"], workingDirectory: repo)
        try Data("base\n".utf8).write(to: repo.appendingPathComponent("tracked.txt"))
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "tracked.txt"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "initial"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "checkout", "-b", "feature/unit-branch"], workingDirectory: repo)

        let payload = try PaneWorkerExecutor.loadGitBranches(for: repo)
        XCTAssertTrue(payload.gitAvailable)
        XCTAssertTrue(payload.repository)
        XCTAssertTrue(payload.branches.contains(where: { $0.name == "feature/unit-branch" }))

        try PaneWorkerExecutor.checkoutGitBranch(for: repo, branch: "feature/unit-branch", isRemote: false)
        let selectedBranch = PaneWorkerExecutor.resolveCurrentBranchName(rootURL: repo)
        XCTAssertEqual(selectedBranch, "feature/unit-branch")
    }

    func testGitCloneRepositoryClonesIntoDestinationDirectoryAndReturnsPath() throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repositoryRoot = tempRoot.appendingPathComponent("origin", isDirectory: true)
        let cloneParent = tempRoot.appendingPathComponent("clones", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloneParent, withIntermediateDirectories: true)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: repositoryRoot)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "unit@test.local"], workingDirectory: repositoryRoot)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Unit Test"], workingDirectory: repositoryRoot)
        try Data("hello\n".utf8).write(to: repositoryRoot.appendingPathComponent("README.md"))
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "README.md"], workingDirectory: repositoryRoot)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "initial"], workingDirectory: repositoryRoot)

        let response = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .gitCloneRepository,
                arguments: [
                    "repositoryURL": repositoryRoot.path,
                    "destinationParentPath": cloneParent.path,
                    "directoryName": "cloned-origin"
                ]
            )
        )
        XCTAssertTrue(response.success)
        let clonedPath = try XCTUnwrap(response.value)
        let clonedURL = URL(fileURLWithPath: clonedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clonedURL.appendingPathComponent(".git").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clonedURL.appendingPathComponent("README.md").path))
    }

    func testDecodeGitHubRepositoryNodesBuildsCloneURLsAndSortsByRecentUpdate() throws {
        let payload = """
        [
          {
            "nameWithOwner": "example/older",
            "description": "Older repo",
            "isPrivate": false,
            "updatedAt": "2024-01-01T10:00:00Z"
          },
          {
            "nameWithOwner": "example/newer",
            "description": "Newer repo",
            "isPrivate": true,
            "updatedAt": "2025-03-01T09:30:00Z"
          }
        ]
        """

        let repositories = try PaneWorkerExecutor.decodeGitHubRepositoryNodes(from: Data(payload.utf8))

        XCTAssertEqual(repositories.map(\.nameWithOwner), ["example/newer", "example/older"])
        XCTAssertEqual(repositories.first?.cloneURL, "https://github.com/example/newer.git")
        XCTAssertEqual(repositories.first?.isPrivate, true)
    }

    func testGitStageAndUnstagePropertyRoundTripAcrossRandomFiles() throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repo = tempRoot.appendingPathComponent("repo-stage", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "unit@test.local"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Unit Test"], workingDirectory: repo)

        let iterations = 16
        for index in 0..<iterations {
            let fileName = "file-\(index)-\(Int.random(in: 100...999)).txt"
            let fileURL = repo.appendingPathComponent(fileName)
            let randomPayload = (0..<Int.random(in: 1...4))
                .map { _ in String(Int.random(in: 0...9999)) }
                .joined(separator: "\n")
            try Data(randomPayload.utf8).write(to: fileURL)

            try PaneWorkerExecutor.stageGitPath(for: repo, relativePath: fileName)
            let staged = try PaneWorkerExecutor.loadGitStatus(for: repo)
            let stagedEntry = try XCTUnwrap(staged.entries.first(where: { $0.relativePath == fileName }))
            XCTAssertNotEqual(stagedEntry.indexStatus, " ")

            try PaneWorkerExecutor.unstageGitPath(for: repo, relativePath: fileName)
            let unstaged = try PaneWorkerExecutor.loadGitStatus(for: repo)
            let unstagedEntry = try XCTUnwrap(unstaged.entries.first(where: { $0.relativePath == fileName }))
            XCTAssertEqual(unstagedEntry.code, "??")
            XCTAssertEqual(unstagedEntry.indexStatus, "?")
            XCTAssertEqual(unstagedEntry.workTreeStatus, "?")
        }
    }

    func testGitHistoryParserPropertyPreservesGeneratedEntries() {
        var generated: [WorkerGitHistoryEntry] = []
        var rawRecords: [String] = []
        for index in 0..<48 {
            let hash = UUID().uuidString.replacingOccurrences(of: "-", with: "") + String(format: "%08x", index)
            let shortHash = String(hash.prefix(7))
            let author = "author-\(Int.random(in: 1...999))"
            let date = "2026-03-\(String(format: "%02d", Int.random(in: 1...28)))T12:00:00Z"
            let subject = "subject-\(index)-\(Int.random(in: 100...999))"
            generated.append(
                WorkerGitHistoryEntry(
                    hash: hash,
                    shortHash: shortHash,
                    authorName: author,
                    authoredDate: date,
                    subject: subject
                )
            )
            rawRecords.append([hash, shortHash, author, date, subject].joined(separator: "\u{1F}"))
        }

        let payload = (rawRecords.joined(separator: "\u{1E}") + "\u{1E}")
        let parsed = PaneWorkerExecutor.parseGitHistoryEntries(from: Data(payload.utf8))
        XCTAssertEqual(parsed.count, generated.count)

        for (expected, actual) in zip(generated, parsed) {
            XCTAssertEqual(actual.hash, expected.hash)
            XCTAssertEqual(actual.shortHash, expected.shortHash)
            XCTAssertEqual(actual.authorName, expected.authorName)
            XCTAssertEqual(actual.authoredDate, expected.authoredDate)
            XCTAssertEqual(actual.subject, expected.subject)
        }
    }

    func testGitStatusParserPropertyRetainsStatusAndPathSignals() {
        let rootURL = tempRoot.appendingPathComponent("parse-root", isDirectory: true)
        let samples = 64
        let statusCodes = [" M", "M ", "A ", " D", "R ", "C ", "??"]

        var rawRecords: [String] = []
        var expectedPaths: [String] = []

        for index in 0..<samples {
            let code = statusCodes[index % statusCodes.count]
            let path = "dir\(index % 7)/file-\(index).txt"
            expectedPaths.append(path)
            rawRecords.append("\(code) \(path)")
            if code.hasPrefix("R") || code.hasPrefix("C") {
                rawRecords.append("renamed-\(path)")
                expectedPaths.removeLast()
                expectedPaths.append("renamed-\(path)")
            }
        }

        let payload = rawRecords.joined(separator: "\0") + "\0"
        let entries = PaneWorkerExecutor.parseGitStatus(from: Data(payload.utf8), rootURL: rootURL)
        XCTAssertEqual(entries.count, expectedPaths.count)

        let observedPaths = entries.map(\.relativePath).sorted()
        XCTAssertEqual(observedPaths, expectedPaths.sorted())
        XCTAssertTrue(entries.allSatisfy { $0.indexStatus.count == 1 && $0.workTreeStatus.count == 1 })
    }

    func testGitDiffReturnsTextForChangedFile() throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repo = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: repo)

        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "unit@test.local"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Unit Test"], workingDirectory: repo)

        let tracked = repo.appendingPathComponent("tracked.txt")
        try Data("before\n".utf8).write(to: tracked)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "tracked.txt"], workingDirectory: repo)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "initial"], workingDirectory: repo)

        try Data("after\n".utf8).write(to: tracked)

        let response = PaneWorkerExecutor.execute(
            pane: .editor,
            request: PaneWorkerRequest(
                method: .gitDiff,
                arguments: [
                    "rootPath": repo.path,
                    "relativePath": "tracked.txt"
                ]
            )
        )
        XCTAssertTrue(response.success)
        let diff = try XCTUnwrap(response.value)
        XCTAssertTrue(diff.contains("tracked.txt"))
        XCTAssertTrue(diff.contains("after"))
    }

    func testUnsupportedMethodsAndMissingArgumentsReturnFailures() {
        let unsupported = PaneWorkerExecutor.execute(
            pane: .terminal,
            request: PaneWorkerRequest(method: .readFile, arguments: [:])
        )
        XCTAssertFalse(unsupported.success)
        XCTAssertTrue((unsupported.error ?? "").contains("Unsupported terminal worker method"))

        let missingArgument = PaneWorkerExecutor.execute(
            pane: .editor,
            request: PaneWorkerRequest(method: .readFile, arguments: [:])
        )
        XCTAssertFalse(missingArgument.success)
        XCTAssertTrue((missingArgument.error ?? "").contains("Missing required argument"))
    }

    func testPaneWorkerStatusHelpersProvideUserFacingStates() {
        XCTAssertEqual(PaneWorkerStatus.ready.level, .healthy)
        XCTAssertEqual(PaneWorkerStatus.ready.message, "Ready")

        let busy = PaneWorkerStatus.busy("Loading")
        XCTAssertEqual(busy.level, .busy)
        XCTAssertEqual(busy.message, "Loading")

        let unavailable = PaneWorkerStatus.unavailable("No access")
        XCTAssertEqual(unavailable.level, .unavailable)
        XCTAssertEqual(unavailable.message, "No access")
    }

    private func initializeGitRepository(at url: URL) throws {
        let result = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "init"],
            workingDirectory: url
        )
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    }

    private func configureGitIdentity(at url: URL) throws {
        let email = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "config", "user.email", "unit@test.local"],
            workingDirectory: url
        )
        XCTAssertEqual(email.terminationStatus, 0, email.stderr)

        let name = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "config", "user.name", "Unit Test"],
            workingDirectory: url
        )
        XCTAssertEqual(name.terminationStatus, 0, name.stderr)
    }
}
