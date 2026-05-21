import AppKit
import Foundation
import PDFKit
import SwiftUI
import XCTest
@testable import CrispyVibes

@MainActor
final class SyntaxAndLanguageDefinitionTests: XCTestCase {
    func testLanguageDefinitionsExposePatternsAndExtensions() {
        let languages: [any LanguageDefinition] = [
            JavaScriptLanguage(),
            JSONLanguage(),
            PythonLanguage(),
            RLanguage()
        ]

        for language in languages {
            XCTAssertFalse(language.name.isEmpty)
            XCTAssertFalse(language.fileExtensions.isEmpty)
            XCTAssertFalse(language.patterns.isEmpty)
        }
    }

    func testKeywordLanguageAddsKeywordAndCommentPatterns() {
        let language = KeywordLanguage(
            name: "TestLang",
            fileExtensions: ["tl"],
            keywords: ["alpha", "beta"],
            lineCommentPrefixes: ["//", "#"],
            blockCommentPattern: "/\\*[\\s\\S]*?\\*/"
        )

        let patterns = language.patterns
        XCTAssertTrue(patterns.contains(where: { $0.tokenType == .keyword }))
        XCTAssertTrue(patterns.contains(where: { $0.tokenType == .comment && $0.options == .anchorsMatchLines }))
        XCTAssertTrue(patterns.contains(where: { $0.tokenType == .comment && $0.options == [] }))
        XCTAssertTrue(patterns.contains(where: { $0.tokenType == .string }))
        XCTAssertTrue(patterns.contains(where: { $0.tokenType == .number }))
        XCTAssertTrue(patterns.contains(where: { $0.tokenType == .operator }))
    }

    func testGenericCodeSyntaxHighlightingIsStableAcrossRandomizedInputs() {
        let language = GenericCodeLanguage(name: "Code")
        let textView = NSTextView()

        for iteration in 0..<160 {
            let randomLine = "let v\(iteration) = \(Int.random(in: 0...999)); // c\(iteration)"
            textView.string = randomLine

            language.applySyntaxHighlighting(
                to: textView,
                theme: .dark,
                baseFont: .monospacedSystemFont(ofSize: 13, weight: .regular)
            )

            guard let storage = textView.textStorage else {
                return XCTFail("Expected text storage")
            }

            let sampledIndex = min(max(storage.length - 1, 0), randomLine.count - 1)
            let attributes = storage.attributes(at: sampledIndex, effectiveRange: nil)
            XCTAssertNotNil(attributes[.font])
            XCTAssertNotNil(attributes[.foregroundColor])
        }
    }

    func testSyntaxThemeFromPalettePreservesBackgroundAndTextTokens() {
        let palette = AppThemePalette.midnightMono
        let theme = SyntaxTheme.fromPalette(palette, colorScheme: .dark)

        XCTAssertEqual(ProjectColorTag(color: Color(theme.background)).storageToken, palette.canvasBackground.storageToken)
        XCTAssertEqual(ProjectColorTag(color: Color(theme.text)).storageToken, palette.terminalForeground.storageToken)
    }
}

