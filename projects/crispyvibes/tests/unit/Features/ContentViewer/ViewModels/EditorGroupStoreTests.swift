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
        let didOpenFirstFile = await waitForCondition(timeout: 2) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "alpha"
        }
        XCTAssertTrue(didOpenFirstFile)

        group.openFileInTab(at: secondURL, fileContentProvider: secondProvider)
        let didOpenSecondFile = await waitForCondition(timeout: 2) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "beta"
        }
        XCTAssertTrue(didOpenSecondFile)

        group.activateTab(ContentViewerTab.file(url: firstURL).id)
        let didRestoreFirstFile = await waitForCondition(timeout: 2) {
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
        let didOpenProjectA = await waitForCondition(timeout: 2) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "alpha"
        }
        XCTAssertTrue(didOpenProjectA)

        group.openFileInTab(
            at: sharedURL,
            projectIdentifier: "project-b",
            fileContentProvider: providerB
        )
        let didOpenProjectB = await waitForCondition(timeout: 2) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "beta"
        }
        XCTAssertTrue(didOpenProjectB)

        XCTAssertEqual(group.tabs.count, 2)

        group.activateTab(ContentViewerTab.file(url: sharedURL, projectIdentifier: "project-a").id)
        let didRestoreProjectA = await waitForCondition(timeout: 2) {
            self.group.markdownViewModel.workerStatus == .ready &&
            self.group.markdownViewModel.rawContent == "alpha"
        }
        XCTAssertTrue(didRestoreProjectA)

        group.activateTab(ContentViewerTab.file(url: sharedURL, projectIdentifier: "project-b").id)
        let didRestoreProjectB = await waitForCondition(timeout: 2) {
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

        let didOpenRemoteFile = await waitForCondition(timeout: 2) {
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
        let didOpenDeletedPreview = await waitForCondition(timeout: 2) {
            localGroup.markdownViewModel.workerStatus == .ready &&
            localGroup.markdownViewModel.rawContent == "previous revision"
        }
        XCTAssertTrue(didOpenDeletedPreview)

        localGroup.openFileInTab(at: otherURL)
        let didOpenOtherFile = await waitForCondition(timeout: 2) {
            localGroup.markdownViewModel.workerStatus == .ready &&
            localGroup.markdownViewModel.rawContent == "other"
        }
        XCTAssertTrue(didOpenOtherFile)

        localGroup.activateTab(ContentViewerTab.file(url: deletedURL).id)
        let didRestoreDeletedPreview = await waitForCondition(timeout: 2) {
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
