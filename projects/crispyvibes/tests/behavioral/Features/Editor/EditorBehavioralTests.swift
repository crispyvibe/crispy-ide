import XCTest
@testable import CrispyVibes

@MainActor
final class EditorBehavioralTests: XCTestCase {
    private final class NoopDetachedWindowManager: EditorDetachedWindowManaging {
        func openWindow(for fileURL: URL) {}
    }

    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        tempRoot = base.appendingPathComponent("crispyvibes-behavioral-editor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testExplorerSelectionRoutesPreviewToMarkdownViewModel() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let markdownFile = projectRoot.appendingPathComponent("note.md")
        try "# Title\nBody".write(to: markdownFile, atomically: true, encoding: .utf8)

        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        let persistenceStore = VibeSpacePersistenceStore(store: appStore)
        let vibespaceManagement = VibeSpaceManagementService(persistenceStore: persistenceStore)

        let layoutStore = LayoutPersistenceService(fileManager: .default)
        let sessionDeps = ProjectSessionDependencies(
            layoutPersistence: layoutStore,
            vibespaceManagement: vibespaceManagement,
            folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
            terminalViewModelFactory: container.makeTerminalViewModel,
            detachedWindowManager: NoopDetachedWindowManager()
        )

        let session = ProjectSession(rootURL: projectRoot, dependencies: sessionDeps)
        let contentViewerStore = container.makeContentViewerStore()
        session.onFileOpenRequested = { (request: ExplorerOpenRequest) in
            switch request.action {
            case .preview:
                contentViewerStore.previewFile(at: request.fileURL)
            case .openTab:
                contentViewerStore.openFileInTab(at: request.fileURL)
            case .openInSplitHorizontal, .openInSplitVertical:
                contentViewerStore.openFileInTab(at: request.fileURL)
            case .openWindow:
                break
            case .openInSplitHorizontal, .openInSplitVertical:
                contentViewerStore.openFileInTab(at: request.fileURL)
            case let .compareGitStatus(code, relativePath):
                if code.contains("D") {
                    contentViewerStore.previewGitFileContent(
                        rootURL: projectRoot,
                        fileURL: request.fileURL,
                        relativePath: relativePath,
                        titleSuffix: "Deleted"
                    )
                } else {
                    contentViewerStore.previewGitDiff(
                        rootURL: projectRoot,
                        fileURL: request.fileURL,
                        relativePath: relativePath,
                        statusCode: code
                    )
                }
            }
        }
        session.activateIfNeeded()

        let fileItem = FileItem(url: markdownFile, isDirectory: false, children: nil)
        session.folderExplorerViewModel.select(fileItem)

        let openExpectation = expectation(description: "markdown preview opened")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            XCTAssertEqual(
                contentViewerStore.markdownViewModel.fileURL?.standardizedFileURL,
                markdownFile.standardizedFileURL
            )
            XCTAssertEqual(contentViewerStore.markdownViewModel.documentType, .markdown)
            openExpectation.fulfill()
        }
        wait(for: [openExpectation], timeout: 1.0)
    }

    func testOpenRequestIsClearedAfterConsumption() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let file = projectRoot.appendingPathComponent("note.md")
        try "# Note".write(to: file, atomically: true, encoding: .utf8)

        let appStore = AppPersistenceDataStore(fileManager: .default, appDirectoryURL: tempRoot)
        let persistenceStore = VibeSpacePersistenceStore(store: appStore)
        let vibespaceManagement = VibeSpaceManagementService(persistenceStore: persistenceStore)
        let layoutStore = LayoutPersistenceService(fileManager: .default)
        let sessionDeps = ProjectSessionDependencies(
            layoutPersistence: layoutStore,
            vibespaceManagement: vibespaceManagement,
            folderExplorerViewModelFactory: container.makeFolderExplorerViewModel,
            terminalViewModelFactory: container.makeTerminalViewModel,
            detachedWindowManager: NoopDetachedWindowManager()
        )

        let session = ProjectSession(rootURL: projectRoot, dependencies: sessionDeps)
        let contentViewerStore = container.makeContentViewerStore()
        session.onFileOpenRequested = { request in
            contentViewerStore.previewFile(at: request.fileURL)
        }
        session.activateIfNeeded()

        let fileItem = FileItem(url: file, isDirectory: false, children: nil)
        session.folderExplorerViewModel.select(fileItem)

        let clearedExpectation = expectation(description: "openRequest cleared after consumption")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            XCTAssertNil(session.folderExplorerViewModel.openRequest,
                         "openRequest must be nil after the Combine sink consumes it")
            clearedExpectation.fulfill()
        }
        wait(for: [clearedExpectation], timeout: 1.0)
    }

}
