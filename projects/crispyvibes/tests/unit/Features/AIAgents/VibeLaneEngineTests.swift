import Foundation
import XCTest
@testable import CrispyVibes

// F059 — execution engine tests. Deterministic: fake worker, fake reviewer,
// fake clock. No shell, no real agent. Each checkpoint is Work → Verification,
// verified by a single independent reviewer of the outcome.

// MARK: - Fakes

@MainActor
private final class FakeWorker: VibeLaneWorkRunning {
    var ok = true
    var note: String? = nil
    var response: String? = nil
    var responses: [String] = []
    var beforeReturn: (() -> Void)?
    var reportedEngine: VibeLaneEngineSnapshot?
    private(set) var calls = 0
    private(set) var prompts: [String] = []
    private(set) var engines: [VibeLaneEngineConfiguration] = []
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        calls += 1
        prompts.append(prompt)
        engines.append(engine)
        beforeReturn?()
        let text = responses.isEmpty ? response : responses.removeFirst()
        return VibeLaneWorkTurn(
            sessionRef: sessionRef ?? "session-1",
            ok: ok,
            note: note,
            responseText: text,
            engine: reportedEngine
        )
    }
}

@MainActor
private final class FakeReviewer: VibeLaneReviewing {
    var outcomes: [VibeLaneReviewOutcome]
    var beforeReturn: (() -> Void)?
    private(set) var calls = 0
    private(set) var engines: [VibeLaneEngineConfiguration] = []
    private(set) var requests: [VibeLaneReviewRequest] = []
    init(_ outcomes: [VibeLaneReviewOutcome]) { self.outcomes = outcomes }
    func review(_ request: VibeLaneReviewRequest, sessionRef: String?) async -> VibeLaneReviewOutcome {
        let outcome = calls < outcomes.count ? outcomes[calls] : (outcomes.last ?? .init(passed: true))
        calls += 1
        engines.append(request.engine)
        requests.append(request)
        beforeReturn?()
        return outcome
    }
}

private final class FakeClock: VibeLaneClock, @unchecked Sendable {
    private var current: TimeInterval
    private let step: TimeInterval
    init(step: TimeInterval = 0) { self.current = 0; self.step = step }
    var now: Date {
        let value = current
        current += step
        return Date(timeIntervalSince1970: value)
    }
}

private final class ManualClock: VibeLaneClock, @unchecked Sendable {
    var value: Date
    init(_ value: Date = Date(timeIntervalSince1970: 0)) {
        self.value = value
    }
    var now: Date { value }
    func advance(_ seconds: TimeInterval) {
        value = value.addingTimeInterval(seconds)
    }
}

private func pass(_ summary: String = "ok") -> VibeLaneReviewOutcome { .init(passed: true, summary: summary) }
private func fail(_ feedback: String) -> VibeLaneReviewOutcome { .init(passed: false, summary: "no", feedback: feedback) }

// MARK: - Helpers

@MainActor
private func makeLane(checkpoints: [VibeLaneCheckpoint], steerLimit: Int = 1) -> VibeLaneDefinition {
    VibeLaneDefinition(name: "Test lane", steerLimit: steerLimit, checkpoints: checkpoints)
}

@MainActor
private func cp(
    _ key: String,
    order: Int,
    maxAttempts: Int = 3,
    timeout: Int = 1800,
    onExhausted: VibeLaneBoundBehavior = .stop
) -> VibeLaneCheckpoint {
    VibeLaneCheckpoint(
        key: key, order: order, goal: "do \(key)",
        verify: VibeLaneVerificationDefinition("done when \(key) is complete"),
        bounds: VibeLaneBounds(maxAttempts: maxAttempts, timeoutSeconds: timeout, onExhausted: onExhausted)
    )
}

@MainActor
private func makeTask(
    lane: VibeLaneDefinition,
    title: String = "t",
    projectPath: String = "/tmp/p"
) -> VibeLaneTask {
    let first = lane.firstCheckpoint!
    return VibeLaneTask(
        projectPath: projectPath, title: title,
        laneID: lane.id, laneVersion: lane.version,
        currentCheckpointKey: first.key
    )
}

// MARK: - Tests

@MainActor
final class VibeLaneEngineTests: XCTestCase {

    /// S01: a two-checkpoint lane runs to done, advancing on each reviewer pass.
    func test_twoCheckpointLane_runsToDone() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0), cp("b", order: 1)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.stopReason, .done)
        XCTAssertEqual(result.checkpointRuns.count, 2)
        XCTAssertTrue(result.checkpointRuns.allSatisfy { $0.status == .passed })
    }

    /// S02: a checkpoint self-corrects — reviewer fails then passes.
    func test_checkpointSelfCorrects() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 5)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([fail("fix it"), pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.checkpointRuns.first?.attempts.count, 2)
    }

    /// R04: a reviewer rejection feeds its feedback into the worker's next prompt.
    func test_reviewerRejectionFeedsBack() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 3)])
        let worker = FakeWorker()
        let reviewer = FakeReviewer([fail("You changed the wrong file."), pass()])
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: reviewer, clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(reviewer.calls, 2)
        XCTAssertEqual(result.checkpointRuns.first?.attempts.count, 2)
        XCTAssertEqual(result.checkpointRuns.first?.attempts.first?.result?.passed, false)
        XCTAssertTrue(worker.prompts.contains { $0.contains("You changed the wrong file") })
    }

    /// S04: attempt cap trips with `verificationFailed` when the checkpoint says to stop.
    func test_attemptCapTrips_whenBoundStops() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 3)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([fail("nope")]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .verificationFailed)
        XCTAssertEqual(result.checkpointRuns.first?.attempts.count, 3)
    }

    /// S01: hand-off carries the task to the next checkpoint, then to done.
    func test_handOff_advancesCurrentCheckpoint() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0), cp("b", order: 1)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.currentCheckpointKey, "b")
        XCTAssertEqual(result.run(forKey: "a")?.status, .passed)
        XCTAssertEqual(result.run(forKey: "b")?.status, .passed)
    }

    /// S04: time limit trips with `timeout` when the checkpoint says to stop.
    func test_timeoutTrips_whenBoundStops() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 100, timeout: 1)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([fail("no")]), clock: FakeClock(step: 1000))
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .timeout)
    }

    /// Timeout is enforced before accepting a long-running successful attempt.
    func test_timeoutAfterWorkerPreventsPass() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 100, timeout: 1)])
        let clock = ManualClock()
        let worker = FakeWorker()
        worker.beforeReturn = { clock.advance(2) }
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: clock)
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .timeout)
    }

    /// A completed PASS verification stands even if the time bound elapsed while
    /// the reviewer was verifying — the bound did not run out "first" (R06).
    func test_passStandsWhenTimeoutElapsesDuringVerification() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 100, timeout: 1)])
        let clock = ManualClock()
        let reviewer = FakeReviewer([pass()])
        reviewer.beforeReturn = { clock.advance(10) }
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: reviewer, clock: clock)
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done, "a verified pass must not be discarded by a timeout during verification")
    }

    /// A transport/tool failure stops the task with `error`, and the failure
    /// detail (why) is recorded in the activity log so the user can see it.
    func test_workerFailure_stopsError() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        let worker = FakeWorker(); worker.ok = false; worker.note = "connect failed: boom"
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .error)
        let errorEntry = (result.activityLog ?? []).first { $0.kind == .error && ($0.detail ?? "").contains("connect failed: boom") }
        XCTAssertNotNil(errorEntry, "the worker failure detail must be surfaced in the activity log")
    }

    /// R04: the engine records the reviewer's result, never worker text.
    func test_attemptRecordsVerificationResult() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 2)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([fail("no")]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.checkpointRuns.first?.attempts.first?.result?.passed, false)
    }

    /// Skill paths are referenced (by path) in the worker's goal prompt so the
    /// worker reads them on demand — they are NOT inlined.
    func test_skillPathsReferencedInPrompt() async throws {
        let checkpoint = VibeLaneCheckpoint(
            key: "a", order: 0,
            work: VibeLaneWorkDefinition(goal: "do a", instructions: "", skills: [".agent/skills/tdd"]),
            verify: VibeLaneVerificationDefinition("done"),
            bounds: VibeLaneBounds(maxAttempts: 3, timeoutSeconds: 1800)
        )
        let lane = makeLane(checkpoints: [checkpoint])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-path-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try createSkillPackage(
            at: projectRoot.appendingPathComponent(".agent/skills/tdd", isDirectory: true)
        )

        let result = await engine.run(
            makeTask(lane: lane, projectPath: projectRoot.path)
        )
        XCTAssertEqual(result.state, .done)
        XCTAssertTrue(worker.prompts.first?.contains(".agent/skills/tdd") == true)
        XCTAssertTrue(worker.prompts.first?.contains("SKILL.md") == true)
    }

    func test_reviewSkillsReachOnlyReviewerWithResolvedPaths() async throws {
        let checkpoint = VibeLaneCheckpoint(
            key: "a",
            order: 0,
            work: VibeLaneWorkDefinition(
                goal: "do a",
                skills: ["tdd"]
            ),
            verify: VibeLaneVerificationDefinition(
                "done",
                reviewSkills: ["code-review"]
            )
        )
        let lane = makeLane(checkpoints: [checkpoint])
        let worker = FakeWorker()
        let reviewer = FakeReviewer([pass()])
        let skillsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-skill-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: skillsRoot) }
        try createSkillPackage(at: skillsRoot.appendingPathComponent("tdd", isDirectory: true))
        try createSkillPackage(
            at: skillsRoot.appendingPathComponent("code-review", isDirectory: true)
        )
        let engine = VibeLaneEngine(
            lane: lane,
            worker: worker,
            reviewer: reviewer,
            skillsRoot: skillsRoot,
            clock: FakeClock()
        )

        let result = await engine.run(makeTask(lane: lane))

        XCTAssertEqual(result.state, .done)
        XCTAssertTrue(worker.prompts.first?.contains("\(skillsRoot.path)/tdd") == true)
        XCTAssertTrue(
            worker.prompts.allSatisfy {
                !$0.contains("\(skillsRoot.path)/code-review")
            }
        )

        let request = try XCTUnwrap(reviewer.requests.first)
        XCTAssertEqual(request.reviewSkillsText, "- \(skillsRoot.path)/code-review")
        let prompt = VibeLaneACPAgentRunner.buildReviewPrompt(
            request: request,
            definition: checkpoint.verify.definition
        )
        XCTAssertTrue(prompt.contains("\(skillsRoot.path)/code-review"))
        XCTAssertTrue(prompt.contains("SKILL.md"))
        XCTAssertTrue(prompt.contains("only to inspect, test, and verify"))
    }

    func test_missingManagedSkillStopsBeforeWorkerRuns() async {
        let checkpoint = VibeLaneCheckpoint(
            key: "a",
            order: 0,
            work: VibeLaneWorkDefinition(goal: "do a", skills: ["missing-skill"]),
            verify: VibeLaneVerificationDefinition("done")
        )
        let lane = makeLane(checkpoints: [checkpoint])
        let worker = FakeWorker()
        let skillsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-skills-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: skillsRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: skillsRoot) }
        let engine = VibeLaneEngine(
            lane: lane,
            worker: worker,
            reviewer: FakeReviewer([pass()]),
            skillsRoot: skillsRoot,
            clock: FakeClock()
        )

        let result = await engine.run(makeTask(lane: lane))

        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .error)
        XCTAssertTrue(worker.prompts.isEmpty)
        XCTAssertTrue(
            (result.activityLog ?? []).contains {
                $0.detail?.contains("missing-skill") == true
            }
        )
    }

    func test_skillLibraryInstallsReadableSkillFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("crispy-vibe-lane-skills-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        VibeLaneSkillLibrary.install(into: root)

        XCTAssertFalse(VibeLaneSkillLibrary.starterNames.isEmpty)
        for skill in VibeLaneSkillLibrary.starters {
            let file = root
                .appendingPathComponent(skill.name, isDirectory: true)
                .appendingPathComponent("SKILL.md")
            let content = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(content.contains("name: \(skill.name)"))
            XCTAssertTrue(content.contains("description: \(skill.description)"))
            XCTAssertTrue(content.contains(skill.body))
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root
                        .appendingPathComponent(skill.name)
                        .appendingPathComponent(VibeLaneSkillStore.metadataFileName)
                        .path
                )
            )
            for resource in skill.resources.keys {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: root
                            .appendingPathComponent(skill.name)
                            .appendingPathComponent(resource)
                            .path
                    )
                )
            }
        }
    }

    private func createSkillPackage(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try """
        ---
        name: test-skill
        description: Test fixture.
        ---

        # Test Skill
        """.write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// On hand-off the worker writes a handoff that becomes the next checkpoint's
    /// inherited context.
    func test_handoffPassedToNextCheckpoint() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0), cp("b", order: 1)])
        let worker = FakeWorker()
        worker.response = "HANDOFF-NOTE-XYZ"
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.run(forKey: "a")?.summary, "HANDOFF-NOTE-XYZ")
        XCTAssertTrue(worker.prompts.contains { $0.contains("Inherited handoff") && $0.contains("HANDOFF-NOTE-XYZ") })
    }

    /// Regression: the user's task (not just the checkpoint goal) MUST reach the worker prompt.
    func test_goalPromptIncludesTaskTitle() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        let worker = FakeWorker()
        let task = makeTask(lane: lane, title: "Add a Van Zandt button to the web app")
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        _ = await engine.run(task)
        XCTAssertTrue(worker.prompts.first?.contains("Add a Van Zandt button to the web app") == true,
                      "the worker's first prompt must include the user's task")
    }

    /// Missing ask-user input pauses before running and opens a Supply request.
    func test_missingAskUserInput_pausesWithSupplyRequest() async {
        let step = VibeLaneCheckpoint(
            key: "a",
            order: 0,
            work: VibeLaneWorkDefinition(goal: "g"),
            verify: VibeLaneVerificationDefinition("done"),
            requires: [VibeLaneInputRequirement(key: "dataset", askUser: true, prompt: "Which dataset?")]
        )
        let lane = makeLane(checkpoints: [step])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .needsInput)
        XCTAssertNil(result.stopReason)
        XCTAssertEqual(result.openInputRequest?.kind, .supply)
        XCTAssertEqual(result.openInputRequest?.missingKeys, ["dataset"])
        XCTAssertEqual(result.run(forKey: "a")?.status, .needsInput)
        XCTAssertEqual(worker.calls, 0, "the worker must not run when a required input is missing")
    }

    /// A non-user-suppliable missing input means the lane is mis-authored.
    func test_missingNonAskUserInput_stopsMisAuthoredLane() async {
        let step = VibeLaneCheckpoint(key: "a", order: 0, goal: "g", verify: VibeLaneVerificationDefinition("done"), requires: ["dataset"])
        let lane = makeLane(checkpoints: [step])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .misAuthoredLane)
        XCTAssertNil(result.openInputRequest)
        XCTAssertEqual(result.run(forKey: "a")?.status, .stopped)
        XCTAssertEqual(worker.calls, 0, "the worker must not run when the lane cannot supply a required input")
    }

    /// A missing key that an EARLIER checkpoint declared it would produce is a
    /// worker emission failure (`missingInput`), not an authoring error.
    func test_missingProducedInput_stopsMissingInput_notMisAuthored() async {
        let a = VibeLaneCheckpoint(key: "a", order: 0, goal: "g", verify: VibeLaneVerificationDefinition("done"), produces: ["repro"])
        let b = VibeLaneCheckpoint(key: "b", order: 1, goal: "g2", verify: VibeLaneVerificationDefinition("done"), requires: ["repro"])
        let lane = makeLane(checkpoints: [a, b])
        let worker = FakeWorker()
        worker.response = "handoff without any OUTPUT line"
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .missingInput, "the lane was authored correctly; the worker failed to emit")
        XCTAssertEqual(result.run(forKey: "b")?.stopReason, .missingInput)
    }

    /// When a checkpoint is missing both an ask-user key and a fatal key, the
    /// task stops without asking — a Supply answer would be wasted effort.
    func test_fatalMissingInputTakesPrecedenceOverSupply() async {
        let step = VibeLaneCheckpoint(
            key: "a",
            order: 0,
            work: VibeLaneWorkDefinition(goal: "g"),
            verify: VibeLaneVerificationDefinition("done"),
            requires: [
                VibeLaneInputRequirement(key: "api_base", askUser: true),
                VibeLaneInputRequirement(key: "dataset", askUser: false),
            ]
        )
        let lane = makeLane(checkpoints: [step])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .misAuthoredLane)
        XCTAssertNil(result.openInputRequest, "the user must not be asked to Supply a task that must stop anyway")
        XCTAssertEqual(worker.calls, 0)
    }

    /// Escalating attempt exhaustion pauses for user steering instead of blindly retrying.
    func test_onExhaustedEscalate_attemptCap_pausesForSteer() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 1, onExhausted: .escalate)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([fail("Need a different approach")]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .needsInput)
        XCTAssertEqual(result.openInputRequest?.kind, .steer)
        XCTAssertEqual(result.openInputRequest?.reason, .verificationFailed)
        XCTAssertEqual(result.openInputRequest?.lastFeedback, "Need a different approach")
        XCTAssertEqual(result.run(forKey: "a")?.status, .needsInput)
    }

    /// Escalating timeout exhaustion pauses for user steering.
    func test_onExhaustedEscalate_timeout_pausesForSteer() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 100, timeout: 1, onExhausted: .escalate)])
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([fail("Still wrong")]), clock: FakeClock(step: 1000))
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .needsInput)
        XCTAssertEqual(result.openInputRequest?.kind, .steer)
        XCTAssertEqual(result.openInputRequest?.reason, .timeout)
    }

    /// Once the lane's steer limit is reached, escalation becomes a hard stop.
    func test_onExhaustedEscalate_atSteerLimit_stops() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0, maxAttempts: 1, onExhausted: .escalate)], steerLimit: 0)
        let engine = VibeLaneEngine(lane: lane, worker: FakeWorker(), reviewer: FakeReviewer([fail("no")]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .steerLimitReached)
        XCTAssertNil(result.openInputRequest)
    }

    /// A paused task is inert until the manager answers the open request.
    func test_run_needsInputTaskDoesNotExecuteWorker() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        var task = makeTask(lane: lane)
        task.state = .needsInput
        task.openInputRequest = VibeLaneInputRequest(kind: .supply, checkpointKey: "a", prompt: "Need value", missingKeys: ["value"])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(task)
        XCTAssertEqual(result.state, .needsInput)
        XCTAssertEqual(worker.calls, 0)
    }

    /// A step's declared output is parsed from its handoff into carry-forward, and
    /// injected into a later step that requires it.
    func test_producedOutput_carriesForwardAndInjects() async {
        let a = VibeLaneCheckpoint(key: "a", order: 0, goal: "g", verify: VibeLaneVerificationDefinition("done"), produces: ["dataset"])
        let b = VibeLaneCheckpoint(key: "b", order: 1, goal: "g2", verify: VibeLaneVerificationDefinition("done"), requires: ["dataset"])
        let lane = makeLane(checkpoints: [a, b])
        let worker = FakeWorker(); worker.response = "OUTPUT dataset: docs/data.json"
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.carryForward?["dataset"], "docs/data.json")
        XCTAssertTrue(worker.prompts.contains { $0.contains("## Inputs") && $0.contains("dataset: docs/data.json") },
                      "step b must receive the required input in its prompt")
    }

    /// A missing declared output is logged — and NEVER deletes a value already
    /// carried forward (e.g. a user-supplied one or an earlier step's output).
    func test_missingDeclaredOutputKeepsPriorValueAndLogs() async {
        let a = VibeLaneCheckpoint(key: "a", order: 0, goal: "g", verify: VibeLaneVerificationDefinition("done"), produces: ["dataset"])
        let b = VibeLaneCheckpoint(key: "b", order: 1, goal: "g2", verify: VibeLaneVerificationDefinition("done"), produces: ["dataset"])
        let lane = makeLane(checkpoints: [a, b])
        let worker = FakeWorker()
        worker.responses = ["work-a", "OUTPUT dataset: docs/first.json", "work-b", "handoff without output", "final"]
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.carryForward?["dataset"], "docs/first.json",
                       "a step that fails to emit must not erase the value already carried forward")
        XCTAssertTrue((result.activityLog ?? []).contains { $0.message == AppStrings.VibeLanes.activityMissingOutput && $0.detail == "dataset" })
    }

    /// Declared outputs emitted in the verified WORK turn survive a handoff that
    /// omits them — the handoff is not the only emission channel.
    func test_outputParsedFromWorkTurnWhenHandoffOmitsIt() async {
        let a = VibeLaneCheckpoint(key: "a", order: 0, goal: "g", verify: VibeLaneVerificationDefinition("done"), produces: ["repro"])
        let lane = makeLane(checkpoints: [a])
        let worker = FakeWorker()
        worker.responses = ["Done.\nOUTPUT repro: tests/flake_test.rs", "thin handoff", "final"]
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.carryForward?["repro"], "tests/flake_test.rs")
    }

    /// An empty handoff response is retried once before falling back.
    func test_emptyHandoffRetriesOnce() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        let worker = FakeWorker()
        worker.responses = ["work-a", "", "HANDOFF-SECOND-TRY", "final"]
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.run(forKey: "a")?.summary, "HANDOFF-SECOND-TRY")
    }

    /// Passed checkpoints persist their handoff to a file, and later checkpoints
    /// receive the file paths (read on demand — durable across fresh sessions).
    func test_handoffWrittenToFileAndPathsInjected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelane-handoffs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lane = makeLane(checkpoints: [cp("a", order: 0), cp("b", order: 1), cp("c", order: 2)])
        let worker = FakeWorker()
        worker.response = "HANDOFF-BODY"
        let task = makeTask(lane: lane)
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), handoffRoot: root, clock: FakeClock())
        let result = await engine.run(task)
        XCTAssertEqual(result.state, .done)

        let fileA = root.appendingPathComponent(task.id.uuidString).appendingPathComponent("a.md")
        let fileB = root.appendingPathComponent(task.id.uuidString).appendingPathComponent("b.md")
        XCTAssertEqual(try String(contentsOf: fileA, encoding: .utf8), "HANDOFF-BODY")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileB.path))

        // Checkpoint c's prompt must reference BOTH earlier handoff files by path.
        let promptC = worker.prompts.first { $0.contains("## This step — C") }
        XCTAssertNotNil(promptC)
        XCTAssertTrue(promptC?.contains("Earlier step handoffs") == true)
        XCTAssertTrue(promptC?.contains(fileA.path) == true, "c must see a's handoff path, not just b's")
        XCTAssertTrue(promptC?.contains(fileB.path) == true)
    }

    /// Every step ends with a handoff summary (including the last), and the final
    /// step also records a separate task outcome.
    func test_everyStepProducesHandoff_andOutcomeIsSeparate() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0), cp("b", order: 1)])
        let worker = FakeWorker(); worker.response = "HANDOFF"
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.run(forKey: "a")?.summary, "HANDOFF")
        XCTAssertEqual(result.run(forKey: "b")?.summary, "HANDOFF", "the final step must also produce a handoff summary")
        XCTAssertEqual(result.outcomeSummary, "HANDOFF", "the final outcome is stored separately from the step handoff")
    }

    /// The task's chosen ACP agent reaches every worker turn and the reviewer.
    func test_taskAgentIDReachesWorkerAndReviewer() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        let worker = FakeWorker()
        let reviewer = FakeReviewer([pass()])
        var task = makeTask(lane: lane)
        task.agentID = "claudeCode"
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: reviewer, clock: FakeClock())
        let result = await engine.run(task)
        XCTAssertEqual(result.state, .done)
        XCTAssertTrue(worker.engines.allSatisfy { $0.agentID == "claudeCode" },
                      "every worker turn (work, handoff, outcome) must carry the task's agent")
        XCTAssertEqual(reviewer.engines.map(\.agentID), ["claudeCode"])
    }

    /// Without an override, agent selection stays nil (app default at send time).
    func test_nilAgentIDPassesThroughAsDefault() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        _ = await engine.run(makeTask(lane: lane))
        XCTAssertTrue(worker.engines.allSatisfy { $0.agentID == nil })
    }

    func test_checkpointEngineReachesEveryTurnAndRecordsActualEngine() async {
        let authored = VibeLaneEngineConfiguration(
            agentID: "codex",
            modelID: "gpt-5.4",
            modeID: "default",
            reasoningLevel: .high
        )
        let actual = VibeLaneEngineSnapshot(
            agentID: "codex",
            agentName: "Codex",
            modelID: "gpt-5.4",
            modelName: "GPT-5.4",
            modeID: "default",
            modeName: "Default",
            trustMode: .fullTrust,
            reasoningLevel: .high
        )
        var checkpoint = cp("a", order: 0)
        checkpoint.engine = authored
        let lane = makeLane(checkpoints: [checkpoint])
        let worker = FakeWorker()
        worker.reportedEngine = actual
        let reviewer = FakeReviewer([VibeLaneReviewOutcome(passed: true, engine: actual)])
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: reviewer, clock: FakeClock())

        let result = await engine.run(makeTask(lane: lane))

        XCTAssertTrue(worker.engines.allSatisfy { $0 == authored })
        XCTAssertEqual(reviewer.engines, [authored])
        XCTAssertEqual(result.run(forKey: "a")?.attempts.first?.engine, actual)
        XCTAssertEqual(result.run(forKey: "a")?.activeEngine, actual)
    }

    func test_engineDefaultsUseAppModelOnlyWithAppDefaultAgent_andAlwaysEnforceFullTrust() {
        let suite = "VibeLaneEngineTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("codex", forKey: AppPreferences.acpDefaultAgentIDKey)
        defaults.set("gpt-5.5", forKey: AppPreferences.acpDefaultModelKey)
        defaults.set(CLITrustMode.standard.rawValue, forKey: AppPreferences.acpDefaultTrustModeKey)
        defaults.set(AgentReasoningLevel.high.rawValue, forKey: AppPreferences.acpDefaultReasoningLevelKey)

        let inherited = VibeLaneEngineConfiguration.default.resolvingDefaults(userDefaults: defaults)
        XCTAssertEqual(inherited.agentID, "codex")
        XCTAssertEqual(inherited.modelID, "gpt-5.5")
        XCTAssertEqual(VibeLaneEngineConfiguration.enforcedTrustMode, .fullTrust)
        XCTAssertEqual(inherited.reasoningLevel, .high)

        let customAgent = VibeLaneEngineConfiguration(agentID: "custom-agent")
            .resolvingDefaults(userDefaults: defaults)
        XCTAssertEqual(customAgent.agentID, "custom-agent")
        XCTAssertNil(customAgent.modelID, "an authored agent with no model must use that agent's default")
    }

    func test_legacyStandardTrustConfigurationDecodesWithoutRestoringTrustChoice() throws {
        let data = Data(#"{"trustMode":"standard"}"#.utf8)

        let decoded = try JSONDecoder().decode(VibeLaneEngineConfiguration.self, from: data)

        XCTAssertTrue(decoded.isDefault)
        XCTAssertEqual(VibeLaneEngineConfiguration.enforcedTrustMode, .fullTrust)
    }

    func test_engineOptionCatalogProvidesDirectAndDiscoveredACPOptions() {
        let catalog = ACPAgentEngineOptionCatalog()

        let direct = catalog.options(for: "codex")
        XCTAssertTrue(direct.supportsReasoning)
        XCTAssertTrue(direct.models.contains(where: { $0.modelId == "gpt-5.5" }))
        XCTAssertTrue(direct.modes.contains(where: { $0.modeId == "plan" }))

        let models = [ACPModelInfo(modelId: "custom-model", name: "Custom Model", description: nil)]
        let modes = [ACPModeInfo(modeId: "review", name: "Review", description: nil)]
        catalog.record(
            agentID: "custom-agent",
            models: models,
            modes: modes,
            supportsReasoning: false
        )

        XCTAssertEqual(
            catalog.options(for: "custom-agent"),
            ACPAgentEngineOptions(models: models, modes: modes, supportsReasoning: false)
        )
    }

    func test_engineOptionCatalogLoadsACPOptionsOnDemandOnlyOnce() async {
        let expected = ACPAgentEngineOptions(
            models: [ACPModelInfo(modelId: "kiro-model", name: "Kiro Model", description: nil)],
            modes: [ACPModeInfo(modeId: "default", name: "Default", description: nil)],
            supportsReasoning: false
        )
        var discoveryCount = 0
        let catalog = ACPAgentEngineOptionCatalog { agentID in
            XCTAssertEqual(agentID, "kiro")
            discoveryCount += 1
            return expected
        }

        await catalog.loadOptionsIfNeeded(for: "kiro")
        await catalog.loadOptionsIfNeeded(for: "kiro")

        XCTAssertEqual(catalog.options(for: "kiro"), expected)
        XCTAssertEqual(discoveryCount, 1)
        XCTAssertFalse(catalog.isLoading(agentID: "kiro"))
        XCTAssertNil(catalog.discoveryError(for: "kiro"))
    }

    func test_rerunAddsAttemptInFreshBudgetEpochAndRestoresDoneState() async {
        let actual = VibeLaneEngineSnapshot(
            agentID: "codex",
            agentName: "Codex",
            trustMode: .fullTrust,
            reasoningLevel: .high
        )
        let override = VibeLaneEngineConfiguration(agentID: "codex", reasoningLevel: .high)
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        var task = makeTask(lane: lane)
        task.state = .running
        task.rerunRequest = VibeLaneRerunRequest(
            checkpointKey: "a",
            engine: override,
            previousState: .done,
            previousStopReason: .done,
            previousCheckpointKey: "a",
            requestedAt: Date(timeIntervalSince1970: 1)
        )
        task.checkpointRuns = [
            VibeLaneCheckpointRun(
                checkpointKey: "a",
                status: .running,
                attempts: [
                    VibeLaneAttempt(
                        index: 0,
                        promptKind: .goal,
                        result: VibeLaneVerificationResult(passed: true),
                        budgetEpoch: 0
                    )
                ],
                startedAt: Date(timeIntervalSince1970: 0),
                activeWindowStartedAt: Date(timeIntervalSince1970: 1),
                budgetEpoch: 1
            )
        ]
        let worker = FakeWorker()
        worker.reportedEngine = actual
        let reviewer = FakeReviewer([VibeLaneReviewOutcome(passed: true, engine: actual)])
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: reviewer, clock: FakeClock())

        let result = await engine.run(task)

        XCTAssertEqual(result.state, .done)
        XCTAssertNil(result.rerunRequest)
        XCTAssertEqual(result.lastRerunCheckpointKey, "a")
        XCTAssertEqual(result.run(forKey: "a")?.attempts.map(\.budgetEpoch), [0, 1])
        XCTAssertEqual(result.run(forKey: "a")?.attempts.last?.engine, actual)
        XCTAssertTrue(worker.engines.allSatisfy { $0 == override })
    }

    // MARK: - Human verification (the user takes the reviewer's seat)

    private func humanCP(_ key: String, order: Int, maxAttempts: Int = 3) -> VibeLaneCheckpoint {
        VibeLaneCheckpoint(
            key: key, order: order, goal: "do \(key)",
            verify: VibeLaneVerificationDefinition("done when \(key) looks right", humanReview: true),
            bounds: VibeLaneBounds(maxAttempts: maxAttempts, timeoutSeconds: 1800)
        )
    }

    /// A human-review checkpoint pauses after the work turn — the reviewer agent
    /// is never consulted.
    func test_humanReview_pausesForVerdictWithoutReviewer() async {
        let lane = makeLane(checkpoints: [humanCP("a", order: 0)])
        let worker = FakeWorker()
        let reviewer = FakeReviewer([pass()])
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: reviewer, clock: FakeClock())
        let result = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(result.state, .needsInput)
        XCTAssertEqual(result.openInputRequest?.kind, .review)
        XCTAssertEqual(result.run(forKey: "a")?.status, .needsInput)
        XCTAssertEqual(worker.calls, 1, "the work happens before the pause")
        XCTAssertEqual(reviewer.calls, 0, "the reviewer agent must never judge a human-review checkpoint")
        XCTAssertTrue(result.run(forKey: "a")?.attempts.isEmpty ?? false,
                      "no attempt is recorded until the verdict arrives")
    }

    /// Approval settles the attempt as PASS and the lane advances to done —
    /// without re-running the work.
    func test_humanApproval_passesAndAdvances() async {
        let lane = makeLane(checkpoints: [humanCP("a", order: 0)])
        let worker = FakeWorker()
        worker.response = "HANDOFF"
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([fail("never consulted")]), clock: FakeClock())
        var paused = await engine.run(makeTask(lane: lane))
        XCTAssertEqual(paused.openInputRequest?.kind, .review)
        let workCallsBeforeVerdict = worker.calls

        // Simulate the manager's answer path.
        paused.pendingHumanVerdict = VibeLaneVerificationResult(passed: true, detail: "Approved by you")
        paused.openInputRequest = nil
        paused.state = .running
        if var run = paused.run(forKey: "a") {
            run.status = .running
            run.stopReason = nil
            run.endedAt = nil
            if let idx = paused.checkpointRuns.firstIndex(where: { $0.checkpointKey == "a" }) {
                paused.checkpointRuns[idx] = run
            }
        }
        let result = await engine.run(paused)
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.run(forKey: "a")?.attempts.count, 1)
        XCTAssertEqual(result.run(forKey: "a")?.attempts.first?.result?.passed, true)
        // Only handoff + outcome turns after the verdict — no re-run of the work.
        XCTAssertEqual(worker.calls - workCallsBeforeVerdict, 2,
                       "approval must not re-run the work prompt")
    }

    /// Rejection records a failed attempt and feeds the user's feedback into the
    /// worker's next prompt, then pauses for review again.
    func test_humanRejection_feedsBackAndRetries() async {
        let lane = makeLane(checkpoints: [humanCP("a", order: 0)])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(lane: lane, worker: worker, reviewer: FakeReviewer([pass()]), clock: FakeClock())
        var paused = await engine.run(makeTask(lane: lane))

        paused.pendingHumanVerdict = VibeLaneVerificationResult(passed: false, feedback: "The nav link is missing")
        paused.openInputRequest = nil
        paused.state = .running
        if var run = paused.run(forKey: "a") {
            run.status = .running
            run.stopReason = nil
            run.endedAt = nil
            if let idx = paused.checkpointRuns.firstIndex(where: { $0.checkpointKey == "a" }) {
                paused.checkpointRuns[idx] = run
            }
        }
        let result = await engine.run(paused)
        XCTAssertEqual(result.state, .needsInput, "the retry pauses for review again")
        XCTAssertEqual(result.run(forKey: "a")?.attempts.count, 1)
        XCTAssertEqual(result.run(forKey: "a")?.attempts.first?.result?.passed, false)
        XCTAssertTrue(worker.prompts.last?.contains("The nav link is missing") == true,
                      "the user's feedback must reach the worker's retry prompt")
    }

    // MARK: - Reviewer verdict parsing

    /// Indented or markdown-decorated verdicts must still parse (a false FAIL
    /// silently burns attempts and steers).
    func test_parseVerdict_toleratesIndentationAndMarkdown() {
        XCTAssertTrue(VibeLaneACPAgentRunner.parseVerdict("  VERDICT: PASS\nSUMMARY: ok").passed)
        XCTAssertTrue(VibeLaneACPAgentRunner.parseVerdict("**VERDICT:** PASS").passed)
        XCTAssertTrue(VibeLaneACPAgentRunner.parseVerdict("verdict: pass.").passed)
        let parsed = VibeLaneACPAgentRunner.parseVerdict("> VERDICT: FAIL\n  FEEDBACK: fix the test")
        XCTAssertFalse(parsed.passed)
        XCTAssertEqual(parsed.feedback, "fix the test")
    }

    /// Ambiguous verdicts fail closed.
    func test_parseVerdict_failsClosed() {
        XCTAssertFalse(VibeLaneACPAgentRunner.parseVerdict("VERDICT: PASS or FAIL").passed)
        XCTAssertFalse(VibeLaneACPAgentRunner.parseVerdict("Looks good to me!").passed)
        XCTAssertFalse(VibeLaneACPAgentRunner.parseVerdict("").passed)
    }

    // MARK: - Durability is a precondition for acting

    /// Regression: a transition that cannot be persisted must halt the run BEFORE
    /// the worker touches the project. Otherwise a full-trust agent keeps editing
    /// while the recorded state falls behind, and a restart replays that work.
    func test_transitionPersistenceFailure_haltsBeforeWorkerRuns() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        let worker = FakeWorker()
        let engine = VibeLaneEngine(
            lane: lane,
            worker: worker,
            reviewer: FakeReviewer([pass()]),
            clock: FakeClock(),
            onTransition: { _ in
                throw VibeLanePersistenceError.unavailable("store offline")
            }
        )

        let result = await engine.run(makeTask(lane: lane))

        XCTAssertEqual(worker.calls, 0, "no work may run once a transition is not durable")
        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .error)
    }

    /// The halt also applies mid-run: once a write fails, the engine must not
    /// start another worker turn.
    func test_transitionPersistenceFailure_midRun_stopsFurtherWork() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0), cp("b", order: 1)])
        let worker = FakeWorker()
        var transitions = 0
        let engine = VibeLaneEngine(
            lane: lane,
            worker: worker,
            reviewer: FakeReviewer([pass()]),
            clock: FakeClock(),
            onTransition: { _ in
                transitions += 1
                // Survive the opening transitions, then lose durability while the
                // first checkpoint is in flight.
                if transitions > 4 {
                    throw VibeLanePersistenceError.unavailable("store offline")
                }
            }
        )

        let result = await engine.run(makeTask(lane: lane))

        XCTAssertEqual(result.state, .stopped)
        XCTAssertEqual(result.stopReason, .error)
        XCTAssertNotEqual(result.state, .done, "the lane must not report done after a lost write")
        XCTAssertLessThanOrEqual(worker.calls, 1, "no second checkpoint may start after a lost write")
    }

    /// A durable run is unaffected: the same engine with a working transition
    /// callback still completes, so the guard is not simply blocking everything.
    func test_durableTransitions_stillRunToDone() async {
        let lane = makeLane(checkpoints: [cp("a", order: 0)])
        var published: [VibeLaneTask] = []
        let engine = VibeLaneEngine(
            lane: lane,
            worker: FakeWorker(),
            reviewer: FakeReviewer([pass()]),
            clock: FakeClock(),
            onTransition: { published.append($0) }
        )

        let result = await engine.run(makeTask(lane: lane))

        XCTAssertEqual(result.state, .done)
        XCTAssertFalse(published.isEmpty)
    }
}
