import Foundation
import XCTest
@testable import CrispyVibes

// F059 — handler-level tests for the `lane.*` / `lane.task.*` CLI commands.
// The router is wired to a real VibeLaneTaskManager over the in-memory store
// (the same doubles the F059 engine/manager tests use), so every command
// exercises the exact code path the UI uses. The worker hangs forever, keeping
// running tasks deterministic; the Supply test drives a real engine pause.

@MainActor
private final class LaneCLIHangingWorker: VibeLaneWorkRunning {
    func work(prompt: String, projectPath: String, sessionRef: String?, agentID: String?) async -> VibeLaneWorkTurn {
        while !_Concurrency.Task.isCancelled {
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000)
        }
        return VibeLaneWorkTurn(sessionRef: sessionRef, ok: false)
    }
}

@MainActor
final class CLICommandRouterLaneHandlersTests: XCTestCase {

    private var container: AppContainer!
    private var router: CLICommandRouter!
    private var manager: VibeLaneTaskManager!
    private var tempProject: URL!
    private var lane: VibeLaneDefinition!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        tempProject = try makeTempDirectory(prefix: "crispyvibes-cli-lanes")
        lane = VibeLaneDefinition(
            name: "Fix a bug",
            detail: "Repro then patch",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "repro", order: 0,
                    goal: "reproduce the bug",
                    verify: VibeLaneVerificationDefinition("repro exists"),
                    produces: ["repro"]
                ),
                VibeLaneCheckpoint(
                    key: "patch", order: 1,
                    goal: "patch it",
                    verify: VibeLaneVerificationDefinition("tests pass"),
                    requires: ["repro"]
                ),
            ]
        )
        manager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(lanes: [lane]),
            worker: LaneCLIHangingWorker(),
            clock: VibeLaneSystemClock(),
            maxConcurrent: 3
        )
        manager.bootstrap()
        router = CLICommandRouter(shelfStore: container.shelfStore)
        router.attachVibeLaneTaskManager(manager)
    }

    override func tearDownWithError() throws {
        manager.shutdown()
        manager = nil
        router = nil
        container = nil
        if let tempProject {
            try? FileManager.default.removeItem(at: tempProject)
        }
    }

    // MARK: - Helpers

    private func request(
        _ method: String,
        params: [String: CLIJSONValue] = [:],
        projectPathEnv: String? = nil
    ) -> CLIRequest {
        CLIRequest(
            id: UUID().uuidString,
            method: method,
            params: params,
            _env: CLIChannelClientEnv(context: nil, vibespace: nil, project_path: projectPathEnv)
        )
    }

    private func ok(_ response: CLIResponse, file: StaticString = #filePath, line: UInt = #line) throws -> [String: CLIJSONValue] {
        guard case let .ok(_, result) = response else {
            XCTFail("expected ok, got \(response)", file: file, line: line)
            throw XCTSkip("unreachable")
        }
        return result
    }

    private func errorCode(_ response: CLIResponse) -> String? {
        guard case let .error(_, code, _) = response else { return nil }
        return code
    }

    /// Poll until the manager's only task reaches `state` (engine transitions are async).
    private func waitForTaskState(_ state: VibeLaneTaskState, timeout: TimeInterval = 5) async -> VibeLaneTask? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let task = manager.tasks.first, task.state == state { return task }
            try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        return manager.tasks.first?.state == state ? manager.tasks.first : nil
    }

    // MARK: - Availability

    func test_commandsReportNotConnectedWithoutManager() async {
        let bare = CLICommandRouter(shelfStore: container.shelfStore)
        let response = await bare.dispatch(request("lane.list"))
        XCTAssertEqual(errorCode(response), CLIErrorCode.notConnected)
    }

    // MARK: - lane.list / lane.show

    func test_laneListAndShow() async throws {
        let list = try ok(await router.dispatch(request("lane.list")))
        let lanes = try XCTUnwrap(list["lanes"]?.arrayValue)
        XCTAssertEqual(lanes.count, 1)
        XCTAssertEqual(lanes[0].objectValue?["name"]?.stringValue, "Fix a bug")
        XCTAssertEqual(lanes[0].objectValue?["checkpointCount"]?.intValue, 2)

        let show = try ok(await router.dispatch(request("lane.show", params: ["lane": .string("fix A BUG")])))
        let detail = try XCTUnwrap(show["lane"]?.objectValue)
        XCTAssertEqual(detail["id"]?.stringValue, lane.id.uuidString)
        let checkpoints = try XCTUnwrap(detail["checkpoints"]?.arrayValue)
        XCTAssertEqual(checkpoints.map { $0.objectValue?["key"]?.stringValue }, ["repro", "patch"])
        XCTAssertEqual(
            checkpoints[1].objectValue?["requires"]?.arrayValue?.first?.objectValue?["key"]?.stringValue,
            "repro"
        )
    }

    func test_laneShowUnknownIsInvalidParams() async {
        let response = await router.dispatch(request("lane.show", params: ["lane": .string("nope")]))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    // MARK: - lane.create / update / delete

    func test_laneCreateWithCheckpoints() async throws {
        let checkpoints: CLIJSONValue = .array([
            .object([
                "key": .string("Ship It!"),
                "order": .int(0),
                "work": .object(["goal": .string("open a PR"), "instructions": .string(""), "skills": .array([])]),
                "verify": .object(["definition": .string("PR exists and CI is green")]),
            ])
        ])
        let result = try ok(await router.dispatch(request("lane.create", params: [
            "name": .string("Ship"),
            "description": .string("Branch and PR"),
            "checkpoints": checkpoints,
        ])))
        let created = try XCTUnwrap(result["lane"]?.objectValue)
        XCTAssertEqual(created["name"]?.stringValue, "Ship")
        XCTAssertEqual(created["description"]?.stringValue, "Branch and PR")
        // Keys are normalized exactly like the UI editor save path.
        XCTAssertEqual(
            created["checkpoints"]?.arrayValue?.first?.objectValue?["key"]?.stringValue,
            "ship-it"
        )
        XCTAssertEqual(manager.lanes.count, 2)
    }

    func test_laneCreateRejectsMalformedCheckpoints() async {
        let response = await router.dispatch(request("lane.create", params: [
            "name": .string("Broken"),
            "checkpoints": .array([.object(["key": .string("x")])]), // missing work/verify
        ]))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
        XCTAssertEqual(manager.lanes.count, 1, "no lane is left behind on invalid checkpoints")
    }

    func test_laneUpdateBumpsVersion() async throws {
        let result = try ok(await router.dispatch(request("lane.update", params: [
            "lane": .string(lane.id.uuidString),
            "name": .string("Fix a bug v2"),
            "steerLimit": .int(3),
        ])))
        let updated = try XCTUnwrap(result["lane"]?.objectValue)
        XCTAssertEqual(updated["name"]?.stringValue, "Fix a bug v2")
        XCTAssertEqual(updated["steerLimit"]?.intValue, 3)
        XCTAssertEqual(updated["version"]?.intValue, lane.version + 1)
    }

    func test_laneUpdateWithNothingToChangeIsInvalidParams() async {
        let response = await router.dispatch(request("lane.update", params: [
            "lane": .string(lane.id.uuidString),
        ]))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    func test_laneDelete() async throws {
        let result = try ok(await router.dispatch(request("lane.delete", params: [
            "lane": .string("Fix a bug"),
        ])))
        XCTAssertEqual(result["deleted"]?.boolValue, true)
        XCTAssertTrue(manager.lanes.isEmpty)
    }

    // MARK: - lane.task.create

    func test_taskCreateUsesEnvProjectFallback() async throws {
        let result = try ok(await router.dispatch(request(
            "lane.task.create",
            params: ["lane": .string("Fix a bug"), "input": .string("Fix the flaky payment test")],
            projectPathEnv: tempProject.path
        )))
        let task = try XCTUnwrap(result["task"]?.objectValue)
        XCTAssertEqual(task["title"]?.stringValue, "Fix the flaky payment test")
        XCTAssertEqual(task["state"]?.stringValue, "running")
        XCTAssertEqual(task["currentCheckpoint"]?.stringValue, "repro")
        XCTAssertEqual(task["projectPath"]?.stringValue, tempProject.standardizedFileURL.path)
        XCTAssertEqual(manager.tasks.count, 1)
    }

    func test_taskCreateWithoutAnyProjectIsInvalidParams() async {
        let response = await router.dispatch(request("lane.task.create", params: [
            "lane": .string("Fix a bug"),
            "input": .string("do it"),
        ]))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_taskCreateSeedsInitialCarryForward() async throws {
        let result = try ok(await router.dispatch(request("lane.task.create", params: [
            "lane": .string("Fix a bug"),
            "input": .string("seeded run"),
            "project": .string(tempProject.path),
            "inputs": .object(["repro": .string("run UITests/login")]),
        ])))
        _ = try XCTUnwrap(result["task"]?.objectValue)
        XCTAssertEqual(manager.tasks.first?.carryForward?["repro"], "run UITests/login")
    }

    // MARK: - lane.task.list / show / stop / delete

    func test_taskListCountsAndStateFilter() async throws {
        _ = manager.createTask(laneID: lane.id, title: "one", projectPath: tempProject.path)
        let all = try ok(await router.dispatch(request("lane.task.list")))
        XCTAssertEqual(all["tasks"]?.arrayValue?.count, 1)
        XCTAssertEqual(all["counts"]?.objectValue?["running"]?.intValue, 1)

        let done = try ok(await router.dispatch(request("lane.task.list", params: ["state": .string("done")])))
        XCTAssertEqual(done["tasks"]?.arrayValue?.count, 0)

        let bad = await router.dispatch(request("lane.task.list", params: ["state": .string("paused")]))
        XCTAssertEqual(errorCode(bad), CLIErrorCode.invalidParams)
    }

    func test_taskStopThenStopAgainIsInvalidParams() async throws {
        let task = try XCTUnwrap(manager.createTask(laneID: lane.id, title: "stop me", projectPath: tempProject.path))
        let result = try ok(await router.dispatch(request("lane.task.stop", params: ["id": .string(task.id.uuidString)])))
        XCTAssertEqual(result["task"]?.objectValue?["state"]?.stringValue, "stopped")
        XCTAssertEqual(result["task"]?.objectValue?["stopReason"]?.stringValue, "stoppedByUser")

        let again = await router.dispatch(request("lane.task.stop", params: ["id": .string(task.id.uuidString)]))
        XCTAssertEqual(errorCode(again), CLIErrorCode.invalidParams)
    }

    func test_taskShowAndDelete() async throws {
        let task = try XCTUnwrap(manager.createTask(laneID: lane.id, title: "inspect", projectPath: tempProject.path))
        let shown = try ok(await router.dispatch(request("lane.task.show", params: ["id": .string(task.id.uuidString)])))
        let detail = try XCTUnwrap(shown["task"]?.objectValue)
        XCTAssertEqual(detail["lane"]?.stringValue, "Fix a bug")
        XCTAssertNotNil(detail["checkpointRuns"]?.arrayValue)

        let deleted = try ok(await router.dispatch(request("lane.task.delete", params: ["id": .string(task.id.uuidString)])))
        XCTAssertEqual(deleted["deleted"]?.boolValue, true)
        XCTAssertTrue(manager.tasks.isEmpty)

        let gone = await router.dispatch(request("lane.task.show", params: ["id": .string(task.id.uuidString)]))
        XCTAssertEqual(errorCode(gone), CLIErrorCode.invalidParams)
    }

    // MARK: - lane.task.answer (Supply, F059-R07)

    func test_answerSupplyResumesTask() async throws {
        // A lane whose first checkpoint needs an ask-user key pauses as
        // needsInput with a Supply request before any worker turn (F059-R05).
        let askLane = VibeLaneDefinition(
            name: "Deploy",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "deploy", order: 0,
                    work: VibeLaneWorkDefinition(goal: "deploy it"),
                    verify: VibeLaneVerificationDefinition("deployed"),
                    requires: [VibeLaneInputRequirement(key: "api_base", askUser: true)]
                )
            ]
        )
        _ = manager.updateLane(askLane) // saves + publishes the new lane
        _ = manager.createTask(laneID: askLane.id, title: "ship", projectPath: tempProject.path)
        let paused = await waitForTaskState(.needsInput)
        let task = try XCTUnwrap(paused, "task should pause for Supply")
        XCTAssertEqual(task.openInputRequest?.kind, .supply)

        // Wrong shape for the open request is refused with guidance.
        let wrong = await router.dispatch(request("lane.task.answer", params: [
            "id": .string(task.id.uuidString),
            "guidance": .string("not a steer"),
        ]))
        XCTAssertEqual(errorCode(wrong), CLIErrorCode.invalidParams)

        let result = try ok(await router.dispatch(request("lane.task.answer", params: [
            "id": .string(task.id.uuidString),
            "values": .object(["api_base": .string("https://api.example.com")]),
        ])))
        XCTAssertEqual(result["task"]?.objectValue?["state"]?.stringValue, "running")
        XCTAssertEqual(manager.task(withID: task.id)?.carryForward?["api_base"], "https://api.example.com")
    }

    func test_answerWithoutOpenRequestIsInvalidParams() async throws {
        let task = try XCTUnwrap(manager.createTask(laneID: lane.id, title: "busy", projectPath: tempProject.path))
        let response = await router.dispatch(request("lane.task.answer", params: [
            "id": .string(task.id.uuidString),
            "guidance": .string("hurry up"),
        ]))
        XCTAssertEqual(errorCode(response), CLIErrorCode.invalidParams)
    }

    // MARK: - help registration

    func test_helpDescribesLaneCommands() async throws {
        let result = try ok(await router.dispatch(request("help", params: ["method": .string("lane.task.create")])))
        let commands = try XCTUnwrap(result["commands"]?.arrayValue)
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.objectValue?["method"]?.stringValue, "lane.task.create")
    }
}
