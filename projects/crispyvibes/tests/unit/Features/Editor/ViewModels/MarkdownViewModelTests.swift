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

    // MARK: - F057 LaTeX editor

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

    func testLatexDocumentOpensEditableInRichMode() async throws {
        let fileURL = tempRoot.appendingPathComponent("paper.tex")
        try Data("\\documentclass{article}\n\\begin{document}\nHello $x^2$.\n\\end{document}\n".utf8).write(to: fileURL)

        viewModel.openFile(at: fileURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.documentType == .latex
        }
        XCTAssertTrue(opened)
        XCTAssertTrue(viewModel.isEditableDocumentType(.latex))
        XCTAssertTrue(viewModel.supportsMarkupViewModeToggle)
        XCTAssertEqual(viewModel.defaultMarkupViewMode, .rich)
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
