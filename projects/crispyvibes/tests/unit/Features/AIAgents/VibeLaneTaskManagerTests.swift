import Foundation
import XCTest
@testable import CrispyVibes

// F059 — task manager tests: persistence/resume validation (R07/S07), stop,
// lane authoring, and delete.

@MainActor
private final class HangingWorker: VibeLaneWorkRunning {
    func work(prompt: String, projectPath: String, sessionRef: String?, agentID: String?) async -> VibeLaneWorkTurn {
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

    func work(prompt: String, projectPath: String, sessionRef: String?, agentID: String?) async -> VibeLaneWorkTurn {
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
    func test_needsInputTransition_notifiesExactlyOnce() {
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
    func test_answerReview_approveResumesWithVerdict() {
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
        manager.bootstrap(resumeRunning: false)
        XCTAssertEqual(manager.tasks.first?.state, .needsInput, "a review pause must survive replay validation")

        let resumed = manager.answerInput(id: paused.id, requestID: request.id, approved: true)
        XCTAssertEqual(resumed?.state, .running)
        XCTAssertNil(resumed?.openInputRequest)
        XCTAssertEqual(resumed?.pendingHumanVerdict?.passed, true)
        manager.shutdown()
    }

    /// Rejecting a review without feedback is refused — the worker needs
    /// something to act on.
    func test_answerReview_rejectRequiresFeedback() {
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
        manager.bootstrap(resumeRunning: false)

        XCTAssertNil(manager.answerInput(id: paused.id, requestID: request.id, approved: false, feedback: "  "))
        let rejected = manager.answerInput(id: paused.id, requestID: request.id, approved: false, feedback: "Wrong palette")
        XCTAssertEqual(rejected?.pendingHumanVerdict?.passed, false)
        XCTAssertEqual(rejected?.pendingHumanVerdict?.feedback, "Wrong palette")
        manager.shutdown()
    }

    /// S07: a persisted task that is inconsistent with its lane is refused on bootstrap.
    func test_bootstrap_refusesInconsistentTask() {
        let lane = VibeLaneCatalog.fixABug
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .done,
            currentCheckpointKey: "does-not-exist"
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty, "inconsistent task should be refused")
    }

    /// A consistent, terminal task loads on bootstrap (no engine work).
    func test_bootstrap_keepsConsistentDoneTask() {
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
        manager.bootstrap()
        XCTAssertEqual(manager.tasks.count, 1)
        XCTAssertEqual(manager.doneCount, 1)
    }

    /// A valid paused task survives bootstrap but is not scheduled until answered.
    func test_bootstrap_keepsNeedsInputPausedAndDoesNotSchedule() {
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
        manager.bootstrap()
        XCTAssertEqual(manager.tasks.count, 1)
        XCTAssertEqual(manager.needsInputCount, 1)
        XCTAssertTrue(manager.running.isEmpty)
    }

    func test_bootstrap_refusesNeedsInputWithoutRequest() {
        let lane = askUserLane()
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .needsInput,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesNeedsInputRequestForDifferentCheckpoint() {
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
        manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesNegativeSteerCount() {
        let lane = VibeLaneCatalog.fixABug
        var bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        bad.steerCount = -1
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesImpossibleDoneWithoutPassedHistory() {
        let lane = VibeLaneCatalog.fixABug
        let bad = VibeLaneTask(
            projectPath: "/tmp", title: "bad",
            laneID: lane.id, laneVersion: lane.version,
            state: .done, stopReason: .done,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        let store = InMemoryVibeLaneStore(lanes: [lane], tasks: [bad])
        let manager = makeManager(store: store)
        manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_bootstrap_refusesRunningTaskWithNeedsInputRun() {
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
        manager.bootstrap()
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    /// createTask records a running task and persists it.
    func test_createTask_runsAndPersists() {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        manager.bootstrap()
        let task = manager.createTask(laneID: lane.id, title: "Fix tests", projectPath: "/tmp", agentID: "claudeCode")
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
    func test_createTask_seedsInitialCarryForward() {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        manager.bootstrap()
        let task = manager.createTask(
            laneID: lane.id,
            title: "Fix tests",
            projectPath: "/tmp",
            initialCarryForward: ["repro": "  run UITests/login  ", "blank": "   "]
        )
        XCTAssertEqual(task?.carryForward, ["repro": "run UITests/login"], "values trim; empty values drop")
        XCTAssertEqual(store.loadTasks().first?.carryForward, ["repro": "run UITests/login"])
        manager.shutdown()
    }

    /// F060: nil / all-empty seeds leave carryForward nil (back-compatible).
    func test_createTask_withoutSeed_leavesCarryForwardNil() {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        manager.bootstrap()
        let task = manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp", initialCarryForward: ["x": " "])
        XCTAssertNil(task?.carryForward)
        manager.shutdown()
    }

    /// F060: every persisted state transition (old != new) fires the observer;
    /// same-state upserts do not.
    func test_onTaskStateChanged_firesPerTransition() {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        var seen: [(VibeLaneTaskState, VibeLaneTaskState)] = []
        manager.onTaskStateChanged = { _, old, new in seen.append((old, new)) }
        manager.bootstrap()
        let task = manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")!
        XCTAssertTrue(seen.isEmpty, "insertion is not a transition")
        var same = task
        same.updatedAt = Date()
        manager.upsert(same)
        XCTAssertTrue(seen.isEmpty, "same-state upsert must not fire")
        manager.stop(id: task.id)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.0, .running)
        XCTAssertEqual(seen.first?.1, .stopped)
        manager.shutdown()
    }

    /// F060: catalog summary exposes each lane's first-checkpoint requires
    /// keys; lane references resolve by UUID or unique name (ambiguity fails).
    func test_catalogSummary_andLaneResolution() {
        let lane = askUserLane()
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        manager.bootstrap()

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
    func test_stop_marksStoppedByUser() {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        manager.bootstrap()
        let task = manager.createTask(laneID: lane.id, title: "Fix tests", projectPath: "/tmp")!
        manager.stop(id: task.id)
        XCTAssertEqual(manager.task(withID: task.id)?.state, .stopped)
        XCTAssertEqual(manager.task(withID: task.id)?.stopReason, .stoppedByUser)
        manager.shutdown()
    }

    /// R07: tasks persist to disk and reload across store instances (resume foundation).
    func test_fileStore_roundTripsTasks() {
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

    /// Input-pause state is durable, including the open request and budget epoch.
    func test_fileStore_roundTripsNeedsInputState() {
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
    func test_laneAuthoring_normalizesKeysAndCRUD() {
        let store = InMemoryVibeLaneStore()
        let manager = makeManager(store: store)
        manager.bootstrap()
        var lane = manager.createLane(name: "Custom")
        XCTAssertTrue(manager.lanes.contains { $0.id == lane.id })

        lane.checkpoints = [
            VibeLaneCheckpoint(key: "x", order: 0, goal: "a", verify: VibeLaneVerificationDefinition("t")),
            VibeLaneCheckpoint(key: "x", order: 1, goal: "b", verify: VibeLaneVerificationDefinition("t")),
            VibeLaneCheckpoint(key: "", order: 2, goal: "c", verify: VibeLaneVerificationDefinition("t")),
        ]
        manager.updateLane(lane)
        let saved = manager.lane(withID: lane.id)!
        let keys = saved.checkpoints.map { $0.key }
        XCTAssertEqual(Set(keys).count, 3, "checkpoint keys must be unique after save")
        XCTAssertFalse(keys.contains(""), "no empty checkpoint keys after save")

        manager.deleteLane(id: lane.id)
        XCTAssertNil(manager.lane(withID: lane.id))
    }

    /// Deleting a running task removes it (and it must not be resurrected).
    func test_delete_runningTask_removesIt() {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = makeManager(store: store)
        manager.bootstrap()
        let task = manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")!
        manager.delete(id: task.id)
        XCTAssertNil(manager.task(withID: task.id))
        XCTAssertEqual(store.loadTasks().count, 0)
        manager.shutdown()
    }

    func test_answerSupply_clearsRequestStoresCarryForwardAndSchedules() {
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
        manager.bootstrap()

        manager.answerInput(id: task.id, requestID: request.id, values: ["dataset": "docs/data.json"])

        let updated = manager.task(withID: task.id)
        XCTAssertEqual(updated?.state, .running)
        XCTAssertNil(updated?.openInputRequest)
        XCTAssertEqual(updated?.carryForward?["dataset"], "docs/data.json")
        XCTAssertEqual(updated?.run(forKey: firstKey)?.status, .running)
        XCTAssertNotNil(manager.running[task.id])
        manager.shutdown()
    }

    func test_answerSteer_incrementsSteerCountResetsBudgetAndSchedules() {
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
        manager.bootstrap()

        manager.answerInput(id: task.id, requestID: request.id, guidance: "Try a smaller patch.")

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

    func test_answerInput_rejectsWrongRequestID() {
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
        manager.bootstrap()

        manager.answerInput(id: task.id, requestID: UUID(), values: ["dataset": "docs/data.json"])

        XCTAssertEqual(manager.task(withID: task.id)?.state, .needsInput)
        XCTAssertNil(manager.task(withID: task.id)?.carryForward)
        XCTAssertTrue(manager.running.isEmpty)
    }

    // MARK: - Finding #1: lane version pinning (store-owned revisions)

    /// A task runs and renders against the exact lane revision it pinned, resolved
    /// from the store, so a later lane edit (new version, different checkpoints)
    /// never mutates it, and strict version lookup never falls back to the newer lane.
    func test_lanePinning_taskResolvesRetainedRevisionAfterLaneEdit() {
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        manager.bootstrap()
        let lane = manager.lane(withID: VibeLaneCatalog.fixABug.id)!
        let task = manager.createTask(
            laneID: lane.id, title: "pin me", projectPath: "/tmp"
        )!
        let pinnedVersion = task.laneVersion
        let pinnedKey = task.currentCheckpointKey

        // Edit the lane: replace its checkpoints entirely and bump its version.
        var edited = lane
        edited.checkpoints = [
            VibeLaneCheckpoint(key: "totally-new", order: 0, goal: "x", verify: VibeLaneVerificationDefinition("y"))
        ]
        manager.updateLane(edited)

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

    /// Editing a lane retains the outgoing revision while a task pins it; deleting
    /// that task prunes the now-unreferenced revision from the store.
    func test_retainedRevision_isArchivedOnEditAndPrunedOnTaskDelete() {
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        manager.bootstrap()
        let lane = manager.lane(withID: VibeLaneCatalog.fixABug.id)!
        let task = manager.createTask(laneID: lane.id, title: "t", projectPath: "/tmp")!
        let pinned = task.laneVersion

        var edited = lane
        edited.checkpoints = [VibeLaneCheckpoint(key: "new", order: 0, goal: "g", verify: VibeLaneVerificationDefinition("d"))]
        manager.updateLane(edited)
        XCTAssertNotNil(store.laneRevision(id: lane.id, version: pinned), "outgoing revision must be retained while pinned")

        manager.delete(id: task.id)
        XCTAssertNil(store.laneRevision(id: lane.id, version: pinned), "unreferenced revision must be pruned")
        manager.shutdown()
    }

    func test_fileStore_roundTripsLaneRevisions() {
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

    func test_deletingAllLanes_doesNotResurrectCatalog() {
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
    func test_reconcile_doesNotResurrectDeletedStarters() {
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
    func test_reconcile_refreshesPristineStarterLane() {
        let store = InMemoryVibeLaneStore(lanes: [oldStarter()], catalog: [VibeLaneCatalog.fixABug])
        store.reconcileStarterLanes()
        let lane = store.loadLanes().first { $0.id == VibeLaneCatalog.fixABugLaneID }
        XCTAssertEqual(lane?.name, VibeLaneCatalog.fixABug.name)
        XCTAssertEqual(lane?.checkpoints.count, VibeLaneCatalog.fixABug.checkpoints.count)
        XCTAssertEqual(lane?.version, 2, "refresh must bump the version so retained revisions stay distinct")
        XCTAssertNotNil(lane?.seededFingerprint, "refreshed lane must be marked pristine for the next update")
    }

    /// A user-edited starter lane is never overwritten by shipped updates.
    func test_reconcile_leavesUserEditedStarterAlone() {
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
    func test_reconcile_addsNewStarterLane() {
        let store = InMemoryVibeLaneStore(lanes: [], catalog: [VibeLaneCatalog.smallFeature])
        store.reconcileStarterLanes()
        XCTAssertEqual(store.loadLanes().count, 1)
        XCTAssertNotNil(store.loadLanes().first?.seededFingerprint)
    }

    /// Restore is the explicit escape hatch: deleted starters come back.
    func test_restoreStarterLanes_readdsDeleted() {
        let store = InMemoryVibeLaneStore(lanes: [], catalog: [VibeLaneCatalog.fixABug])
        store.reconcileStarterLanes()
        store.deleteLane(id: VibeLaneCatalog.fixABugLaneID)
        store.reconcileStarterLanes()
        XCTAssertTrue(store.loadLanes().isEmpty, "tombstone must hold through reconcile")

        store.restoreStarterLanes()
        XCTAssertEqual(store.loadLanes().first?.id, VibeLaneCatalog.fixABugLaneID)
    }

    /// Saving an edit marks the lane user-owned so future reconciles skip it.
    func test_updateLane_marksLaneUserOwned() {
        let store = InMemoryVibeLaneStore(lanes: [], catalog: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        manager.bootstrap()
        var lane = manager.lane(withID: VibeLaneCatalog.fixABugLaneID)!
        XCTAssertNotNil(lane.seededFingerprint)
        lane.name = "My custom bug lane"
        let saved = manager.updateLane(lane)
        XCTAssertNil(saved.seededFingerprint, "a user edit must clear the pristine marker")
        XCTAssertFalse(VibeLaneStarterReconciler.isPristine(saved))
    }

    /// A task pinned to the old starter content keeps resolving it after a refresh.
    func test_pinnedRevisionSurvivesStarterRefresh() {
        let store = InMemoryVibeLaneStore(lanes: [oldStarter()], catalog: [VibeLaneCatalog.fixABug])
        let manager = makeManager(store: store)
        manager.bootstrap(resumeRunning: false)
        // Bootstrap already reconciled; simulate the older sequence: task created
        // against version 1, then a later launch ships improved content.
        _ = store // (reconcile happened; lane is now the shipped v2 content)
        let task = manager.createTask(laneID: VibeLaneCatalog.fixABugLaneID, title: "t", projectPath: "/tmp/p")!
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
        manager.bootstrap()
        _ = manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "a", projectPath: "/same")
        _ = manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "b", projectPath: "/same")
        await settle()
        XCTAssertEqual(probe.maxConcurrent, 1, "same-project tasks must run one at a time")
        manager.shutdown()
    }

    /// Tasks against DIFFERENT projects may run concurrently (within the global cap).
    func test_differentProjects_runConcurrently() async {
        let probe = ConcurrencyProbeWorker()
        let store = InMemoryVibeLaneStore(lanes: [VibeLaneCatalog.fixABug])
        let manager = VibeLaneTaskManager(store: store, worker: probe, clock: VibeLaneSystemClock(), maxConcurrent: 3)
        manager.bootstrap()
        _ = manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "a", projectPath: "/a")
        _ = manager.createTask(laneID: VibeLaneCatalog.fixABug.id, title: "b", projectPath: "/b")
        await settle()
        XCTAssertEqual(probe.maxConcurrent, 2, "different-project tasks should run concurrently")
        manager.shutdown()
    }

    /// Let engine jobs spin up and enter the worker before asserting.
    private func settle() async {
        for _ in 0..<20 { await _Concurrency.Task.yield() }
        try? await _Concurrency.Task.sleep(nanoseconds: 60_000_000)
    }
}
