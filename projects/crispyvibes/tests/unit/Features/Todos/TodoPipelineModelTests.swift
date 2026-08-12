import XCTest
@testable import CrispyVibes

/// F060 — pure-model tests for the pipeline additions: file-link parsing and
/// JSON decode, triage shape validation, and Todo's pipeline fields.
@MainActor
final class TodoPipelineModelTests: XCTestCase {

    // MARK: - File links

    func testParsePathTokenSplitsTrailingLineAnchor() {
        XCTAssertEqual(TodoFileLink.parsePathToken("src/Parser.swift:120").path, "src/Parser.swift")
        XCTAssertEqual(TodoFileLink.parsePathToken("src/Parser.swift:120").line, 120)
        XCTAssertEqual(TodoFileLink.parsePathToken("src/Parser.swift").line, nil)
        // Line 0 / negative / non-numeric suffixes stay part of the path.
        XCTAssertEqual(TodoFileLink.parsePathToken("a/b:0").path, "a/b:0")
        XCTAssertEqual(TodoFileLink.parsePathToken("a/b:x").path, "a/b:x")
        // A bare leading colon is not an anchor.
        XCTAssertEqual(TodoFileLink.parsePathToken(":9").path, ":9")
    }

    func testFileLinkDecodesFromJSONAndFormatsDisplayName() {
        let link = TodoFileLink(json: [
            "id": "l1", "todoId": "t1", "path": "/p/src/Parser.swift",
            "line": 42, "createdAt": "2026-01-01T10:00:00Z",
        ])
        XCTAssertEqual(link?.line, 42)
        XCTAssertEqual(link?.displayName, "Parser.swift:42")
        XCTAssertNil(TodoFileLink(json: ["id": "x"]), "missing required fields must fail decode")
    }

    // MARK: - Triage

    func testTriageDecodeRejectsMalformedAndAcceptsValidShape() {
        XCTAssertNil(TodoTriage.decode(from: nil))
        XCTAssertNil(TodoTriage.decode(from: "not json"))
        XCTAssertNil(TodoTriage.decode(from: #"{"status": "bogus"}"#), "unknown status must fail decode")

        let laneID = UUID()
        let valid = """
        {
          "status": "done",
          "todoUpdatedAtSnapshot": "2026-01-01T10:00:00Z",
          "questions": [{"text": "Which env?", "carryForwardKey": "env"}],
          "lanes": [
            {"laneID": "\(laneID.uuidString)", "name": "Fix a bug", "score": 0.9},
            {"laneID": "\(UUID().uuidString)", "name": "Research", "score": 0.4}
          ],
          "laneShaped": true,
          "prefill": {"goal": "fix login trim"}
        }
        """
        let triage = TodoTriage.decode(from: valid)
        XCTAssertEqual(triage?.status, .done)
        XCTAssertEqual(triage?.openQuestionCount, 1)
        XCTAssertEqual(triage?.suggestedLane?.laneID, laneID, "highest score wins")
        XCTAssertEqual(triage?.prefill?["goal"], "fix login trim")
    }

    func testTriageRoundTripsThroughEncodedJSON() {
        var triage = TodoTriage(status: .done)
        triage.questions = [.init(text: "q", carryForwardKey: nil)]
        triage.laneShaped = false
        let json = triage.encodedJSON()
        XCTAssertNotNil(json)
        XCTAssertEqual(TodoTriage.decode(from: json), triage)
    }

    // MARK: - Todo pipeline fields

    func testTodoDecodesPipelineFieldsAndTreatsMalformedTriageAsAbsent() {
        var json: [String: Any] = [
            "id": "t1", "vibespaceId": "vs", "title": "x", "status": "active",
            "createdAt": "2026-01-01T10:00:00Z", "updatedAt": "2026-01-01T10:00:00Z",
            "laneTaskId": "task-1", "refinementSessionId": "sess-1",
            "triageJson": #"{"status": "skipped"}"#,
        ]
        var todo = Todo(json: json)
        XCTAssertEqual(todo?.laneTaskID, "task-1")
        XCTAssertEqual(todo?.refinementSessionID, "sess-1")
        XCTAssertEqual(todo?.triage?.status, .skipped)

        json["triageJson"] = "{broken"
        todo = Todo(json: json)
        XCTAssertNotNil(todo, "malformed triage must not fail the todo decode")
        XCTAssertNil(todo?.triage, "malformed triage is treated as absent")
    }
}
