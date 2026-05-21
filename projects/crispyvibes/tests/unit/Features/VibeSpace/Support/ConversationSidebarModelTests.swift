import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ConversationSidebarModelTests: XCTestCase {

    // MARK: - FTSSearchResult

    func test_FTSSearchResult_parsesFullJSON() {
        let json: [String: Any] = [
            "messageId": "msg-1",
            "threadId": "thread-1",
            "threadTitle": "Fix auth bug",
            "snippet": "The <b>auth</b> token was expired",
            "agentId": "kiro",
            "projectPath": "/path/to/project",
            "updatedAt": "2026-04-29T10:00:00Z",
            "rank": -1.5,
        ]
        let result = FTSSearchResult(json: json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "msg-1")
        XCTAssertEqual(result?.threadId, "thread-1")
        XCTAssertEqual(result?.threadTitle, "Fix auth bug")
        XCTAssertEqual(result?.snippet, "The <b>auth</b> token was expired")
        XCTAssertEqual(result?.agentId, "kiro")
        XCTAssertEqual(result?.projectPath, "/path/to/project")
        XCTAssertEqual(result?.projectName, "project")
    }

    func test_FTSSearchResult_returnsNilForMissingRequiredFields() {
        XCTAssertNil(FTSSearchResult(json: [:]))
        XCTAssertNil(FTSSearchResult(json: ["messageId": "1"]))
        XCTAssertNil(FTSSearchResult(json: ["messageId": "1", "threadId": "2"]))
        XCTAssertNil(FTSSearchResult(json: ["messageId": "1", "threadId": "2", "threadTitle": "T"]))
    }

    func test_FTSSearchResult_defaultsOptionalFields() {
        let json: [String: Any] = [
            "messageId": "msg-1",
            "threadId": "thread-1",
            "threadTitle": "Title",
            "snippet": "text",
        ]
        let result = FTSSearchResult(json: json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.agentId, "")
        XCTAssertEqual(result?.projectPath, "")
        XCTAssertEqual(result?.updatedAt, "")
        XCTAssertEqual(result?.projectName, "")
    }

    func test_FTSSearchResult_relativeTime_validDate() {
        let now = ISO8601DateFormatter().string(from: Date())
        let json: [String: Any] = [
            "messageId": "1", "threadId": "1", "threadTitle": "T", "snippet": "s",
            "updatedAt": now,
        ]
        let result = FTSSearchResult(json: json)!
        XCTAssertFalse(result.relativeTime.isEmpty)
    }

    func test_FTSSearchResult_relativeTime_emptyForInvalidDate() {
        let json: [String: Any] = [
            "messageId": "1", "threadId": "1", "threadTitle": "T", "snippet": "s",
            "updatedAt": "not-a-date",
        ]
        let result = FTSSearchResult(json: json)!
        XCTAssertEqual(result.relativeTime, "")
    }

    // MARK: - ConversationThreadSummary

    func test_ThreadSummary_parsesFullJSON() {
        let json: [String: Any] = [
            "id": "thread-1",
            "title": "Fix pagination",
            "agentId": "codex",
            "transportKind": "codex_direct",
            "projectPath": "/path/to/backend",
            "updatedAt": "2026-04-29T10:00:00Z",
        ]
        let summary = ConversationThreadSummary(json: json)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.id, "thread-1")
        XCTAssertEqual(summary?.title, "Fix pagination")
        XCTAssertEqual(summary?.agentId, "codex")
        XCTAssertEqual(summary?.projectDisplayName, "backend")
    }

    func test_ThreadSummary_returnsNilForMissingFields() {
        XCTAssertNil(ConversationThreadSummary(json: [:]))
        XCTAssertNil(ConversationThreadSummary(json: ["id": "1"]))
        XCTAssertNil(ConversationThreadSummary(json: ["id": "1", "title": "T"]))
    }

    func test_ThreadSummary_defaultsOptionalFields() {
        let json: [String: Any] = ["id": "1", "title": "T", "agentId": "kiro"]
        let summary = ConversationThreadSummary(json: json)!
        XCTAssertEqual(summary.transportKind, "")
        XCTAssertEqual(summary.projectPath, "")
        XCTAssertEqual(summary.updatedAt, "")
        XCTAssertFalse(summary.hasActiveSession)
    }

    func test_ThreadSummary_projectDisplayName_emptyPathReturnsGeneral() {
        let json: [String: Any] = ["id": "1", "title": "T", "agentId": "kiro", "projectPath": ""]
        let summary = ConversationThreadSummary(json: json)!
        XCTAssertEqual(summary.projectDisplayName, "General")
    }

    func test_ThreadSummary_initFromSearchResult() {
        let json: [String: Any] = [
            "messageId": "msg-1", "threadId": "thread-1", "threadTitle": "Auth fix",
            "snippet": "text", "agentId": "codex", "projectPath": "/p/backend",
            "updatedAt": "2026-04-29T10:00:00Z",
        ]
        let searchResult = FTSSearchResult(json: json)!
        let summary = ConversationThreadSummary(searchResult: searchResult)
        XCTAssertEqual(summary.id, "thread-1")
        XCTAssertEqual(summary.title, "Auth fix")
        XCTAssertEqual(summary.agentId, "codex")
        XCTAssertEqual(summary.projectPath, "/p/backend")
        XCTAssertEqual(summary.updatedAt, "2026-04-29T10:00:00Z")
    }

    func test_ThreadSummary_relativeTime_validDate() {
        let now = ISO8601DateFormatter().string(from: Date())
        let json: [String: Any] = ["id": "1", "title": "T", "agentId": "k", "updatedAt": now]
        let summary = ConversationThreadSummary(json: json)!
        XCTAssertFalse(summary.relativeTime.isEmpty)
    }

    func test_ThreadSummary_relativeTime_emptyForMissingDate() {
        let json: [String: Any] = ["id": "1", "title": "T", "agentId": "k"]
        let summary = ConversationThreadSummary(json: json)!
        XCTAssertEqual(summary.relativeTime, "")
    }

    // MARK: - Snippet Highlighting

    func test_snippetParts_noBoldTags() {
        let parts = FTSSnippetParser.parse("plain text without tags")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].text, "plain text without tags")
        XCTAssertFalse(parts[0].isBold)
    }

    func test_snippetParts_singleBoldTag() {
        let parts = FTSSnippetParser.parse("the <b>auth</b> token")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0].text, "the ")
        XCTAssertFalse(parts[0].isBold)
        XCTAssertEqual(parts[1].text, "auth")
        XCTAssertTrue(parts[1].isBold)
        XCTAssertEqual(parts[2].text, " token")
        XCTAssertFalse(parts[2].isBold)
    }

    func test_snippetParts_multipleBoldTags() {
        let parts = FTSSnippetParser.parse("<b>fix</b> the <b>auth</b> bug")
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0].text, "fix")
        XCTAssertTrue(parts[0].isBold)
        XCTAssertEqual(parts[1].text, " the ")
        XCTAssertFalse(parts[1].isBold)
        XCTAssertEqual(parts[2].text, "auth")
        XCTAssertTrue(parts[2].isBold)
        XCTAssertEqual(parts[3].text, " bug")
        XCTAssertFalse(parts[3].isBold)
    }

    func test_snippetParts_emptyString() {
        let parts = FTSSnippetParser.parse("")
        XCTAssertTrue(parts.isEmpty)
    }

    func test_snippetParts_onlyBoldTag() {
        let parts = FTSSnippetParser.parse("<b>everything</b>")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].text, "everything")
        XCTAssertTrue(parts[0].isBold)
    }

    func test_snippetParts_adjacentBoldTags() {
        let parts = FTSSnippetParser.parse("<b>hello</b><b>world</b>")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].text, "hello")
        XCTAssertEqual(parts[1].text, "world")
        XCTAssertTrue(parts[0].isBold)
        XCTAssertTrue(parts[1].isBold)
    }
}
