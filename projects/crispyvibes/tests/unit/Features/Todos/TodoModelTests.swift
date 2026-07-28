import XCTest
@testable import CrispyVibes

/// F053 — pure-model tests for the Todos list shaping, message grouping, and
/// sticky-color parsing that drive the management surface.
@MainActor
final class TodoModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTodo(
        id: String,
        title: String = "Task",
        body: String? = nil,
        project: String? = "/tmp/alpha",
        colorTag: String? = nil,
        completed: Bool = false,
        createdAt: String = "2026-01-01T10:00:00Z",
        completedAt: String? = nil
    ) -> Todo {
        Todo(
            id: id,
            vibespaceID: "vs",
            projectPath: project,
            title: title,
            body: body,
            colorTag: colorTag,
            filePath: nil,
            status: completed ? .completed : .active,
            dueAt: nil,
            reminderAt: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: completedAt
        )
    }

    private func makeMessage(
        id: String,
        author: String = "user",
        createdAt: String
    ) -> TodoMessage {
        TodoMessage(id: id, todoID: "t", body: "m-\(id)", authorKind: author, createdAt: createdAt, updatedAt: createdAt)
    }

    // MARK: - TodoListSections

    func testShapeScopesToProjectUnlessAllRequested() {
        let todos = [
            makeTodo(id: "a", project: "/tmp/alpha"),
            makeTodo(id: "b", project: "/tmp/beta"),
            makeTodo(id: "c", project: nil),
        ]
        let scoped = TodoListSections.shape(todos, projectPath: "/tmp/alpha", includeAllProjects: false, query: "")
        XCTAssertEqual(scoped.active.map(\.id), ["a"])

        let all = TodoListSections.shape(todos, projectPath: "/tmp/alpha", includeAllProjects: true, query: "")
        XCTAssertEqual(Set(all.active.map(\.id)), ["a", "b", "c"])
    }

    func testShapeSplitsActiveAndCompletedWithStableSort() {
        let todos = [
            makeTodo(id: "old", createdAt: "2026-01-01T09:00:00Z"),
            makeTodo(id: "new", createdAt: "2026-01-02T09:00:00Z"),
            makeTodo(id: "doneLate", completed: true, createdAt: "2026-01-01T08:00:00Z", completedAt: "2026-01-03T09:00:00Z"),
            makeTodo(id: "doneEarly", completed: true, createdAt: "2026-01-01T07:00:00Z", completedAt: "2026-01-02T09:00:00Z"),
        ]
        let shaped = TodoListSections.shape(todos, projectPath: "/tmp/alpha", includeAllProjects: false, query: "")
        // Active: newest creation first; renames/edits must not reorder (sort key is createdAt).
        XCTAssertEqual(shaped.active.map(\.id), ["new", "old"])
        // Completed: most recently completed first.
        XCTAssertEqual(shaped.completed.map(\.id), ["doneLate", "doneEarly"])
    }

    func testShapeSearchMatchesTitleAndBodyCaseInsensitively() {
        let todos = [
            makeTodo(id: "t1", title: "Fix login crash"),
            makeTodo(id: "t2", title: "Groceries", body: "buy LOGIN sticker"),
            makeTodo(id: "t3", title: "Unrelated"),
        ]
        let shaped = TodoListSections.shape(todos, projectPath: "/tmp/alpha", includeAllProjects: false, query: "login")
        XCTAssertEqual(Set(shaped.active.map(\.id)), ["t1", "t2"])
    }

    func testShapeBlankQueryIsNoFilter() {
        let todos = [makeTodo(id: "a")]
        let shaped = TodoListSections.shape(todos, projectPath: "/tmp/alpha", includeAllProjects: false, query: "   ")
        XCTAssertEqual(shaped.active.map(\.id), ["a"])
    }

    // MARK: - TodoMessageGroup

    private func parse(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    func testGroupingCollapsesSameAuthorWithinWindow() {
        let messages = [
            makeMessage(id: "1", createdAt: "2026-01-01T10:00:00Z"),
            makeMessage(id: "2", createdAt: "2026-01-01T10:02:00Z"),
            makeMessage(id: "3", createdAt: "2026-01-01T10:04:00Z"),
        ]
        let groups = TodoMessageGroup.group(messages, parseDate: parse)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].messages.map(\.id), ["1", "2", "3"])
    }

    func testGroupingSplitsOnAuthorChange() {
        let messages = [
            makeMessage(id: "1", author: "user", createdAt: "2026-01-01T10:00:00Z"),
            makeMessage(id: "2", author: "agent", createdAt: "2026-01-01T10:01:00Z"),
            makeMessage(id: "3", author: "agent", createdAt: "2026-01-01T10:02:00Z"),
        ]
        let groups = TodoMessageGroup.group(messages, parseDate: parse)
        XCTAssertEqual(groups.map(\.authorKind), ["user", "agent"])
        XCTAssertEqual(groups[1].messages.map(\.id), ["2", "3"])
    }

    func testGroupingSplitsWhenWindowElapses() {
        let messages = [
            makeMessage(id: "1", createdAt: "2026-01-01T10:00:00Z"),
            makeMessage(id: "2", createdAt: "2026-01-01T10:06:00Z"),
        ]
        let groups = TodoMessageGroup.group(messages, parseDate: parse)
        XCTAssertEqual(groups.count, 2)
    }

    func testGroupingSplitsOnUnparseableTimestampInsteadOfMerging() {
        let messages = [
            makeMessage(id: "1", createdAt: "2026-01-01T10:00:00Z"),
            makeMessage(id: "2", createdAt: "not-a-date"),
        ]
        let groups = TodoMessageGroup.group(messages, parseDate: parse)
        XCTAssertEqual(groups.count, 2)
    }

    // MARK: - Sticky colors

    func testStickyColorParsesKnownTagsAndRejectsUnknown() {
        XCTAssertEqual(makeTodo(id: "a", colorTag: "yellow").stickyColor, .yellow)
        XCTAssertNil(makeTodo(id: "b", colorTag: "chartreuse").stickyColor)
        XCTAssertNil(makeTodo(id: "c", colorTag: nil).stickyColor)
    }
}
