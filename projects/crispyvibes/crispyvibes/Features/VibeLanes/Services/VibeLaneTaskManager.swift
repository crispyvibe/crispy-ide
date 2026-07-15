import Combine
import Foundation
import OSLog

// F059 — the execution component's public face. Owns the set of tasks and lanes,
// runs engines, persists every transition, and publishes state for the UI to
// render. The UI never reaches past this object.
//
// The implementation is split for size/cohesion (coding-guidelines, "types over
// 200 LOC: split impl into extensions in separate files"):
//   • VibeLaneTaskManager+Scheduling.swift    — which tasks run and when
//   • VibeLaneTaskManager+LaneAuthoring.swift  — lane create/update/delete
// The shared stored dependencies below are `internal` (not `private`) so those
// same-module extensions can reach them. The observable collections stay
// `@Published private(set)` and are mutated only through methods in THIS file.

@MainActor
final class VibeLaneTaskManager: ObservableObject {
    @Published private(set) var tasks: [VibeLaneTask] = []
    @Published private(set) var lanes: [VibeLaneDefinition] = []

    let store: VibeLaneStoring
    let worker: VibeLaneWorkRunning
    let reviewer: VibeLaneReviewing
    let skillsRoot: URL?
    /// Root directory for per-task handoff files (durable carry-forward substrate).
    let handoffRoot: URL?
    /// Notifies the user when a task transitions into Needs you. nil = silent (tests).
    let notifier: VibeLaneNotifying?
    /// F060 — observes every persisted state transition (old != new). The todo
    /// pipeline bridge is the sole consumer; nil = no observer. Fired from
    /// `upsert`, the single writer of `tasks`, so no transition can bypass it.
    var onTaskStateChanged: ((UUID, VibeLaneTaskState, VibeLaneTaskState) -> Void)?
    let clock: VibeLaneClock
    let maxConcurrent: Int
    /// Conservative default cap on tasks running concurrently across all projects.
    /// Combined with per-project serialization (at most one running task per
    /// project path), this bounds unattended agent activity so multiple tasks
    /// can't edit the same project at once (finding #7 / threat-model residual risk).
    nonisolated static let defaultMaxConcurrent = 4
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app", category: "vibelanes")

    /// In-flight engine jobs by task id (accessed by the +Scheduling extension).
    var running: [UUID: _Concurrency.Task<Void, Never>] = [:]
    /// Per-task run generation. Bumped on stop/delete/resume so a late engine
    /// transition from a superseded run can't resurrect or clobber the task
    /// (accessed by the +Scheduling extension).
    var generation: [UUID: Int] = [:]

    init(
        store: VibeLaneStoring,
        worker: VibeLaneWorkRunning,
        reviewer: VibeLaneReviewing? = nil,
        skillsRoot: URL? = nil,
        handoffRoot: URL? = nil,
        notifier: VibeLaneNotifying? = nil,
        clock: VibeLaneClock = VibeLaneSystemClock(),
        maxConcurrent: Int = VibeLaneTaskManager.defaultMaxConcurrent
    ) {
        self.store = store
        self.worker = worker
        self.reviewer = reviewer ?? VibeLaneUnavailableReviewer()
        self.skillsRoot = skillsRoot
        self.handoffRoot = handoffRoot
        self.notifier = notifier
        self.clock = clock
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Lifecycle

    /// Load lanes + tasks from the store and resume tasks that were running,
    /// validating each against its lane before replaying (R07 / S07). Shipped
    /// starter lanes are reconciled first (seed / refresh pristine / honor
    /// deletions) so catalog improvements reach users who never edited them.
    func bootstrap(resumeRunning: Bool = true) {
        store.reconcileStarterLanes()
        lanes = store.loadLanes()
        let loaded = store.loadTasks()
        var resumable: [VibeLaneTask] = []
        for task in loaded {
            guard let lane = resolvedLane(for: task),
                  task.isConsistent(with: lane) else {
                logger.warning("vibelane task \(task.id.uuidString, privacy: .public) refused: inconsistent persisted state")
                continue
            }
            resumable.append(task)
        }
        tasks = resumable.sorted { $0.updatedAt > $1.updatedAt }
        if resumeRunning {
            for task in tasks where task.state == .running {
                startIfCapacity(task)
            }
            scheduleQueued()
        }
    }

    // MARK: - Reads

    /// Look up a lane by id. When `version` is provided the match is strict — no
    /// fallback to a different (e.g. newer) version — so a task's pinned version
    /// is never silently swapped for an edited lane.
    func lane(withID id: UUID, version: Int? = nil) -> VibeLaneDefinition? {
        guard let version else { return lanes.first { $0.id == id } }
        return lanes.first { $0.id == id && $0.version == version }
    }

    func task(withID id: UUID) -> VibeLaneTask? { tasks.first { $0.id == id } }

    /// The lane a task actually runs and renders against. Prefer the retained
    /// revision so catalog/template edits cannot silently change an existing task
    /// that pinned the same id/version.
    func resolvedLane(for task: VibeLaneTask) -> VibeLaneDefinition? {
        store.laneRevision(id: task.laneID, version: task.laneVersion)
            ?? lane(withID: task.laneID, version: task.laneVersion)
    }

    var runningCount: Int { tasks.filter { $0.state == .running }.count }
    var needsInputCount: Int { tasks.filter { $0.state == .needsInput }.count }
    var stoppedCount: Int { tasks.filter { $0.state == .stopped }.count }
    var doneCount: Int { tasks.filter { $0.state == .done }.count }

    // MARK: - Commands (UI → execution)

    @discardableResult
    func createTask(
        laneID: UUID,
        title: String,
        projectPath: String,
        agentID: String? = nil,
        initialCarryForward: [String: String]? = nil
    ) -> VibeLaneTask? {
        guard let lane = lane(withID: laneID), let first = lane.firstCheckpoint else {
            logger.warning("createTask: lane \(laneID.uuidString, privacy: .public) not found or empty")
            return nil
        }
        store.archiveLaneRevision(lane)
        // F060 — seeded carry-forward lets a dispatched todo satisfy the first
        // checkpoint's `requires` contract without an immediate Supply pause.
        // Same trust class as Supply answers; empty values are dropped.
        let seeded = initialCarryForward?
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        let task = VibeLaneTask(
            projectPath: projectPath,
            title: title,
            laneID: lane.id,
            laneVersion: lane.version,
            agentID: agentID,
            state: .running,
            currentCheckpointKey: first.key,
            carryForward: (seeded?.isEmpty == false) ? seeded : nil,
            repoBaselineRef: VibeLaneGit.head(projectPath)
        )
        upsert(task)
        store.saveTask(task)
        startIfCapacity(task)
        return task
    }

    func stop(id: UUID) {
        generation[id] = (generation[id] ?? 0) + 1
        running[id]?.cancel()
        running[id] = nil
        guard var task = task(withID: id), !task.isTerminal else { return }
        if var run = task.run(forKey: task.currentCheckpointKey) {
            run.status = .stopped
            run.stopReason = .stoppedByUser
            run.endedAt = clock.now
            replace(run: run, in: &task)
        }
        task.state = .stopped
        task.stopReason = .stoppedByUser
        task.openInputRequest = nil
        let activity = AppStrings.VibeLanes.activityStopped(AppStrings.VibeLanes.reasonStoppedByYou)
        task.currentActivity = activity
        var log = task.activityLog ?? []
        log.append(VibeLaneActivityLogEntry(at: clock.now, kind: .system, message: activity))
        task.activityLog = log
        task.updatedAt = clock.now
        upsert(task)
        store.saveTask(task)
        releaseSessions(for: task)
        scheduleQueued()
    }

    @discardableResult
    func answerInput(id: UUID, requestID: UUID, values: [String: String]) -> VibeLaneTask? {
        guard var task = validInputTask(id: id, requestID: requestID, kind: .supply),
              let request = task.openInputRequest else { return nil }
        var cleaned: [String: String] = [:]
        for key in request.missingKeys {
            let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return nil }
            cleaned[key] = value
        }
        var carried = task.carryForward ?? [:]
        for (key, value) in cleaned { carried[key] = value }
        task.carryForward = carried
        return resumeFromInput(&task)
    }

    @discardableResult
    func answerInput(id: UUID, requestID: UUID, guidance: String) -> VibeLaneTask? {
        let cleaned = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard var task = validInputTask(id: id, requestID: requestID, kind: .steer),
              let request = task.openInputRequest,
              var run = task.run(forKey: task.currentCheckpointKey) else { return nil }
        task.pendingSteerGuidance = Self.combinedSteerFeedback(
            reviewerFeedback: request.lastFeedback,
            userGuidance: cleaned
        )
        task.steerCount += 1
        let now = clock.now
        run.budgetEpoch += 1
        run.status = .running
        run.stopReason = nil
        run.endedAt = nil
        run.activeWindowStartedAt = now
        replace(run: run, in: &task)
        return resumeFromInput(&task, now: now)
    }

    /// Answer a human-review request: the user verifies the checkpoint's outcome
    /// themselves. Approve records a PASS; rejection requires feedback, which
    /// loops back to the worker exactly like a reviewer FAIL.
    @discardableResult
    func answerInput(id: UUID, requestID: UUID, approved: Bool, feedback: String? = nil) -> VibeLaneTask? {
        let cleaned = feedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard approved || !cleaned.isEmpty else { return nil }
        guard var task = validInputTask(id: id, requestID: requestID, kind: .review) else { return nil }
        task.pendingHumanVerdict = VibeLaneVerificationResult(
            passed: approved,
            detail: approved ? AppStrings.VibeLanes.approvedByYou : nil,
            feedback: approved ? nil : cleaned
        )
        return resumeFromInput(&task)
    }

    func delete(id: UUID) {
        generation[id] = (generation[id] ?? 0) + 1
        running[id]?.cancel()
        running[id] = nil
        if let task = task(withID: id) { releaseSessions(for: task) }
        tasks.removeAll { $0.id == id }
        store.deleteTask(id: id)
        removeHandoffFiles(taskID: id)
        pruneLaneRevisions()
    }

    /// Cancel all in-flight engine tasks and release their sessions (call on shutdown).
    func shutdown() {
        for task in running.values { task.cancel() }
        running.removeAll()
        for task in tasks { releaseSessions(for: task) }
    }

    func releaseSessions(for task: VibeLaneTask) {
        worker.release(sessionRef: task.workerSessionRef)
        reviewer.release(sessionRef: task.reviewerSessionRef)
    }

    private func validInputTask(id: UUID, requestID: UUID, kind: VibeLaneInputRequestKind) -> VibeLaneTask? {
        guard let task = task(withID: id),
              task.state == .needsInput,
              let request = task.openInputRequest,
              request.id == requestID,
              request.kind == kind,
              request.checkpointKey == task.currentCheckpointKey else {
            return nil
        }
        return task
    }

    private func resumeFromInput(_ task: inout VibeLaneTask, now: Date? = nil) -> VibeLaneTask {
        generation[task.id] = (generation[task.id] ?? 0) + 1
        let timestamp = now ?? clock.now
        if var run = task.run(forKey: task.currentCheckpointKey) {
            run.status = .running
            run.stopReason = nil
            run.endedAt = nil
            run.activeWindowStartedAt = timestamp
            replace(run: run, in: &task)
        }
        task.state = .running
        task.stopReason = nil
        task.openInputRequest = nil
        task.updatedAt = timestamp
        upsert(task)
        store.saveTask(task)
        startIfCapacity(task)
        return task
    }

    private static func combinedSteerFeedback(reviewerFeedback: String?, userGuidance: String) -> String {
        let feedback = reviewerFeedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !feedback.isEmpty else { return userGuidance }
        return """
        \(AppStrings.VibeLanes.reviewerFeedbackBeforeSteering)
        \(feedback)

        \(AppStrings.VibeLanes.userSteeringGuidance)
        \(userGuidance)
        """
    }

    private func replace(run: VibeLaneCheckpointRun, in task: inout VibeLaneTask) {
        if let idx = task.checkpointRuns.firstIndex(where: { $0.checkpointKey == run.checkpointKey }) {
            task.checkpointRuns[idx] = run
        } else {
            task.checkpointRuns.append(run)
        }
    }

    // MARK: - State

    /// Insert or replace a task. The sole writer of `tasks`, keeping the
    /// `@Published private(set)` setter local to this file. Detecting the
    /// transition INTO `needsInput` here (the single chokepoint) is what fires
    /// the Needs-you notification exactly once per open request.
    func upsert(_ task: VibeLaneTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            let previous = tasks[idx]
            tasks[idx] = task
            if task.state == .needsInput, previous.state != .needsInput {
                notifier?.notifyNeedsInput(task)
            }
            if task.state != previous.state {
                onTaskStateChanged?(task.id, previous.state, task.state)
            }
        } else {
            tasks.insert(task, at: 0)
            if task.state == .needsInput {
                notifier?.notifyNeedsInput(task)
            }
        }
    }

    /// Reload the published lane list from the store. Kept in this file so the
    /// `@Published private(set) lanes` setter stays private here; the authoring
    /// extension calls this after mutating lanes in the store.
    func reloadLanes() {
        lanes = store.loadLanes().sorted { $0.name < $1.name }
    }

    /// Drop retained lane revisions no living task pins.
    private func pruneLaneRevisions() {
        let keep = Set(tasks.map { VibeLaneRevisionKey(laneID: $0.laneID, version: $0.laneVersion) })
        store.pruneLaneRevisions(keep: keep)
    }

    /// Remove a deleted task's persisted handoff files.
    private func removeHandoffFiles(taskID: UUID) {
        guard let root = handoffRoot else { return }
        let dir = root.appendingPathComponent(taskID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
