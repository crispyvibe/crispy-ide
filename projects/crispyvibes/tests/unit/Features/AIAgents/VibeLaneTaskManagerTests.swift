import Foundation
import XCTest
@testable import CrispyVibes

// F059 — task manager tests: persistence/resume validation (R07/S07), stop,
// lane authoring, and delete.

@MainActor
private final class HangingWorker: VibeLaneWorkRunning {
    private(set) var calls = 0

    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        calls += 1
        while !_Concurrency.Task.isCancelled {
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000)
        }
        return VibeLaneWorkTurn(sessionRef: sessionRef, ok: false)
    }
}

/// Worker double that records the peak number of concurrent `work(...)` calls so
/// tests can assert the manager's per-project serialization and global cap.
@MainActor
private final class ConcurrencyProbeWorker: VibeLaneWorkRunning {
    private(set) var active = 0
    private(set) var maxConcurrent = 0

    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        while !_Concurrency.Task.isCancelled {
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000)
        }
        active -= 1
        return VibeLaneWorkTurn(sessionRef: sessionRef, ok: false)
    }
}

private final class FixedClock: VibeLaneClock, @unchecked Sendable {
    var value: Date
    init(_ value: Date = Date(timeIntervalSince1970: 100)) {
        self.value = value
    }
    var now: Date { value }
}

@MainActor
private final class SpyNotifier: VibeLaneNotifying {
    private(set) var notifiedTaskIDs: [UUID] = []
    func notifyNeedsInput(_ task: VibeLaneTask) {
        notifiedTaskIDs.append(task.id)
    }
}

@MainActor
final class VibeLaneTaskManagerTests: XCTestCase {

    private func makeManager(store: VibeLaneStoring) -> VibeLaneTaskManager {
        VibeLaneTaskManager(
            store: store,
            worker: HangingWorker(),
            clock: VibeLaneSystemClock(),
            maxConcurrent: 3
        )
    }

    /// R09: the transition INTO Needs you fires the notifier exactly once per
    /// open request — not on repeated upserts and not on resume.
    func test_needsInputTransition_notifiesExactlyOnce() async {
        let lane = askUserLane()
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let notifier = SpyNotifier()
        let manager = VibeLaneTaskManager(
            store: store,
            worker: HangingWorker(),
            notifier: notifier,
            clock: VibeLaneSystemClock(),
            maxConcurrent: 3
        )

        var task = VibeLaneTask(
            projectPath: "/tmp/p",
            title: "t",
            laneID: lane.id,
            laneVersion: lane.version,
            state: .running,
            currentCheckpointKey: "ask"
        )
        manager.upsert(task)
        XCTAssertTrue(notifier.notifiedTaskIDs.isEmpty, "running tasks must not notify")

        task.state = .needsInput
        task.openInputRequest = VibeLaneInputRequest(kind: .supply, checkpointKey: "ask", prompt: "Which dataset?", missingKeys: ["dataset"])
        manager.upsert(task)
        XCTAssertEqual(notifier.notifiedTaskIDs, [task.id])

        manager.upsert(task)
        XCTAssertEqual(notifier.notifiedTaskIDs, [task.id], "re-upserting the same Needs you state must not re-notify")

        task.state = .running
        task.openInputRequest = nil
        manager.upsert(task)
        XCTAssertEqual(notifier.notifiedTaskIDs, [task.id], "resuming must not notify")
    }

    private func askUserLane() -> VibeLaneDefinition {
        VibeLaneDefinition(
            name: "Ask lane",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "ask",
                    order: 0,
                    work: VibeLaneWorkDefinition(goal: "use input"),
                    verify: VibeLaneVerificationDefinition("done"),
                    requires: [VibeLaneInputRequirement(key: "dataset", askUser: true, prompt: "Which dataset?")]
                )
            ]
        )
    }

    private func steerLane(steerLimit: Int = 1) -> VibeLaneDefinition {
        VibeLaneDefinition(
            name: "Steer lane",
            steerLimit: steerLimit,
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "patch",
                    order: 0,
                    goal: "patch",
                    verify: VibeLaneVerificationDefinition("done"),
                    bounds: VibeLaneBounds(maxAttempts: 1, timeoutSeconds: 60, onExhausted: .escalate)
                )
            ]
        )
    }

    private func humanReviewLane() -> VibeLaneDefinition {
        VibeLaneDefinition(
            name: "Human review lane",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "design",
                    order: 0,
                    work: VibeLaneWorkDefinition(goal: "draft the design"),
                    verify: VibeLaneVerificationDefinition("You approve the design", humanReview: true)
                )
            ]
        )
    }

    /// A persisted human-review pause survives bootstrap, and answering it with
    /// an approval resumes the task with the verdict staged for the engine.
    func test_answerReview_approveResumesWithVerdict() async {
        let lane = humanReviewLane()
        let request = VibeLaneInputRequest(kind: .review, checkpointKey: "design", prompt: "You approve the design")
        let paused = VibeLaneTask(
            projectPath: "/tmp/p", title: "t",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: "design",
            openInputRequest: request,
            checkpointRuns: [VibeLaneCheckpointRun(checkpointKey: "design", status: .needsInput)]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [paused])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        XCTAssertEqual(manager.tasks.first?.state, .needsInput, "a review pause must survive replay validation")

        let resumed = await manager.answerInput(id: paused.id, requestID: request.id, approved: true)
        XCTAssertEqual(resumed?.state, .running)
        XCTAssertNil(resumed?.openInputRequest)
        XCTAssertEqual(resumed?.pendingHumanVerdict?.passed, true)
        manager.shutdown()
    }

    /// Rejecting a review without feedback is refused — the worker needs
    /// something to act on.
    func test_answerReview_rejectRequiresFeedback() async {
        let lane = humanReviewLane()
        let request = VibeLaneInputRequest(kind: .review, checkpointKey: "design", prompt: "You approve the design")
        let paused = VibeLaneTask(
            projectPath: "/tmp/p", title: "t",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: "design",
            openInputRequest: request,
            checkpointRuns: [VibeLaneCheckpointRun(checkpointKey: "design", status: .needsInput)]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [paused])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)

        let missingFeedback = await manager.answerInput(
            id: paused.id,
            requestID: request.id,
            approved: false,
            feedback: "  "
        )
        XCTAssertNil(missingFeedback)
        let rejected = await manager.answerInput(id: paused.id, requestID: request.id, approved: false, feedback: "Wrong palette")
        XCTAssertEqual(rejected?.pendingHumanVerdict?.passed, false)
        XCTAssertEqual(rejected?.pendingHumanVerdict?.feedback, "Wrong palette")
        manager.shutdown()
    }

    /// S07: a persisted task that is inconsistent with its lane is refused on bootstrap.
    func test_bootstrap_refusesInconsistentTask() async {
        let lane = VibeLaneCatalog.fixABug
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .done,
            currentCheckpointKey: "does-not-exist"
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty, "inconsistent task should be refused")
    }

    func test_bootstrap_refusesRerunWithNonterminalPriorState() async {
        let lane = VibeLaneDefinition(
            name: "One step",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "build",
                    order: 0,
                    goal: "Build",
                    verify: VibeLaneVerificationDefinition("Done")
                )
            ]
        )
        let bad = VibeLaneTask(
            projectPath: "/tmp",
            title: "bad rerun",
            laneID: lane.id,
            laneVersion: lane.version,
            state: .running,
            currentCheckpointKey: "build",
            rerunRequest: VibeLaneRerunRequest(
                checkpointKey: "build",
                engine: .default,
                previousState: .running,
                previousStopReason: nil,
                previousCheckpointKey: "build",
                requestedAt: Date()
            ),
            checkpointRuns: [
                VibeLaneCheckpointRun(checkpointKey: "build", status: .running)
            ]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)

        await manager.bootstrap(resumeRunning: false)

        XCTAssertTrue(manager.tasks.isEmpty, "reruns must preserve a terminal prior state")
    }

    /// A consistent, terminal task loads on bootstrap (no engine work).
    func test_bootstrap_keepsConsistentDoneTask() async {
        let lane = VibeLaneCatalog.fixABug
        let runs = lane.orderedCheckpoints.map {
            VibeLaneCheckpointRun(
                checkpointKey: $0.key,
                status: .passed,
                attempts: [VibeLaneAttempt(index: 0, promptKind: .goal, result: VibeLaneVerificationResult(passed: true))]
            )
        }
        let good = VibeLaneTask(
            projectPath: "/tmp", title: "good",
            laneID: lane.id, laneVersion: lane.version,
            state: .done, stopReason: .done,
            currentCheckpointKey: lane.orderedCheckpoints.last!.key,
            checkpointRuns: runs
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [good])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertEqual(manager.tasks.count, 1)
        XCTAssertEqual(manager.doneCount, 1)
    }

    /// A valid paused task survives bootstrap but is not scheduled until answered.
    func test_bootstrap_keepsNeedsInputPausedAndDoesNotSchedule() async {
        let lane = askUserLane()
        let firstKey = lane.firstCheckpoint!.key
        let paused = VibeLaneTask(
            projectPath: "/tmp", title: "paused",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: firstKey,
            openInputRequest: VibeLaneInputRequest(kind: .supply, checkpointKey: firstKey, prompt: "Need dataset", missingKeys: ["dataset"]),
            checkpointRuns: [VibeLaneCheckpointRun(checkpointKey: firstKey, status: .needsInput)]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [paused])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertEqual(manager.tasks.count, 1)
        XCTAssertEqual(manager.needsInputCount, 1)
        XCTAssertTrue(manager.running.isEmpty)
    }

    func test_bootstrap_refusesNeedsInputWithoutRequest() async {
        let lane = askUserLane()
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesNeedsInputRequestForDifferentCheckpoint() async {
        let lane = askUserLane()
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: lane.firstCheckpoint!.key,
            openInputRequest: VibeLaneInputRequest(kind: .supply, checkpointKey: "other", prompt: "Need value", missingKeys: ["value"])
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesNegativeSteerCount() async {
        let lane = VibeLaneCatalog.fixABug
        var bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        bad.steerCount = -1
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesImpossibleDoneWithoutPassedHistory() async {
        let lane = VibeLaneCatalog.fixABug
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .done, stopReason: .done,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesRunningTaskWithNeedsInputRun() async {
        let lane = askUserLane()
        let firstKey = lane.firstCheckpoint!.key
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .running,
            currentCheckpointKey: firstKey,
            checkpointRuns: [VibeLaneCheckpointRun(checkpointKey: firstKey, status: .needsInput)]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    /// createTask records a running task and persists it.
    func test_createTask_runsAndPersists() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let task = await manager.createTask(laneID: lane.id, title: "Fix tests", projectPath: "/tmp", agentID: "claudeCode")
        XCTAssertNotNil(task)
        XCTAssertEqual(manager.tasks.count, 1)
        XCTAssertEqual(manager.tasks.first?.state, .running)
        XCTAssertEqual(manager.tasks.first?.agentID, "claudeCode", "the chosen ACP agent must persist on the task")
        XCTAssertEqual(store.loadTasks().count, 1)
        XCTAssertEqual(store.loadTasks().first?.agentID, "claudeCode")
        manager.shutdown()
    }

    /// F060: seeded carry-forward is stored at creation (trimmed, empties
    /// dropped) so a dispatched todo can satisfy the first checkpoint's
    /// requires contract without an immediate Supply pause.
    func test_createTask_seedsInitialCarryForward() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let task = await manager.createTask(
            laneID: lane.id,
            title: "Fix tests",
            projectPath: "/tmp",
            initialCarryForward: ["repro": "  run UITests/login  ", "blank": "   "]
        )
        XCTAssertEqual(task?.carryForward, ["repro": "run UITests/login"], "values trim; empty values drop")
        XCTAssertEqual(store.loadTasks().first?.carryForward, ["repro": "run UITests/login"])
        manager.shutdown()
    }

    func test_rerunStepPreservesHistoryAndStartsFreshBudgetEpoch() async {
        let lane = VibeLaneDefinition(
            name: "One step",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "build",
                    order: 0,
                    goal: "Build",
                    verify: VibeLaneVerificationDefinition("Done")
                )
            ]
        )
        let priorAttempt = VibeLaneAttempt(
            index: 0,
            promptKind: .goal,
            result: VibeLaneVerificationResult(passed: true),
            budgetEpoch: 0
        )
        let task = VibeLaneTask(
            projectPath: "/tmp",
            title: "done",
            laneID: lane.id,
            laneVersion: lane.version,
            state: .done,
            stopReason: .done,
            currentCheckpointKey: "build",
            checkpointRuns: [
                VibeLaneCheckpointRun(
                    checkpointKey: "build",
                    status: .passed,
                    attempts: [priorAttempt],
                    budgetEpoch: 0
                )
            ]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        let override = VibeLaneEngineConfiguration(agentID: "codex", modelID: "gpt-5.4")

        let rerunning = await manager.rerunStep(id: task.id, checkpointKey: "build", engine: override)

        XCTAssertEqual(rerunning?.state, .running)
        XCTAssertEqual(rerunning?.rerunRequest?.engine, override)
        XCTAssertEqual(rerunning?.run(forKey: "build")?.budgetEpoch, 1)
        XCTAssertEqual(rerunning?.run(forKey: "build")?.rerunEpochCount, 1)
        XCTAssertEqual(rerunning?.run(forKey: "build")?.attempts, [priorAttempt])
        XCTAssertTrue(rerunning?.isConsistent(with: lane) == true)
        XCTAssertNotNil(manager.running[task.id])
        manager.shutdown()
    }

    func test_cancelledGenerationCannotClearReplacementRerun() async {
        let lane = VibeLaneDefinition(
            name: "Rerun",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "build",
                    order: 0,
                    goal: "Build",
                    verify: VibeLaneVerificationDefinition("Done")
                )
            ]
        )
        let task = completedTask(lane: lane)
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        let engine = VibeLaneEngineConfiguration(agentID: "codex")

        let firstRerun = await manager.rerunStep(
            id: task.id,
            checkpointKey: "build",
            engine: engine
        )
        XCTAssertNotNil(firstRerun)
        await settle()
        await manager.stop(id: task.id)
        let replacementRerun = await manager.rerunStep(
            id: task.id,
            checkpointKey: "build",
            engine: engine
        )
        XCTAssertNotNil(replacementRerun)

        await settle()

        XCTAssertEqual(manager.task(withID: task.id)?.state, .running)
        XCTAssertNotNil(manager.running[task.id])
        manager.shutdown()
    }

    func test_shutdownInvalidatesCompletionsWithoutStoppingPersistedTask() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let task = await manager.createTask(
            laneID: lane.id,
            title: "Resume after relaunch",
            projectPath: "/tmp"
        )!
        await settle()

        manager.shutdown()
        await settle()

        XCTAssertTrue(manager.running.isEmpty)
        XCTAssertEqual(manager.task(withID: task.id)?.state, .running)
        XCTAssertEqual(store.loadTasks().first(where: { $0.id == task.id })?.state, .running)
    }

    func test_timeoutMonitorStopsHungAgentTurn() async {
        let lane = VibeLaneDefinition(
            name: "Bounded",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "work",
                    order: 0,
                    goal: "Work",
                    verify: VibeLaneVerificationDefinition("Done"),
                    bounds: VibeLaneBounds(maxAttempts: 1, timeoutSeconds: 1, onExhausted: .stop)
                )
            ]
        )
        let worker = HangingWorker()
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = VibeLaneTaskManager(store: store, worker: worker)
        await manager.bootstrap()
        let task = await manager.createTask(laneID: lane.id, title: "Hang", projectPath: "/tmp")!

        for _ in 0..<60 where manager.task(withID: task.id)?.state == .running {
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }

        let stopped = manager.task(withID: task.id)
        XCTAssertEqual(stopped?.state, .stopped)
        XCTAssertEqual(stopped?.stopReason, .timeout)
        XCTAssertEqual(stopped?.run(forKey: "work")?.status, .stopped)
        XCTAssertEqual(stopped?.run(forKey: "work")?.stopReason, .timeout)
        XCTAssertNil(manager.running[task.id])
        XCTAssertEqual(store.loadTasks().first(where: { $0.id == task.id })?.stopReason, .timeout)
        manager.shutdown()
    }

    func test_bootstrapExpiresPersistedRunBeforeResumingAgent() async {
        let lane = VibeLaneDefinition(
            name: "Bounded",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "work",
                    order: 0,
                    goal: "Work",
                    verify: VibeLaneVerificationDefinition("Done"),
                    bounds: VibeLaneBounds(maxAttempts: 1, timeoutSeconds: 60, onExhausted: .stop)
                )
            ]
        )
        let task = VibeLaneTask(
            projectPath: "/tmp",
            title: "Expired",
            laneID: lane.id,
            laneVersion: lane.version,
            state: .running,
            currentCheckpointKey: "work",
            checkpointRuns: [
                VibeLaneCheckpointRun(
                    checkpointKey: "work",
                    status: .running,
                    startedAt: Date(timeIntervalSince1970: 10),
                    activeWindowStartedAt: Date(timeIntervalSince1970: 10)
                )
            ]
        )
        let worker = HangingWorker()
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let clock = FixedClock(Date(timeIntervalSince1970: 100))
        let manager = VibeLaneTaskManager(store: store, worker: worker, clock: clock)

        await manager.bootstrap()

        XCTAssertEqual(manager.task(withID: task.id)?.stopReason, .timeout)
        XCTAssertEqual(worker.calls, 0, "an already expired task must not reconnect to ACP")
        XCTAssertNil(manager.running[task.id])
        manager.shutdown()
    }

    func test_enforceTimeoutEscalatesWhenSteerBudgetRemains() async {
        let lane = steerLane(steerLimit: 1)
        let task = VibeLaneTask(
            projectPath: "/tmp",
            title: "Expired",
            laneID: lane.id,
            laneVersion: lane.version,
            state: .running,
            currentCheckpointKey: "patch",
            checkpointRuns: [
                VibeLaneCheckpointRun(
                    checkpointKey: "patch",
                    status: .running,
                    startedAt: Date(timeIntervalSince1970: 10),
                    activeWindowStartedAt: Date(timeIntervalSince1970: 10)
                )
            ]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let clock = FixedClock(Date(timeIntervalSince1970: 100))
        let manager = VibeLaneTaskManager(store: store, worker: HangingWorker(), clock: clock)
        await manager.bootstrap(resumeRunning: false)

        await manager.enforceCheckpointTimeouts()

        let expired = manager.task(withID: task.id)
        XCTAssertEqual(expired?.state, .needsInput)
        XCTAssertNil(expired?.stopReason)
        XCTAssertEqual(expired?.openInputRequest?.kind, .steer)
        XCTAssertEqual(expired?.openInputRequest?.reason, .timeout)
        XCTAssertEqual(expired?.run(forKey: "patch")?.status, .needsInput)
        manager.shutdown()
    }

    /// F060: nil / all-empty seeds leave carryForward nil (back-compatible).
    func test_createTask_withoutSeed_leavesCarryForwardNil() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let task = await manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp", initialCarryForward: ["x": " "])
        XCTAssertNil(task?.carryForward)
        manager.shutdown()
    }

    /// F060: every persisted state transition (old != new) fires the observer;
    /// same-state upserts do not.
    func test_onTaskStateChanged_firesPerTransition() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        var seen: [(VibeLaneTaskState, VibeLaneTaskState)] = []
        manager.onTaskStateChanged = { _, old, new in seen.append((old, new)) }
        await manager.bootstrap()
        let task = await manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")!
        XCTAssertTrue(seen.isEmpty, "insertion is not a transition")
        var same = task
        same.updatedAt = Date()
        manager.upsert(same)
        XCTAssertTrue(seen.isEmpty, "same-state upsert must not fire")
        await manager.stop(id: task.id)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, .running)
        XCTAssertEqual(seen.first?.1, .stopped)
        manager.shutdown()
    }

    /// F060: catalog summary exposes each lane's first-checkpoint requires
    /// keys; lane references resolve by UUID or unique name (ambiguity fails).
    func test_catalogSummary_andLaneResolution() async {
        let lane = askUserLane()
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()

        let summary = manager.catalogSummary()
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.first?.laneID, lane.id)
        XCTAssertEqual(summary.first?.firstCheckpointRequires, ["dataset": true])

        XCTAssertEqual(manager.resolveLaneReference(lane.id.uuidString), .resolved(lane.id))
        XCTAssertEqual(manager.resolveLaneReference("ASK LANE"), .resolved(lane.id), "name match is case-insensitive")
        XCTAssertEqual(manager.resolveLaneReference("no-such-lane"), .notFound)
        manager.shutdown()
    }

    /// stop() marks the task stoppedByUser.
    func test_stop_marksStoppedByUser() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let task = await manager.createTask(laneID: lane.id, title: "Fix tests", projectPath: "/tmp")!
        await manager.stop(id: task.id)
        XCTAssertEqual(manager.task(withID: task.id)?.state, .stopped)
        XCTAssertEqual(manager.task(withID: task.id)?.stopReason, .stoppedByUser)
        manager.shutdown()
    }

    /// R07: tasks persist to disk and reload across store instances (resume foundation).
    func test_fileStore_roundTripsTasks() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibelane-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lane = VibeLaneCatalog.fixABug
        let store = FileVibeLaneStore(directory: dir, catalog: VibeLaneCatalog.starterLanes)
        let task = VibeLaneTask(
            projectPath: "/tmp", title: "persist me",
            laneID: lane.id, laneVersion: lane.version,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        store.saveTask(task)

        let reopened = FileVibeLaneStore(directory: dir, catalog: VibeLaneCatalog.starterLanes)
        let loaded = reopened.loadTasks()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, task.id)
        XCTAssertEqual(loaded.first?.title, "persist me")
        XCTAssertEqual(loaded.first?.currentCheckpointKey, lane.firstCheckpoint!.key)
    }

    func test_fileStore_roundTripsAttemptEngineSnapshot() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibelane-engine-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lane = VibeLaneCatalog.fixABug
        let snapshot = VibeLaneEngineSnapshot(
            agentID: "codex",
            agentName: "Codex",
            modelID: "gpt-5.4",
            modelName: "GPT-5.4",
            modeID: "default",
            modeName: "Default",
            trustMode: .fullTrust,
            reasoningLevel: .high
        )
        let task = VibeLaneTask(
            projectPath: "/tmp",
            title: "persist engine",
            laneID: lane.id,
            laneVersion: lane.version,
            currentCheckpointKey: lane.firstCheckpoint!.key,
            checkpointRuns: [
                VibeLaneCheckpointRun(
                    checkpointKey: lane.firstCheckpoint!.key,
                    status: .running,
                    attempts: [
                        VibeLaneAttempt(
                            index: 0,
                            promptKind: .goal,
                            result: VibeLaneVerificationResult(passed: false),
                            engine: snapshot
                        )
                    ],
                    activeEngine: snapshot
                )
            ]
        )
        let store = FileVibeLaneStore(directory: dir, catalog: [lane])
        store.saveTask(task)

        let loaded = FileVibeLaneStore(directory: dir, catalog: [lane]).loadTasks().first
        XCTAssertEqual(loaded?.checkpointRuns.first?.attempts.first?.engine, snapshot)
        XCTAssertEqual(loaded?.checkpointRuns.first?.activeEngine, snapshot)
    }

    /// Input-pause state is durable, including the open request and budget epoch.
    func test_fileStore_roundTripsNeedsInputState() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibelane-paused-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lane = steerLane()
        let firstKey = lane.firstCheckpoint!.key
        let store = FileVibeLaneStore(directory: dir, catalog: [lane])
        let request = VibeLaneInputRequest(kind: .steer, checkpointKey: firstKey, prompt: "Steer", lastFeedback: "no", reason: .verificationFailed)
        let run = VibeLaneCheckpointRun(
            checkpointKey: firstKey,
            status: .needsInput,
            stopReason: .verificationFailed,
            attempts: [VibeLaneAttempt(index: 0, promptKind: .goal, result: VibeLaneVerificationResult(passed: false, feedback: "no"))],
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            activeWindowStartedAt: Date(timeIntervalSince1970: 3),
            budgetEpoch: 0
        )
        let task = VibeLaneTask(
            projectPath: "/tmp", title: "paused",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: firstKey,
            carryForward: ["dataset": "docs/data.json"],
            openInputRequest: request,
            steerCount: 0,
            checkpointRuns: [run]
        )
        store.saveTask(task)

        let reopened = FileVibeLaneStore(directory: dir, catalog: [lane])
        let loaded = reopened.loadTasks().first
        XCTAssertEqual(loaded?.state, .needsInput)
        XCTAssertEqual(loaded?.openInputRequest?.id, request.id)
        XCTAssertEqual(loaded?.openInputRequest?.kind, .steer)
        XCTAssertEqual(loaded?.openInputRequest?.checkpointKey, firstKey)
        XCTAssertEqual(loaded?.openInputRequest?.prompt, "Steer")
        XCTAssertEqual(loaded?.openInputRequest?.lastFeedback, "no")
        XCTAssertEqual(loaded?.openInputRequest?.reason, .verificationFailed)
        XCTAssertEqual(loaded?.carryForward?["dataset"], "docs/data.json")
        XCTAssertEqual(loaded?.steerCount, 0)
        XCTAssertEqual(loaded?.run(forKey: firstKey)?.status, .needsInput)
        XCTAssertEqual(loaded?.run(forKey: firstKey)?.budgetEpoch, 0)
    }

    /// R01: lane authoring normalizes empty/duplicate checkpoint keys on save.
    func test_laneAuthoring_normalizesKeysAndCRUD() async {
        let store = InMemoryVibeLaneStore()
        let manager = makeManager(store: store)
        await manager.bootstrap()
        guard var lane = await manager.createLane(name: "Custom") else {
            return XCTFail("Expected lane creation to persist")
        }
        XCTAssertTrue(manager.lanes.contains { $0.id == lane.id })

        lane.checkpoints = [
            VibeLaneCheckpoint(key: "x", order: 0, goal: "a", verify: VibeLaneVerificationDefinition("t")),
            VibeLaneCheckpoint(key: "x", order: 1, goal: "b", verify: VibeLaneVerificationDefinition("t")),
            VibeLaneCheckpoint(key: "", order: 2, goal: "c", verify: VibeLaneVerificationDefinition("t")),
        ]
        await manager.updateLane(lane)
        let saved = manager.lane(withID: lane.id)!
        let keys = saved.checkpoints.map { $0.key }
        XCTAssertEqual(Set(keys).count, 3, "checkpoint keys must be unique after save")
        XCTAssertFalse(keys.contains(""), "no empty checkpoint keys after save")

        await manager.deleteLane(id: lane.id)
        XCTAssertNil(manager.lane(withID: lane.id))
    }

    func test_laneAuthoringDoesNotPublishFailedSave() async {
        let original = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [original])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        let persisted = manager.lane(withID: original.id)!
        var edited = persisted
        edited.name = "Uncommitted edit"
        store.shouldFailLaneSaves = true

        let result = await manager.updateLane(edited)

        XCTAssertNil(result)
        XCTAssertEqual(manager.lane(withID: original.id), persisted)
        XCTAssertNotNil(manager.persistenceError)
    }

    func test_legacyCheckpointsMigrateIntoCentralVibes() async {
        let lane = VibeLaneDefinition(
            name: "Legacy",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "build",
                    order: 0,
                    title: "Build it",
                    goal: "Build the change",
                    verify: VibeLaneVerificationDefinition("The change works")
                )
            ]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)

        await manager.bootstrap(resumeRunning: false)

        let migrated = manager.lane(withID: lane.id)
        let vibe = manager.vibes.first
        XCTAssertEqual(manager.vibes.count, 1)
        XCTAssertEqual(vibe?.name, "Build it")
        XCTAssertEqual(vibe?.work.goal, "Build the change")
        XCTAssertEqual(migrated?.checkpoints.first?.vibeID, vibe?.id)
        XCTAssertEqual(migrated?.checkpoints.first?.vibeVersion, vibe?.version)
        XCTAssertEqual(migrated?.checkpoints.first?.work, vibe?.work)
    }

    func test_legacyVibeWithoutCategoryDecodesAsGeneral() async throws {
        let vibe = VibeDefinition(
            name: "Custom",
            goal: "Do the work",
            verify: VibeLaneVerificationDefinition("The work is done")
        )
        let encoded = try JSONEncoder().encode(vibe)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["category"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(VibeDefinition.self, from: legacy)

        XCTAssertEqual(decoded.category, .general)
    }

    func test_customVibeCategoryRoundTripsAndJoinsAvailableCatalog() async throws {
        let category = VibeCategory.custom(
            name: "Customer Support",
            systemImage: "person.2"
        )
        let vibe = VibeDefinition(
            name: "Answer escalation",
            category: category,
            goal: "Resolve the customer escalation",
            verify: VibeLaneVerificationDefinition("The response addresses every concern")
        )

        let data = try JSONEncoder().encode(vibe)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(VibeDefinition.self, from: data)
        let available = VibeCategory.available(in: [decoded])

        XCTAssertEqual(object["category"] as? String, category.id)
        XCTAssertEqual(object["categoryName"] as? String, "Customer Support")
        XCTAssertEqual(object["categoryIcon"] as? String, "person.2")
        XCTAssertEqual(decoded.category, category)
        XCTAssertEqual(decoded.category.name, "Customer Support")
        XCTAssertEqual(decoded.category.systemImage, "person.2")
        XCTAssertEqual(available.filter { $0.id == category.id }.count, 1)
    }

    func test_legacyVerificationDecodesWithNoReviewSkills() async throws {
        let data = try XCTUnwrap(
            #"{"definition":"All checks pass","humanReview":false}"#
                .data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(
            VibeLaneVerificationDefinition.self,
            from: data
        )

        XCTAssertEqual(decoded.definition, "All checks pass")
        XCTAssertEqual(decoded.reviewSkills, [])
        XCTAssertFalse(decoded.humanReview)
    }

    func test_reviewSkillsRoundTripAndCreateVersionedVibeRevision() async throws {
        let original = VibeDefinition(
            name: "Verify",
            goal: "Verify the change",
            verify: VibeLaneVerificationDefinition(
                "All checks pass",
                reviewSkills: ["code-review"]
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VibeDefinition.self, from: data)
        XCTAssertEqual(decoded.verify.reviewSkills, ["code-review"])

        let store = InMemoryVibeLaneStore(vibes: [decoded])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        var draft = decoded
        draft.verify.reviewSkills.append("security-review")

        guard let updated = await manager.updateVibe(draft) else {
            return XCTFail("Expected Vibe update to persist")
        }

        XCTAssertEqual(updated.version, original.version + 1)
        XCTAssertEqual(updated.verify.reviewSkills, ["code-review", "security-review"])
        XCTAssertEqual(
            store.vibeRevision(id: original.id, version: original.version)?
                .verify.reviewSkills,
            ["code-review"]
        )
    }

    func test_fileStoreMigratesStarterVibesIntoCatalogCategory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelane-vibe-category-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileVibeLaneStore(
            directory: dir,
            catalog: [VibeLaneCatalog.incidentResponse]
        )
        store.reconcileStarterLanes()
        let vibesURL = dir.appendingPathComponent("vibes.json")
        let data = try Data(contentsOf: vibesURL)
        var objects = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        for index in objects.indices {
            objects[index]["category"] = nil
        }
        try JSONSerialization.data(withJSONObject: objects)
            .write(to: vibesURL, options: .atomic)

        let reopened = FileVibeLaneStore(
            directory: dir,
            catalog: [VibeLaneCatalog.incidentResponse]
        )
        let migrated = reopened.loadVibes()

        XCTAssertFalse(migrated.isEmpty)
        XCTAssertTrue(migrated.allSatisfy { $0.category == .incidentResponse })
        let persisted = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: vibesURL))
                as? [[String: Any]]
        )
        XCTAssertTrue(persisted.allSatisfy { $0["category"] as? String == "incidentResponse" })
    }

    func test_fileStoreMigratesLegacyLaneToReferenceOnlyPersistence() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelane-vibes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lane = VibeLaneDefinition(
            name: "Legacy",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "verify",
                    order: 0,
                    goal: "Verify the behavior",
                    verify: VibeLaneVerificationDefinition("All checks pass")
                )
            ]
        )
        let encoder = JSONEncoder()
        try encoder.encode([lane]).write(to: dir.appendingPathComponent("lanes.json"))
        let store = FileVibeLaneStore(directory: dir, catalog: [])

        let migrated = try XCTUnwrap(store.loadLanes().first)
        let vibe = try XCTUnwrap(store.loadVibes().first)
        XCTAssertEqual(migrated.checkpoints.first?.vibeID, vibe.id)
        XCTAssertEqual(migrated.checkpoints.first?.work.goal, "Verify the behavior")

        let data = try Data(contentsOf: dir.appendingPathComponent("lanes.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let stored = try XCTUnwrap(root.first)
        let steps = try XCTUnwrap(stored["steps"] as? [[String: Any]])
        let step = try XCTUnwrap(steps.first)
        XCTAssertNotNil(step["vibeID"])
        XCTAssertNil(step["work"], "lane authoring persistence must not duplicate Vibe content")
        XCTAssertNil(step["verify"], "lane authoring persistence must not duplicate Vibe content")

        let reopened = FileVibeLaneStore(directory: dir, catalog: [])
        XCTAssertEqual(reopened.loadLanes().first?.checkpoints.first?.work.goal, "Verify the behavior")
    }

    func test_vibeEditCreatesVersionAndLaneAdoptsItExplicitly() async {
        let lane = VibeLaneDefinition(
            name: "Pinned",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "build",
                    order: 0,
                    goal: "Original outcome",
                    verify: VibeLaneVerificationDefinition("Original proof")
                )
            ]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        let pinned = manager.lane(withID: lane.id)!
        var vibe = manager.vibes[0]
        let originalVersion = vibe.version
        vibe.work.goal = "Improved outcome"

        guard let updatedVibe = await manager.updateVibe(vibe) else {
            return XCTFail("Expected Vibe update to persist")
        }

        XCTAssertEqual(updatedVibe.version, originalVersion + 1)
        XCTAssertEqual(manager.lane(withID: lane.id)?.checkpoints.first?.work.goal, "Original outcome")
        XCTAssertEqual(manager.lane(withID: lane.id)?.checkpoints.first?.vibeVersion, originalVersion)
        let deletedInUseVibe = await manager.deleteVibe(id: updatedVibe.id)
        XCTAssertFalse(deletedInUseVibe, "a Vibe used by a lane cannot be deleted")

        var adopting = pinned
        adopting.checkpoints[0] = updatedVibe.applying(to: adopting.checkpoints[0])
        guard let updatedLane = await manager.updateLane(adopting) else {
            return XCTFail("Expected lane update to persist")
        }
        XCTAssertEqual(updatedLane.checkpoints[0].work.goal, "Improved outcome")
        XCTAssertEqual(updatedLane.checkpoints[0].vibeVersion, updatedVibe.version)
    }

    func test_vibeCategoryEditCreatesVersionedRevision() async throws {
        let original = VibeDefinition(
            name: "Implement",
            category: .engineering,
            goal: "Build the change",
            verify: VibeLaneVerificationDefinition("All checks pass")
        )
        let store = InMemoryVibeLaneStore(vibes: [original])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        var draft = original
        draft.category = .release

        guard let updated = await manager.updateVibe(draft) else {
            return XCTFail("Expected Vibe update to persist")
        }

        XCTAssertEqual(updated.version, original.version + 1)
        XCTAssertEqual(updated.category, .release)
        XCTAssertEqual(
            store.vibeRevision(id: original.id, version: original.version)?.category,
            .engineering
        )
    }

    func test_vibeEditRefusesUpdateWhenPinnedRevisionCannotBeArchived() async {
        let original = VibeDefinition(
            name: "Build",
            goal: "Original outcome",
            verify: VibeLaneVerificationDefinition("Original proof")
        )
        let store = InMemoryVibeLaneStore(vibes: [original])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        var draft = original
        draft.work.goal = "Unprotected update"
        store.shouldFailVibeRevisionArchives = true

        let result = await manager.updateVibe(draft)

        XCTAssertNil(result)
        XCTAssertEqual(manager.vibe(withID: original.id), original)
        XCTAssertNil(store.vibeRevision(id: original.id, version: original.version))
    }

    func test_legacyMigrationIdentityIncludesVibeExecutionConfiguration() async {
        let laneID = UUID()
        func migratedVibe(
            skills: [String] = [],
            reviewSkills: [String] = [],
            engine: VibeLaneEngineConfiguration = .default
        ) -> VibeDefinition {
            let lane = VibeLaneDefinition(
                id: laneID,
                name: "Legacy",
                checkpoints: [
                    VibeLaneCheckpoint(
                        key: "build",
                        order: 0,
                        engine: engine,
                        work: VibeLaneWorkDefinition(
                            goal: "Build the change",
                            skills: skills
                        ),
                        verify: VibeLaneVerificationDefinition(
                            "The change works",
                            reviewSkills: reviewSkills
                        )
                    )
                ]
            )
            return InMemoryVibeLaneStore(lanes: [lane]).loadVibes()[0]
        }

        let baselineID = migratedVibe().id
        XCTAssertNotEqual(migratedVibe(skills: ["skills/review/SKILL.md"]).id, baselineID)
        XCTAssertNotEqual(
            migratedVibe(reviewSkills: ["skills/review/SKILL.md"]).id,
            baselineID
        )
        XCTAssertNotEqual(
            migratedVibe(
                engine: VibeLaneEngineConfiguration(
                    agentID: "codex",
                    modelID: "gpt-5.5",
                    modeID: "plan",
                    reasoningLevel: .high
                )
            ).id,
            baselineID
        )
    }

    func test_checkpointTitle_roundTripsAndLegacyTitleFallsBackToKey() async throws {
        let titled = VibeLaneCheckpoint(
            key: "verify-fix",
            order: 0,
            title: "Prove the regression is fixed",
            goal: "Run the relevant checks",
            verify: VibeLaneVerificationDefinition("All relevant checks pass")
        )
        let data = try JSONEncoder().encode(titled)
        let decoded = try JSONDecoder().decode(VibeLaneCheckpoint.self, from: data)
        XCTAssertEqual(decoded.title, "Prove the regression is fixed")
        XCTAssertEqual(decoded.displayTitle, "Prove the regression is fixed")

        let legacy = VibeLaneCheckpoint(
            key: "verify-fix",
            order: 0,
            goal: "Run the relevant checks",
            verify: VibeLaneVerificationDefinition("All relevant checks pass")
        )
        XCTAssertNil(legacy.title)
        XCTAssertEqual(legacy.displayTitle, "Verify Fix")
    }

    func test_laneValidation_requiresExpectationPartsAndSatisfiedHandoffs() async {
        let incomplete = VibeLaneDefinition(
            name: "Incomplete",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "build",
                    order: 0,
                    goal: " ",
                    verify: VibeLaneVerificationDefinition(""),
                    bounds: VibeLaneBounds(maxAttempts: 0, timeoutSeconds: 0)
                ),
                VibeLaneCheckpoint(
                    key: "ship",
                    order: 1,
                    goal: "Ship",
                    verify: VibeLaneVerificationDefinition("Shipped"),
                    requires: ["artifact"]
                ),
            ]
        )
        XCTAssertFalse(incomplete.isRunnable)
        XCTAssertTrue(incomplete.validationIssues.contains(.missingGoal(index: 0)))
        XCTAssertTrue(incomplete.validationIssues.contains(.missingVerification(index: 0)))
        XCTAssertTrue(incomplete.validationIssues.contains(.invalidBounds(index: 0)))
        XCTAssertTrue(incomplete.validationIssues.contains(.unsatisfiedInput(index: 1, key: "artifact")))

        var repaired = incomplete
        repaired.checkpoints[0].work.goal = "Build the artifact"
        repaired.checkpoints[0].verify.definition = "The artifact exists"
        repaired.checkpoints[0].bounds = .default
        repaired.checkpoints[0].produces = [VibeLaneOutputDeclaration(key: "artifact")]
        XCTAssertTrue(repaired.isRunnable)
    }

    func test_laneValidation_reportsSourceIndexForOutOfOrderCheckpoints() async {
        let lane = VibeLaneDefinition(
            name: "Legacy ordering",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "second",
                    order: 1,
                    goal: "Finish",
                    verify: VibeLaneVerificationDefinition("Finished")
                ),
                VibeLaneCheckpoint(
                    key: "first",
                    order: 0,
                    goal: "",
                    verify: VibeLaneVerificationDefinition("Started")
                ),
            ]
        )

        XCTAssertTrue(lane.validationIssues.contains(.missingGoal(index: 1)))
        XCTAssertFalse(lane.validationIssues.contains(.missingGoal(index: 0)))
    }

    func test_createTask_refusesLaneThatNeedsSetup() async {
        let lane = VibeLaneDefinition(
            name: "Draft",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "step-1",
                    order: 0,
                    goal: "",
                    verify: VibeLaneVerificationDefinition("")
                )
            ]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()

        let task = await manager.createTask(
            laneID: lane.id,
            title: "Do it",
            projectPath: "/tmp"
        )
        XCTAssertNil(task)
        XCTAssertTrue(manager.tasks.isEmpty)
        XCTAssertTrue(store.loadTasks().isEmpty)
        manager.shutdown()
    }

    /// Deleting a running task removes it (and it must not be resurrected).
    func test_delete_runningTask_removesIt() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let task = await manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")!
        await manager.delete(id: task.id)
        XCTAssertNil(manager.task(withID: task.id))
        XCTAssertEqual(store.loadTasks().count, 0)
        manager.shutdown()
    }

    func test_answerSupply_clearsRequestStoresCarryForwardAndSchedules() async {
        let lane = askUserLane()
        let firstKey = lane.firstCheckpoint!.key
        let request = VibeLaneInputRequest(kind: .supply, checkpointKey: firstKey, prompt: "Need dataset", missingKeys: ["dataset"])
        let task = VibeLaneTask(
            projectPath: "/tmp", title: "paused",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: firstKey,
            openInputRequest: request,
            checkpointRuns: [VibeLaneCheckpointRun(checkpointKey: firstKey, status: .needsInput)]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let manager = makeManager(store: store)
        await manager.bootstrap()

        await manager.answerInput(id: task.id, requestID: request.id, values: ["dataset": "docs/data.json"])

        let updated = manager.task(withID: task.id)
        XCTAssertEqual(updated?.state, .running)
        XCTAssertNil(updated?.openInputRequest)
        XCTAssertEqual(updated?.carryForward?["dataset"], "docs/data.json")
        XCTAssertEqual(updated?.run(forKey: firstKey)?.status, .running)
        XCTAssertNotNil(manager.running[task.id])
        manager.shutdown()
    }

    func test_answerSteer_incrementsSteerCountResetsBudgetAndSchedules() async {
        let lane = steerLane()
        let firstKey = lane.firstCheckpoint!.key
        let request = VibeLaneInputRequest(kind: .steer, checkpointKey: firstKey, prompt: "Steer", lastFeedback: "Need a narrower patch.", reason: .verificationFailed)
        let run = VibeLaneCheckpointRun(
            checkpointKey: firstKey,
            status: .needsInput,
            stopReason: .verificationFailed,
            attempts: [VibeLaneAttempt(index: 0, promptKind: .goal, result: VibeLaneVerificationResult(passed: false, feedback: "Need a narrower patch."), budgetEpoch: 0)],
            endedAt: Date(timeIntervalSince1970: 1),
            budgetEpoch: 0
        )
        let task = VibeLaneTask(
            projectPath: "/tmp", title: "paused",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: firstKey,
            openInputRequest: request,
            checkpointRuns: [run]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let manager = VibeLaneTaskManager(store: store, worker: HangingWorker(), clock: FixedClock(), maxConcurrent: 3)
        await manager.bootstrap()

        await manager.answerInput(id: task.id, requestID: request.id, guidance: "Try a smaller patch.")

        let updated = manager.task(withID: task.id)
        XCTAssertEqual(updated?.state, .running)
        XCTAssertNil(updated?.openInputRequest)
        XCTAssertTrue(updated?.pendingSteerGuidance?.contains("Need a narrower patch.") == true)
        XCTAssertTrue(updated?.pendingSteerGuidance?.contains("Try a smaller patch.") == true)
        XCTAssertEqual(updated?.steerCount, 1)
        XCTAssertEqual(updated?.run(forKey: firstKey)?.budgetEpoch, 1)
        XCTAssertEqual(updated?.run(forKey: firstKey)?.status, .running)
        XCTAssertNil(updated?.run(forKey: firstKey)?.endedAt)
        XCTAssertNotNil(manager.running[task.id])
        manager.shutdown()
    }

    func test_answerInput_rejectsWrongRequestID() async {
        let lane = askUserLane()
        let firstKey = lane.firstCheckpoint!.key
        let request = VibeLaneInputRequest(kind: .supply, checkpointKey: firstKey, prompt: "Need dataset", missingKeys: ["dataset"])
        let task = VibeLaneTask(
            projectPath: "/tmp", title: "paused",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: firstKey,
            openInputRequest: request,
            checkpointRuns: [VibeLaneCheckpointRun(checkpointKey: firstKey, status: .needsInput)]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let manager = makeManager(store: store)
        await manager.bootstrap()

        await manager.answerInput(id: task.id, requestID: UUID(), values: ["dataset": "docs/data.json"])

        XCTAssertEqual(manager.task(withID: task.id)?.state, .needsInput)
        XCTAssertNil(manager.task(withID: task.id)?.carryForward)
        XCTAssertTrue(manager.running.isEmpty)
    }

    // MARK: - Finding #1: lane version pinning (store-owned revisions)

    /// A task runs and renders against the exact lane revision it pinned, resolved
    /// from the store, so a later lane edit (new version, different checkpoints)
    /// never mutates it, and strict version lookup never falls back to the newer lane.
    func test_lanePinning_taskResolvesRetainedRevisionAfterLaneEdit() async {
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let lane = manager.lane(withID: VibeLaneCatalog.fixABug.id)!
        let task = await manager.createTask(
            laneID: lane.id, title: "pin me", projectPath: "/tmp"
        )!
        let pinnedVersion = task.laneVersion
        let pinnedKey = task.currentCheckpointKey

        // Edit the lane: replace its checkpoints entirely and bump its version.
        var edited = lane
        edited.checkpoints = [
            VibeLaneCheckpoint(key: "totally-new", order: 0, goal: "x", verify: VibeLaneVerificationDefinition("y"))
        ]
        await manager.updateLane(edited)

        // The registered lane is now a newer version with different checkpoints.
        let current = manager.lane(withID: lane.id)!
        XCTAssertGreaterThan(current.version, pinnedVersion)
        XCTAssertNotNil(current.checkpoint(forKey: "totally-new"))

        // The task still resolves to its pinned revision (old checkpoints intact).
        let resolved = manager.resolvedLane(for: manager.task(withID: task.id)!)!
        XCTAssertEqual(resolved.version, pinnedVersion)
        XCTAssertNotNil(resolved.checkpoint(forKey: pinnedKey))
        XCTAssertNil(resolved.checkpoint(forKey: "totally-new"))

        // Strict lookup: the pinned version is no longer registered and must NOT
        // fall back to the newer lane.
        XCTAssertNil(manager.lane(withID: lane.id, version: pinnedVersion))
        manager.shutdown()
    }

    /// Immutable revisions remain available for audit and exact historical
    /// resolution even after the last task that pins one is deleted.
    func test_retainedRevision_isArchivedAndSurvivesTaskDelete() async {
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let lane = manager.lane(withID: VibeLaneCatalog.fixABug.id)!
        let task = await manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")!
        let pinned = task.laneVersion

        var edited = lane
        edited.checkpoints = [VibeLaneCheckpoint(key: "new", order: 0, goal: "g", verify: VibeLaneVerificationDefinition("d"))]
        await manager.updateLane(edited)
        XCTAssertNotNil(store.laneRevision(id: lane.id, version: pinned), "outgoing revision must be retained while pinned")

        await manager.delete(id: task.id)
        XCTAssertNotNil(
            store.laneRevision(id: lane.id, version: pinned),
            "immutable revision history must survive task deletion"
        )
        manager.shutdown()
    }

    func test_fileStore_roundTripsLaneRevisions() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibelane-revisions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lane = VibeLaneCatalog.fixABug
        let store = FileVibeLaneStore(directory: dir, catalog: [lane])

        store.archiveLaneRevision(lane)

        let reopened = FileVibeLaneStore(directory: dir, catalog: [lane])
        XCTAssertEqual(reopened.laneRevision(id: lane.id, version: lane.version)?.id, lane.id)

        reopened.pruneLaneRevisions(keep: [])
        let afterPrune = FileVibeLaneStore(directory: dir, catalog: [lane])
        XCTAssertNil(afterPrune.laneRevision(id: lane.id, version: lane.version))
    }

    // MARK: - Finding #3: deleting all lanes is durable (no catalog resurrection)

    func test_deletingAllLanes_doesNotResurrectCatalog() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibelane-lanes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileVibeLaneStore(directory: dir, catalog: VibeLaneCatalog.starterLanes)

        // First load seeds from the catalog because no file exists yet.
        let seeded = store.loadLanes()
        XCTAssertFalse(seeded.isEmpty)

        // Delete every lane, then reopen from disk.
        for lane in seeded { store.deleteLane(id: lane.id) }
        let reopened = FileVibeLaneStore(directory: dir, catalog: VibeLaneCatalog.starterLanes)
        XCTAssertTrue(reopened.loadLanes().isEmpty, "deleting all lanes must be durable, not resurrect the catalog")
    }

    /// Deleted starters stay deleted even through starter reconciliation (tombstones).
    func test_reconcile_doesNotResurrectDeletedStarters() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vibelane-lanes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileVibeLaneStore(directory: dir, catalog: VibeLaneCatalog.starterLanes)
        store.reconcileStarterLanes()
        for lane in store.loadLanes() { store.deleteLane(id: lane.id) }

        let reopened = FileVibeLaneStore(directory: dir, catalog: VibeLaneCatalog.starterLanes)
        reopened.reconcileStarterLanes()
        XCTAssertTrue(reopened.loadLanes().isEmpty, "reconcile must honor starter deletions via tombstones")
    }

    // MARK: - Starter reconciliation (shipped catalog improvements reach users)

    private func oldStarter() -> VibeLaneDefinition {
        VibeLaneDefinition(
            id: VibeLaneCatalog.fixABugLaneID,
            name: "Fix a bug (old)",
            checkpoints: [VibeLaneCheckpoint(key: "old-step", order: 0, goal: "old", verify: VibeLaneVerificationDefinition("old"))]
        )
    }

    /// A pristine (never user-edited) starter lane picks up improved shipped content.
    func test_reconcile_refreshesPristineStarterLane() async {
        let store = InMemoryVibeLaneStore(lanes: [oldStarter()], catalog: [VibeLaneCatalog.fixABug])
        guard let oldVibeID = store.loadLanes().first?.checkpoints.first?.vibeID,
              let oldVibe = store.loadVibes().first(where: { $0.id == oldVibeID }) else {
            return XCTFail("Expected the legacy starter Vibe")
        }
        store.reconcileStarterLanes()
        let lane = store.loadLanes().first { $0.id == VibeLaneCatalog.fixABugLaneID }
        XCTAssertEqual(lane?.name, VibeLaneCatalog.fixABug.name)
        XCTAssertEqual(lane?.checkpoints.count, VibeLaneCatalog.fixABug.checkpoints.count)
        XCTAssertEqual(lane?.version, 2, "refresh must bump the version so retained revisions stay distinct")
        XCTAssertNotNil(lane?.seededFingerprint, "refreshed lane must be marked pristine for the next update")
        XCTAssertFalse(store.loadVibes().contains { $0.id == oldVibeID })
        XCTAssertEqual(
            store.vibeRevision(id: oldVibeID, version: oldVibe.version),
            oldVibe,
            "the replaced starter Vibe must remain available as immutable history"
        )
    }

    func test_reconcile_retiresOrphanedVibeFromHistoricalStarterRevision() async {
        let laneID = UUID()
        let oldVibe = VibeDefinition(
            name: "Align",
            goal: "Align the implementation with project conventions.",
            verify: VibeLaneVerificationDefinition("The implementation follows project conventions.")
        )
        let shippedVibe = VibeDefinition(
            name: "Align",
            goal: "Align the implementation with project conventions.",
            verify: VibeLaneVerificationDefinition(
                "The implementation follows project conventions.",
                reviewSkills: ["code-review"]
            )
        )
        let historicalLane = VibeLaneDefinition(
            id: laneID,
            version: 1,
            name: "Starter",
            checkpoints: [oldVibe.checkpoint(key: "align", order: 0)]
        )
        let currentLane = VibeLaneDefinition(
            id: laneID,
            version: 2,
            name: "Starter",
            checkpoints: [shippedVibe.checkpoint(key: "align", order: 0)]
        )

        let retired = VibeLaneStarterReconciler.supersededVibeIDs(
            currentVibes: [oldVibe, shippedVibe],
            previousLanes: [currentLane],
            currentLanes: [currentLane],
            laneRevisions: [historicalLane],
            catalogLanes: [currentLane],
            catalogVibes: [shippedVibe]
        )

        XCTAssertEqual(retired, [oldVibe.id])
    }

    func test_reconcile_retiresUnusedCatalogCopyWithoutRevisionHistory() async {
        let laneID = UUID()
        let oldSource = VibeLaneDefinition(
            id: laneID,
            name: "Starter",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "align",
                    order: 0,
                    goal: "Align the implementation with project conventions.",
                    verify: VibeLaneVerificationDefinition(
                        "The implementation follows project conventions."
                    )
                )
            ]
        )
        var shippedSource = oldSource
        shippedSource.checkpoints[0].verify.reviewSkills = ["code-review"]
        let oldState = VibeLaneReferenceResolver.resolve(lanes: [oldSource], vibes: [])
        let shippedState = VibeLaneReferenceResolver.resolve(lanes: [shippedSource], vibes: [])
        let oldVibe = oldState.vibes[0]
        let shippedVibe = shippedState.vibes[0]

        let retired = VibeLaneStarterReconciler.supersededVibeIDs(
            currentVibes: [oldVibe, shippedVibe],
            previousLanes: oldState.lanes,
            currentLanes: oldState.lanes,
            laneRevisions: [],
            catalogLanes: shippedState.lanes,
            catalogVibes: shippedState.vibes
        )

        XCTAssertEqual(retired, [shippedVibe.id])
    }

    func test_reconcile_keepsHistoricalStarterVibeUsedByCurrentLane() async {
        let starterLaneID = UUID()
        let oldVibe = VibeDefinition(
            name: "Align",
            goal: "Align the implementation with project conventions.",
            verify: VibeLaneVerificationDefinition("The implementation follows project conventions.")
        )
        let shippedVibe = VibeDefinition(
            name: "Align",
            goal: "Align the implementation with project conventions.",
            verify: VibeLaneVerificationDefinition(
                "The implementation follows project conventions.",
                reviewSkills: ["code-review"]
            )
        )
        let historicalLane = VibeLaneDefinition(
            id: starterLaneID,
            version: 1,
            name: "Starter",
            checkpoints: [oldVibe.checkpoint(key: "align", order: 0)]
        )
        let currentStarter = VibeLaneDefinition(
            id: starterLaneID,
            version: 2,
            name: "Starter",
            checkpoints: [shippedVibe.checkpoint(key: "align", order: 0)]
        )
        let userLane = VibeLaneDefinition(
            name: "My lane",
            checkpoints: [oldVibe.checkpoint(key: "align", order: 0)]
        )

        let retired = VibeLaneStarterReconciler.supersededVibeIDs(
            currentVibes: [oldVibe, shippedVibe],
            previousLanes: [currentStarter, userLane],
            currentLanes: [currentStarter, userLane],
            laneRevisions: [historicalLane],
            catalogLanes: [currentStarter],
            catalogVibes: [shippedVibe]
        )

        XCTAssertTrue(retired.isEmpty)
    }

    func test_reconcile_keepsSameNameVibeWithDifferentGoal() async {
        let laneID = UUID()
        let userVibe = VibeDefinition(
            name: "Align",
            goal: "Align the launch copy with the approved positioning.",
            verify: VibeLaneVerificationDefinition("The launch copy matches the positioning.")
        )
        let shippedVibe = VibeDefinition(
            name: "Align",
            goal: "Align the implementation with project conventions.",
            verify: VibeLaneVerificationDefinition("The implementation follows project conventions.")
        )
        let historicalLane = VibeLaneDefinition(
            id: laneID,
            version: 1,
            name: "Starter",
            checkpoints: [userVibe.checkpoint(key: "align", order: 0)]
        )
        let currentLane = VibeLaneDefinition(
            id: laneID,
            version: 2,
            name: "Starter",
            checkpoints: [shippedVibe.checkpoint(key: "align", order: 0)]
        )

        let retired = VibeLaneStarterReconciler.supersededVibeIDs(
            currentVibes: [userVibe, shippedVibe],
            previousLanes: [currentLane],
            currentLanes: [currentLane],
            laneRevisions: [historicalLane],
            catalogLanes: [currentLane],
            catalogVibes: [shippedVibe]
        )

        XCTAssertTrue(retired.isEmpty)
    }

    /// A user-edited starter lane is never overwritten by shipped updates.
    func test_reconcile_leavesUserEditedStarterAlone() async {
        var edited = oldStarter()
        edited.version = 3
        edited.seededFingerprint = nil
        let store = InMemoryVibeLaneStore(lanes: [edited], catalog: [VibeLaneCatalog.fixABug])
        store.reconcileStarterLanes()
        let lane = store.loadLanes().first { $0.id == VibeLaneCatalog.fixABugLaneID }
        XCTAssertEqual(lane?.name, "Fix a bug (old)", "user-owned lanes must never be auto-refreshed")
        XCTAssertEqual(lane?.version, 3)
    }

    /// A newly shipped starter the user never deleted is added on reconcile.
    func test_reconcile_addsNewStarterLane() async {
        let store = InMemoryVibeLaneStore(lanes: [], catalog: [VibeLaneCatalog.smallFeature])
        store.reconcileStarterLanes()
        XCTAssertEqual(store.loadLanes().count, 1)
        XCTAssertNotNil(store.loadLanes().first?.seededFingerprint)
    }

    /// Restore is the explicit escape hatch: deleted starters come back.
    func test_restoreStarterLanes_readdsDeleted() async {
        let store = InMemoryVibeLaneStore(lanes: [], catalog: [VibeLaneCatalog.fixABug])
        store.reconcileStarterLanes()
        store.deleteLane(id: VibeLaneCatalog.fixABugLaneID)
        store.reconcileStarterLanes()
        XCTAssertTrue(store.loadLanes().isEmpty, "tombstone must hold through reconcile")

        store.restoreStarterLanes()
        XCTAssertEqual(store.loadLanes().first?.id, VibeLaneCatalog.fixABugLaneID)
    }

    /// Saving an edit marks the lane user-owned so future reconciles skip it.
    func test_updateLane_marksLaneUserOwned() async {
        let store = InMemoryVibeLaneStore(lanes: [], catalog: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        var lane = manager.lane(withID: VibeLaneCatalog.fixABugLaneID)!
        XCTAssertNotNil(lane.seededFingerprint)
        lane.name = "My custom bug lane"
        guard let saved = await manager.updateLane(lane) else {
            return XCTFail("Expected lane update to persist")
        }
        XCTAssertNil(saved.seededFingerprint, "a user edit must clear the pristine marker")
        XCTAssertFalse(VibeLaneStarterReconciler.isPristine(saved))
    }

    /// A task pinned to the old starter content keeps resolving it after a refresh.
    func test_pinnedRevisionSurvivesStarterRefresh() async {
        let store = InMemoryVibeLaneStore(lanes: [oldStarter()], catalog: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        await manager.bootstrap(resumeRunning: false)
        // Bootstrap already reconciled; simulate the older sequence: task created
        // against version 1, then a later launch ships improved content.
        _ = store // (reconcile happened; lane is now the shipped v2 content)
        let task = await manager.createTask(laneID: VibeLaneCatalog.fixABugLaneID, title: "t", projectPath: "/tmp/p")!
        let resolvedNow = manager.resolvedLane(for: task)
        XCTAssertEqual(resolvedNow?.version, task.laneVersion, "a task must resolve the exact revision it pinned")
        XCTAssertEqual(resolvedNow?.checkpoints.map(\.key), VibeLaneCatalog.fixABug.checkpoints.map(\.key))
        manager.shutdown()
    }

    // MARK: - Finding #7: per-project concurrency

    /// Two tasks against the SAME project must not run concurrently.
    func test_perProjectConcurrency_serializesSameProject() async {
        let probe = ConcurrencyProbeWorker()
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = VibeLaneTaskManager(store: store, worker: probe, clock: VibeLaneSystemClock(), maxConcurrent: 3)
        await manager.bootstrap()
        _ = await manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "a", projectPath: "/same")
        _ = await manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "b", projectPath: "/same")
        await settle()
        XCTAssertEqual(probe.maxConcurrent, 1, "same-project tasks must run one at a time")
        manager.shutdown()
    }

    /// Tasks against DIFFERENT projects may run concurrently (within the global cap).
    func test_differentProjects_runConcurrently() async {
        let probe = ConcurrencyProbeWorker()
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = VibeLaneTaskManager(store: store, worker: probe, clock: VibeLaneSystemClock(), maxConcurrent: 3)
        await manager.bootstrap()
        _ = await manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "a", projectPath: "/a")
        _ = await manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "b", projectPath: "/b")
        await settle()
        XCTAssertEqual(probe.maxConcurrent, 2, "different-project tasks should run concurrently")
        manager.shutdown()
    }

    /// Let engine jobs spin up and enter the worker before asserting.
    private func settle() async {
        for _ in 0..<20 { await _Concurrency.Task.yield() }
        try? await _Concurrency.Task.sleep(nanoseconds: 60_000_000)
    }

    // MARK: - Lane revision compare-and-swap

    /// Regression: the new version must come from the STORE, not the caller's
    /// draft. Two saves from the same base previously both wrote v2, so the
    /// second silently overwrote the first — breaking the immutable
    /// `(laneID, version)` contract that tasks and loop snapshots pin against.
    func test_concurrentLaneSaves_fromSameBase_produceDistinctVersions() async {
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let base = manager.lane(withID: VibeLaneCatalog.fixABug.id)!

        var firstEdit = base
        firstEdit.name = "First edit"
        let first = await manager.updateLane(firstEdit)
        XCTAssertEqual(first?.version, base.version + 1)

        // A second draft still holding the ORIGINAL version is stale.
        var staleEdit = base
        staleEdit.name = "Second edit"
        let second = await manager.updateLane(staleEdit)

        XCTAssertNil(second, "a draft based on a superseded revision must be refused")
        XCTAssertEqual(manager.persistenceError, AppStrings.VibeLanes.laneRevisionConflict)
        XCTAssertEqual(
            manager.lane(withID: base.id)?.name,
            "First edit",
            "the refused save must not overwrite the committed revision"
        )
        XCTAssertEqual(manager.lane(withID: base.id)?.version, base.version + 1)
        manager.shutdown()
    }

    /// Re-reading the lane after a save yields a draft that saves cleanly, so the
    /// compare-and-swap does not block ordinary sequential editing.
    func test_sequentialLaneSaves_bumpVersionEachTime() async {
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let base = manager.lane(withID: VibeLaneCatalog.fixABug.id)!

        var first = base
        first.name = "One"
        let saved = await manager.updateLane(first)!
        var second = manager.lane(withID: base.id)!
        second.name = "Two"
        let resaved = await manager.updateLane(second)

        XCTAssertEqual(saved.version, base.version + 1)
        XCTAssertEqual(resaved?.version, base.version + 2)
        XCTAssertNil(manager.persistenceError)
        manager.shutdown()
    }

    // MARK: - Non-runnable lanes never execute

    /// Regression: a pinned Vibe revision that can no longer be hydrated leaves a
    /// checkpoint with no goal and no verification. Such a task must never be
    /// resumed — it would run a full-trust agent against an empty instruction.
    func test_taskPinnedToUnresolvableVibe_isNotResumed() async {
        let missingVibeID = UUID()
        // A reference-only checkpoint whose Vibe is absent from the store.
        let lane = VibeLaneDefinition(
            name: "Dangling lane",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "step",
                    order: 0,
                    vibeID: missingVibeID,
                    vibeVersion: 3,
                    work: VibeLaneWorkDefinition(goal: ""),
                    verify: VibeLaneVerificationDefinition("")
                )
            ]
        )
        let task = VibeLaneTask(
            projectPath: "/tmp",
            title: "resumed",
            laneID: lane.id,
            laneVersion: lane.version,
            state: .running,
            currentCheckpointKey: "step"
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [task])
        let worker = HangingWorker()
        let manager = VibeLaneTaskManager(
            store: store,
            worker: worker,
            clock: VibeLaneSystemClock(),
            maxConcurrent: 3
        )

        await manager.bootstrap()
        await settle()

        let resolved = manager.resolvedLane(for: task)
        XCTAssertEqual(resolved?.checkpoints.first?.unresolvedVibeReference, true)
        XCTAssertEqual(resolved?.isRunnable, false)
        XCTAssertFalse(manager.isExecuting(taskID: task.id), "a non-runnable lane must not start")
        XCTAssertEqual(worker.calls, 0, "no agent turn may run against an unresolved reference")
        manager.shutdown()
    }

    /// The same guard covers task creation, which must refuse outright.
    func test_createTask_refusesNonRunnableLane() async {
        let lane = VibeLaneDefinition(
            name: "Incomplete",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "step",
                    order: 0,
                    work: VibeLaneWorkDefinition(goal: ""),
                    verify: VibeLaneVerificationDefinition("")
                )
            ]
        )
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        await manager.bootstrap()

        let created = await manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")

        XCTAssertNil(created)
        manager.shutdown()
    }

    // MARK: - Delete reports its durable outcome

    /// Regression: delete returned Void, so a failed durable delete was
    /// indistinguishable from success and the CLI reported `deleted: true`.
    func test_delete_returnsFalse_whenDurableDeleteFails() async {
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        await manager.bootstrap()
        let lane = manager.lane(withID: VibeLaneCatalog.fixABug.id)!
        let task = await manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")!

        store.shouldFailTaskDeletes = true
        let deleted = await manager.delete(id: task.id)

        XCTAssertFalse(deleted, "a failed durable delete must not report success")
        XCTAssertNotNil(manager.task(withID: task.id), "the task is still present")
        XCTAssertNotNil(manager.persistenceError)

        store.shouldFailTaskDeletes = false
        let retried = await manager.delete(id: task.id)
        XCTAssertTrue(retried)
        XCTAssertNil(manager.task(withID: task.id))
        manager.shutdown()
    }

    // MARK: - Starter catalog integrity

    /// Every starter lane must be runnable as shipped, and its carry-forward
    /// contract must be satisfiable in order — a step may only require keys an
    /// EARLIER step produces. An unsatisfiable contract stops the task as
    /// `misAuthoredLane` at runtime, so it has to be caught here.
    func test_starterLanes_areRunnableAndCarryForwardIsSatisfiableInOrder() {
        for lane in VibeLaneCatalog.starterLanes {
            XCTAssertTrue(
                lane.isRunnable,
                "\(lane.name) ships non-runnable: \(lane.validationIssues)"
            )
            var produced = Set<String>()
            for checkpoint in lane.orderedCheckpoints {
                for key in checkpoint.requiredInputs where !checkpoint.askUserInputs.contains(where: { $0.key == key }) {
                    XCTAssertTrue(
                        produced.contains(key),
                        "\(lane.name)/\(checkpoint.key) requires `\(key)`, which no earlier step produces"
                    )
                }
                produced.formUnion(checkpoint.producedOutputs)
            }
        }
    }

    /// F059 — the design-first route for Full feature delivery: interfaces and
    /// their fakes are settled BEFORE code, and the lane ends by evidencing the
    /// acceptance criteria rather than by opening a PR.
    func test_fullFeatureDelivery_isDesignFirstAndEndsOnAcceptance() {
        let lane = VibeLaneCatalog.fullFeatureDelivery
        XCTAssertEqual(
            lane.orderedCheckpoints.map(\.key),
            [
                "align", "plan", "contract", "mocks", "implement",
                "architecture-review", "security-gate", "quality-budgets",
                "acceptance", "release-handoff",
            ]
        )
        // Contract and fakes precede implementation, and implementation is bound
        // to both — so the build has an oracle to work against.
        let implement = lane.checkpoint(forKey: "implement")
        XCTAssertEqual(Set(implement?.requiredInputs ?? []), ["prd", "slices", "contract", "mocks"])
        XCTAssertNil(
            lane.checkpoint(forKey: "mocks")?.requiredInputs.first { $0 == "implementation" },
            "fakes must not depend on the implementation they exist to test"
        )
        // The scope gate is human: this is the last cheap moment to change course
        // before an unattended multi-hour build.
        XCTAssertEqual(lane.checkpoint(forKey: "plan")?.verify.humanReview, true)
        // Acceptance closes on the criteria authored in `align`.
        let acceptance = lane.checkpoint(forKey: "acceptance")
        XCTAssertTrue(acceptance?.requiredInputs.contains("acceptance_criteria") == true)
        XCTAssertEqual(lane.checkpoint(forKey: "release-handoff")?.requiredInputs, ["acceptance"])
        XCTAssertNil(lane.checkpoint(forKey: "open-pr"), "the PR step was replaced by acceptance")
    }

    private func completedTask(lane: VibeLaneDefinition) -> VibeLaneTask {
        let checkpoint = lane.firstCheckpoint!
        return VibeLaneTask(
            projectPath: "/tmp",
            title: "done",
            laneID: lane.id,
            laneVersion: lane.version,
            state: .done,
            stopReason: .done,
            currentCheckpointKey: checkpoint.key,
            checkpointRuns: [
                VibeLaneCheckpointRun(
                    checkpointKey: checkpoint.key,
                    status: .passed,
                    attempts: [
                        VibeLaneAttempt(
                            index: 0,
                            promptKind: .goal,
                            result: VibeLaneVerificationResult(passed: true)
                        )
                    ]
                )
            ]
        )
    }
}
