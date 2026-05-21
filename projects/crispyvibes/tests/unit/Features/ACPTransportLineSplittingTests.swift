import Foundation
import XCTest
@testable import CrispyVibes

/// Tests for ACPTransport.extractJSONMessages — the JSON boundary detection
/// used by ACPTransport, CodexSession, and ClaudeCodeSession read loops.
@MainActor
final class ACPTransportLineSplittingTests: XCTestCase {

    /// Extract JSON messages using the production code.
    private func extract(from string: String) -> [Data] {
        var buffer = string.data(using: .utf8)!
        var results: [Data] = []
        ACPTransport.extractJSONMessages(from: &buffer) { results.append($0) }
        return results
    }

    private func validJSONCount(from string: String) -> Int {
        extract(from: string).filter {
            (try? JSONSerialization.jsonObject(with: $0)) != nil
        }.count
    }

    // MARK: - Basic

    func test_singleMessage() {
        XCTAssertEqual(extract(from: "{\"id\":1}\n").count, 1)
    }

    func test_twoMessages() {
        XCTAssertEqual(extract(from: "{\"id\":1}\n{\"id\":2}\n").count, 2)
    }

    func test_escapedNewline_doesNotSplit() {
        let results = extract(from: "{\"text\":\"line1\\\\nline2\"}\n")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(validJSONCount(from: "{\"text\":\"line1\\\\nline2\"}\n"), 1)
    }

    func test_emptyLinesBetweenMessages() {
        XCTAssertEqual(extract(from: "{\"id\":1}\n\n\n{\"id\":2}\n").count, 2)
    }

    func test_noTrailingNewline() {
        XCTAssertEqual(extract(from: "{\"id\":1}").count, 1)
    }

    // MARK: - Literal newline in JSON string value

    func test_literalNewlineInValue_oneLine() {
        XCTAssertEqual(extract(from: "{\"text\":\"line1\nline2\"}\n").count, 1)
    }

    func test_literalNewlineInValue_validJSON() {
        XCTAssertEqual(validJSONCount(from: "{\"text\":\"line1\nline2\"}\n"), 1)
    }

    func test_bulletList_oneLine() {
        let text = "- google.com\n- youtube.com\n- facebook.com"
        let json = "{\"method\":\"update\",\"params\":{\"text\":\"\(text)\"}}\n"
        XCTAssertEqual(extract(from: json).count, 1)
    }

    func test_bulletList_validJSON() {
        let text = "- google.com\n- youtube.com\n- facebook.com"
        let json = "{\"method\":\"update\",\"params\":{\"text\":\"\(text)\"}}\n"
        XCTAssertEqual(validJSONCount(from: json), 1)
    }

    func test_multipleNewlines_oneLine() {
        XCTAssertEqual(extract(from: "{\"text\":\"a\nb\nc\nd\ne\"}\n").count, 1)
    }

    // MARK: - Mixed

    func test_validThenNewlineMessage() {
        let combined = "{\"id\":1}\n{\"text\":\"hello\nworld\"}\n"
        XCTAssertEqual(validJSONCount(from: combined), 2)
    }

    func test_newlineMessageThenValid() {
        let combined = "{\"text\":\"a\nb\"}\n{\"id\":2}\n"
        XCTAssertEqual(validJSONCount(from: combined), 2)
    }

    // MARK: - Edge cases

    func test_newlineAtStartOfValue() {
        XCTAssertEqual(extract(from: "{\"text\":\"\nhello\"}\n").count, 1)
    }

    func test_newlineAtEndOfValue() {
        XCTAssertEqual(extract(from: "{\"text\":\"hello\n\"}\n").count, 1)
    }

    func test_onlyNewlineAsValue() {
        XCTAssertEqual(extract(from: "{\"text\":\"\n\"}\n").count, 1)
    }

    func test_carriageReturnNewline() {
        XCTAssertEqual(extract(from: "{\"text\":\"line1\r\nline2\"}\n").count, 1)
    }

    func test_nestedObjects() {
        let json = "{\"a\":{\"b\":{\"c\":\"deep\"}}}\n"
        XCTAssertEqual(extract(from: json).count, 1)
        XCTAssertEqual(validJSONCount(from: json), 1)
    }

    func test_bracesInsideString_notCounted() {
        let json = "{\"text\":\"{ not a real object }\"}\n"
        XCTAssertEqual(extract(from: json).count, 1)
        XCTAssertEqual(validJSONCount(from: json), 1)
    }

    func test_escapedQuoteInsideString() {
        let json = "{\"text\":\"she said \\\"hello\\\"\"}\n"
        XCTAssertEqual(extract(from: json).count, 1)
        XCTAssertEqual(validJSONCount(from: json), 1)
    }

    func test_escapedBackslashBeforeQuote() {
        // \\\\" in JSON = literal backslash followed by end-of-string quote
        let json = "{\"path\":\"C:\\\\Users\\\\test\"}\n"
        XCTAssertEqual(extract(from: json).count, 1)
        XCTAssertEqual(validJSONCount(from: json), 1)
    }
}
