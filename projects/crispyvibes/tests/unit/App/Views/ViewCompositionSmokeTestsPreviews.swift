import AppKit
import Foundation
import PDFKit
import SwiftUI
import XCTest
@testable import CrispyVibes

@MainActor
extension ViewCompositionSmokeTests {
    func testGitDiffAndMarkupPreviewsComposeWithoutCrashing() throws {
        let diff = """
        ### Changes
        diff --git a/README.md b/README.md
        index 1111111..2222222 100644
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,2 @@
        -old line
        +new line
         unchanged
        """
        let diffPreview = GitDiffPreview(content: diff)
        mount(diffPreview)
        XCTAssertFalse(String(describing: diffPreview.body).isEmpty)

        let fallbackDiffPreview = GitDiffPreview(content: "not-a-git-diff")
        mount(fallbackDiffPreview)
        XCTAssertFalse(String(describing: fallbackDiffPreview.body).isEmpty)

        let markdownContent = Box("# Heading\n\nSome content")
        let markdownEditor = MarkupRenderedEditor(
            mode: .markdown,
            baseDirectoryURL: tempRoot,
            commandRequest: nil,
            content: binding(markdownContent)
        )
        mount(markdownEditor)

        let htmlContent = Box("<h1>Heading</h1><p>Body</p>")
        let htmlEditor = MarkupRenderedEditor(
            mode: .html,
            baseDirectoryURL: tempRoot,
            commandRequest: nil,
            content: binding(htmlContent)
        )
        mount(htmlEditor)
    }

    func testRasterImagePreviewHostAndCanvasComposeWithoutCrashing() throws {
        let pngURL = tempRoot.appendingPathComponent("preview.png")
        try writeFixturePNG(to: pngURL, size: NSSize(width: 64, height: 48))

        var dirtyStates: [Bool] = []
        let rasterHost = RasterImagePreviewHost(
            fileURL: pngURL,
            onSaveDataRequest: nil,
            onDirtyStateChange: { dirtyStates.append($0) }
        )
        mount(rasterHost)
        XCTAssertFalse(String(describing: rasterHost.body).isEmpty)
        XCTAssertEqual(dirtyStates.last, false)

        let unsupportedURL = tempRoot.appendingPathComponent("preview.txt")
        try Data("not an image".utf8).write(to: unsupportedURL)
        let unsupportedHost = RasterImagePreviewHost(
            fileURL: unsupportedURL,
            onSaveDataRequest: nil,
            onDirtyStateChange: { _ in }
        )
        mount(unsupportedHost)
        XCTAssertFalse(String(describing: unsupportedHost.body).isEmpty)

        let canvas = EditableRasterImageCanvasView(frame: .zero)
        var callbackStates: [Bool] = []
        canvas.setDirtyStateObserver { callbackStates.append($0) }
        canvas.loadImage(makeSolidImage(size: NSSize(width: 40, height: 30), color: .systemBlue))
        XCTAssertTrue(canvas.hasRenderableImage)
        XCTAssertFalse(canvas.hasPendingEdits)
        XCTAssertTrue(canvas.copyCompositedImageToPasteboard())

        let savedImageURL = tempRoot.appendingPathComponent("saved.png")
        switch canvas.saveCompositedImage(to: savedImageURL) {
        case .success:
            XCTAssertTrue(FileManager.default.fileExists(atPath: savedImageURL.path))
        case let .failure(error):
            XCTFail("Expected composited image save success, got error: \(error)")
        }
        XCTAssertFalse(callbackStates.isEmpty)
        XCTAssertFalse(canvas.clearEdits())

        canvas.loadImage(nil)
        XCTAssertFalse(canvas.hasRenderableImage)
        switch canvas.saveCompositedImage(to: tempRoot.appendingPathComponent("missing.png")) {
        case .success:
            XCTFail("Expected save to fail when no renderable image is loaded.")
        case .failure:
            break
        }
        XCTAssertFalse(canvas.copyCompositedImageToPasteboard())
    }

    func testCodePlainTextAndPDFPreviewsComposeWithoutCrashing() throws {
        let codeURL = tempRoot.appendingPathComponent("script.js")
        try Data("const value = 1;\n".utf8).write(to: codeURL)
        let plainURL = tempRoot.appendingPathComponent("notes.txt")
        try Data("plain text\n".utf8).write(to: plainURL)
        let pdfURL = tempRoot.appendingPathComponent("preview.pdf")
        try writeFixturePDF(to: pdfURL)

        let codeContent = Box("const value = 1;\n")
        let codeEditor = CodeEditorView(
            fileURL: codeURL,
            language: JavaScriptLanguage(),
            content: binding(codeContent),
            onContentChange: { _ in }
        )
        mount(codeEditor)

        let plainContent = Box("plain text\n")
        let plainEditor = PlainTextEditor(
            fileURL: plainURL,
            content: binding(plainContent),
            onContentChange: { _ in }
        )
        mount(plainEditor)

        let pdfPreview = PDFFilePreview(fileURL: pdfURL)
        mount(pdfPreview)
    }

    func testMarkdownImageCandidateScannerFindsAndSortsRelativePaths() throws {
        let docs = tempRoot.appendingPathComponent("docs", isDirectory: true)
        let assets = docs.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let alphaPNG = assets.appendingPathComponent("alpha.png")
        let zebraJPG = assets.appendingPathComponent("zebra.jpg")
        let nonImage = assets.appendingPathComponent("notes.md")
        try writeFixturePNG(to: alphaPNG, size: NSSize(width: 20, height: 20))
        try writeFixturePNG(to: zebraJPG, size: NSSize(width: 20, height: 20))
        try Data("# notes".utf8).write(to: nonImage)

        let candidates = MarkdownImageCandidateScanner.scan(baseDirectoryURL: docs)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first?.filename, "alpha.png")
        XCTAssertEqual(candidates.last?.filename, "zebra.jpg")
        XCTAssertEqual(candidates.first?.relativePath, "assets/alpha.png")
        XCTAssertEqual(candidates.first?.insertPath, "assets/alpha.png")
        XCTAssertTrue(candidates.first?.previewURL.hasPrefix("file://") == true)
        XCTAssertTrue(MarkdownImageCandidateScanner.scan(baseDirectoryURL: nil).isEmpty)
    }
}
