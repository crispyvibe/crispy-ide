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
// same-module extensions can reach them. Observable state remains
// `@Published private(set)` and extensions publish through the helpers below.

@MainActor
final class VibeLaneTaskManager: ObservableObject {
    @Published private(set) var tasks: [VibeLaneTask] = []
    @Published private(set) var lanes: [VibeLaneDefinition] = []
    @Published private(set) var vibes: [VibeDefinition] = []
    @Published private(set) var persistenceError: String?
    @Published private(set) var hasBootstrapped = false

    let store: VibeLanePersisting
    let worker: VibeLaneWorkRunning
    let reviewer: VibeLaneReviewing
    let engineOptionCatalog: ACPAgentEngineOptionCatalog
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
    /// Internal (not private) so the split extensions in
    /// `VibeLaneTaskManager+*.swift` can log against the same category.
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app", category: "vibelanes")

    /// In-flight engine jobs by task id (accessed by the +Scheduling extension).
    var running: [UUID: _Concurrency.Task<Void, Never>] = [:]
    /// Per-task run generation. Bumped on stop/delete/resume so a late engine
    /// transition from a superseded run can't resurrect or clobber the task
    /// (accessed by the +Scheduling extension).
    var generation: [UUID: Int] = [:]
    /// Prevents cancelled completion handlers from scheduling new work while
    /// application teardown is in progress.
    var isShuttingDown = false
    /// Enforces checkpoint deadlines independently of ACP prompt completion.
    /// Some agents can leave a session/prompt request open indefinitely.
    var timeoutMonitor: _Concurrency.Task<Void, Never>?
    var laneRevisions: [VibeLaneRevisionKey: VibeLaneDefinition] = [:]
    var vibeRevisions: [VibeRevisionKey: VibeDefinition] = [:]
    /// Task commands that have invalidated an engine generation but have not
    /// yet committed their authoritative durable state.
    var taskCommandPersistence: Set<UUID> = []

    init(
        store: VibeLanePersisting,
        worker: VibeLaneWorkRunning,
        reviewer: VibeLaneReviewing? = nil,
        engineOptionCatalog: ACPAgentEngineOptionCatalog? = nil,
        skillsRoot: URL? = nil,
        handoffRoot: URL? = nil,
        notifier: VibeLaneNotifying? = nil,
        clock: VibeLaneClock = VibeLaneSystemClock(),
        maxConcurrent: Int = VibeLaneTaskManager.defaultMaxConcurrent
    ) {
        self.store = store
        self.worker = worker
        self.reviewer = reviewer ?? VibeLaneUnavailableReviewer()
        self.engineOptionCatalog = engineOptionCatalog ?? ACPAgentEngineOptionCatalog()
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
    func bootstrap(resumeRunning: Bool = true) async {
        let snapshot: VibeLanePersistenceSnapshot
        do {
            snapshot = try await store.reconcileStarterLanesPersisted()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            hasBootstrapped = true
            return
        }
        apply(snapshot)
        var resumable: [VibeLaneTask] = []
        for task in snapshot.tasks {
            guard let lane = resolvedLane(for: task),
                  task.isConsistent(with: lane) else {
                logger.warning("vibelane task \(task.id.uuidString, privacy: .public) refused: inconsistent persisted state")
                continue
            }
            resumable.append(task)
        }
        tasks = resumable.sorted { $0.updatedAt > $1.updatedAt }
        hasBootstrapped = true
        if resumeRunning {
            await enforceCheckpointTimeouts()
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

    func vibe(withID id: UUID, version: Int? = nil) -> VibeDefinition? {
        guard let version else { return vibes.first { $0.id == id } }
        if let current = vibes.first(where: { $0.id == id && $0.version == version }) {
            return current
        }
        return vibeRevisions[VibeRevisionKey(vibeID: id, version: version)]
    }

    func latestVibe(for checkpoint: VibeLaneCheckpoint) -> VibeDefinition? {
        guard let vibeID = checkpoint.vibeID else { return nil }
        return vibe(withID: vibeID)
    }

    func vibeUsageCount(id: UUID) -> Int {
        lanes.reduce(into: 0) { count, lane in
            count += lane.checkpoints.filter { $0.vibeID == id }.count
        }
    }

    func task(withID id: UUID) -> VibeLaneTask? { tasks.first { $0.id == id } }

    func isExecuting(taskID: UUID) -> Bool {
        running[taskID] != nil
    }

    func task(withOccurrenceID occurrenceID: UUID) -> VibeLaneTask? {
        tasks.first { $0.origin.occurrenceID == occurrenceID }
    }

    /// The lane a task actually runs and renders against. Prefer the retained
    /// revision so catalog/template edits cannot silently change an existing task
    /// that pinned the same id/version.
    func resolvedLane(for task: VibeLaneTask) -> VibeLaneDefinition? {
        laneRevisions[VibeLaneRevisionKey(laneID: task.laneID, version: task.laneVersion)]
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
    ) async -> VibeLaneTask? {
        guard let lane = lane(withID: laneID) else {
            logger.warning("createTask: lane \(laneID.uuidString, privacy: .public) not found or empty")
            return nil
        }
        return await createTask(
            laneSnapshot: lane,
            title: title,
            projectPath: projectPath,
            agentID: agentID,
            origin: .manual,
            initialCarryForward: initialCarryForward
        )
    }

    /// Creates a task from an exact immutable lane snapshot. Loops use this
    /// overload so future edits to the source lane cannot change unattended
    /// work, and occurrence IDs make retries idempotent.
    @discardableResult
    func createTask(
        laneSnapshot lane: VibeLaneDefinition,
        title: String,
        projectPath: String,
        agentID: String? = nil,
        origin: VibeLaneTaskOrigin,
        initialCarryForward: [String: String]? = nil
    ) async -> VibeLaneTask? {
        if let occurrenceID = origin.occurrenceID,
           let existing = task(withOccurrenceID: occurrenceID) {
            return existing
        }
        guard lane.isRunnable else {
            logger.warning("createTask: lane \(lane.id.uuidString, privacy: .public) needs setup")
            return nil
        }
        guard let first = lane.firstCheckpoint else {
            logger.warning("createTask: lane \(lane.id.uuidString, privacy: .public) is empty")
            return nil
        }
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
            origin: origin,
            state: .running,
            currentCheckpointKey: first.key,
            carryForward: (seeded?.isEmpty == false) ? seeded : nil
        )
        do {
            try await store.persistTask(task)
        } catch {
            logger.error("createTask: could not durably save task \(task.id.uuidString, privacy: .public)")
            persistenceError = error.localizedDescription
            return nil
        }
        laneRevisions[VibeLaneRevisionKey(laneID: lane.id, version: lane.version)] = lane
        persistenceError = nil
        upsert(task)
        startIfCapacity(task)
        return task
    }

    @discardableResult
    func stop(id: UUID) async -> Bool {
        guard let original = task(withID: id), !original.isTerminal else {
            return false
        }
        var task = original
        if var run = task.run(forKey: task.currentCheckpointKey) {
            run.status = .stopped
            run.stopReason = .stoppedByUser
            run.endedAt = clock.now
            replace(run: run, in: &task)
        }
        task.state = .stopped
        task.stopReason = .stoppedByUser
        task.openInputRequest = nil
        task.pendingHumanEngine = nil
        task.rerunRequest = nil
        let activity = AppStrings.VibeLanes.activityStopped(AppStrings.VibeLanes.reasonStoppedByYou)
        task.currentActivity = activity
        var log = task.activityLog ?? []
        log.append(VibeLaneActivityLogEntry(at: clock.now, kind: .system, message: activity))
        task.activityLog = log
        task.updatedAt = clock.now
        generation[id] = (generation[id] ?? 0) + 1
        running[id]?.cancel()
        running[id] = nil
        taskCommandPersistence.insert(id)
        do {
            try await store.persistTask(task)
        } catch {
            taskCommandPersistence.remove(id)
            logger.error("stop: could not durably save task \(task.id.uuidString, privacy: .public)")
            persistenceError = error.localizedDescription
            if original.state == .running {
                startIfCapacity(original)
            }
            return false
        }
        persistenceError = nil
        upsert(task)
        taskCommandPersistence.remove(id)
        releaseSessions(for: task)
        scheduleQueued()
        return true
    }

    @discardableResult
    func answerInput(
        id: UUID,
        requestID: UUID,
        values: [String: String]
    ) async -> VibeLaneTask? {
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
        return await resumeFromInput(&task)
    }

    @discardableResult
    func answerInput(
        id: UUID,
        requestID: UUID,
        guidance: String
    ) async -> VibeLaneTask? {
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
        return await resumeFromInput(&task, now: now)
    }

    /// Answer a human-review request: the user verifies the checkpoint's outcome
    /// themselves. Approve records a PASS; rejection requires feedback, which
    /// loops back to the worker exactly like a reviewer FAIL.
    @discardableResult
    func answerInput(
        id: UUID,
        requestID: UUID,
        approved: Bool,
        feedback: String? = nil
    ) async -> VibeLaneTask? {
        let cleaned = feedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard approved || !cleaned.isEmpty else { return nil }
        guard var task = validInputTask(id: id, requestID: requestID, kind: .review) else { return nil }
        task.pendingHumanVerdict = VibeLaneVerificationResult(
            passed: approved,
            detail: approved ? AppStrings.VibeLanes.approvedByYou : nil,
            feedback: approved ? nil : cleaned
        )
        return await resumeFromInput(&task)
    }

    /// Delete a task and its durable row. Returns false when the durable delete
    /// failed — the task is then still present, so callers (notably the CLI) must
    /// not report success.
    @discardableResult
    func delete(id: UUID) async -> Bool {
        let existing = task(withID: id)
        generation[id] = (generation[id] ?? 0) + 1
        running[id]?.cancel()
        running[id] = nil
        taskCommandPersistence.insert(id)
        do {
            try await store.removeTask(id: id)
        } catch {
            taskCommandPersistence.remove(id)
            persistenceError = error.localizedDescription
            if existing?.state == .running, let existing {
                startIfCapacity(existing)
            }
            return false
        }
        if let existing { releaseSessions(for: existing) }
        tasks.removeAll { $0.id == id }
        taskCommandPersistence.remove(id)
        persistenceError = nil
        removeHandoffFiles(taskID: id)
        scheduleQueued()
        return true
    }

    /// Cancel all in-flight engine tasks and release their sessions (call on shutdown).
    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        for id in running.keys {
            generation[id] = (generation[id] ?? 0) + 1
        }
        for task in running.values {
            task.cancel()
        }
        running.removeAll()
        timeoutMonitor?.cancel()
        timeoutMonitor = nil
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

    private func resumeFromInput(
        _ task: inout VibeLaneTask,
        now: Date? = nil
    ) async -> VibeLaneTask? {
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
        do {
            try await store.persistTask(task)
        } catch {
            persistenceError = error.localizedDescription
            return nil
        }
        persistenceError = nil
        upsert(task)
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

    func replace(run: VibeLaneCheckpointRun, in task: inout VibeLaneTask) {
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

    func apply(_ snapshot: VibeLanePersistenceSnapshot) {
        lanes = snapshot.lanes.sorted { $0.name < $1.name }
        vibes = snapshot.vibes.sorted { $0.name < $1.name }
        laneRevisions = Dictionary(
            uniqueKeysWithValues: snapshot.laneRevisions.map {
                (VibeLaneRevisionKey(laneID: $0.id, version: $0.version), $0)
            }
        )
        vibeRevisions = Dictionary(
            uniqueKeysWithValues: snapshot.vibeRevisions.map {
                (VibeRevisionKey(vibeID: $0.id, version: $0.version), $0)
            }
        )
    }

    func publishCurrentLane(_ lane: VibeLaneDefinition) {
        lanes.removeAll { $0.id == lane.id }
        lanes.append(lane)
        lanes.sort { $0.name < $1.name }
    }

    func removePublishedLane(id: UUID) {
        lanes.removeAll { $0.id == id }
    }

    func publishCurrentVibe(_ vibe: VibeDefinition) {
        vibes.removeAll { $0.id == vibe.id }
        vibes.append(vibe)
        vibes.sort { $0.name < $1.name }
    }

    func removePublishedVibe(id: UUID) {
        vibes.removeAll { $0.id == id }
    }

    func recordPersistenceResult(_ error: Error?) {
        persistenceError = error?.localizedDescription
    }

    /// Surface a domain-level write refusal (e.g. a stale-revision conflict) that
    /// is not an underlying store error.
    func recordPersistenceMessage(_ message: String?) {
        persistenceError = message
    }

    /// Remove a deleted task's persisted handoff files.
    private func removeHandoffFiles(taskID: UUID) {
        guard let root = handoffRoot else { return }
        let dir = root.appendingPathComponent(taskID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
