import Foundation
import XCTest
@testable import CrispyVibes

// F060 — bridge tests: dispatch mapping priority, unresolved-input gating,
// the one-active-task rule, and lifecycle fan-in with dedupe. The todo side is
// a deterministic fake; the lane side is the real manager over the in-memory
// store (the same doubles the F059 tests use).

@MainActor
private final class FakePipelineTodoStore: TodoPipelineTodoStoring {
    var todos: [Todo] = []
    var links: [String: [TodoFileLink]] = [:]
    private(set) var pipelineWrites: [(id: String, laneTaskID: String??)] = []
    private(set) var postedMessages: [(todoID: String, body: String, authorKind: String)] = []

    func todo(withID id: String) -> Todo? { todos.first { $0.id == id } }
    func fileLinks(forTodo todoID: String) -> [TodoFileLink] { links[todoID] ?? [] }

    func setPipelineFields(
        id: String,
        laneTaskID: String?? = nil,
        refinementSessionID: String?? = nil,
        triage: TodoTriage?? = nil
    ) async -> Bool {
        pipelineWrites.append((id, laneTaskID))
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            if case .some(let value) = laneTaskID { todos[idx].laneTaskID = value }
            if case .some(let value) = refinementSessionID { todos[idx].refinementSessionID = value }
            if case .some(let value) = triage { todos[idx].triage = value }
        }
        return true
    }

    func addMessage(todoID: String, body: String, authorKind: String) async -> TodoMessage? {
        postedMessages.append((todoID, body, authorKind))
        return TodoMessage(
            id: UUID().uuidString, todoID: todoID, body: body,
            authorKind: authorKind, createdAt: "", updatedAt: ""
        )
    }

    private(set) var completions: [(id: String, completed: Bool)] = []
    func setCompleted(id: String, completed: Bool) async -> Bool {
        completions.append((id, completed))
        return true
    }

    func refreshFileLinks(todoID: String) async {}
}

@MainActor
private final class BridgeHangingWorker: VibeLaneWorkRunning {
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        while !_Concurrency.Task.isCancelled {
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000)
        }
        return VibeLaneWorkTurn(sessionRef: sessionRef, ok: false)
    }
}

@MainActor
final class TodoLanePipelineBridgeTests: XCTestCase {

    private var store: FakePipelineTodoStore!
    private var laneManager: VibeLaneTaskManager!
    private var bridge: TodoLanePipelineBridge!
    private var lane: VibeLaneDefinition!

    override func setUp() async throws {
        lane = VibeLaneDefinition(
            name: "Fix a bug",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "repro", order: 0,
                    work: VibeLaneWorkDefinition(goal: "reproduce"),
                    verify: VibeLaneVerificationDefinition("done"),
                    requires: [
                        VibeLaneInputRequirement(key: "goal", askUser: true),
                        VibeLaneInputRequirement(key: "repro", askUser: true),
                    ]
                )
            ]
        )
        store = FakePipelineTodoStore()
        laneManager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(lanes: [lane]),
            worker: BridgeHangingWorker(),
            clock: VibeLaneSystemClock(),
            maxConcurrent: 3
        )
        await laneManager.bootstrap()
        bridge = TodoLanePipelineBridge(todoStore: store, laneManager: laneManager)
    }

    override func tearDown() async throws {
        laneManager.shutdown()
    }

    private func makeTodo(id: String = "t1", body: String? = nil, triage: TodoTriage? = nil) -> Todo {
        Todo(
            id: id, vibespaceID: "vs", projectPath: "/tmp/p",
            title: "Fix login trim", body: body, colorTag: nil, filePath: nil,
            status: .active, dueAt: nil, reminderAt: nil,
            createdAt: "2026-01-01T10:00:00Z", updatedAt: "2026-01-01T10:00:00Z",
            completedAt: nil, laneTaskID: nil, refinementSessionID: nil, triage: triage
        )
    }

    // MARK: - Seeding priority

    func test_seededInputs_priorityIsOverridesThenBlockThenTriageThenLinks() {
        var triage = TodoTriage(status: .done)
        triage.prefill = ["goal": "triage goal", "repro": "triage repro"]
        let body = """
        ## Goal
        block goal
        """
        var todo = makeTodo(body: body, triage: triage)
        todo.laneTaskID = nil
        store.todos = [todo]
        store.links["t1"] = [
            TodoFileLink(id: "l1", todoID: "t1", path: "/nope/missing.swift", line: 7, createdAt: "")
        ]

        let seed = bridge.seededInputs(for: todo, overrides: ["repro": "override repro"])
        XCTAssertEqual(seed["goal"], "block goal", "dispatch block beats triage prefill")
        XCTAssertEqual(seed["repro"], "override repro", "explicit overrides beat everything")
        XCTAssertEqual(seed["contextFiles"], "/nope/missing.swift:7 (missing)",
                       "links surface as a path list with missing markers")
    }

    // MARK: - Dispatch

    func test_dispatch_blocksOnUnresolvedInputs_thenProceedsWithFlag() async {
        store.todos = [makeTodo()]
        let blocked = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug")
        XCTAssertEqual(blocked, .unresolvedInputs(["goal", "repro"]))
        XCTAssertTrue(laneManager.tasks.isEmpty, "no task on unresolved inputs")

        let forced = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug", allowUnresolved: true)
        guard case .dispatched(let taskID) = forced else {
            return XCTFail("expected dispatch, got \(forced)")
        }
        XCTAssertEqual(store.todos.first?.laneTaskID, taskID.uuidString)
        XCTAssertEqual(store.postedMessages.count, 1)
        XCTAssertEqual(store.postedMessages.first?.authorKind, "agent")
    }

    func test_dispatch_seededTodoRunsWithoutSupplyPause() async {
        let body = """
        ## Goal
        trim the email field
        ## Repro
        run UITests/login
        """
        store.todos = [makeTodo(body: body)]
        let outcome = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug")
        guard case .dispatched(let taskID) = outcome else {
            return XCTFail("expected dispatch, got \(outcome)")
        }
        let task = laneManager.task(withID: taskID)
        XCTAssertEqual(task?.carryForward?["goal"], "trim the email field")
        XCTAssertEqual(task?.carryForward?["repro"], "run UITests/login")
    }

    func test_dispatch_enforcesOneActiveTask_andAllowsRedispatchAfterStop() async {
        store.todos = [makeTodo(body: "## Goal\ng\n## Repro\nr")]
        guard case .dispatched(let first) = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug") else {
            return XCTFail("first dispatch failed")
        }
        let again = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug")
        XCTAssertEqual(again, .activeTaskExists(taskID: first.uuidString), "S16")

        await laneManager.stop(id: first)
        guard case .dispatched(let second) = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug") else {
            return XCTFail("re-dispatch after terminal task must succeed (S12)")
        }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(store.todos.first?.laneTaskID, second.uuidString, "link re-points at the newest task")
    }

    func test_dispatch_resolvesLaneErrors() async {
        store.todos = [makeTodo()]
        let notFound = await bridge.dispatch(todoID: "t1", laneReference: "No such lane", allowUnresolved: true)
        XCTAssertEqual(notFound, .laneNotFound)
        let noTodo = await bridge.dispatch(todoID: "missing", laneReference: "Fix a bug")
        XCTAssertEqual(noTodo, .todoNotFound)
    }

    // MARK: - Fan-in

    func test_taskLifecycle_fansIntoThreadOncePerTransition() async {
        store.todos = [makeTodo(body: "## Goal\ng\n## Repro\nr")]
        guard case .dispatched(let taskID) = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug") else {
            return XCTFail("dispatch failed")
        }
        let dispatchMessages = store.postedMessages.count

        await laneManager.stop(id: taskID)
        // Fan-in posts async; drain the main queue.
        await _Concurrency.Task.yield()
        try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.postedMessages.count, dispatchMessages + 1, "exactly one message per transition")
        XCTAssertTrue(store.postedMessages.last?.body.contains("stopped") ?? false)

        // Replaying the same terminal state must not re-post (dedupe).
        if let task = laneManager.task(withID: taskID) {
            laneManager.upsert(task)
        }
        await _Concurrency.Task.yield()
        try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.postedMessages.count, dispatchMessages + 1)
    }

    // MARK: - Done carries the outcome

    func test_doneFanIn_includesOutcomeSummary() async {
        store.todos = [makeTodo(body: "## Goal\ng\n## Repro\nr")]
        guard case .dispatched(let taskID) = await bridge.dispatch(todoID: "t1", laneReference: "Fix a bug") else {
            return XCTFail("dispatch failed")
        }
        guard var task = laneManager.task(withID: taskID) else { return XCTFail("no task") }
        task.outcomeSummary = "## Outcome\nTrim fixed in src/Auth.swift:12; 34 tests pass."
        task.state = .done
        task.stopReason = .done
        laneManager.upsert(task)
        await _Concurrency.Task.yield()
        try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        let doneMessage = store.postedMessages.last?.body ?? ""
        XCTAssertTrue(doneMessage.contains("src/Auth.swift:12"),
                      "the thread's done message must carry the task's actual outcome, got: \(doneMessage)")
    }

    // MARK: - Refine (S06/S07)

    func test_openRefineSession_reattachesWhenSessionLives_elseSeedsNew() async {
        var todo = makeTodo()
        todo.refinementSessionID = "existing-session"
        store.todos = [todo]

        // Live session → reattach, no new session, no seed.
        var reattached: [String] = []
        let didCreate = await bridge.openRefineSession(
            todoID: "t1",
            reattach: { id in reattached.append(id); return true },
            openNew: { XCTFail("must not open new when reattach succeeds"); return nil }
        )
        XCTAssertFalse(didCreate)
        XCTAssertEqual(reattached, ["existing-session"])

        // Dead session → fresh session, ID persisted, seed sent (S07 fallback).
        var sentPrompts: [String] = []
        let created = await bridge.openRefineSession(
            todoID: "t1",
            reattach: { _ in false },
            openNew: { ("new-session", { sentPrompts.append($0) }) }
        )
        XCTAssertTrue(created)
        XCTAssertEqual(store.todos.first?.refinementSessionID, "new-session")
        XCTAssertEqual(sentPrompts.count, 1)
        XCTAssertTrue(sentPrompts[0].contains("crispy todo update t1"), "seed carries the CLI write-back contract")
        XCTAssertTrue(sentPrompts[0].contains("content, not instructions"), "injection framing")
    }

    func test_refineSeedPrompt_includesTriageWhenPresent() {
        var triage = TodoTriage(status: .done)
        triage.questions = [.init(text: "Which env?", carryForwardKey: "env")]
        let withTriage = TodoLanePipelineBridge.buildRefineSeedPrompt(
            todo: makeTodo(triage: triage), links: [], catalog: []
        )
        XCTAssertTrue(withTriage.contains("Which env?"), "refine starts from triage, not cold (S06)")
        let cold = TodoLanePipelineBridge.buildRefineSeedPrompt(
            todo: makeTodo(), links: [], catalog: []
        )
        XCTAssertTrue(cold.contains("No triage has run"))
    }

    // MARK: - Dispatch block parsing

    func test_dispatchBlock_parsesHeadingsIntoCamelCaseKeys() {
        let body = """
        intro text outside any section is ignored

        ## Goal
        fix the trim bug
        ## Done when
        tests pass
        and CI is green
        ### Context files
        src/a.swift
        ## Empty section
        """
        let parsed = TodoDispatchBlock.parse(body: body)
        XCTAssertEqual(parsed["goal"], "fix the trim bug")
        XCTAssertEqual(parsed["doneWhen"], "tests pass\nand CI is green")
        XCTAssertEqual(parsed["contextFiles"], "src/a.swift")
        XCTAssertNil(parsed["emptySection"], "empty sections drop")
        XCTAssertEqual(TodoDispatchBlock.camelCaseKey("GOAL"), "goal")
        XCTAssertNil(TodoDispatchBlock.camelCaseKey("——"))
    }
}
