import XCTest
@testable import CrispyVibes

final class EditorHTMLSecurityTests: XCTestCase {

    private func editorHTMLContents() throws -> String {
        let bundle = Bundle(for: type(of: self).self)
        // The editor.html is in the main app bundle's MarkdownRuntime resources
        guard let url = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "MarkdownRuntime")
                ?? bundle.url(forResource: "editor", withExtension: "html") else {
            // Fallback: read directly from source tree for unit test targets that don't bundle resources
            let sourceURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // EditorHTMLSecurityTests.swift
                .deletingLastPathComponent() // Services
                .deletingLastPathComponent() // Editor
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // unit
                .deletingLastPathComponent() // tests
                .appendingPathComponent("crispyvibes/Resources/MarkdownRuntime/editor.html")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testEditorHTMLContainsCSPMetaTag() throws {
        let html = try editorHTMLContents()
        XCTAssertTrue(
            html.contains("Content-Security-Policy"),
            "editor.html must contain a Content-Security-Policy meta tag"
        )
    }

    func testCSPBlocksInlineEventHandlers() throws {
        let html = try editorHTMLContents()
        // script-src must NOT contain 'unsafe-inline' (without a nonce, that would allow event handlers)
        // It should use a nonce-based policy
        let scriptSrcRange = html.range(of: "script-src[^;]+", options: .regularExpression)
        guard let range = scriptSrcRange else {
            XCTFail("editor.html CSP must contain a script-src directive")
            return
        }
        let scriptSrc = String(html[range])
        XCTAssertFalse(
            scriptSrc.contains("'unsafe-inline'"),
            "script-src must not contain 'unsafe-inline' — use nonce instead"
        )
        XCTAssertTrue(
            scriptSrc.contains("'nonce-"),
            "script-src must use a nonce for the editor's inline script"
        )
    }

    func testCSPBlocksNetworkExfiltration() throws {
        let html = try editorHTMLContents()
        XCTAssertTrue(
            html.contains("connect-src 'none'"),
            "CSP must block connect-src to prevent data exfiltration via fetch/XHR"
        )
    }

    func testInlineScriptHasNonceAttribute() throws {
        let html = try editorHTMLContents()
        XCTAssertTrue(
            html.contains("script nonce="),
            "The inline <script> tag must have a nonce attribute matching the CSP"
        )
    }

    func testCSPScriptSrcDisallowsFileScheme() throws {
        let html = try editorHTMLContents()
        // F055: KaTeX scripts are co-located in MarkdownRuntime and load under
        // 'self'. script-src must NOT allow file:, which would let injected
        // markdown reference arbitrary local scripts (root read-access).
        guard let range = html.range(of: "script-src[^;]+", options: .regularExpression) else {
            XCTFail("editor.html CSP must contain a script-src directive")
            return
        }
        let scriptSrc = String(html[range])
        XCTAssertFalse(
            scriptSrc.contains("file:"),
            "script-src must not allow the file: scheme — co-locate scripts under 'self'"
        )
    }
}
