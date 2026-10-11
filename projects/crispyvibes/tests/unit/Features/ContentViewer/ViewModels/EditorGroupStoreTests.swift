import Foundation
import XCTest
@testable import CrispyVibes

actor RecordingFileContentProvider: FileContentProviding {
    private let contentByPath: [String: Data]
    private var readPaths: [String] = []

    init(contentByPath: [String: Data]) {
        self.contentByPath = contentByPath
    }

    func readFile(at path: String) async throws -> Data {
        readPaths.append(path)
        guard let data = contentByPath[path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func writeFile(at path: String, contents: Data) async throws {}

    func recordedReadPaths() -> [String] {
        readPaths
    }
}

private actor RecordingPaneWorker: PaneWorkerExecuting {
    private let readFileContents: [String: String]
    private let gitFileContents: [String: String]
    private var invocations: [(method: PaneWorkerMethod, arguments: [String: String])] = []

    init(
        readFileContents: [String: String] = [:],
        gitFileContents: [String: String] = [:]
    ) {
        self.readFileContents = readFileContents
        self.gitFileContents = gitFileContents
    }

    func restart() async {}

    func execute(
        _ method: PaneWorkerMethod,
        arguments: [String: String],
        timeout: TimeInterval
    ) async throws -> String? {
        invocations.append((method, arguments))
        switch method {
        case .readFile:
            let path = arguments["filePath"] ?? ""
            guard let content = readFileContents[path] else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return content
        case .gitFileContent:
            let path = arguments["relativePath"] ?? ""
            guard let content = gitFileContents[path] else {
                throw PaneWorkerError.workerFailure("No git content for \(path)")
            }
            return content
        case .gitDiff:
            return "diff"
        default:
            return nil
        }
    }

    func recordedInvocations() -> [(PaneWorkerMethod, [String: String])] {
        invocations
    }
}

@MainActor
final class EditorGroupStoreTests: XCTestCase {
    private var container: AppContainer!
    private var group: EditorGroupStore!
    private var dockedFileViewerCoordinator: DockedFileViewerCoordinator!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        group = EditorGroupStore(markdownViewModel: container.makeMarkdownViewModel(bufferStore: DocumentBufferStore()), commentsPanel: CommentsPanelStore())
        dockedFileViewerCoordinator = DockedFileViewerCoordinator(
            editorGroupFactory: { [container] id in
                EditorGroupStore(id: id, markdownViewModel: container!.makeMarkdownViewModel(bufferStore: DocumentBufferStore()), commentsPanel: CommentsPanelStore())
            }
        )
    }

    override func tearDownWithError() throws {
        dockedFileViewerCoordinator = nil
        group = nil
        container = nil
    }

    func testLinkedMarkdownFileOpensThroughOwningEditorGroup() async throws {
        let sourceURL = URL(fileURLWithPath: "/remote/project/source.md")
        let targetURL = URL(fileURLWithPath: "/remote/project/guide.md")
        let projectIdentifier = "remote-project"
        let provider = RecordingFileContentProvider(
            contentByPath: [
                sourceURL.path: Data("[Guide](guide.md#setup)".utf8),
                targetURL.path: Data("# Setup".utf8)
            ]
        )

        group.openFileInTab(
            at: sourceURL,
            projectIdentifier: projectIdentifier,
            fileContentProvider: provider
        )
        let sourceOpened = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.rawContent.contains("Guide")
        }
        XCTAssertTrue(sourceOpened)

        group.markdownViewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInCrispy,
                targetKind: .localFile,
                href: "guide.md#setup",
                resolvedURL: targetURL.absoluteString + "#setup",
                fragment: "setup"
            )
        )

        let targetReference = FileDocumentReference(
            url: targetURL,
            projectIdentifier: projectIdentifier
        )
        let targetTab = ContentViewerTab.file(reference: targetReference)
        XCTAssertEqual(group.activeTabID, targetTab.id)
        XCTAssertTrue(group.tabs.contains { $0.id == targetTab.id })
        XCTAssertNotNil(group.fileContentProvider(for: targetTab.id))
        XCTAssertEqual(
            group.markdownViewModel.richNavigationRequest(
                for: targetReference.documentIdentity
            )?.fragment,
            "setup"
        )
    }

    func testActivateTabRestoresProviderForThatFile() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/provider-a.md")
        let secondURL = URL(fileURLWithPath: "/tmp/provider-b.md")
        let firstProvider = RecordingFileContentProvider(
            contentByPath: [firstURL.path: Data("alpha".utf8)]
        )
        let secondProvider = RecordingFileContentProvider(
            contentByPath: [secondURL.path: Data("beta".utf8)]
        )

        group.openFileInTab(at: firstURL, fileContentProvider: firstProvider)
        let didOpenFirstFile = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "alpha"
        }
        XCTAssertTrue(didOpenFirstFile)

        group.openFileInTab(at: secondURL, fileContentProvider: secondProvider)
        let didOpenSecondFile = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "beta"
        }
        XCTAssertTrue(didOpenSecondFile)

        group.activateTab(ContentViewerTab.file(url: firstURL).id)
        let didRestoreFirstFile = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "alpha"
        }
        XCTAssertTrue(didRestoreFirstFile)

        let firstProviderReads = await firstProvider.recordedReadPaths()
        let secondProviderReads = await secondProvider.recordedReadPaths()
        XCTAssertEqual(firstProviderReads, [firstURL.path])
        XCTAssertEqual(secondProviderReads, [secondURL.path])
    }

    func testSameFilePathInDifferentProjectsGetsDistinctTabsAndProviders() async throws {
        let sharedURL = URL(fileURLWithPath: "/tmp/shared.md")
        let providerA = RecordingFileContentProvider(contentByPath: [sharedURL.path: Data("alpha".utf8)])
        let providerB = RecordingFileContentProvider(contentByPath: [sharedURL.path: Data("beta".utf8)])

        group.openFileInTab(
            at: sharedURL,
            projectIdentifier: "project-a",
            fileContentProvider: providerA
        )
        let didOpenProjectA = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "alpha"
        }
        XCTAssertTrue(didOpenProjectA)

        group.openFileInTab(
            at: sharedURL,
            projectIdentifier: "project-b",
            fileContentProvider: providerB
        )
        let didOpenProjectB = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "beta"
        }
        XCTAssertTrue(didOpenProjectB)

        XCTAssertEqual(group.tabs.count, 2)

        group.activateTab(ContentViewerTab.file(url: sharedURL, projectIdentifier: "project-a").id)
        let didRestoreProjectA = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "alpha"
        }
        XCTAssertTrue(didRestoreProjectA)

        group.activateTab(ContentViewerTab.file(url: sharedURL, projectIdentifier: "project-b").id)
        let didRestoreProjectB = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "beta"
        }
        XCTAssertTrue(didRestoreProjectB)

        let providerAReads = await providerA.recordedReadPaths()
        let providerBReads = await providerB.recordedReadPaths()
        XCTAssertEqual(providerAReads, [sharedURL.path])
        XCTAssertEqual(providerBReads, [sharedURL.path])
    }

    func testDockedFileViewerCoordinatorReopensExistingGroupWithProviderAwareReference() async throws {
        let remoteURL = URL(fileURLWithPath: "/remote/project/readme.md")
        let remoteReference = FileDocumentReference(
            url: remoteURL,
            projectIdentifier: "remote-project"
        )
        let remoteProvider = RecordingFileContentProvider(
            contentByPath: [remoteURL.path: Data("remote".utf8)]
        )
        let tileID = UUID()

        _ = dockedFileViewerCoordinator.editorGroup(for: tileID, fileURL: remoteURL)
        let upgradedGroup = dockedFileViewerCoordinator.editorGroup(
            for: tileID,
            fileURL: remoteURL,
            documentReference: remoteReference,
            fileContentProvider: remoteProvider
        )

        let didOpenRemoteFile = await waitForCondition(timeout: 8) {
            upgradedGroup.activeTabID == ContentViewerTab.file(reference: remoteReference).id &&
            upgradedGroup.markdownViewModel.workerStatus == .ready &&
            upgradedGroup.markdownViewModel.rawContent == "remote"
        }
        XCTAssertTrue(didOpenRemoteFile)
        let remoteProviderReads = await remoteProvider.recordedReadPaths()
        XCTAssertEqual(remoteProviderReads, [remoteURL.path])
    }

    func testActivatingDeletedGitPreviewTabReloadsGitContentInsteadOfReadingDisk() async throws {
        let deletedURL = URL(fileURLWithPath: "/tmp/deleted.swift")
        let otherURL = URL(fileURLWithPath: "/tmp/other.swift")
        let worker = RecordingPaneWorker(
            readFileContents: [otherURL.path: "other"],
            gitFileContents: ["Sources/deleted.swift": "previous revision"]
        )
        let markdownViewModel = MarkdownViewModel(worker: worker, bufferStore: DocumentBufferStore())
        let localGroup = EditorGroupStore(markdownViewModel: markdownViewModel, commentsPanel: CommentsPanelStore())

        localGroup.previewGitFileContent(
            rootURL: URL(fileURLWithPath: "/tmp/repo"),
            fileURL: deletedURL,
            relativePath: "Sources/deleted.swift",
            titleSuffix: "Deleted"
        )
        let didOpenDeletedPreview = await waitForCondition(timeout: 8) {
            localGroup.markdownViewModel.workerStatus == .ready &&
            localGroup.markdownViewModel.rawContent == "previous revision"
        }
        XCTAssertTrue(didOpenDeletedPreview)

        localGroup.openFileInTab(at: otherURL)
        let didOpenOtherFile = await waitForCondition(timeout: 8) {
            localGroup.markdownViewModel.workerStatus == .ready &&
            localGroup.markdownViewModel.rawContent == "other"
        }
        XCTAssertTrue(didOpenOtherFile)

        localGroup.activateTab(ContentViewerTab.file(url: deletedURL).id)
        let didRestoreDeletedPreview = await waitForCondition(timeout: 8) {
            localGroup.markdownViewModel.workerStatus == .ready &&
            localGroup.markdownViewModel.rawContent == "previous revision" &&
            localGroup.markdownViewModel.errorMessage == nil
        }
        XCTAssertTrue(didRestoreDeletedPreview)

        let deletedReadAttempts = await worker.recordedInvocations().filter {
            $0.0 == .readFile && $0.1["filePath"] == deletedURL.path
        }
        let deletedGitLoads = await worker.recordedInvocations().filter {
            $0.0 == .gitFileContent && $0.1["relativePath"] == "Sources/deleted.swift"
        }

        XCTAssertTrue(deletedReadAttempts.isEmpty)
        XCTAssertEqual(deletedGitLoads.count, 2)
    }
}


@MainActor
final class EditorGroupNavigationRegressionTests: XCTestCase {
    private var container: AppContainer!
    private var group: EditorGroupStore!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        group = makeGroup()
    }

    override func tearDownWithError() throws {
        group = nil
        container = nil
    }

    func testRenderedMarkdownLocalLinkRecordsCrossFileBackAndForwardHistory() async throws {
        let root = try makeTempDirectory(prefix: "crispyvibes-editor-navigation")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("A.md")
        let targetURL = root.appendingPathComponent("B.md")
        try Data("[B](B.md)".utf8).write(to: sourceURL)
        try Data("# B".utf8).write(to: targetURL)
        let provider = LocalFileContentProvider()
        let projectIdentifier = root.path

        group.openFileInTab(
            at: sourceURL,
            projectIdentifier: projectIdentifier,
            fileContentProvider: provider
        )
        let sourceLoaded = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.rawContent.contains("[B]")
        }
        XCTAssertTrue(sourceLoaded)

        group.markdownViewModel.handleMarkdownLinkAction(
            localLinkRequest(to: targetURL, href: "B.md")
        )

        let sourceTabID = ContentViewerTab.file(url: sourceURL, projectIdentifier: projectIdentifier).id
        let targetTabID = ContentViewerTab.file(url: targetURL, projectIdentifier: projectIdentifier).id
        XCTAssertEqual(group.activeTabID, targetTabID)
        XCTAssertTrue(group.canNavigateBack)

        group.navigateBack()
        XCTAssertEqual(group.activeTabID, sourceTabID)
        XCTAssertTrue(group.canNavigateForward)

        group.navigateForward()
        XCTAssertEqual(group.activeTabID, targetTabID)
    }

    func testDockedRootLookupAndProviderUpgradePreserveActiveLinkedFile() async throws {
        let root = try makeTempDirectory(prefix: "crispyvibes-docked-editor-navigation")
        defer { try? FileManager.default.removeItem(at: root) }
        let rootURL = root.appendingPathComponent("A.md")
        let linkedURL = root.appendingPathComponent("B.md")
        let rootProvider = RecordingFileContentProvider(
            contentByPath: [rootURL.path: Data("# A".utf8)]
        )
        let linkedProvider = RecordingFileContentProvider(
            contentByPath: [linkedURL.path: Data("# B".utf8)]
        )
        let linkedReference = FileDocumentReference(
            url: linkedURL,
            projectIdentifier: root.path
        )

        group.openFileInTab(at: rootURL, fileContentProvider: rootProvider)
        group.openFileInTab(
            at: linkedURL,
            documentReference: linkedReference,
            fileContentProvider: linkedProvider
        )
        let linkedLoaded = await waitForCondition(timeout: 8) {
            self.group.markdownViewModel.rawContent == "# B"
        }
        XCTAssertTrue(linkedLoaded)

        let tileID = UUID()
        let coordinator = DockedFileViewerCoordinator(editorGroupFactory: { _ in
            XCTFail("The assigned live group must be reused")
            return self.makeGroup()
        })
        coordinator.assignEditorGroup(group, for: tileID, fileURL: rootURL)

        let repeated = coordinator.editorGroup(for: tileID, fileURL: rootURL)
        XCTAssertTrue(repeated === group)
        XCTAssertEqual(group.activeFileDocumentReference, linkedReference)
        XCTAssertTrue(group.activeFileContentProvider as AnyObject === linkedProvider)

        let qualifiedRoot = FileDocumentReference(
            url: rootURL,
            projectIdentifier: root.path
        )
        let upgraded = coordinator.editorGroup(
            for: tileID,
            fileURL: rootURL,
            documentReference: qualifiedRoot,
            fileContentProvider: rootProvider
        )

        XCTAssertTrue(upgraded === group)
        XCTAssertEqual(group.activeFileDocumentReference, linkedReference)
        XCTAssertTrue(group.activeFileContentProvider as AnyObject === linkedProvider)
        XCTAssertNotNil(group.fileContentProvider(for: ContentViewerTab.file(reference: qualifiedRoot).id))
        XCTAssertTrue(group.tabs.contains { $0.id == ContentViewerTab.file(reference: qualifiedRoot).id })
        XCTAssertFalse(group.tabs.contains { $0.id == ContentViewerTab.file(url: rootURL).id })
    }

    func testClosingTabsPrunesBackAndForwardHistorySafely() throws {
        let root = try makeTempDirectory(prefix: "crispyvibes-editor-closed-history")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A.md")
        let b = root.appendingPathComponent("B.md")
        let c = root.appendingPathComponent("C.md")
        try Data("[B](B.md)".utf8).write(to: a)
        try Data("[C](C.md)".utf8).write(to: b)
        try Data("# C".utf8).write(to: c)
        let projectIdentifier = root.path

        group.openFileInTab(at: a, projectIdentifier: projectIdentifier, fileContentProvider: LocalFileContentProvider())
        group.markdownViewModel.handleMarkdownLinkAction(localLinkRequest(to: b, href: "B.md"))
        group.markdownViewModel.handleMarkdownLinkAction(localLinkRequest(to: c, href: "C.md"))
        group.navigateBack()

        let aID = ContentViewerTab.file(url: a, projectIdentifier: projectIdentifier).id
        let bID = ContentViewerTab.file(url: b, projectIdentifier: projectIdentifier).id
        let cID = ContentViewerTab.file(url: c, projectIdentifier: projectIdentifier).id
        XCTAssertEqual(group.activeTabID, bID)
        XCTAssertTrue(group.canNavigateBack)
        XCTAssertTrue(group.canNavigateForward)

        group.closeTab(aID)
        group.closeTab(cID)

        XCTAssertEqual(group.activeTabID, bID)
        XCTAssertFalse(group.canNavigateBack)
        XCTAssertFalse(group.canNavigateForward)
        group.navigateBack()
        group.navigateForward()
        XCTAssertEqual(group.activeTabID, bID)
    }

    func testSameDocumentNavigationCommandTakesPrecedenceThenFallbackUsesCrossFileHistory() throws {
        let root = try makeTempDirectory(prefix: "crispyvibes-editor-native-fallback")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A.md")
        let b = root.appendingPathComponent("B.md")
        try Data("[B](B.md)".utf8).write(to: a)
        try Data("# B".utf8).write(to: b)
        let projectIdentifier = root.path
        let sourceReference = FileDocumentReference(url: a, projectIdentifier: projectIdentifier)
        let targetReference = FileDocumentReference(url: b, projectIdentifier: projectIdentifier)

        group.openFileInTab(at: a, documentReference: sourceReference, fileContentProvider: LocalFileContentProvider())
        group.markdownViewModel.handleMarkdownLinkAction(localLinkRequest(to: b, href: "B.md"))
        group.markdownViewModel.updateRenderedNavigationState(
            MarkdownNavigationState(
                documentID: targetReference.documentIdentity,
                canNavigateBack: true,
                canNavigateForward: true
            )
        )

        group.navigateBack()

        let backCommand = group.markdownViewModel.renderedNavigationCommand(
            for: targetReference.documentIdentity
        )
        XCTAssertEqual(backCommand?.documentID, targetReference.documentIdentity)
        XCTAssertEqual(backCommand?.direction, .back)
        XCTAssertEqual(group.activeFileDocumentReference, targetReference)

        group.navigateForward()
        let forwardCommand = group.markdownViewModel.renderedNavigationCommand(
            for: targetReference.documentIdentity
        )
        XCTAssertEqual(forwardCommand?.documentID, targetReference.documentIdentity)
        XCTAssertEqual(forwardCommand?.direction, .forward)
        XCTAssertEqual(group.activeFileDocumentReference, targetReference)

        group.markdownViewModel.handleRenderedNavigationFallback(.back)
        XCTAssertEqual(group.activeFileDocumentReference, sourceReference)
    }

    func testRetargetMapsLinkedBackAndForwardHistoryToRenamedTabs() throws {
        let parent = try makeTempDirectory(prefix: "crispyvibes-editor-retarget-history")
        defer { try? FileManager.default.removeItem(at: parent) }
        let originalRoot = parent.appendingPathComponent("original", isDirectory: true)
        let renamedRoot = parent.appendingPathComponent("renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: originalRoot, withIntermediateDirectories: true)
        let originalA = originalRoot.appendingPathComponent("A.md")
        let originalB = originalRoot.appendingPathComponent("B.md")
        try Data("[B](B.md)".utf8).write(to: originalA)
        try Data("# B".utf8).write(to: originalB)
        let projectIdentifier = originalRoot.path

        group.openFileInTab(
            at: originalA,
            projectIdentifier: projectIdentifier,
            fileContentProvider: LocalFileContentProvider()
        )
        group.markdownViewModel.handleMarkdownLinkAction(localLinkRequest(to: originalB, href: "B.md"))
        try FileManager.default.moveItem(at: originalRoot, to: renamedRoot)
        group.retargetFileSystemLocation(from: originalRoot, to: renamedRoot)

        let renamedAID = ContentViewerTab.file(
            url: renamedRoot.appendingPathComponent("A.md"),
            projectIdentifier: projectIdentifier
        ).id
        let renamedBID = ContentViewerTab.file(
            url: renamedRoot.appendingPathComponent("B.md"),
            projectIdentifier: projectIdentifier
        ).id
        XCTAssertEqual(group.activeTabID, renamedBID)

        group.navigateBack()
        XCTAssertEqual(group.activeTabID, renamedAID)
        XCTAssertTrue(group.canNavigateForward)

        group.navigateForward()
        XCTAssertEqual(group.activeTabID, renamedBID)
    }

    private func makeGroup() -> EditorGroupStore {
        EditorGroupStore(
            markdownViewModel: container.makeMarkdownViewModel(bufferStore: DocumentBufferStore()),
            commentsPanel: CommentsPanelStore()
        )
    }

    private func localLinkRequest(to url: URL, href: String) -> MarkdownLinkActionRequest {
        MarkdownLinkActionRequest(
            action: .openInCrispy,
            targetKind: .localFile,
            href: href,
            resolvedURL: url.absoluteString,
            fragment: nil
        )
    }
}


@MainActor
final class EditorIdentityMigrationRegressionTests: XCTestCase {
    func testProjectQualificationMigratesAllActiveMarkdownStateAndGroupHistory() async throws {
        let root = try makeTempDirectory(prefix: "crispyvibes-project-qualification")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A.md")
        let b = root.appendingPathComponent("B.md")
        try Data("[B](B.md)".utf8).write(to: a)
        try Data("# B".utf8).write(to: b)
        let container = AppContainer.makeDefault()
        let viewModel = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
        let group = EditorGroupStore(markdownViewModel: viewModel, commentsPanel: CommentsPanelStore())
        let oldReference = FileDocumentReference(url: b)
        let newReference = FileDocumentReference(url: b, projectIdentifier: root.path)

        group.openFileInTab(at: a, fileContentProvider: LocalFileContentProvider())
        viewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInCrispy,
                targetKind: .localFile,
                href: "B.md",
                resolvedURL: b.absoluteString,
                fragment: nil
            )
        )
        let loaded = await waitForCondition(timeout: 8) { viewModel.rawContent == "# B" }
        XCTAssertTrue(loaded)
        viewModel.userDidEdit("# Unsaved B")
        seedMigratingState(on: viewModel, documentID: oldReference.documentIdentity)

        group.upgradeFileReference(
            from: oldReference,
            to: newReference,
            fileContentProvider: LocalFileContentProvider()
        )

        assertMigratedState(
            viewModel,
            oldID: oldReference.documentIdentity,
            newID: newReference.documentIdentity,
            expectedURL: b
        )
        XCTAssertEqual(viewModel.displayContent, "# Unsaved B")
        XCTAssertTrue(viewModel.activeBuffer?.isDirty == true)
        XCTAssertEqual(group.activeTabID, ContentViewerTab.file(reference: newReference).id)

        clearRenderedBackState(on: viewModel, documentID: newReference.documentIdentity)
        group.navigateBack()
        XCTAssertEqual(group.activeFileDocumentReference?.url, a.standardizedFileURL)
        group.navigateForward()
        XCTAssertEqual(group.activeFileDocumentReference, newReference)
    }

    func testFilesystemRenameMigratesAllActiveMarkdownStateBufferAndGroupHistory() async throws {
        let parent = try makeTempDirectory(prefix: "crispyvibes-filesystem-rename")
        defer { try? FileManager.default.removeItem(at: parent) }
        let originalRoot = parent.appendingPathComponent("original", isDirectory: true)
        let renamedRoot = parent.appendingPathComponent("renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: originalRoot, withIntermediateDirectories: true)
        let oldA = originalRoot.appendingPathComponent("A.md")
        let oldB = originalRoot.appendingPathComponent("B.md")
        try Data("[B](B.md)".utf8).write(to: oldA)
        try Data("# B".utf8).write(to: oldB)
        let projectIdentifier = originalRoot.path
        let container = AppContainer.makeDefault()
        let viewModel = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
        let group = EditorGroupStore(markdownViewModel: viewModel, commentsPanel: CommentsPanelStore())
        let oldReference = FileDocumentReference(url: oldB, projectIdentifier: projectIdentifier)
        let newB = renamedRoot.appendingPathComponent("B.md")
        let newReference = FileDocumentReference(url: newB, projectIdentifier: projectIdentifier)

        group.openFileInTab(
            at: oldA,
            projectIdentifier: projectIdentifier,
            fileContentProvider: LocalFileContentProvider()
        )
        viewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInCrispy,
                targetKind: .localFile,
                href: "B.md",
                resolvedURL: oldB.absoluteString,
                fragment: nil
            )
        )
        let loaded = await waitForCondition(timeout: 8) { viewModel.rawContent == "# B" }
        XCTAssertTrue(loaded)
        viewModel.userDidEdit("# Flushed before rename")
        seedMigratingState(on: viewModel, documentID: oldReference.documentIdentity)
        group.flushUnsavedEdits(forFileURL: oldB)

        try FileManager.default.moveItem(at: originalRoot, to: renamedRoot)
        group.retargetFileSystemLocation(from: originalRoot, to: renamedRoot)

        assertMigratedState(
            viewModel,
            oldID: oldReference.documentIdentity,
            newID: newReference.documentIdentity,
            expectedURL: newB
        )
        XCTAssertEqual(viewModel.displayContent, "# Flushed before rename")
        XCTAssertEqual(try String(contentsOf: newB, encoding: .utf8), "# Flushed before rename")
        XCTAssertEqual(group.activeTabID, ContentViewerTab.file(reference: newReference).id)

        clearRenderedBackState(on: viewModel, documentID: newReference.documentIdentity)
        group.navigateBack()
        XCTAssertEqual(group.activeFileDocumentReference?.url, renamedRoot.appendingPathComponent("A.md").standardizedFileURL)
        group.navigateForward()
        XCTAssertEqual(group.activeFileDocumentReference, newReference)
    }

    func testCrossFileHistoryKeepsNewestChronologicalSuffixAtLimit() throws {
        let root = try makeTempDirectory(prefix: "crispyvibes-editor-history-limit")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = AppContainer.makeDefault()
        let viewModel = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
        let group = EditorGroupStore(markdownViewModel: viewModel, commentsPanel: CommentsPanelStore())
        let urls = (0...(EditorGroupStore.navigationHistoryLimit + 1)).map {
            root.appendingPathComponent("\($0).md")
        }
        for url in urls { try Data("# \(url.lastPathComponent)".utf8).write(to: url) }
        group.openFileInTab(at: urls[0], fileContentProvider: LocalFileContentProvider())
        for target in urls.dropFirst() {
            viewModel.handleMarkdownLinkAction(
                MarkdownLinkActionRequest(
                    action: .openInCrispy,
                    targetKind: .localFile,
                    href: target.lastPathComponent,
                    resolvedURL: target.absoluteString,
                    fragment: nil
                )
            )
        }

        XCTAssertEqual(group.backNavigationTabIDsSnapshot.count, EditorGroupStore.navigationHistoryLimit)
        XCTAssertEqual(group.backNavigationTabIDsSnapshot.first, ContentViewerTab.file(url: urls[1]).id)
        XCTAssertEqual(group.backNavigationTabIDsSnapshot.last, ContentViewerTab.file(url: urls[EditorGroupStore.navigationHistoryLimit]).id)

        for _ in 0..<EditorGroupStore.navigationHistoryLimit { group.navigateBack() }
        XCTAssertEqual(group.activeTabID, ContentViewerTab.file(url: urls[1]).id)
        XCTAssertFalse(group.canNavigateBack)
        XCTAssertEqual(group.forwardNavigationTabIDsSnapshot.count, EditorGroupStore.navigationHistoryLimit)
        for _ in 0..<EditorGroupStore.navigationHistoryLimit { group.navigateForward() }
        XCTAssertEqual(group.activeTabID, ContentViewerTab.file(url: urls.last!).id)
    }

    private func seedMigratingState(on viewModel: MarkdownViewModel, documentID: String) {
        viewModel.setCurrentMarkupViewMode(.source)
        viewModel.pendingSourceSelection = MarkdownViewModel.PendingSourceSelection(
            documentID: documentID,
            selection: .init(line: 7, column: 3)
        )
        viewModel.updateRenderedNavigationState(
            MarkdownNavigationState(
                documentID: documentID,
                canNavigateBack: true,
                canNavigateForward: true,
                backScrollPositions: [.init(x: 0, y: 120)],
                forwardScrollPositions: [.init(x: 0, y: 240)]
            )
        )
        viewModel.setPendingRichNavigationRequest(
            MarkdownRichNavigationRequest(documentID: documentID, fragment: "section")
        )
        viewModel.requestRenderedNavigation(.back)
    }

    private func assertMigratedState(
        _ viewModel: MarkdownViewModel,
        oldID: String,
        newID: String,
        expectedURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(viewModel.currentDocumentID, newID, file: file, line: line)
        XCTAssertEqual(viewModel.activeEditorTabID, newID, file: file, line: line)
        XCTAssertEqual(viewModel.fileURL, expectedURL.standardizedFileURL, file: file, line: line)
        XCTAssertEqual(viewModel.currentMarkupViewMode, .source, file: file, line: line)
        XCTAssertEqual(viewModel.pendingSourceSelection?.documentID, newID, file: file, line: line)
        XCTAssertEqual(viewModel.pendingRichNavigationRequest?.documentID, newID, file: file, line: line)
        XCTAssertEqual(viewModel.renderedNavigationCommandRequest?.documentID, newID, file: file, line: line)
        XCTAssertEqual(viewModel.renderedNavigationState(for: newID)?.documentID, newID, file: file, line: line)
        XCTAssertEqual(viewModel.renderedNavigationState(for: newID)?.backScrollPositions.count, 1, file: file, line: line)
        XCTAssertEqual(viewModel.renderedNavigationState(for: newID)?.forwardScrollPositions.count, 1, file: file, line: line)
        XCTAssertNil(viewModel.renderedNavigationState(for: oldID), file: file, line: line)
        XCTAssertNil(viewModel.bufferStore.buffer(for: oldID), file: file, line: line)
        XCTAssertNotNil(viewModel.bufferStore.buffer(for: newID), file: file, line: line)
    }

    private func clearRenderedBackState(on viewModel: MarkdownViewModel, documentID: String) {
        if let command = viewModel.renderedNavigationCommandRequest {
            XCTAssertTrue(viewModel.claimRenderedNavigationCommand(id: command.id))
        }
        viewModel.updateRenderedNavigationState(
            MarkdownNavigationState(
                documentID: documentID,
                canNavigateBack: false,
                canNavigateForward: false
            )
        )
    }
}
