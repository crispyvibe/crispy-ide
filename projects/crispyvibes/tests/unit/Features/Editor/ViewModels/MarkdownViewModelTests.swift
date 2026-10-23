import AppKit
import Foundation
import PDFKit
import SwiftUI
import XCTest
@testable import CrispyVibes

actor RecordingBinaryFileContentProvider: FileContentProviding {
    private let readDataByPath: [String: Data]
    private var writes: [(path: String, contents: Data)] = []

    nonisolated var requiresMaterializedLocalPreview: Bool { true }

    init(readDataByPath: [String: Data]) {
        self.readDataByPath = readDataByPath
    }

    func readFile(at path: String) async throws -> Data {
        guard let data = readDataByPath[path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func writeFile(at path: String, contents: Data) async throws {
        writes.append((path: path, contents: contents))
    }

    func recordedWrites() -> [(path: String, contents: Data)] {
        writes
    }
}

actor ReadinessFailingFileContentProvider: FileContentProviding {
    func readFile(at path: String) async throws -> Data {
        throw SSHRemoteError.timeout("sftp readiness")
    }

    func writeFile(at path: String, contents: Data) async throws {}
}

actor SequencedTextFileContentProvider: FileContentProviding {
    private var readsByPath: [String: [Data]]
    private var readCountByPath: [String: Int] = [:]

    nonisolated var requiresMaterializedLocalPreview: Bool { false }

    init(readsByPath: [String: [Data]]) {
        self.readsByPath = readsByPath
    }

    func readFile(at path: String) async throws -> Data {
        guard var sequence = readsByPath[path], !sequence.isEmpty else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let next = sequence.removeFirst()
        readsByPath[path] = sequence
        readCountByPath[path, default: 0] += 1
        return next
    }

    func writeFile(at path: String, contents: Data) async throws {}

    func readCount(for path: String) -> Int {
        readCountByPath[path, default: 0]
    }
}

@MainActor
private final class RecordingExternalFileOpener: ExternalFileOpening {
    private(set) var openedURLs: [URL] = []
    private(set) var receivedRemoteProvider = false

    func open(
        fileURL: URL,
        fileContentProvider: (any FileContentProviding)?
    ) async throws -> URL {
        openedURLs.append(fileURL)
        receivedRemoteProvider = fileContentProvider?.requiresMaterializedLocalPreview == true
        return fileURL
    }
}

@MainActor
final class MarkdownViewModelTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!
    private var viewModel: MarkdownViewModel!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-markdown-vm")
        container = AppContainer.makeDefault()
        viewModel = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        viewModel = nil
        container = nil
    }

    func testMarkdownWebLinksRouteToInjectedDestinations() throws {
        var crispyRequest: (url: URL, projectPath: String?)?
        var defaultBrowserURL: URL?
        let router = MarkdownLinkRouter(
            openInCrispyBrowser: { url, projectPath in
                crispyRequest = (url, projectPath)
            },
            openInDefaultBrowser: { url in
                defaultBrowserURL = url
            }
        )
        let linkedViewModel = MarkdownViewModel(
            worker: container.makePaneWorker(pane: .editor),
            bufferStore: DocumentBufferStore(),
            markdownLinkRouter: router
        )
        let sourceURL = tempRoot.appendingPathComponent("source.md")
        try Data("# Source".utf8).write(to: sourceURL)
        let reference = FileDocumentReference(
            url: sourceURL,
            projectIdentifier: tempRoot.path
        )
        linkedViewModel.openFileInTab(at: sourceURL, documentReference: reference)

        linkedViewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInCrispy,
                targetKind: .web,
                href: "https://example.com/report",
                resolvedURL: "https://example.com/report",
                fragment: nil
            )
        )
        XCTAssertEqual(crispyRequest?.url.absoluteString, "https://example.com/report")
        XCTAssertEqual(crispyRequest?.projectPath, tempRoot.path)

        linkedViewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInDefaultBrowser,
                targetKind: .web,
                href: "https://example.com/help",
                resolvedURL: "https://example.com/help",
                fragment: nil
            )
        )
        XCTAssertEqual(defaultBrowserURL?.absoluteString, "https://example.com/help")
    }

    func testMarkdownWebLinkRejectsEmbeddedCredentials() {
        var openedURL: URL?
        let linkedViewModel = MarkdownViewModel(
            worker: container.makePaneWorker(pane: .editor),
            bufferStore: DocumentBufferStore(),
            markdownLinkRouter: MarkdownLinkRouter(
                openInCrispyBrowser: { url, _ in openedURL = url },
                openInDefaultBrowser: { url in openedURL = url }
            )
        )

        linkedViewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInCrispy,
                targetKind: .web,
                href: "https://user:secret@example.com",
                resolvedURL: "https://user:secret@example.com",
                fragment: nil
            )
        )

        XCTAssertNil(openedURL)
        XCTAssertEqual(linkedViewModel.errorMessage, AppStrings.Editor.invalidLinkDestination)
    }

    func testRelativeMarkdownLinkOpensTabAndRegistersRichHeadingNavigation() throws {
        let sourceURL = tempRoot.appendingPathComponent("source.md")
        let targetURL = tempRoot.appendingPathComponent("guide.md")
        try Data("[Guide](guide.md#installation)".utf8).write(to: sourceURL)
        try Data("# Installation".utf8).write(to: targetURL)
        let projectIdentifier = tempRoot.path
        let sourceReference = FileDocumentReference(
            url: sourceURL,
            projectIdentifier: projectIdentifier
        )
        viewModel.openFileInTab(at: sourceURL, documentReference: sourceReference)

        viewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInCrispy,
                targetKind: .localFile,
                href: "guide.md#installation",
                resolvedURL: targetURL.absoluteString + "#installation",
                fragment: "installation"
            )
        )

        let targetReference = FileDocumentReference(
            url: targetURL,
            projectIdentifier: projectIdentifier
        )
        XCTAssertEqual(viewModel.activeEditorTabID, targetReference.documentIdentity)
        XCTAssertTrue(viewModel.editorTabs.contains { $0.id == targetReference.documentIdentity })
        let navigation = viewModel.richNavigationRequest(for: targetReference.documentIdentity)
        XCTAssertEqual(navigation?.fragment, "installation")
        if let navigation {
            XCTAssertTrue(viewModel.claimRichNavigationRequest(id: navigation.id))
        }
        XCTAssertNil(viewModel.pendingRichNavigationRequest)
    }

    func testMissingLocalMarkdownLinkDoesNotOpenTab() throws {
        let sourceURL = tempRoot.appendingPathComponent("source.md")
        try Data("# Source".utf8).write(to: sourceURL)
        viewModel.openFileInTab(at: sourceURL)
        let originalTabCount = viewModel.editorTabs.count
        let missingURL = tempRoot.appendingPathComponent("missing.md")

        viewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInCrispy,
                targetKind: .localFile,
                href: "missing.md",
                resolvedURL: missingURL.absoluteString,
                fragment: nil
            )
        )

        XCTAssertEqual(viewModel.editorTabs.count, originalTabCount)
        XCTAssertEqual(viewModel.errorMessage, AppStrings.Editor.linkedFileUnavailable)
    }

    func testMissingLocalMarkdownLinkIsBlockedForDefaultApp() throws {
        var openedURL: URL?
        let linkedViewModel = MarkdownViewModel(
            worker: container.makePaneWorker(pane: .editor),
            bufferStore: DocumentBufferStore(),
            markdownLinkRouter: MarkdownLinkRouter(
                openInCrispyBrowser: { _, _ in },
                openInDefaultBrowser: { openedURL = $0 }
            )
        )
        let sourceURL = tempRoot.appendingPathComponent("source.md")
        try Data("# Source".utf8).write(to: sourceURL)
        linkedViewModel.openFileInTab(at: sourceURL)
        let missingURL = tempRoot.appendingPathComponent("missing.md")

        linkedViewModel.handleMarkdownLinkAction(
            MarkdownLinkActionRequest(
                action: .openInDefaultBrowser,
                targetKind: .localFile,
                href: "missing.md",
                resolvedURL: missingURL.absoluteString,
                fragment: nil
            )
        )

        XCTAssertNil(openedURL)
        XCTAssertEqual(linkedViewModel.errorMessage, AppStrings.Editor.linkedFileUnavailable)
    }

    func testOpenMarkdownEditAndSaveRoundTrip() async throws {
        let fileURL = tempRoot.appendingPathComponent("README.md")
        try Data("# Start\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "# Start\n"
        }
        XCTAssertTrue(opened)

        XCTAssertEqual(viewModel.documentType, .markdown)
        XCTAssertTrue(viewModel.canEditCurrentDocument)
        XCTAssertEqual(viewModel.title, "README.md")

        viewModel.updateText("# Updated\n")
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.save()
        let savedReady = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && !self.viewModel.hasUnsavedChanges
        }
        XCTAssertTrue(savedReady)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(saved, "# Updated\n")
    }

    func testExternalFileOpenServiceRemovesRemoteSnapshotWhenLaunchFails() async {
        let sourceURL = URL(fileURLWithPath: "/srv/app/page.html")
        let provider = RecordingBinaryFileContentProvider(
            readDataByPath: [sourceURL.path: Data("<p>remote</p>".utf8)]
        )
        var attemptedURL: URL?
        let service = ExternalFileOpenService(openURL: { url in
            attemptedURL = url
            return false
        })

        do {
            _ = try await service.open(fileURL: sourceURL, fileContentProvider: provider)
            XCTFail("Expected Launch Services failure")
        } catch {
            XCTAssertEqual(error as? ExternalFileOpenError, .launchFailed)
        }

        XCTAssertNotNil(attemptedURL)
        if let attemptedURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: attemptedURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: attemptedURL.deletingLastPathComponent().path))
        }
    }

    func testOpenHTMLInSystemSavesCurrentRevisionBeforeOpening() async throws {
        let fileURL = tempRoot.appendingPathComponent("page.html")
        try Data("<p>before</p>".utf8).write(to: fileURL)
        let opener = RecordingExternalFileOpener()
        let htmlViewModel = MarkdownViewModel(
            worker: container.makePaneWorker(pane: .editor),
            bufferStore: DocumentBufferStore(),
            externalFileOpener: opener
        )

        htmlViewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            htmlViewModel.workerStatus == .ready && htmlViewModel.documentType == .html
        }
        XCTAssertTrue(opened)

        htmlViewModel.updateText("<p>after</p>")
        htmlViewModel.openHTMLInSystem()
        let externallyOpened = await waitForCondition(timeout: 8) {
            opener.openedURLs == [fileURL] && !htmlViewModel.isOpeningInSystem
        }
        XCTAssertTrue(externallyOpened)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "<p>after</p>")
        XCTAssertFalse(htmlViewModel.hasUnsavedChanges)
    }

    // MARK: - F057 LaTeX editor


    func testOpenHTMLInSystemPersistsIntentionalEmptyRevision() async throws {
        let fileURL = tempRoot.appendingPathComponent("empty-page.html")
        try Data("<p>before</p>".utf8).write(to: fileURL)
        let opener = RecordingExternalFileOpener()
        let htmlViewModel = MarkdownViewModel(
            worker: container.makePaneWorker(pane: .editor),
            bufferStore: DocumentBufferStore(),
            externalFileOpener: opener
        )

        htmlViewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            htmlViewModel.workerStatus == .ready && htmlViewModel.documentType == .html
        }
        XCTAssertTrue(opened)
        htmlViewModel.updateText("")
        htmlViewModel.openHTMLInSystem()
        let openedExternally = await waitForCondition(timeout: 8) {
            opener.openedURLs == [fileURL] && !htmlViewModel.isOpeningInSystem
        }
        XCTAssertTrue(openedExternally)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "")
    }
    func testDetectDocumentTypeRoutesLatexExtensions() {
        for ext in ["tex", "latex", "ltx", "TEX", "Latex", "LTX"] {
            let url = URL(fileURLWithPath: "/tmp/doc.\(ext)")
            XCTAssertEqual(
                MarkdownViewModel.detectDocumentType(for: url),
                .latex,
                "expected .latex for extension .\(ext)"
            )
        }
        // `.bib` must remain plain text — only `tex` was pulled out of the
        // plain-text set, not the rest of the TeX-adjacent extensions.
        XCTAssertEqual(
            MarkdownViewModel.detectDocumentType(for: URL(fileURLWithPath: "/tmp/refs.bib")),
            .plainText
        )
        XCTAssertEqual(
            MarkdownViewModel.detectDocumentType(for: URL(fileURLWithPath: "/tmp/README.md")),
            .markdown
        )
    }

    func testLatexDocumentOpensEditableInToolchainAwareDefaultMode() async throws {
        let fileURL = tempRoot.appendingPathComponent("paper.tex")
        try Data("\\documentclass{article}\n\\begin{document}\nHello $x^2$.\n\\end{document}\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.documentType == .latex
        }
        XCTAssertTrue(opened)
        XCTAssertTrue(viewModel.isEditableDocumentType(.latex))
        XCTAssertTrue(viewModel.supportsMarkupViewModeToggle)
        // LaTeX prefers the full-TeX PDF view when a local toolchain is
        // installed, otherwise the dependency-free rich view.
        let expectedDefault: MarkdownViewModel.MarkupViewMode =
            LaTeXNativeCompiler.isToolchainAvailable ? .compiled : .rich
        XCTAssertEqual(viewModel.defaultMarkupViewMode, expectedDefault)
        XCTAssertEqual(viewModel.currentMarkupViewMode, expectedDefault)

        viewModel.setCurrentMarkupViewMode(.rich)
        XCTAssertEqual(viewModel.currentMarkupViewMode, .rich)
    }

    func testInsertLatexSnippetQueuesRequestForLatexDocuments() async throws {
        let fileURL = tempRoot.appendingPathComponent("paper.tex")
        try Data("\\begin{document}\n\\end{document}\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.documentType == .latex
        }
        XCTAssertTrue(opened)
        XCTAssertNil(viewModel.latexInsertionRequest)

        viewModel.insertLatexSnippet("\\alpha ")
        XCTAssertEqual(viewModel.latexInsertionRequest?.text, "\\alpha ")
    }

    func testInsertLatexSnippetIgnoredForNonLatexDocuments() async throws {
        let fileURL = tempRoot.appendingPathComponent("README.md")
        try Data("# Hi\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.documentType == .markdown
        }
        XCTAssertTrue(opened)

        viewModel.insertLatexSnippet("\\alpha ")
        XCTAssertNil(viewModel.latexInsertionRequest)
    }

    func testLatexEditAndSaveRoundTrip() async throws {
        let fileURL = tempRoot.appendingPathComponent("paper.tex")
        try Data("\\begin{document}\nHello.\n\\end{document}\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.documentType == .latex
        }
        XCTAssertTrue(opened)
        XCTAssertTrue(viewModel.isEditableDocumentType(viewModel.documentType))

        viewModel.updateText("\\begin{document}\nHello edited.\n\\end{document}\n")
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.save()
        let savedReady = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && !self.viewModel.hasUnsavedChanges
        }
        XCTAssertTrue(savedReady)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(saved, "\\begin{document}\nHello edited.\n\\end{document}\n")
    }

    func testEditorTabLifecycleDeduplicatesAndClosesTabs() async throws {
        let firstURL = tempRoot.appendingPathComponent("README.md")
        let secondURL = tempRoot.appendingPathComponent("notes.txt")
        try Data("# First\n".utf8).write(to: firstURL)
        try Data("Second".utf8).write(to: secondURL)

        viewModel.openFileInTab(at: firstURL)
        let firstOpened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.title == "README.md"
        }
        XCTAssertTrue(firstOpened)
        XCTAssertEqual(viewModel.editorTabs.count, 1)
        XCTAssertEqual(viewModel.activeEditorTabID, firstURL.standardizedFileURL.path)

        viewModel.openFileInTab(at: firstURL)
        XCTAssertEqual(viewModel.editorTabs.count, 1)

        viewModel.openFileInTab(at: secondURL)
        let secondOpened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.title == "notes.txt"
        }
        XCTAssertTrue(secondOpened)
        XCTAssertEqual(viewModel.editorTabs.count, 2)

        viewModel.closeEditorTab(withID: secondURL.standardizedFileURL.path)
        let closedSecond = await waitForCondition(timeout: 8) {
            self.viewModel.title == "README.md"
        }
        XCTAssertTrue(closedSecond)
        XCTAssertEqual(viewModel.editorTabs.count, 1)
        XCTAssertEqual(viewModel.activeEditorTabID, firstURL.standardizedFileURL.path)
    }

    func testOpenFileInTabRegistersPendingSourceSelection() throws {
        let fileURL = tempRoot.appendingPathComponent("README.md")
        try Data("# Heading\nBody\n".utf8).write(to: fileURL)

        viewModel.openFileInTab(at: fileURL, line: 7, column: 3)

        XCTAssertEqual(viewModel.editorTabs.count, 1)
        XCTAssertEqual(viewModel.activeEditorTabID, fileURL.standardizedFileURL.path)
        XCTAssertEqual(
            viewModel.pendingSourceSelection,
            MarkdownViewModel.PendingSourceSelection(
                documentID: fileURL.standardizedFileURL.path,
                selection: MarkdownViewModel.SourceSelection(line: 7, column: 3)
            )
        )
    }

    func testOpenFileInTabUpdatesPendingSourceSelectionForExistingTab() throws {
        let fileURL = tempRoot.appendingPathComponent("README.md")
        try Data("# Heading\nBody\n".utf8).write(to: fileURL)

        viewModel.openFileInTab(at: fileURL, line: 3, column: 2)
        viewModel.openFileInTab(at: fileURL, line: 11, column: 5)

        XCTAssertEqual(viewModel.editorTabs.count, 1)
        XCTAssertEqual(viewModel.activeEditorTabID, fileURL.standardizedFileURL.path)
        XCTAssertEqual(
            viewModel.pendingSourceSelection,
            MarkdownViewModel.PendingSourceSelection(
                documentID: fileURL.standardizedFileURL.path,
                selection: MarkdownViewModel.SourceSelection(line: 11, column: 5)
            )
        )
    }

    func testOpenFileCancelsPreviousInFlightOpenTask() async throws {
        let firstURL = tempRoot.appendingPathComponent("first.md")
        let secondURL = tempRoot.appendingPathComponent("second.md")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)

        viewModel.openFile(at: firstURL)
        let firstTask = viewModel.openFileTask
        XCTAssertNotNil(firstTask)

        viewModel.openFile(at: secondURL)

        XCTAssertTrue(firstTask?.isCancelled == true)
        let openedSecond = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "second"
        }
        XCTAssertTrue(openedSecond)
    }

    func testPreviewGitDiffLoadsDiffContentWhenRepositoryHasChanges() async throws {
        guard try gitAvailable() else {
            throw XCTSkip("Git is not available on this machine.")
        }

        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "init"], workingDirectory: tempRoot)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.email", "unit@test.local"], workingDirectory: tempRoot)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "config", "user.name", "Unit Test"], workingDirectory: tempRoot)

        let tracked = tempRoot.appendingPathComponent("tracked.txt")
        try Data("before\n".utf8).write(to: tracked)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "add", "tracked.txt"], workingDirectory: tempRoot)
        _ = try runProcess(executable: "/usr/bin/env", arguments: ["git", "commit", "-m", "initial"], workingDirectory: tempRoot)

        try Data("after\n".utf8).write(to: tracked)

        viewModel.previewGitDiff(
            rootURL: tempRoot,
            fileURL: tracked,
            relativePath: "tracked.txt",
            statusCode: " M"
        )

        let loaded = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready &&
            self.viewModel.documentType == .gitDiff &&
            self.viewModel.rawContent.contains("tracked.txt")
        }
        XCTAssertTrue(loaded)
        XCTAssertFalse(viewModel.canEditCurrentDocument)
        XCTAssertEqual(viewModel.title, "tracked.txt (Changes)")
    }

    func testOpenHTMLEditAndSaveRoundTrip() async throws {
        let fileURL = tempRoot.appendingPathComponent("index.html")
        try Data("<h1>Start</h1>".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.documentType == .html
        }
        XCTAssertTrue(opened)
        XCTAssertTrue(viewModel.canEditCurrentDocument)

        viewModel.updateText("<h1>Updated</h1>")
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.save()
        let savedReady = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && !self.viewModel.hasUnsavedChanges
        }
        XCTAssertTrue(savedReady)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(saved, "<h1>Updated</h1>")
    }

    func testOpenPlainTextIsEditable() async throws {
        let fileURL = tempRoot.appendingPathComponent("notes.txt")
        try Data("plain text".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "plain text"
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(viewModel.documentType, .plainText)
        XCTAssertTrue(viewModel.canEditCurrentDocument)
        XCTAssertNil(viewModel.codeLanguageKind)
        XCTAssertNil(viewModel.plainTextEditorLanguage)

        viewModel.updateText("updated plain text")
        XCTAssertEqual(viewModel.rawContent, "updated plain text")
    }

    func testOpenAndSaveWithInjectedLocalFileContentProvider() async throws {
        let fileURL = tempRoot.appendingPathComponent("provider-backed.txt")
        try Data("provider text".utf8).write(to: fileURL)
        viewModel.fileContentProvider = LocalFileContentProvider()

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 2) {
            self.viewModel.workerStatus == .ready &&
            self.viewModel.rawContent == "provider text"
        }
        XCTAssertTrue(opened)

        viewModel.updateText("provider updated")
        viewModel.save()

        let saved = await waitForCondition(timeout: 2) {
            self.viewModel.workerStatus == .ready &&
            !self.viewModel.hasUnsavedChanges
        }
        XCTAssertTrue(saved)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "provider updated")
    }

    func testOpenCodeFileDetectsLanguageAndUsesEditablePlainTextMode() async throws {
        let fileURL = tempRoot.appendingPathComponent("main.swift")
        try Data("print(\"ok\")\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent.contains("print")
        }
        XCTAssertTrue(opened)

        XCTAssertEqual(viewModel.documentType, .plainText)
        XCTAssertTrue(viewModel.canEditCurrentDocument)
        XCTAssertEqual(viewModel.codeLanguageKind, .swift)
        XCTAssertEqual(viewModel.plainTextEditorLanguage?.name, "Swift")
    }

    func testOpenAdditionalCodeFilesDetectLanguageKinds() async throws {
        let fixtures: [(name: String, content: String, kind: CodeLanguageKind, languageName: String)] = [
            ("script.js", "export const value = 1\n", .javascript, "JavaScript"),
            ("query.sql", "SELECT * FROM table_name;\n", .sql, "SQL"),
            ("config.yaml", "service:\n  name: crispyvibes\n", .yaml, "YAML")
        ]

        for fixture in fixtures {
            let fileURL = tempRoot.appendingPathComponent(fixture.name)
            try Data(fixture.content.utf8).write(to: fileURL)

            viewModel.openFile(at: fileURL)
            let opened = await waitForCondition(timeout: 8) {
                self.viewModel.workerStatus == .ready &&
                self.viewModel.title == fixture.name
            }
            XCTAssertTrue(opened, "Failed to open \(fixture.name)")
            XCTAssertEqual(viewModel.documentType, .plainText)
            XCTAssertEqual(viewModel.codeLanguageKind, fixture.kind)
            XCTAssertEqual(viewModel.plainTextEditorLanguage?.name, fixture.languageName)
        }
    }

    func testOpenRFileUsesSpecializedRDocumentRoute() async throws {
        let fileURL = tempRoot.appendingPathComponent("analysis.r")
        try Data("summary(c(1, 2, 3))\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.title == "analysis.r"
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(viewModel.documentType, .r)
        XCTAssertTrue(viewModel.canEditCurrentDocument)
        XCTAssertNil(viewModel.codeLanguageKind)
        XCTAssertNil(viewModel.plainTextEditorLanguage)
    }

    func testOpenImageAndPdfSetPreviewURLs() throws {
        let imageURL = tempRoot.appendingPathComponent("image.png")
        let pdfURL = tempRoot.appendingPathComponent("sample.pdf")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: pdfURL)

        viewModel.openFile(at: imageURL)
        XCTAssertEqual(viewModel.documentType, .image)
        XCTAssertEqual(viewModel.imageFileURL?.path, imageURL.path)
        XCTAssertNil(viewModel.pdfFileURL)
        XCTAssertEqual(viewModel.workerStatus, .ready)

        viewModel.openFile(at: pdfURL)
        XCTAssertEqual(viewModel.documentType, .pdf)
        XCTAssertEqual(viewModel.pdfFileURL?.path, pdfURL.path)
        XCTAssertNil(viewModel.imageFileURL)
        XCTAssertEqual(viewModel.workerStatus, .ready)
    }

    func testLocalProviderBackedImageOpenKeepsDirectFileURL() throws {
        let imageURL = tempRoot.appendingPathComponent("local-preview.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        viewModel.fileContentProvider = LocalFileContentProvider()

        viewModel.openFile(at: imageURL)

        XCTAssertEqual(viewModel.documentType, .image)
        XCTAssertEqual(viewModel.imageFileURL?.path, imageURL.path)
        XCTAssertNil(viewModel.materializedPreviewURL)
        XCTAssertEqual(viewModel.workerStatus, .ready)
    }

    func testRemoteImageOpenMaterializesLocalPreviewFile() async throws {
        let remoteURL = URL(fileURLWithPath: "/remote/assets/photo.png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let provider = RecordingBinaryFileContentProvider(readDataByPath: [remoteURL.path: imageData])
        viewModel.fileContentProvider = provider

        viewModel.openFile(at: remoteURL)

        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready &&
            self.viewModel.documentType == .image &&
            self.viewModel.imageFileURL != nil
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(viewModel.fileURL?.path, remoteURL.path)

        let stagedURL = try XCTUnwrap(viewModel.imageFileURL)
        XCTAssertNotEqual(stagedURL.standardizedFileURL.path, remoteURL.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertEqual(try Data(contentsOf: stagedURL), imageData)
    }

    func testRemoteImageSaveWritesBackThroughProviderAndUpdatesStagedFile() async throws {
        let remoteURL = URL(fileURLWithPath: "/remote/assets/photo.png")
        let originalData = Data([0x89, 0x50, 0x4E, 0x47])
        let updatedData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D])
        let provider = RecordingBinaryFileContentProvider(readDataByPath: [remoteURL.path: originalData])
        viewModel.fileContentProvider = provider

        viewModel.openFile(at: remoteURL)
        let imageOpened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.imageFileURL != nil
        }
        XCTAssertTrue(imageOpened)

        let stagedURL = try XCTUnwrap(viewModel.imageFileURL)
        let saveCompleted = expectation(description: "remote image save completed")

        viewModel.saveImagePreviewData(updatedData, from: stagedURL) { result in
            if case .failure(let error) = result {
                XCTFail("Expected remote image save to succeed, got \(error)")
            }
            saveCompleted.fulfill()
        }

        await fulfillment(of: [saveCompleted], timeout: 8)

        let writes = await provider.recordedWrites()
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.path, remoteURL.path)
        XCTAssertEqual(writes.first?.contents, updatedData)
        XCTAssertEqual(try Data(contentsOf: stagedURL), updatedData)
        XCTAssertFalse(viewModel.hasUnsavedImageEdits)
    }

    func testRemotePDFOpenMaterializesLocalPreviewFile() async throws {
        let remoteURL = URL(fileURLWithPath: "/remote/docs/guide.pdf")
        let pdfData = Data([0x25, 0x50, 0x44, 0x46])
        let provider = RecordingBinaryFileContentProvider(readDataByPath: [remoteURL.path: pdfData])
        viewModel.fileContentProvider = provider

        viewModel.openFile(at: remoteURL)

        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready &&
            self.viewModel.documentType == .pdf &&
            self.viewModel.pdfFileURL != nil
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(viewModel.fileURL?.path, remoteURL.path)

        let stagedURL = try XCTUnwrap(viewModel.pdfFileURL)
        XCTAssertNotEqual(stagedURL.standardizedFileURL.path, remoteURL.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertEqual(try Data(contentsOf: stagedURL), pdfData)
    }

    func testOpenSuppressesConnectionReadinessErrorsWhenRequested() async {
        let remoteURL = URL(fileURLWithPath: "/remote/docs/readme.md")
        viewModel.fileContentProvider = ReadinessFailingFileContentProvider()

        viewModel.openFile(at: remoteURL, suppressConnectionReadinessErrors: true)

        let failed = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus.level == .unavailable
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(viewModel.workerStatus.message, "SSH connection unavailable")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOpenSVGSetsImagePreviewURL() throws {
        let svgURL = tempRoot.appendingPathComponent("diagram.svg")
        let svgPayload = """
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\">
          <rect width=\"12\" height=\"12\" fill=\"#ffffff\" />
        </svg>
        """
        try Data(svgPayload.utf8).write(to: svgURL)

        viewModel.openFile(at: svgURL)
        XCTAssertEqual(viewModel.documentType, .image)
        XCTAssertEqual(viewModel.imageFileURL?.path, svgURL.path)
        XCTAssertNil(viewModel.pdfFileURL)
        XCTAssertEqual(viewModel.workerStatus, .ready)
    }

    func testImageDocumentDirtyStateTracksUnsavedImageEdits() throws {
        let imageURL = tempRoot.appendingPathComponent("preview.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)

        viewModel.openFile(at: imageURL)
        XCTAssertEqual(viewModel.documentType, .image)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.hasUnsavedImageEdits)
        XCTAssertFalse(viewModel.hasUnsavedTextChanges)

        viewModel.setImageEditDirtyState(true)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.hasUnsavedImageEdits)
        XCTAssertFalse(viewModel.hasUnsavedTextChanges)

        viewModel.setImageEditDirtyState(false)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.hasUnsavedImageEdits)
        XCTAssertFalse(viewModel.hasUnsavedTextChanges)
    }

    func testImageDirtyStateDoesNotApplyToNonImageDocuments() async throws {
        let markdownURL = tempRoot.appendingPathComponent("notes.md")
        try Data("# Notes\n".utf8).write(to: markdownURL)

        viewModel.openFile(at: markdownURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.documentType == .markdown
        }
        XCTAssertTrue(opened)
        XCTAssertFalse(viewModel.hasUnsavedImageEdits)

        viewModel.setImageEditDirtyState(true)
        XCTAssertFalse(viewModel.hasUnsavedImageEdits)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testOpeningNewFileClearsExistingUnsavedImageEditState() throws {
        let imageURL = tempRoot.appendingPathComponent("preview.png")
        let textURL = tempRoot.appendingPathComponent("notes.txt")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        try Data("hello".utf8).write(to: textURL)

        viewModel.openFile(at: imageURL)
        XCTAssertEqual(viewModel.documentType, .image)
        viewModel.setImageEditDirtyState(true)
        XCTAssertTrue(viewModel.hasUnsavedImageEdits)
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.openFile(at: textURL)
        XCTAssertEqual(viewModel.documentType, .plainText)
        XCTAssertFalse(viewModel.hasUnsavedImageEdits)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testUnsupportedExtensionFallsBackToPlainTextWhenReadable() async throws {
        let unknownURL = tempRoot.appendingPathComponent("data.unknown")
        try Data("payload".utf8).write(to: unknownURL)

        viewModel.openFile(at: unknownURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "payload"
        }
        XCTAssertTrue(opened)

        XCTAssertEqual(viewModel.documentType, .plainText)
        XCTAssertNil(viewModel.unsupportedFileMessage)
        XCTAssertEqual(viewModel.lastSavedContent, "payload", "lastSavedContent must match rawContent after unsupported→plainText promotion")
        XCTAssertFalse(viewModel.hasUnsavedChanges, "Promoted file should not start with unsaved-changes flag")
    }

    func testOpenMissingMarkdownSetsErrorState() async {
        let missing = tempRoot.appendingPathComponent("missing.md")
        viewModel.openFile(at: missing)

        let failed = await waitForCondition(timeout: 8) { self.viewModel.workerStatus.level == .unavailable }
        XCTAssertTrue(failed)
        XCTAssertTrue((viewModel.errorMessage ?? "").contains("Unable to open file"))
    }

    func testOpenMissingUnsupportedFileSetsUnsupportedMessage() async {
        let missing = tempRoot.appendingPathComponent("missing.bin")
        viewModel.openFile(at: missing)

        let failed = await waitForCondition(timeout: 8) { self.viewModel.workerStatus.level == .unavailable }
        XCTAssertTrue(failed)
        XCTAssertEqual(viewModel.unsupportedFileMessage, "Preview is not available for this file type.")
    }

    func testMarkdownAutosavePersistsAfterDebounce() async throws {
        let fileURL = tempRoot.appendingPathComponent("autosave.md")
        try Data("# Start\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) { self.viewModel.workerStatus == .ready }
        XCTAssertTrue(opened)

        viewModel.updateText("# Autosaved\n")
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        let saved = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready &&
            !self.viewModel.hasUnsavedChanges &&
            (try? String(contentsOf: fileURL, encoding: .utf8)) == "# Autosaved\n"
        }
        XCTAssertTrue(saved)
    }

    func testDefaultTitleWhenNoFileIsSelected() {
        XCTAssertEqual(viewModel.title, "No File Selected")
        XCTAssertEqual(viewModel.documentType, .none)
    }

    func testExternalReloadKeepsCurrentContentUntilReplacementArrives() async throws {
        let fileURL = tempRoot.appendingPathComponent("notes.txt")
        let provider = SequencedTextFileContentProvider(
            readsByPath: [
                fileURL.path: [Data("before".utf8), Data("after".utf8)]
            ]
        )
        viewModel.fileContentProvider = provider

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "before"
        }
        XCTAssertTrue(opened)

        viewModel.reloadIfFileChanged(changedPaths: [fileURL.path])

        XCTAssertEqual(viewModel.rawContent, "before")
        XCTAssertEqual(viewModel.workerStatus, .busy("Reloading file"))

        let reloaded = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "after"
        }
        XCTAssertTrue(reloaded)
        let readCount = await provider.readCount(for: fileURL.path)
        XCTAssertEqual(readCount, 2)
        XCTAssertEqual(viewModel.lastSavedContent, "after")
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testOpeningSharedDirtyBufferDoesNotReloadOrOverwriteEdits() async throws {
        let fileURL = tempRoot.appendingPathComponent("shared.md")
        let provider = SequencedTextFileContentProvider(
            readsByPath: [
                fileURL.path: [Data("base".utf8), Data("external".utf8)]
            ]
        )
        let sharedBufferStore = DocumentBufferStore()
        let firstViewModel = container.makeMarkdownViewModel(bufferStore: sharedBufferStore)
        let secondViewModel = container.makeMarkdownViewModel(bufferStore: sharedBufferStore)
        firstViewModel.fileContentProvider = provider
        secondViewModel.fileContentProvider = provider

        firstViewModel.openFileInTab(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            firstViewModel.workerStatus == .ready && firstViewModel.rawContent == "base"
        }
        XCTAssertTrue(opened)

        firstViewModel.updateText("dirty in memory")
        XCTAssertEqual(firstViewModel.rawContent, "dirty in memory")
        XCTAssertTrue(firstViewModel.hasUnsavedChanges)

        secondViewModel.openFileInTab(at: fileURL)
        let attached = await waitForCondition(timeout: 2) {
            secondViewModel.workerStatus == .ready && secondViewModel.rawContent == "dirty in memory"
        }
        XCTAssertTrue(attached)
        XCTAssertTrue(secondViewModel.hasUnsavedChanges)

        let readCount = await provider.readCount(for: fileURL.path)
        XCTAssertEqual(readCount, 1)
    }

    func testExternalReloadOfCleanBufferDoesNotEnterLoadingState() async throws {
        let fileURL = tempRoot.appendingPathComponent("external.md")
        let provider = SequencedTextFileContentProvider(
            readsByPath: [
                fileURL.path: [Data("before".utf8), Data("after".utf8)]
            ]
        )
        viewModel.fileContentProvider = provider

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "before"
        }
        XCTAssertTrue(opened)

        viewModel.reloadIfFileChanged(changedPaths: [fileURL.path])

        XCTAssertFalse(viewModel.activeBuffer?.isLoading ?? true)
        XCTAssertEqual(viewModel.rawContent, "before")

        let reloaded = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.rawContent == "after"
        }
        XCTAssertTrue(reloaded)
    }
}


@MainActor
final class MarkdownNavigationViewModelTests: XCTestCase {
    private var container: AppContainer!
    private var viewModel: MarkdownViewModel!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        viewModel = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
    }

    override func tearDownWithError() throws {
        viewModel = nil
        container = nil
    }

    func testNavigationCommandIsConsumedOnlyByMatchingRequestID() {
        let documentURL = URL(fileURLWithPath: "/tmp/markdown-command.md")
        let reference = FileDocumentReference(url: documentURL, projectIdentifier: "/tmp")
        viewModel.openFileInTab(at: documentURL, documentReference: reference)
        viewModel.requestRenderedNavigation(.back)
        let request = viewModel.renderedNavigationCommand(for: reference.documentIdentity)

        XCTAssertFalse(viewModel.claimRenderedNavigationCommand(id: UUID()))
        XCTAssertEqual(viewModel.renderedNavigationCommand(for: reference.documentIdentity), request)

        XCTAssertTrue(viewModel.claimRenderedNavigationCommand(id: request?.id ?? UUID()))
        XCTAssertNil(viewModel.renderedNavigationCommand(for: reference.documentIdentity))
    }

    func testNavigationStateIsSavedAndRestoredPerDocumentThenClearedOnClose() {
        let first = FileDocumentReference(
            url: URL(fileURLWithPath: "/tmp/markdown-history-a.md"),
            projectIdentifier: "/tmp"
        )
        let second = FileDocumentReference(
            url: URL(fileURLWithPath: "/tmp/markdown-history-b.md"),
            projectIdentifier: "/tmp"
        )
        let firstState = MarkdownNavigationState(
            documentID: first.documentIdentity,
            canNavigateBack: true,
            canNavigateForward: true,
            backScrollPositions: [MarkdownScrollPosition(x: 0, y: 120)],
            forwardScrollPositions: [MarkdownScrollPosition(x: 4, y: 360)]
        )
        let secondState = MarkdownNavigationState(
            documentID: second.documentIdentity,
            canNavigateBack: true,
            canNavigateForward: false,
            backScrollPositions: [MarkdownScrollPosition(x: 0, y: 80)]
        )

        viewModel.openFileInTab(at: first.url, documentReference: first)
        viewModel.updateRenderedNavigationState(firstState)
        viewModel.openFileInTab(at: second.url, documentReference: second)
        viewModel.updateRenderedNavigationState(secondState)

        XCTAssertEqual(viewModel.renderedNavigationState(for: first.documentIdentity), firstState)
        XCTAssertEqual(viewModel.renderedNavigationState(for: second.documentIdentity), secondState)
        XCTAssertTrue(viewModel.canNavigateBackInRenderedDocument)
        XCTAssertFalse(viewModel.canNavigateForwardInRenderedDocument)

        viewModel.activateEditorTab(withID: first.documentIdentity)
        XCTAssertTrue(viewModel.canNavigateBackInRenderedDocument)
        XCTAssertTrue(viewModel.canNavigateForwardInRenderedDocument)
        XCTAssertEqual(viewModel.renderedNavigationState(for: first.documentIdentity), firstState)

        viewModel.requestRenderedNavigation(.forward)
        viewModel.closeEditorTab(withID: first.documentIdentity)
        XCTAssertNil(viewModel.renderedNavigationState(for: first.documentIdentity))
        XCTAssertNil(viewModel.renderedNavigationCommand(for: first.documentIdentity))
        XCTAssertEqual(viewModel.renderedNavigationState(for: second.documentIdentity), secondState)
    }

    func testBridgePayloadDecodingAndRestoreScriptAreBoundedAndJSONSafe() throws {
        let positions = (0...MarkdownNavigationState.maximumHistoryCount).map {
            ["x": NSNumber(value: $0), "y": NSNumber(value: $0 * 2)]
        }
        let state = try XCTUnwrap(MarkdownNavigationState.decodeBridgePayload(
            documentID: "project|/tmp/quoted-\"document.md",
            body: [
                "canBack": true,
                "canForward": true,
                "backPositions": positions,
                "forwardPositions": positions
            ]
        ))

        XCTAssertEqual(state.backScrollPositions.count, MarkdownNavigationState.maximumHistoryCount)
        XCTAssertEqual(state.backScrollPositions.first?.x, 1)
        XCTAssertEqual(state.forwardScrollPositions.last?.y, 200)

        let script = try XCTUnwrap(MarkupRenderedEditor.Coordinator.navigationStateRestoreScript(state))
        let prefix = "window.crispyvibesRestoreMarkdownNavigationState("
        XCTAssertTrue(script.hasPrefix(prefix))
        XCTAssertTrue(script.hasSuffix(");"))
        let payload = String(script.dropFirst(prefix.count).dropLast(2))
        let decoded = try JSONDecoder().decode(
            MarkdownNavigationState.self,
            from: try XCTUnwrap(payload.data(using: .utf8))
        )
        XCTAssertEqual(decoded, state)
    }
}


@MainActor
final class MarkdownOneShotClaimTests: XCTestCase {
    func testFormattingClaimTrackerSurvivesCoordinatorRemountAndStaysBounded() {
        let tracker = EditorCommandClaimTracker()
        let request = EditorCommandRequest(command: .bold)

        XCTAssertTrue(tracker.claim(request.id), "The first mounted coordinator owns the request")
        XCTAssertFalse(tracker.claim(request.id), "A remounted coordinator cannot redispatch it")

        for _ in 0...EditorCommandClaimTracker.maximumClaimCount {
            XCTAssertTrue(tracker.claim(UUID()))
        }
        XCTAssertEqual(tracker.retainedClaimCount, EditorCommandClaimTracker.maximumClaimCount)

        tracker.reset()
        XCTAssertEqual(tracker.retainedClaimCount, 0)
        XCTAssertTrue(tracker.claim(request.id))
    }

    func testNavigationClaimsClearBeforeDeliveryAndStaleIDsCannotClearNewRequests() {
        let container = AppContainer.makeDefault()
        let viewModel = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
        let reference = FileDocumentReference(
            url: URL(fileURLWithPath: "/tmp/one-shot-navigation.md"),
            projectIdentifier: "/tmp"
        )
        viewModel.openFileInTab(at: reference.url, documentReference: reference)

        let firstAnchor = MarkdownRichNavigationRequest(
            documentID: reference.documentIdentity,
            fragment: "first"
        )
        let secondAnchor = MarkdownRichNavigationRequest(
            documentID: reference.documentIdentity,
            fragment: "second"
        )
        viewModel.setPendingRichNavigationRequest(firstAnchor)
        viewModel.setPendingRichNavigationRequest(secondAnchor)
        XCTAssertFalse(viewModel.claimRichNavigationRequest(id: firstAnchor.id))
        XCTAssertEqual(viewModel.pendingRichNavigationRequest, secondAnchor)
        XCTAssertTrue(viewModel.claimRichNavigationRequest(id: secondAnchor.id))
        XCTAssertFalse(viewModel.claimRichNavigationRequest(id: secondAnchor.id))

        viewModel.requestRenderedNavigation(.back)
        let firstCommand = viewModel.renderedNavigationCommandRequest
        viewModel.requestRenderedNavigation(.forward)
        let secondCommand = viewModel.renderedNavigationCommandRequest
        XCTAssertFalse(viewModel.claimRenderedNavigationCommand(id: firstCommand?.id ?? UUID()))
        XCTAssertEqual(viewModel.renderedNavigationCommandRequest, secondCommand)
        XCTAssertTrue(viewModel.claimRenderedNavigationCommand(id: secondCommand?.id ?? UUID()))
        XCTAssertFalse(viewModel.claimRenderedNavigationCommand(id: secondCommand?.id ?? UUID()))
    }
}
