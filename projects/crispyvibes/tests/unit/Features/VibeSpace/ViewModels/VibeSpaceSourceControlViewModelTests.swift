import Foundation
import XCTest
import Combine
@testable import CrispyVibes

@MainActor
final class VibeSpaceSourceControlViewModelTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-vibespace-scm")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testDiscoverGitRepositoriesFindsContainingAndNestedRoots() throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        let nestedRepositoryURL = tempRoot.appendingPathComponent("packages/child-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRepositoryURL, withIntermediateDirectories: true)

        try initializeGitRepository(at: tempRoot)
        try initializeGitRepository(at: nestedRepositoryURL)

        let payload = try PaneWorkerExecutor.discoverGitRepositories(for: tempRoot)
        let repositoryPaths = Set(payload.repositories.map(\.repositoryRootPath))

        XCTAssertTrue(payload.gitAvailable)
        XCTAssertTrue(repositoryPaths.contains(tempRoot.standardizedFileURL.path))
        XCTAssertTrue(repositoryPaths.contains(nestedRepositoryURL.standardizedFileURL.path))
    }

    func testDiscoverGitRepositoriesDoesNotScanNestedReposWhenRootIsNotInGit() throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        let nestedRepositoryURL = tempRoot.appendingPathComponent("packages/child-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRepositoryURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: nestedRepositoryURL)

        let payload = try PaneWorkerExecutor.discoverGitRepositories(for: tempRoot)

        XCTAssertTrue(payload.gitAvailable)
        XCTAssertTrue(payload.repositories.isEmpty)
    }

    func testDiscoverGitRepositoriesHonorsIgnoredDirectoryNames() throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        let nestedRepositoryURL = tempRoot
            .appendingPathComponent("SourcePackages/checkouts/child-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRepositoryURL, withIntermediateDirectories: true)

        try initializeGitRepository(at: tempRoot)
        try initializeGitRepository(at: nestedRepositoryURL)

        let payload = try PaneWorkerExecutor.discoverGitRepositories(
            for: tempRoot,
            settings: VibeSpaceSourceControlSettings(
                ignoredDirectoryNames: ["SourcePackages"],
                scanMaxDepth: 8,
                scanMaxRepositories: 64,
                autoPresentedRepositoryLimit: 12
            )
        )
        let repositoryPaths = Set(payload.repositories.map(\.repositoryRootPath))

        XCTAssertTrue(repositoryPaths.contains(tempRoot.standardizedFileURL.path))
        XCTAssertFalse(repositoryPaths.contains(nestedRepositoryURL.standardizedFileURL.path))
    }

    func testDiscoverGitRepositoriesHonorsScanDepthLimit() throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        let shallowRepositoryURL = tempRoot.appendingPathComponent("packages/child-repo", isDirectory: true)
        let deepRepositoryURL = tempRoot.appendingPathComponent(
            "packages/generated/deeper/too-deep-repo",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: shallowRepositoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deepRepositoryURL, withIntermediateDirectories: true)

        try initializeGitRepository(at: tempRoot)
        try initializeGitRepository(at: shallowRepositoryURL)
        try initializeGitRepository(at: deepRepositoryURL)

        let payload = try PaneWorkerExecutor.discoverGitRepositories(
            for: tempRoot,
            settings: VibeSpaceSourceControlSettings(
                ignoredDirectoryNames: [],
                scanMaxDepth: 3,
                scanMaxRepositories: 64,
                autoPresentedRepositoryLimit: 12
            )
        )
        let repositoryPaths = Set(payload.repositories.map(\.repositoryRootPath))

        XCTAssertTrue(repositoryPaths.contains(shallowRepositoryURL.standardizedFileURL.path))
        XCTAssertFalse(repositoryPaths.contains(deepRepositoryURL.standardizedFileURL.path))
    }

    @MainActor
    func testSelectedNestedRepositorySortsAheadOfParentRepository() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        let childProjectURL = tempRoot.appendingPathComponent("packages/child-repo", isDirectory: true)
        let selectedFileURL = childProjectURL.appendingPathComponent("Sources/feature.swift")
        try FileManager.default.createDirectory(
            at: selectedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try initializeGitRepository(at: tempRoot)
        try initializeGitRepository(at: childProjectURL)

        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let parentProject = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)
        let childProject = container.makeProjectSession(rootURL: childProjectURL, vibespaceID: nil)

        viewModel.updateVibeSpace(
            projects: [parentProject, childProject],
            focusedProject: childProject,
            selectedFileURL: selectedFileURL,
            sourceControlSettings: .default
        )

        let loaded = await waitForCondition(timeout: 8) {
            viewModel.state == .ready && viewModel.repositories.count == 2
        }
        XCTAssertTrue(loaded, "Expected source control repositories to finish loading.")

        XCTAssertEqual(
            viewModel.repositories.map { $0.repositoryRootURL.path },
            [
                childProjectURL.standardizedFileURL.path,
                tempRoot.standardizedFileURL.path
            ]
        )
    }

    func testRepositoryRefreshUsesRepositoryRelativePaths() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository status tests.")

        let sourcesURL = tempRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let fileURL = sourcesURL.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: tempRoot)
        try Data("print(\"hello\")\n".utf8).write(to: fileURL)

        let repository = VibeSpaceSourceControlRepositoryViewModel(
            repositoryRootURL: tempRoot,
            worker: container.makePaneWorker(pane: .sourceControl)
        )
        await repository.refresh()

        XCTAssertEqual(repository.loadState, .ready)
        XCTAssertEqual(repository.statusItems.first?.relativePath, "Sources/App/main.swift")
        XCTAssertEqual(repository.statusItems.first?.fileName, "main.swift")
        XCTAssertEqual(repository.statusItems.first?.parentRelativePath, "Sources/App")
        XCTAssertEqual(repository.statusItems.first?.url.path, fileURL.standardizedFileURL.path)
    }

    func testVibeSpaceFileDidSaveRefreshesOwningRepositoryStatus() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository status tests.")

        let sourcesURL = tempRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let fileURL = sourcesURL.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: tempRoot)
        try configureGitIdentity(at: tempRoot)
        try Data("print(\"hello\")\n".utf8).write(to: fileURL)
        try stageAll(in: tempRoot)
        try commitAll(in: tempRoot, message: "Initial commit")

        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let project = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)

        viewModel.updateVibeSpace(
            projects: [project],
            focusedProject: project,
            selectedFileURL: fileURL,
            sourceControlSettings: .default
        )

        let loaded = await waitForCondition(timeout: 8) {
            viewModel.state == .ready
                && viewModel.repositories.count == 1
                && viewModel.repositories.first?.loadState == .ready
                && viewModel.repositories.first?.statusItems.isEmpty == true
        }
        XCTAssertTrue(loaded, "Expected repository status to load before save notification test.")

        try Data("print(\"updated\")\n".utf8).write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .vibespaceFileDidSave, object: fileURL.standardizedFileURL)

        let refreshed = await waitForCondition(timeout: 5) {
            viewModel.repositories.first?.statusItems.first?.relativePath == "Sources/App/main.swift"
        }

        XCTAssertTrue(refreshed, "Expected repository status to refresh after a vibespace save notification.")
    }

    func testUpdateVibeSpaceLoadsExistingDirtyRepositoryStateOnInitialOpen() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository status tests.")

        let sourcesURL = tempRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let fileURL = sourcesURL.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: tempRoot)
        try configureGitIdentity(at: tempRoot)
        try Data("print(\"hello\")\n".utf8).write(to: fileURL)
        try stageAll(in: tempRoot)
        try commitAll(in: tempRoot, message: "Initial commit")
        try Data("print(\"updated\")\n".utf8).write(to: fileURL, options: .atomic)

        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let project = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)

        viewModel.updateVibeSpace(
            projects: [project],
            focusedProject: project,
            selectedFileURL: fileURL,
            sourceControlSettings: .default
        )

        let loaded = await waitForCondition(timeout: 8) {
            viewModel.state == .ready
                && viewModel.repositories.count == 1
                && viewModel.repositories.first?.loadState == .ready
                && viewModel.repositories.first?.statusItems.first?.relativePath == "Sources/App/main.swift"
        }

        XCTAssertTrue(loaded, "Expected existing dirty files to appear on the initial SCM vibespace load.")
    }

    func testLocalProjectWatcherRefreshesRepositoryStatusWithoutExplorerLoaded() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository status tests.")

        let sourcesURL = tempRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let fileURL = sourcesURL.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: tempRoot)
        try configureGitIdentity(at: tempRoot)
        try Data("print(\"hello\")\n".utf8).write(to: fileURL)
        try stageAll(in: tempRoot)
        try commitAll(in: tempRoot, message: "Initial commit")

        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let project = container.makeProjectSession(rootURL: tempRoot, vibespaceID: nil)

        viewModel.updateVibeSpace(
            projects: [project],
            focusedProject: project,
            selectedFileURL: fileURL,
            sourceControlSettings: .default
        )

        let loaded = await waitForCondition(timeout: 8) {
            viewModel.state == .ready
                && viewModel.repositories.count == 1
                && viewModel.repositories.first?.loadState == .ready
                && viewModel.repositories.first?.statusItems.isEmpty == true
        }
        XCTAssertTrue(loaded, "Expected repository status to load before local watcher test.")

        try Data("print(\"updated\")\n".utf8).write(to: fileURL, options: .atomic)

        let refreshed = await waitForCondition(timeout: 5) {
            viewModel.repositories.first?.statusItems.first?.relativePath == "Sources/App/main.swift"
        }

        XCTAssertTrue(refreshed, "Expected SCM root watcher to refresh repository status after a local file change.")
    }

    func testDiscoverRepositoriesUsesRemoteGitExplorerBackend() async {
        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let remoteRoot = URL(fileURLWithPath: "/srv/app")
        let gitExplorer = RemoteGitExplorerStub(
            discoveredRepositoryRoots: [remoteRoot.path]
        )
        let projectReference = VibeSpaceSourceControlProjectReference(
            rootURL: remoteRoot,
            title: "Remote",
            orderIndex: 0,
            projectIdentifier: "ssh://testuser@example.com:22\(remoteRoot.path)",
            usesProjectGitBackend: true,
            gitExplorer: AnyGitExplorer(gitExplorer)
        )

        viewModel.sourceControlSettings = .default
        viewModel.projectReferences = [projectReference]

        await viewModel.discoverRepositories(for: [projectReference])

        XCTAssertEqual(gitExplorer.discoverCallCount, 1)
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.repositories.count, 1)
        XCTAssertEqual(viewModel.repositories.first?.repositoryRootURL.path, remoteRoot.path)
        XCTAssertEqual(
            viewModel.repositories.first?.id,
            "\(projectReference.projectIdentifier)|\(remoteRoot.path)"
        )
    }

    func testDiscoverRepositoriesKeepsLocalRepositoriesWhenRemoteGitIsUnavailable() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        try initializeGitRepository(at: tempRoot)

        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let localProject = VibeSpaceSourceControlProjectReference(
            rootURL: tempRoot,
            title: "Local",
            orderIndex: 0,
            projectIdentifier: tempRoot.path,
            usesProjectGitBackend: false,
            gitExplorer: nil
        )
        let remoteRoot = URL(fileURLWithPath: "/srv/app")
        let remoteProject = VibeSpaceSourceControlProjectReference(
            rootURL: remoteRoot,
            title: "Remote",
            orderIndex: 1,
            projectIdentifier: "ssh://testuser@example.com:22\(remoteRoot.path)",
            usesProjectGitBackend: true,
            gitExplorer: AnyGitExplorer(
                RemoteGitExplorerStub(
                    discoveredRepositoryRoots: [],
                    discoverPayload: WorkerGitRepositoryDiscoveryPayload(
                        gitAvailable: false,
                        repositories: [],
                        message: "SSH connection failed."
                    )
                )
            )
        )

        viewModel.sourceControlSettings = .default
        viewModel.projectReferences = [localProject, remoteProject]

        await viewModel.discoverRepositories(for: [localProject, remoteProject])

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.repositories.map(\.repositoryRootURL.path), [tempRoot.standardizedFileURL.path])
        XCTAssertEqual(
            viewModel.message,
            "Git unavailable for Remote: SSH connection failed."
        )
    }

    func testDiscoverRepositoriesKeepsLocalRepositoriesWhenRemoteDiscoveryThrows() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        try initializeGitRepository(at: tempRoot)

        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let localProject = VibeSpaceSourceControlProjectReference(
            rootURL: tempRoot,
            title: "Local",
            orderIndex: 0,
            projectIdentifier: tempRoot.path,
            usesProjectGitBackend: false,
            gitExplorer: nil
        )
        let remoteRoot = URL(fileURLWithPath: "/srv/app")
        let remoteProject = VibeSpaceSourceControlProjectReference(
            rootURL: remoteRoot,
            title: "Remote",
            orderIndex: 1,
            projectIdentifier: "ssh://testuser@example.com:22\(remoteRoot.path)",
            usesProjectGitBackend: true,
            gitExplorer: AnyGitExplorer(
                RemoteGitExplorerStub(
                    discoveredRepositoryRoots: [],
                    discoverError: TestError.sshUnavailable
                )
            )
        )

        viewModel.sourceControlSettings = .default
        viewModel.projectReferences = [localProject, remoteProject]

        await viewModel.discoverRepositories(for: [localProject, remoteProject])

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.repositories.map(\.repositoryRootURL.path), [tempRoot.standardizedFileURL.path])
        XCTAssertEqual(
            viewModel.message,
            "Unable to discover repositories for Remote: SSH connection failed."
        )
    }

    func testDiscoverRepositoriesPublishesLocalRepositoriesBeforeSlowRemoteDiscoveryCompletes() async throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for repository discovery tests.")

        try initializeGitRepository(at: tempRoot)

        let viewModel = container.makeVibeSpaceSourceControlViewModel()
        let localProject = VibeSpaceSourceControlProjectReference(
            rootURL: tempRoot,
            title: "Local",
            orderIndex: 0,
            projectIdentifier: tempRoot.path,
            usesProjectGitBackend: false,
            gitExplorer: nil
        )
        let remoteRoot = URL(fileURLWithPath: "/srv/app")
        let remoteExplorer = RemoteGitExplorerStub(
            discoveredRepositoryRoots: [remoteRoot.path],
            discoverDelayNanoseconds: 1_000_000_000
        )
        let remoteProject = VibeSpaceSourceControlProjectReference(
            rootURL: remoteRoot,
            title: "Remote",
            orderIndex: 1,
            projectIdentifier: "ssh://testuser@example.com:22\(remoteRoot.path)",
            usesProjectGitBackend: true,
            gitExplorer: AnyGitExplorer(remoteExplorer)
        )

        viewModel.sourceControlSettings = .default
        viewModel.projectReferences = [localProject, remoteProject]

        let discoveryTask = Task {
            await viewModel.discoverRepositories(for: [localProject, remoteProject])
        }

        let localPublished = await waitForCondition(timeout: 3) {
            viewModel.state == .ready
                && viewModel.repositories.map(\.repositoryRootURL.path) == [self.tempRoot.standardizedFileURL.path]
        }

        XCTAssertTrue(localPublished, "Expected the local repository to appear before remote discovery finished.")
        XCTAssertTrue(remoteExplorer.isDiscovering)

        await discoveryTask.value

        XCTAssertEqual(
            Set(viewModel.repositories.map(\.repositoryRootURL.path)),
            Set([self.tempRoot.standardizedFileURL.path, remoteRoot.path])
        )
    }

    func testRemoteRepositoryRefreshUsesGitExplorerState() async {
        let remoteRoot = URL(fileURLWithPath: "/srv/app")
        let fileURL = remoteRoot.appendingPathComponent("Sources/App/main.swift")
        let gitExplorer = RemoteGitExplorerStub(
            discoveredRepositoryRoots: [remoteRoot.path],
            statusItems: [
                GitStatusItem(
                    code: " M",
                    indexStatus: " ",
                    workTreeStatus: "M",
                    relativePath: "Sources/App/main.swift",
                    url: fileURL
                )
            ],
            branchOptions: [
                GitBranchOption(
                    name: "main",
                    displayName: "main",
                    isCurrent: true,
                    isRemote: false
                )
            ],
            currentBranchName: "main"
        )

        let repository = VibeSpaceSourceControlRepositoryViewModel(
            id: "ssh://testuser@example.com:22\(remoteRoot.path)|\(remoteRoot.path)",
            repositoryRootURL: remoteRoot,
            worker: container.makePaneWorker(pane: .sourceControl),
            gitExplorer: AnyGitExplorer(gitExplorer)
        )

        await repository.refresh()

        XCTAssertEqual(gitExplorer.loadStatusCallCount, 1)
        XCTAssertEqual(gitExplorer.loadBranchesCallCount, 1)
        XCTAssertEqual(repository.loadState, .ready)
        XCTAssertEqual(repository.branchName, "main")
        XCTAssertEqual(repository.statusItems.map(\.relativePath), ["Sources/App/main.swift"])
        XCTAssertEqual(repository.statusItems.first?.url.path, fileURL.path)
    }

    func testRepositoryRefreshPreservesLastSnapshotWhenLaterRefreshFails() async throws {
        let repoRoot = URL(fileURLWithPath: "/tmp/example-repo")
        let fileURL = repoRoot.appendingPathComponent("Sources/App/main.swift")
        let initialSnapshot = WorkerGitRepositorySnapshotPayload(
            gitAvailable: true,
            repository: true,
            entries: [
                WorkerGitStatusNode(
                    code: " M",
                    indexStatus: " ",
                    workTreeStatus: "M",
                    path: fileURL.path,
                    relativePath: "Sources/App/main.swift"
                )
            ],
            currentBranch: "main",
            branches: [
                WorkerGitBranchNode(name: "main", displayName: "main", isCurrent: true, isRemote: false)
            ],
            message: nil
        )
        let worker = SnapshotSequenceWorker(
            responses: [
                .success(try JSONEncoder().encode(initialSnapshot)),
                .failure(PaneWorkerError.workerFailure("snapshot failed"))
            ]
        )
        let repository = VibeSpaceSourceControlRepositoryViewModel(
            repositoryRootURL: repoRoot,
            worker: worker
        )

        await repository.refresh()
        XCTAssertEqual(repository.loadState, .ready)
        XCTAssertEqual(repository.branchName, "main")
        XCTAssertEqual(repository.statusItems.map(\.relativePath), ["Sources/App/main.swift"])

        await repository.refresh()

        XCTAssertEqual(repository.loadState, .ready)
        XCTAssertEqual(repository.branchName, "main")
        XCTAssertEqual(repository.statusItems.map(\.relativePath), ["Sources/App/main.swift"])
        XCTAssertEqual(repository.message, "Unable to load repository status: snapshot failed")
    }

    func testRepositoryRefreshQueuesFollowUpRefreshWhileSnapshotIsInFlight() async throws {
        let repoRoot = URL(fileURLWithPath: "/tmp/example-repo")
        let fileURL = repoRoot.appendingPathComponent("Sources/App/main.swift")
        let recoverySnapshot = WorkerGitRepositorySnapshotPayload(
            gitAvailable: true,
            repository: true,
            entries: [
                WorkerGitStatusNode(
                    code: " M",
                    indexStatus: " ",
                    workTreeStatus: "M",
                    path: fileURL.path,
                    relativePath: "Sources/App/main.swift"
                )
            ],
            currentBranch: "main",
            branches: [
                WorkerGitBranchNode(name: "main", displayName: "main", isCurrent: true, isRemote: false)
            ],
            message: nil
        )
        let worker = BlockingSnapshotSequenceWorker(
            responses: [
                .failure(PaneWorkerError.workerFailure("snapshot failed")),
                .success(try JSONEncoder().encode(recoverySnapshot))
            ]
        )
        let repository = VibeSpaceSourceControlRepositoryViewModel(
            repositoryRootURL: repoRoot,
            worker: worker
        )

        let firstRefresh = Task { await repository.refresh() }
        await worker.waitForFirstExecution()

        let queuedRefresh = Task { await repository.refresh() }
        await worker.releaseFirstExecution()

        await firstRefresh.value
        await queuedRefresh.value

        let executeCount = await worker.executeCount
        XCTAssertEqual(executeCount, 2)
        XCTAssertEqual(repository.loadState, .ready)
        XCTAssertEqual(repository.branchName, "main")
        XCTAssertEqual(repository.statusItems.map(\.relativePath), ["Sources/App/main.swift"])
        XCTAssertNil(repository.message)
    }

    func testLoadGitFileContentReturnsPreviousRevisionForDeletedFile() throws {
        try XCTSkipUnless(gitAvailable(), "Git is required for deleted file content tests.")

        let sourcesURL = tempRoot.appendingPathComponent("Sources/App", isDirectory: true)
        let fileURL = sourcesURL.appendingPathComponent("main.swift")
        let relativePath = "Sources/App/main.swift"
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: tempRoot)
        try configureGitIdentity(at: tempRoot)
        try Data("print(\"hello\")\n".utf8).write(to: fileURL)
        try stageAll(in: tempRoot)
        try commitAll(in: tempRoot, message: "Initial commit")
        try FileManager.default.removeItem(at: fileURL)

        let content = try PaneWorkerExecutor.loadGitFileContent(for: tempRoot, relativePath: relativePath)

        XCTAssertEqual(content, "print(\"hello\")\n")
    }

    func testStatusItemDiscardAvailabilityOnlyAppliesToTrackedUnstagedChanges() {
        let modifiedTracked = VibeSpaceSourceControlStatusItem(
            repositoryRootURL: tempRoot,
            code: " M",
            indexStatus: " ",
            workTreeStatus: "M",
            relativePath: "Sources/App/main.swift",
            url: tempRoot.appendingPathComponent("Sources/App/main.swift")
        )
        XCTAssertTrue(modifiedTracked.canDiscardChanges)

        let untracked = VibeSpaceSourceControlStatusItem(
            repositoryRootURL: tempRoot,
            code: "??",
            indexStatus: "?",
            workTreeStatus: "?",
            relativePath: "Sources/App/new.swift",
            url: tempRoot.appendingPathComponent("Sources/App/new.swift")
        )
        XCTAssertFalse(untracked.canDiscardChanges)

        let stagedOnly = VibeSpaceSourceControlStatusItem(
            repositoryRootURL: tempRoot,
            code: "M ",
            indexStatus: "M",
            workTreeStatus: " ",
            relativePath: "Sources/App/main.swift",
            url: tempRoot.appendingPathComponent("Sources/App/main.swift")
        )
        XCTAssertFalse(stagedOnly.canDiscardChanges)
    }

    func testStatusItemLacksCommittedHistoryForAddedFilesOnly() {
        let untracked = VibeSpaceSourceControlStatusItem(
            repositoryRootURL: tempRoot,
            code: "??",
            indexStatus: "?",
            workTreeStatus: "?",
            relativePath: "Sources/App/new.swift",
            url: tempRoot.appendingPathComponent("Sources/App/new.swift")
        )
        XCTAssertTrue(untracked.lacksCommittedHistory)

        let stagedAdded = VibeSpaceSourceControlStatusItem(
            repositoryRootURL: tempRoot,
            code: "A ",
            indexStatus: "A",
            workTreeStatus: " ",
            relativePath: "Sources/App/new.swift",
            url: tempRoot.appendingPathComponent("Sources/App/new.swift")
        )
        XCTAssertTrue(stagedAdded.lacksCommittedHistory)

        let modifiedTracked = VibeSpaceSourceControlStatusItem(
            repositoryRootURL: tempRoot,
            code: " M",
            indexStatus: " ",
            workTreeStatus: "M",
            relativePath: "Sources/App/main.swift",
            url: tempRoot.appendingPathComponent("Sources/App/main.swift")
        )
        XCTAssertFalse(modifiedTracked.lacksCommittedHistory)
    }

    // MARK: - Task Lifecycle Tests

    func testRefreshCancelsActiveObservedRefreshTask() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        let dummyTask: Task<Void, Never> = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
        vm.activeObservedRefreshTask = dummyTask
        vm.refresh()
        XCTAssertTrue(dummyTask.isCancelled)
    }

    func testRefreshCancelsActiveInitialRefreshTasks() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        let tasks: [Task<Void, Never>] = (0..<3).map { _ in Task { try? await Task.sleep(nanoseconds: 10_000_000_000) } }
        vm.activeInitialRefreshTasks = tasks
        vm.refresh()
        for task in tasks {
            XCTAssertTrue(task.isCancelled)
        }
        XCTAssertTrue(vm.activeInitialRefreshTasks.isEmpty)
    }

    func testConsumeObservedRefreshQueueCancelsPreviousActiveTask() async throws {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })

        // Set up a repository VM directly so consumeObservedRefreshQueue has something to refresh.
        let repoVM = VibeSpaceSourceControlRepositoryViewModel(
            id: tempRoot.standardizedFileURL.path,
            repositoryRootURL: tempRoot,
            worker: worker
        )
        vm.repositories = [repoVM]
        vm.state = .ready

        let oldTask: Task<Void, Never> = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
        vm.activeObservedRefreshTask = oldTask

        vm.pendingObservedPaths = [tempRoot.appendingPathComponent("file.txt").path]
        vm.consumeObservedRefreshQueue()

        XCTAssertTrue(oldTask.isCancelled)
        XCTAssertNotNil(vm.activeObservedRefreshTask)
    }

    func testFilteredObservedPathsSkipsIgnoredDirectories() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        vm.sourceControlSettings = VibeSpaceSourceControlSettings(
            ignoredDirectoryNames: ["DerivedData", "node_modules"],
            scanMaxDepth: 8,
            scanMaxRepositories: 64,
            autoPresentedRepositoryLimit: 12
        )
        vm.projectReferences = [
            VibeSpaceSourceControlProjectReference(
                rootURL: tempRoot,
                title: "Temp",
                orderIndex: 0,
                projectIdentifier: tempRoot.path,
                usesProjectGitBackend: false,
                gitExplorer: nil
            )
        ]

        let filtered = vm.filteredObservedPaths(from: [
            tempRoot.appendingPathComponent("DerivedData/build.log").path,
            tempRoot.appendingPathComponent("node_modules/react/index.js").path,
            tempRoot.appendingPathComponent("Sources/App/main.swift").path,
            tempRoot.appendingPathComponent(".git/index").path,
            tempRoot.appendingPathComponent(".git/HEAD").path
        ])

        XCTAssertEqual(
            filtered,
            Set([
                tempRoot.appendingPathComponent("Sources/App/main.swift").standardizedFileURL.path,
                tempRoot.appendingPathComponent(".git/HEAD").standardizedFileURL.path
            ])
        )
    }

    func testFilteredObservedPathsStillIgnoresGitInternalsWhenIgnoredDirectoriesAreEmpty() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        vm.sourceControlSettings = VibeSpaceSourceControlSettings(
            ignoredDirectoryNames: [],
            scanMaxDepth: 8,
            scanMaxRepositories: 64,
            autoPresentedRepositoryLimit: 12
        )
        vm.projectReferences = [
            VibeSpaceSourceControlProjectReference(
                rootURL: tempRoot,
                title: "Temp",
                orderIndex: 0,
                projectIdentifier: tempRoot.path,
                usesProjectGitBackend: false,
                gitExplorer: nil
            )
        ]

        let filtered = vm.filteredObservedPaths(from: [
            tempRoot.appendingPathComponent(".git/index").path,
            tempRoot.appendingPathComponent(".git/refs/heads/main").path,
            tempRoot.appendingPathComponent("Sources/App/main.swift").path
        ])

        XCTAssertEqual(
            filtered,
            Set([
                tempRoot.appendingPathComponent(".git/refs/heads/main").standardizedFileURL.path,
                tempRoot.appendingPathComponent("Sources/App/main.swift").standardizedFileURL.path
            ])
        )
    }

    func testFilteredObservedPathsUsesExpectedGitPathAllowDenyMatrix() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        vm.sourceControlSettings = VibeSpaceSourceControlSettings(
            ignoredDirectoryNames: [],
            scanMaxDepth: 8,
            scanMaxRepositories: 64,
            autoPresentedRepositoryLimit: 12
        )
        vm.projectReferences = [
            VibeSpaceSourceControlProjectReference(
                rootURL: tempRoot,
                title: "Temp",
                orderIndex: 0,
                projectIdentifier: tempRoot.path,
                usesProjectGitBackend: false,
                gitExplorer: nil
            )
        ]

        let filtered = vm.filteredObservedPaths(from: [
            tempRoot.appendingPathComponent(".git").path,
            tempRoot.appendingPathComponent(".git/index").path,
            tempRoot.appendingPathComponent(".git/logs/HEAD").path,
            tempRoot.appendingPathComponent(".git/objects/ab/cd").path,
            tempRoot.appendingPathComponent(".git/HEAD").path,
            tempRoot.appendingPathComponent(".git/FETCH_HEAD").path,
            tempRoot.appendingPathComponent(".git/ORIG_HEAD").path,
            tempRoot.appendingPathComponent(".git/config").path,
            tempRoot.appendingPathComponent(".git/packed-refs").path,
            tempRoot.appendingPathComponent(".git/refs/heads/main").path,
            tempRoot.appendingPathComponent("Sources/App/main.swift").path
        ])

        XCTAssertEqual(
            filtered,
            Set([
                tempRoot.appendingPathComponent(".git/HEAD").standardizedFileURL.path,
                tempRoot.appendingPathComponent(".git/FETCH_HEAD").standardizedFileURL.path,
                tempRoot.appendingPathComponent(".git/ORIG_HEAD").standardizedFileURL.path,
                tempRoot.appendingPathComponent(".git/config").standardizedFileURL.path,
                tempRoot.appendingPathComponent(".git/packed-refs").standardizedFileURL.path,
                tempRoot.appendingPathComponent(".git/refs/heads/main").standardizedFileURL.path,
                tempRoot.appendingPathComponent("Sources/App/main.swift").standardizedFileURL.path
            ])
        )
    }

    func testRefreshRepositoriesIgnoresOnlyIgnoredDirectoryChanges() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        vm.sourceControlSettings = VibeSpaceSourceControlSettings(
            ignoredDirectoryNames: ["DerivedData"],
            scanMaxDepth: 8,
            scanMaxRepositories: 64,
            autoPresentedRepositoryLimit: 12
        )
        vm.projectReferences = [
            VibeSpaceSourceControlProjectReference(
                rootURL: tempRoot,
                title: "Temp",
                orderIndex: 0,
                projectIdentifier: tempRoot.path,
                usesProjectGitBackend: false,
                gitExplorer: nil
            )
        ]

        vm.refreshRepositories(affectedBy: [tempRoot.appendingPathComponent("DerivedData/build.log").path])
        XCTAssertTrue(vm.pendingObservedPaths.isEmpty)
        XCTAssertNil(vm.pendingObservedRefreshTask)

        let trackedFilePath = tempRoot.appendingPathComponent("Sources/App/main.swift").path
        vm.refreshRepositories(affectedBy: [trackedFilePath])
        XCTAssertEqual(
            vm.pendingObservedPaths,
            Set([URL(fileURLWithPath: trackedFilePath).standardizedFileURL.path])
        )
        XCTAssertNotNil(vm.pendingObservedRefreshTask)
    }

    func testRefreshRepositoriesIgnoresGitIndexButAllowsHeadChanges() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        vm.sourceControlSettings = .default
        vm.projectReferences = [
            VibeSpaceSourceControlProjectReference(
                rootURL: tempRoot,
                title: "Temp",
                orderIndex: 0,
                projectIdentifier: tempRoot.path,
                usesProjectGitBackend: false,
                gitExplorer: nil
            )
        ]

        vm.refreshRepositories(affectedBy: [tempRoot.appendingPathComponent(".git/index").path])
        XCTAssertTrue(vm.pendingObservedPaths.isEmpty)
        XCTAssertNil(vm.pendingObservedRefreshTask)

        let headPath = tempRoot.appendingPathComponent(".git/HEAD").path
        vm.refreshRepositories(affectedBy: [headPath])
        XCTAssertEqual(
            vm.pendingObservedPaths,
            Set([URL(fileURLWithPath: headPath).standardizedFileURL.path])
        )
        XCTAssertNotNil(vm.pendingObservedRefreshTask)
    }

    func testRefreshRepositoriesCoalescesFilteredPathsAcrossCalls() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in worker })
        vm.sourceControlSettings = VibeSpaceSourceControlSettings(
            ignoredDirectoryNames: ["DerivedData"],
            scanMaxDepth: 8,
            scanMaxRepositories: 64,
            autoPresentedRepositoryLimit: 12
        )
        vm.projectReferences = [
            VibeSpaceSourceControlProjectReference(
                rootURL: tempRoot,
                title: "Temp",
                orderIndex: 0,
                projectIdentifier: tempRoot.path,
                usesProjectGitBackend: false,
                gitExplorer: nil
            )
        ]

        let firstPath = tempRoot.appendingPathComponent("Sources/App/main.swift").path
        vm.refreshRepositories(affectedBy: [
            firstPath,
            tempRoot.appendingPathComponent(".git/index").path
        ])

        let firstTask = vm.pendingObservedRefreshTask

        let secondPath = tempRoot.appendingPathComponent("Sources/App/other.swift").path
        let headPath = tempRoot.appendingPathComponent(".git/HEAD").path
        vm.refreshRepositories(affectedBy: [
            tempRoot.appendingPathComponent("DerivedData/build.log").path,
            tempRoot.appendingPathComponent(".git/index").path,
            secondPath,
            headPath
        ])

        XCTAssertEqual(
            vm.pendingObservedPaths,
            Set([
                URL(fileURLWithPath: firstPath).standardizedFileURL.path,
                URL(fileURLWithPath: secondPath).standardizedFileURL.path,
                URL(fileURLWithPath: headPath).standardizedFileURL.path
            ])
        )
        XCTAssertTrue(firstTask?.isCancelled == true)
        XCTAssertNotNil(vm.pendingObservedRefreshTask)
    }

    func testConsumeObservedRefreshQueueRefreshesDeepestMatchingRepositoryOnly() async throws {
        let childRepositoryRoot = tempRoot.appendingPathComponent("packages/child-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: childRepositoryRoot, withIntermediateDirectories: true)

        let parentWorker = SnapshotSequenceWorker(responses: [.success(try makeSnapshotPayload())])
        let childWorker = SnapshotSequenceWorker(responses: [.success(try makeSnapshotPayload())])
        let vm = VibeSpaceSourceControlViewModel(workerFactory: { _ in parentWorker })
        vm.repositories = [
            VibeSpaceSourceControlRepositoryViewModel(
                repositoryRootURL: tempRoot,
                worker: parentWorker
            ),
            VibeSpaceSourceControlRepositoryViewModel(
                repositoryRootURL: childRepositoryRoot,
                worker: childWorker
            )
        ]
        vm.state = .ready
        vm.pendingObservedPaths = [
            childRepositoryRoot.appendingPathComponent("Sources/App/main.swift").path
        ]

        vm.consumeObservedRefreshQueue()

        let deadline = Date().addingTimeInterval(2)
        var childExecuteCount = 0
        var parentExecuteCount = 0
        while Date() < deadline {
            childExecuteCount = await childWorker.executeCount
            parentExecuteCount = await parentWorker.executeCount
            if childExecuteCount == 1 {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(childExecuteCount, 1)
        XCTAssertEqual(parentExecuteCount, 0)
    }

    func testRepositoryOpenHistoryCancelsPreviousHistoryTask() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let repo = VibeSpaceSourceControlRepositoryViewModel(
            repositoryRootURL: tempRoot,
            worker: worker
        )
        let oldTask: Task<Void, Never> = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
        repo.activeHistoryTask = oldTask
        repo.openHistory(scope: .repository)
        XCTAssertTrue(oldTask.isCancelled)
        XCTAssertNotNil(repo.activeHistoryTask)
    }

    func testRepositoryDismissHistoryCancelsActiveHistoryTask() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let repo = VibeSpaceSourceControlRepositoryViewModel(
            repositoryRootURL: tempRoot,
            worker: worker
        )
        let task: Task<Void, Never> = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
        repo.activeHistoryTask = task
        repo.activeHistoryScope = .repository
        repo.dismissHistory()
        XCTAssertTrue(task.isCancelled)
    }

    func testRepositoryRunMutationCancelsPreviousMutationTask() async {
        let worker = SnapshotSequenceWorker(responses: [])
        let repo = VibeSpaceSourceControlRepositoryViewModel(
            repositoryRootURL: tempRoot,
            worker: worker
        )
        let oldTask: Task<Void, Never> = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
        repo.activeMutationTask = oldTask
        repo.runMutation(
            activityMessage: "test",
            method: .gitStageAll,
            arguments: ["rootPath": tempRoot.path]
        )
        XCTAssertTrue(oldTask.isCancelled)
        XCTAssertNotNil(repo.activeMutationTask)
    }

    private func initializeGitRepository(at url: URL) throws {
        let result = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "init"],
            workingDirectory: url
        )
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    }

    private func makeSnapshotPayload(
        entries: [WorkerGitStatusNode] = [],
        currentBranch: String? = nil,
        branches: [WorkerGitBranchNode] = []
    ) throws -> Data {
        try JSONEncoder().encode(
            WorkerGitRepositorySnapshotPayload(
                gitAvailable: true,
                repository: true,
                entries: entries,
                currentBranch: currentBranch,
                branches: branches,
                message: nil
            )
        )
    }

    private func configureGitIdentity(at url: URL) throws {
        let email = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "config", "user.email", "tests@crispyvibes.dev"],
            workingDirectory: url
        )
        XCTAssertEqual(email.terminationStatus, 0, email.stderr)

        let name = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "config", "user.name", "CrispyVibes Tests"],
            workingDirectory: url
        )
        XCTAssertEqual(name.terminationStatus, 0, name.stderr)
    }

    private func stageAll(in url: URL) throws {
        let result = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "add", "-A"],
            workingDirectory: url
        )
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    }

    private func commitAll(in url: URL, message: String) throws {
        let result = try runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "commit", "-m", message],
            workingDirectory: url
        )
        XCTAssertEqual(result.terminationStatus, 0, result.stderr)
    }

    @MainActor
    private final class RemoteGitExplorerStub: GitExploring {
        let commandExecutor: any CommandExecuting = LocalCommandExecutor()

        @Published var isAvailable: Bool = true
        @Published var statusItems: [GitStatusItem]
        @Published var branchOptions: [GitBranchOption]
        @Published var currentBranchName: String?
        @Published var gitState: FolderExplorerViewModel.GitState = .ready
        @Published var commitMessageDraft: String = ""
        @Published var isOperating: Bool = false
        @Published var operationMessage: String?
        @Published var historyEntries: [GitCommitEntry] = []
        @Published var isHistoryLoading: Bool = false
        @Published var activeHistoryScope: GitHistoryScope?

        var discoverCallCount = 0
        var loadStatusCallCount = 0
        var loadBranchesCallCount = 0
        var isDiscovering = false

        private let discoveredRepositoryRoots: [String]
        private let discoverPayload: WorkerGitRepositoryDiscoveryPayload?
        private let discoverError: Error?
        private let discoverDelayNanoseconds: UInt64

        init(
            discoveredRepositoryRoots: [String],
            discoverPayload: WorkerGitRepositoryDiscoveryPayload? = nil,
            discoverError: Error? = nil,
            discoverDelayNanoseconds: UInt64 = 0,
            statusItems: [GitStatusItem] = [],
            branchOptions: [GitBranchOption] = [],
            currentBranchName: String? = nil
        ) {
            self.discoveredRepositoryRoots = discoveredRepositoryRoots
            self.discoverPayload = discoverPayload
            self.discoverError = discoverError
            self.discoverDelayNanoseconds = discoverDelayNanoseconds
            self.statusItems = statusItems
            self.branchOptions = branchOptions
            self.currentBranchName = currentBranchName
        }

        func discoverRepositories(at rootPath: String) async throws -> WorkerGitRepositoryDiscoveryPayload {
            discoverCallCount += 1
            isDiscovering = true
            defer { isDiscovering = false }
            if discoverDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: discoverDelayNanoseconds)
            }
            if let discoverError {
                throw discoverError
            }
            if let discoverPayload {
                return discoverPayload
            }
            return WorkerGitRepositoryDiscoveryPayload(
                gitAvailable: true,
                repositories: discoveredRepositoryRoots.map { WorkerGitRepositoryNode(repositoryRootPath: $0) },
                message: nil
            )
        }

        func loadStatus(for rootPath: String) async throws {
            loadStatusCallCount += 1
        }

        func stage(files: [String], in rootPath: String) async throws {}
        func unstage(files: [String], in rootPath: String) async throws {}
        func commit(message: String, in rootPath: String) async throws {}
        func checkout(branch: String, isRemoteBranch: Bool, in rootPath: String) async throws {}

        func loadBranches(for rootPath: String) async throws {
            loadBranchesCallCount += 1
        }

        func loadDiff(relativePath: String, in rootPath: String) async throws -> String { "" }
        func loadHistory(for rootPath: String, scope: GitHistoryScope?) async throws {}
    }

    private enum TestError: LocalizedError {
        case sshUnavailable

        var errorDescription: String? {
            switch self {
            case .sshUnavailable:
                return "SSH connection failed."
            }
        }
    }

    private actor SnapshotSequenceWorker: PaneWorkerExecuting {
        enum Response {
            case success(Data)
            case failure(Error)
        }

        private var responses: [Response]
        private var executionCountValue = 0

        init(responses: [Response]) {
            self.responses = responses
        }

        var executeCount: Int { executionCountValue }

        func restart() async {}

        func execute(
            _ method: PaneWorkerMethod,
            arguments: [String: String],
            timeout: TimeInterval
        ) async throws -> String? {
            guard method == .gitRepositorySnapshot else {
                throw PaneWorkerError.workerFailure("Unexpected method: \(method.rawValue)")
            }
            guard !responses.isEmpty else {
                throw PaneWorkerError.workerFailure("No stubbed response available")
            }
            executionCountValue += 1
            let response = responses.removeFirst()
            switch response {
            case .success(let data):
                return String(decoding: data, as: UTF8.self)
            case .failure(let error):
                throw error
            }
        }
    }

    private actor BlockingSnapshotSequenceWorker: PaneWorkerExecuting {
        enum Response {
            case success(Data)
            case failure(Error)
        }

        private var responses: [Response]
        private var executionCountValue = 0
        private var firstExecutionStartedContinuation: CheckedContinuation<Void, Never>?
        private var firstExecutionReleaseContinuation: CheckedContinuation<Void, Never>?

        init(responses: [Response]) {
            self.responses = responses
        }

        var executeCount: Int { executionCountValue }

        func restart() async {}

        func waitForFirstExecution() async {
            if executionCountValue >= 1 { return }
            await withCheckedContinuation { continuation in
                firstExecutionStartedContinuation = continuation
            }
        }

        func releaseFirstExecution() {
            firstExecutionReleaseContinuation?.resume()
            firstExecutionReleaseContinuation = nil
        }

        func execute(
            _ method: PaneWorkerMethod,
            arguments: [String: String],
            timeout: TimeInterval
        ) async throws -> String? {
            guard method == .gitRepositorySnapshot else {
                throw PaneWorkerError.workerFailure("Unexpected method: \(method.rawValue)")
            }
            guard !responses.isEmpty else {
                throw PaneWorkerError.workerFailure("No stubbed response available")
            }

            executionCountValue += 1
            let response = responses.removeFirst()

            if executionCountValue == 1 {
                firstExecutionStartedContinuation?.resume()
                firstExecutionStartedContinuation = nil
                await withCheckedContinuation { continuation in
                    firstExecutionReleaseContinuation = continuation
                }
            }

            switch response {
            case .success(let data):
                return String(decoding: data, as: UTF8.self)
            case .failure(let error):
                throw error
            }
        }
    }
}
