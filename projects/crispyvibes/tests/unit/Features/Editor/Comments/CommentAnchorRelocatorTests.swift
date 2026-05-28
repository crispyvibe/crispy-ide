@testable import CrispyVibes
import XCTest

@MainActor
final class CommentAnchorRelocatorTests: XCTestCase {

    // MARK: - Hash + model

    func test_hash_matchesExpectedSha256() {
        // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let h = CommentAnchor.hash("hello")
        XCTAssertEqual(h, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func test_wholeLine_anchorCoversFullText() {
        let anchor = CommentAnchor.wholeLine(3, lineText: "let x = 42")
        XCTAssertEqual(anchor.startLine, 3)
        XCTAssertEqual(anchor.startColumn, 1)
        XCTAssertEqual(anchor.endLine, 3)
        XCTAssertEqual(anchor.endColumn, 11)
        XCTAssertEqual(anchor.anchorText, "let x = 42")
    }

    // MARK: - Step 1: exact match

    func test_relocate_unchangedReturnsUnchanged() {
        let lines = ["line one", "let x = 42", "line three"]
        let anchor = CommentAnchor(
            startLine: 2, startColumn: 1, endLine: 2, endColumn: 11,
            anchorHash: CommentAnchor.hash("let x = 42"),
            anchorText: "let x = 42",
            leadingContext: "", trailingContext: ""
        )
        XCTAssertEqual(CommentAnchorRelocator.relocate(anchor: anchor, in: lines), .unchanged)
    }

    // MARK: - Step 2: fuzzy line search

    func test_relocate_findsAnchorAfterLinesInsertedAbove() {
        let original = ["line one", "let x = 42", "line three"]
        var modified = original
        modified.insert("// new line", at: 0)
        modified.insert("// another", at: 0)
        // anchor was at line 2; should now be at line 4
        let anchor = CommentAnchor(
            startLine: 2, startColumn: 1, endLine: 2, endColumn: 11,
            anchorHash: CommentAnchor.hash("let x = 42"),
            anchorText: "let x = 42",
            leadingContext: "line one",
            trailingContext: "line three"
        )
        let outcome = CommentAnchorRelocator.relocate(anchor: anchor, in: modified)
        if case let .relocated(newAnchor, _) = outcome {
            XCTAssertEqual(newAnchor.startLine, 4)
        } else {
            XCTFail("expected relocated, got \(outcome)")
        }
    }

    func test_relocate_findsAnchorMovedDown() {
        let original = ["a", "b", "let x = 42", "c"]
        var modified = original
        modified.removeFirst()
        modified.removeFirst()
        // anchor was at line 3; should now be at line 1
        let anchor = CommentAnchor(
            startLine: 3, startColumn: 1, endLine: 3, endColumn: 11,
            anchorHash: CommentAnchor.hash("let x = 42"),
            anchorText: "let x = 42",
            leadingContext: "", trailingContext: ""
        )
        let outcome = CommentAnchorRelocator.relocate(anchor: anchor, in: modified)
        if case let .relocated(newAnchor, _) = outcome {
            XCTAssertEqual(newAnchor.startLine, 1)
        } else {
            XCTFail("expected relocated, got \(outcome)")
        }
    }

    // MARK: - Step 4: stale

    func test_relocate_returnsStaleWhenTextRemoved() {
        let lines = ["foo", "bar", "baz"]
        let anchor = CommentAnchor(
            startLine: 1, startColumn: 1, endLine: 1, endColumn: 11,
            anchorHash: CommentAnchor.hash("let x = 42"),
            anchorText: "let x = 42",
            leadingContext: "", trailingContext: ""
        )
        XCTAssertEqual(CommentAnchorRelocator.relocate(anchor: anchor, in: lines), .stale)
    }

    func test_relocate_returnsStaleOnEmptyFile() {
        let anchor = CommentAnchor(
            startLine: 1, startColumn: 1, endLine: 1, endColumn: 11,
            anchorHash: CommentAnchor.hash("let x = 42"),
            anchorText: "let x = 42",
            leadingContext: "", trailingContext: ""
        )
        XCTAssertEqual(CommentAnchorRelocator.relocate(anchor: anchor, in: []), .stale)
    }

    // MARK: - Snippet extraction

    func test_extractSnippet_singleLineRange() {
        let lines = ["hello world", "second line"]
        let snippet = CommentAnchorRelocator.extractSnippet(
            lines: lines,
            startLine: 1, startColumn: 7, endLine: 1, endColumn: 12
        )
        XCTAssertEqual(snippet, "world")
    }

    func test_extractSnippet_outOfBoundsReturnsNil() {
        let lines = ["short"]
        let snippet = CommentAnchorRelocator.extractSnippet(
            lines: lines,
            startLine: 5, startColumn: 1, endLine: 5, endColumn: 1
        )
        XCTAssertNil(snippet)
    }
}

@MainActor
final class CommentModelsTests: XCTestCase {

    func test_isEdited_falseWhenSameTimestamp() {
        let now = Date()
        let c = Comment(
            id: "1", vibespaceID: "v", filePath: "/f", parentID: nil,
            body: "hi", authorKind: .user, authorLabel: nil,
            createdAt: now, updatedAt: now, resolvedAt: nil, isStale: false,
            anchor: CommentAnchor.wholeLine(1, lineText: "hi")
        )
        XCTAssertFalse(c.isEdited)
    }

    func test_isEdited_trueWhenUpdateNoticeablyLater() {
        let created = Date()
        let updated = created.addingTimeInterval(60)
        let c = Comment(
            id: "1", vibespaceID: "v", filePath: "/f", parentID: nil,
            body: "hi", authorKind: .user, authorLabel: nil,
            createdAt: created, updatedAt: updated, resolvedAt: nil, isStale: false,
            anchor: CommentAnchor.wholeLine(1, lineText: "hi")
        )
        XCTAssertTrue(c.isEdited)
    }

    func test_thread_statusFollowsRoot() {
        let now = Date()
        let root = Comment(
            id: "1", vibespaceID: "v", filePath: "/f", parentID: nil,
            body: "ok", authorKind: .user, authorLabel: nil,
            createdAt: now, updatedAt: now, resolvedAt: now, isStale: false,
            anchor: CommentAnchor.wholeLine(1, lineText: "ok")
        )
        let thread = CommentThread(root: root, replies: [])
        XCTAssertEqual(thread.status, .resolved)
    }

    func test_thread_statusActiveByDefault() {
        let root = Comment(
            id: "1", vibespaceID: "v", filePath: "/f", parentID: nil,
            body: "ok", authorKind: .user, authorLabel: nil,
            createdAt: Date(), updatedAt: Date(), resolvedAt: nil, isStale: false,
            anchor: CommentAnchor.wholeLine(1, lineText: "ok")
        )
        let thread = CommentThread(root: root, replies: [])
        XCTAssertEqual(thread.status, .active)
    }

    func test_thread_statusStaleWhenRootStale() {
        let root = Comment(
            id: "1", vibespaceID: "v", filePath: "/f", parentID: nil,
            body: "ok", authorKind: .user, authorLabel: nil,
            createdAt: Date(), updatedAt: Date(), resolvedAt: nil, isStale: true,
            anchor: CommentAnchor.wholeLine(1, lineText: "ok")
        )
        let thread = CommentThread(root: root, replies: [])
        XCTAssertEqual(thread.status, .stale)
    }

    // MARK: - RPC encoder

    func test_encodeAdd_includesAnchorAndOptionalParent() {
        let anchor = CommentAnchor(
            startLine: 5, startColumn: 1, endLine: 5, endColumn: 10,
            anchorHash: "abc", anchorText: "x = 1", leadingContext: "", trailingContext: ""
        )
        let payload = CommentRPCEncoder.encodeAdd(
            id: "id-1", vibespaceID: "vs-1", filePath: "/f.swift", parentID: "p-1",
            body: "comment body", authorKind: .agent, authorLabel: "acpchat.x", anchor: anchor
        )
        XCTAssertEqual(payload["id"] as? String, "id-1")
        XCTAssertEqual(payload["vibespaceId"] as? String, "vs-1")
        XCTAssertEqual(payload["parentId"] as? String, "p-1")
        XCTAssertEqual(payload["authorKind"] as? String, "agent")
        XCTAssertEqual(payload["authorLabel"] as? String, "acpchat.x")
        let anchorDict = payload["anchor"] as? [String: Any]
        XCTAssertEqual(anchorDict?["startLine"] as? Int, 5)
        XCTAssertEqual(anchorDict?["anchorHash"] as? String, "abc")
    }
}
