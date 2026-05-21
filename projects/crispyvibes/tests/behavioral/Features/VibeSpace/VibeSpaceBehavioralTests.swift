import XCTest
@testable import CrispyVibes

@MainActor
final class VibeSpaceBehavioralTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!
    private var stateFileURL: URL!
    private var vibespacePersistenceStore: VibeSpacePersistenceStore!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempRoot = base.appendingPathComponent("crispyvibes-behavioral-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        stateFileURL = tempRoot.appendingPathComponent("layout.json")
        container = AppContainer.makeDefault()
        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        vibespacePersistenceStore = VibeSpacePersistenceStore(store: appStore)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
        vibespacePersistenceStore = nil
    }

    func testVibeSpaceAddAndRemoveProjectsFlow() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [first])
        XCTAssertEqual(vibespace.projects.count, 1)

        let added = vibespace.addProjects(from: [second])
        XCTAssertNotNil(added)
        XCTAssertEqual(vibespace.projects.count, 2)

        let removeID = vibespace.projects[0].id
        vibespace.removeProject(id: removeID)
        XCTAssertEqual(vibespace.projects.count, 1)
    }

    func testVibeSpaceConfigAndLayoutRoundTripFlow() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        let missing = tempRoot.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(name: "Fixture", projectURLs: [first, second, missing])
        XCTAssertEqual(vibespace.projects.count, 2)
        XCTAssertEqual(vibespace.unresolvedProjectPaths.count, 1)
        vibespace.setColorTag(ProjectColorTag(red: 0.6, green: 0.1, blue: 0.7), for: vibespace.projects[0].id)
        vibespace.focusedProjectID = vibespace.projects[1].id

        let config = vibespace.configFile
        let projectConfigs = vibespace.projects.reduce(into: [String: ProjectConfigFile]()) { result, project in
            let path = project.rootURL.path
            var pc = ProjectConfigFile.empty(projectPath: path)
            if let tag = vibespace.projectColorTagsByPath[path] { pc.colorTag = tag.storageToken }
            if let idx = vibespace.projectShortcutByPath[path] { pc.shortcutIndex = idx }
            if let o = vibespace.projectStartupOverridesByPath[path] { pc.startupOverride = o }
            if let s = vibespace.projectTerminalShellOverridesByPath[path] { pc.terminalShellOverride = s }
            result[path] = pc
        }
        let restored = container.makeVibeSpaceState(config: config, projectConfigs: projectConfigs)

        XCTAssertEqual(restored.projects.count, 2)
        XCTAssertEqual(restored.unresolvedProjectPaths.count, 1)
        XCTAssertEqual(restored.focusedProjectID, restored.projects[1].id)
        XCTAssertNotNil(restored.projectColorTagsByPath[first.standardizedFileURL.path])

        let layout = makeLayoutPersistenceService()
        layout.setRailSize(350, for: .right, vibespaceID: restored.id)
        layout.setDetailedTerminalPaneHeight(410, for: restored.id)
        layout.setPaneLayout(
            ProjectPaneLayoutState(
                explorerFraction: 0.4,
                terminalFraction: 0.3,
                explorerPoints: 280,
                terminalPoints: 220
            ),
            for: first
        )

        let reloadedLayout = makeLayoutPersistenceService()
        reloadedLayout.loadVibeSpaceLayoutIfNeeded(for: restored.id)
        XCTAssertEqual(reloadedLayout.railSize(for: .right, vibespaceID: restored.id), 350, accuracy: 0.01)
        XCTAssertEqual(reloadedLayout.detailedTerminalPaneHeight(for: restored.id), 410, accuracy: 0.01)
        XCTAssertEqual(reloadedLayout.paneLayout(for: first).explorerPoints, 280)
    }

    func testGitWorkflowBehavioralPropertyForStageCommitPushAndHistory() throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repository = tempRoot.appendingPathComponent("repo", isDirectory: true)
        let remote = tempRoot.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: repository)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init", "--bare", remote.path], workingDirectory: repository)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "behavior@test.local"], workingDirectory: repository)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Behavior Test"], workingDirectory: repository)

        let seed = repository.appendingPathComponent("seed.txt")
        try Data("seed\n".utf8).write(to: seed)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "seed.txt"], workingDirectory: repository)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "seed"], workingDirectory: repository)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "remote", "add", "origin", remote.path], workingDirectory: repository)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "push", "-u", "origin", "HEAD"], workingDirectory: repository)

        var changedPaths: [String] = []
        for iteration in 0..<12 {
            let relativePath = "src/file-\(iteration)-\(Int.random(in: 100...999)).txt"
            let fileURL = repository.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = (0..<Int.random(in: 1...6))
                .map { _ in String(Int.random(in: 0...9999)) }
                .joined(separator: "\n")
            try Data(payload.utf8).write(to: fileURL)

            let stage = PaneWorkerExecutor.execute(
                pane: .explorer,
                request: PaneWorkerRequest(
                    method: .gitStage,
                    arguments: [
                        "rootPath": repository.path,
                        "relativePath": relativePath
                    ]
                )
            )
            XCTAssertTrue(stage.success, stage.error ?? "")
            changedPaths.append(relativePath)
        }

        let commitMessage = "behavioral-\(UUID().uuidString.prefix(8))"
        let commit = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .gitCommit,
                arguments: [
                    "rootPath": repository.path,
                    "message": commitMessage
                ]
            )
        )
        XCTAssertTrue(commit.success, commit.error ?? "")

        let push = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .gitPush,
                arguments: [
                    "rootPath": repository.path
                ]
            )
        )
        XCTAssertTrue(push.success, push.error ?? "")

        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "checkout", "-b", "feature/behavioral-switch"], workingDirectory: repository)
        let checkoutMain = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .gitCheckoutBranch,
                arguments: [
                    "rootPath": repository.path,
                    "branch": "main",
                    "isRemote": "0"
                ]
            )
        )
        if !checkoutMain.success {
            let checkoutMaster = PaneWorkerExecutor.execute(
                pane: .explorer,
                request: PaneWorkerRequest(
                    method: .gitCheckoutBranch,
                    arguments: [
                        "rootPath": repository.path,
                        "branch": "master",
                        "isRemote": "0"
                    ]
                )
            )
            XCTAssertTrue(checkoutMaster.success, checkoutMaster.error ?? "")
        }

        let historyResponse = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .gitCommitHistory,
                arguments: [
                    "rootPath": repository.path,
                    "limit": "20"
                ]
            )
        )
        XCTAssertTrue(historyResponse.success, historyResponse.error ?? "")
        let commitHistory: WorkerGitHistoryPayload = try decodeJSON(historyResponse.value)
        XCTAssertTrue(commitHistory.entries.contains(where: { $0.subject == commitMessage }))

        let samplePath = try XCTUnwrap(changedPaths.randomElement())
        let fileHistoryResponse = PaneWorkerExecutor.execute(
            pane: .explorer,
            request: PaneWorkerRequest(
                method: .gitFileHistory,
                arguments: [
                    "rootPath": repository.path,
                    "relativePath": samplePath,
                    "limit": "20"
                ]
            )
        )
        XCTAssertTrue(fileHistoryResponse.success, fileHistoryResponse.error ?? "")
        let fileHistory: WorkerGitHistoryPayload = try decodeJSON(fileHistoryResponse.value)
        XCTAssertFalse(fileHistory.entries.isEmpty)
    }

    func testExplorerBehavioralPropertyShowsHiddenAndMarksIgnoredEntries() async throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        let repository = tempRoot.appendingPathComponent("explorer-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: repository)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "core.excludesfile", "/dev/null"], workingDirectory: repository)

        let iterations = 10
        for iteration in 0..<iterations {
            let hiddenName = ".hidden-\(iteration)"
            let ignoredName = "ignored-\(iteration)"
            let visibleName = "visible-\(iteration)"

            try FileManager.default.createDirectory(
                at: repository.appendingPathComponent(hiddenName, isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: repository.appendingPathComponent(ignoredName, isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: repository.appendingPathComponent(visibleName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let ignorePatterns = (0..<iterations).map { "ignored-\($0)/" }.joined(separator: "\n")
        try Data((ignorePatterns + "\n").utf8).write(to: repository.appendingPathComponent(".gitignore"))

        let viewModel = container.makeFolderExplorerViewModel()
        viewModel.setRootFolder(repository)

        let loaded = await waitForCondition(timeout: 8) {
            !viewModel.rootItems.isEmpty && viewModel.workerStatus == .ready
        }
        XCTAssertTrue(loaded)

        for iteration in 0..<iterations {
            let hiddenName = ".hidden-\(iteration)"
            let ignoredName = "ignored-\(iteration)"
            let visibleName = "visible-\(iteration)"

            let hiddenEntry = try XCTUnwrap(viewModel.rootItems.first(where: { $0.displayName == hiddenName }))
            XCTAssertTrue(hiddenEntry.isHidden)
            XCTAssertFalse(hiddenEntry.isGitIgnored)

            let ignoredEntry = try XCTUnwrap(viewModel.rootItems.first(where: { $0.displayName == ignoredName }))
            XCTAssertTrue(ignoredEntry.isGitIgnored)

            let visibleEntry = try XCTUnwrap(viewModel.rootItems.first(where: { $0.displayName == visibleName }))
            XCTAssertFalse(visibleEntry.isHidden)
            XCTAssertFalse(visibleEntry.isGitIgnored)
        }
    }

    private func makeLayoutPersistenceService() -> LayoutPersistenceService {
        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        let service = LayoutPersistenceService(persistenceStore: appStore)
        service.setVibeSpacePersistenceStore(vibespacePersistenceStore)
        return service
    }
}

private func decodeJSON<T: Decodable>(_ text: String?) throws -> T {
    let payload = try XCTUnwrap(text)
    return try JSONDecoder().decode(T.self, from: Data(payload.utf8))
}

private func gitAvailable() throws -> Bool {
    let result = try runProcess(executable: "/usr/bin/env", arguments: ["git", "--version"], workingDirectory: nil)
    return result.terminationStatus == 0
}

@discardableResult
private func runProcess(
    executable: String,
    arguments: [String],
    workingDirectory: URL?
) throws -> (terminationStatus: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let workingDirectory {
        process.currentDirectoryURL = workingDirectory
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, stdout, stderr)
}

@MainActor
private func waitForCondition(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.05,
    condition: @escaping () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
    return condition()
}
