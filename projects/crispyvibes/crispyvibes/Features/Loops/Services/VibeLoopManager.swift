import Combine
import Foundation

protocol VibeLoopClock: Sendable {
    var now: Date { get }
}

struct VibeLoopSystemClock: VibeLoopClock {
    var now: Date { Date() }
}

@MainActor
final class VibeLoopManager: ObservableObject {
    // Mutation-through-methods: every write routes through `commitState` (which
    // persists first) or `bootstrap`, so the setters stay file-private.
    @Published private(set) var definitions: [VibeLoopDefinition] = []
    @Published private(set) var runtimeStates: [UUID: VibeLoopRuntimeState] = [:]
    @Published private(set) var runRecords: [VibeLoopRunRecord] = []
    @Published private(set) var observedLaneTasks: [UUID: VibeLaneTask] = [:]
    @Published private(set) var observedLanes: [VibeLaneDefinition] = []
    @Published private(set) var persistenceError: String?

    let store: VibeLoopPersisting
    let laneManager: VibeLaneTaskManager
    let clock: VibeLoopClock
    var onScheduleChanged: (() -> Void)?
    var hasBootstrapped = false

    /// Set when loading durable state failed. While true the in-memory
    /// collections are NOT known to reflect the store, so writes are refused
    /// rather than persisting a partial view over good data.
    private(set) var hasUnreadablePersistedState = false

    private let fileManager: FileManager
    private var laneObservations: Set<AnyCancellable> = []
    /// One reconciliation at a time. Lane-task publications arrive in bursts and
    /// each reconciliation persists the whole loop state, so overlapping runs
    /// could commit a snapshot built from stale collections.
    private var reconciliationTask: Task<Void, Never>?
    private var reconciliationPending = false

    init(
        store: VibeLoopPersisting,
        laneManager: VibeLaneTaskManager,
        clock: VibeLoopClock = VibeLoopSystemClock(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.laneManager = laneManager
        self.clock = clock
        self.fileManager = fileManager
        laneManager.$tasks
            .sink { [weak self] tasks in
                guard let self else { return }
                let indexed = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
                if indexed != self.observedLaneTasks {
                    self.observedLaneTasks = indexed
                }
                if self.hasBootstrapped {
                    self.scheduleReconciliation()
                }
            }
            .store(in: &laneObservations)
        laneManager.$lanes
            .sink { [weak self] lanes in
                guard let self, lanes != self.observedLanes else { return }
                self.observedLanes = lanes
            }
            .store(in: &laneObservations)
    }

    /// Coalesce reconciliation into a single tracked task. A publication that
    /// arrives while one is in flight sets a pending flag instead of starting a
    /// second concurrent pass.
    private func scheduleReconciliation() {
        guard reconciliationTask == nil else {
            reconciliationPending = true
            return
        }
        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.reconciliationPending = false
                await self.reconcileLaneTaskStates(Array(self.observedLaneTasks.values))
            } while self.reconciliationPending && !Task.isCancelled
            self.reconciliationTask = nil
        }
    }

    /// Release the lane observations and stop any in-flight reconciliation.
    func shutdown() {
        reconciliationTask?.cancel()
        reconciliationTask = nil
        reconciliationPending = false
        laneObservations.removeAll()
        onScheduleChanged = nil
    }

    /// Replace one loop's transient runtime projection in memory only.
    ///
    /// Runtime state is normally derived and committed together with its run
    /// record through `commitState`. This seam exists so projection tests can set
    /// up a state combination directly (matching the existing `...ForTesting`
    /// convention elsewhere in the app) without opening the published setter.
    func setRuntimeStateForTesting(_ state: VibeLoopRuntimeState?, id: UUID) {
        runtimeStates[id] = state
    }

    func bootstrap() async {
        do {
            let state = try await store.loadPersistedState()
            definitions = sortedDefinitions(state.definitions)
            runtimeStates = Dictionary(
                state.runtimeStates.map { ($0.loopID, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            runRecords = state.runRecords.sorted { $0.scheduledAt > $1.scheduledAt }
            persistenceError = nil
            hasUnreadablePersistedState = false
        } catch {
            // Keep whatever is already in memory. Clearing to empty here would
            // make the surface look like "no schedules yet", and the next save
            // would persist that empty view over the durable state.
            hasUnreadablePersistedState = true
            persistenceError = AppStrings.Loops.persistenceUnavailable
        }
        hasBootstrapped = true
        await reconcileLaneTaskStates(Array(observedLaneTasks.values))
        await recoverPendingOccurrences()
    }

    func definition(withID id: UUID) -> VibeLoopDefinition? {
        definitions.first { $0.id == id }
    }

    func runs(for loopID: UUID) -> [VibeLoopRunRecord] {
        runRecords.filter { $0.loopID == loopID }.sorted { $0.scheduledAt > $1.scheduledAt }
    }

    func latestLane(for definition: VibeLoopDefinition) -> VibeLaneDefinition? {
        observedLanes.first { $0.id == definition.laneID }
    }

    func hasLaneUpdate(for definition: VibeLoopDefinition) -> Bool {
        guard let current = latestLane(for: definition) else { return false }
        return current.version != definition.laneVersion
    }

    @discardableResult
    func save(_ proposed: VibeLoopDefinition) async -> Bool {
        var definition = proposed
        definition.name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        definition.taskInstruction = definition.taskInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        definition.projectPath = URL(fileURLWithPath: definition.projectPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        definition.laneID = definition.laneSnapshot.id
        definition.laneVersion = definition.laneSnapshot.version
        definition.updatedAt = clock.now
        guard validationFailure(for: definition) == nil else { return false }

        var updatedDefinitions = definitions
        var updatedRuntime = runtimeStates
        if let existing = self.definition(withID: definition.id) {
            let restartsCadence = existing.schedule != definition.schedule
                || (!existing.isEnabled && definition.isEnabled)
            var runtime = updatedRuntime[definition.id] ?? VibeLoopRuntimeState(loopID: definition.id)
            if restartsCadence {
                runtime.lastClaimedScheduledAt = clock.now
            }
            if runtime.lastFailure != nil {
                runtime.lastFailure = nil
            }
            if runtime != updatedRuntime[definition.id] {
                updatedRuntime[definition.id] = runtime
            }
            updatedDefinitions.removeAll { $0.id == definition.id }
        }
        updatedDefinitions.append(definition)
        updatedDefinitions = sortedDefinitions(updatedDefinitions)
        guard await commitState(
            definitions: updatedDefinitions,
            runtimeStates: updatedRuntime,
            runRecords: runRecords
        ) else {
            return false
        }
        onScheduleChanged?()
        return true
    }

    @discardableResult
    func setEnabled(
        _ enabled: Bool,
        id: UUID,
        confirmsFullTrust: Bool = false
    ) async -> Bool {
        guard var definition = definition(withID: id) else { return false }
        if !enabled {
            definition.isEnabled = false
            definition.updatedAt = clock.now
            var updatedDefinitions = definitions.filter { $0.id != id }
            updatedDefinitions.append(definition)
            guard await commitState(
                definitions: sortedDefinitions(updatedDefinitions),
                runtimeStates: runtimeStates,
                runRecords: runRecords
            ) else {
                return false
            }
            onScheduleChanged?()
            return true
        }
        if !confirmsFullTrust {
            return false
        }
        definition.isEnabled = true
        return await save(definition)
    }

    @discardableResult
    func delete(id: UUID, stopActiveRun: Bool = false) async -> Bool {
        let activeTaskID = activeTask(for: id)?.id
        if stopActiveRun, let activeTaskID {
            if definition(withID: id)?.isEnabled == true,
               !(await setEnabled(false, id: id)) {
                return false
            }
            guard await laneManager.stop(id: activeTaskID) else {
                return false
            }
        }
        var updatedRuntime = runtimeStates
        updatedRuntime[id] = nil
        guard await commitState(
            definitions: definitions.filter { $0.id != id },
            runtimeStates: updatedRuntime,
            runRecords: runRecords.filter { $0.loopID != id }
        ) else {
            return false
        }
        onScheduleChanged?()
        return true
    }

    func validationFailure(for definition: VibeLoopDefinition) -> VibeLoopFailure? {
        guard !definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !definition.taskInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return failure(.invalidLane, AppStrings.Loops.validationRequired)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: definition.projectPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return failure(.invalidProject, AppStrings.Loops.projectUnavailable)
        }
        guard definition.laneSnapshot.isRunnable,
              definition.laneID == definition.laneSnapshot.id,
              definition.laneVersion == definition.laneSnapshot.version else {
            return failure(.invalidLane, AppStrings.Loops.invalidLane)
        }
        guard (try? VibeLoopScheduleCalculator.validate(definition.schedule)) != nil else {
            return failure(.invalidSchedule, AppStrings.Loops.invalidSchedule)
        }
        return nil
    }

    func status(for definition: VibeLoopDefinition) -> VibeLoopStatus {
        state(for: definition).status
    }

    func state(for definition: VibeLoopDefinition) -> VibeLoopStateSnapshot {
        let schedule: VibeLoopScheduleState
        if !definition.isEnabled {
            schedule = .paused
        } else if runtimeStates[definition.id]?.lastFailure != nil {
            schedule = .blocked
        } else {
            schedule = .enabled
        }

        let tasks = activeTasks(for: definition.id)
        let attentionTask = tasks.first { $0.state == .needsInput }
        let activeTask = attentionTask ?? tasks.first
        let execution: VibeLoopExecutionState
        if attentionTask != nil {
            execution = .needsInput
        } else if activeTask != nil {
            execution = laneManager.isExecuting(taskID: activeTask!.id) ? .running : .queued
        } else {
            execution = .idle
        }
        return VibeLoopStateSnapshot(
            schedule: schedule,
            execution: execution,
            activeTaskID: activeTask?.id
        )
    }

    func activeTask(for loopID: UUID) -> VibeLaneTask? {
        activeTasks(for: loopID).first
    }

    func activeTasks(for loopID: UUID) -> [VibeLaneTask] {
        observedLaneTasks.values
            .filter { $0.origin.loopID == loopID && !$0.isTerminal }
            .sorted {
                if $0.state != $1.state {
                    if $0.state == .needsInput { return true }
                    if $1.state == .needsInput { return false }
                }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    @discardableResult
    func stopRun(loopID: UUID, taskID: UUID, pauseLoop: Bool) async -> Bool {
        guard let task = observedLaneTasks[taskID],
              task.origin.loopID == loopID,
              !task.isTerminal else {
            return false
        }
        if pauseLoop, !(await setEnabled(false, id: loopID)) {
            return false
        }
        return await laneManager.stop(id: taskID)
    }

    func nextRunDate(for definition: VibeLoopDefinition) -> Date? {
        guard definition.isEnabled else { return nil }
        return VibeLoopScheduleCalculator.nextOccurrence(
            for: definition,
            runtime: runtimeStates[definition.id]
        )
    }

    var attentionCount: Int {
        definitions.filter {
            let status = status(for: $0)
            return status == .needsInput || status == .blocked
        }.count
    }

    @discardableResult
    func persistCurrentState() async -> Bool {
        await commitState(
            definitions: definitions,
            runtimeStates: runtimeStates,
            runRecords: runRecords
        )
    }

    @discardableResult
    func commitState(
        definitions: [VibeLoopDefinition],
        runtimeStates: [UUID: VibeLoopRuntimeState],
        runRecords: [VibeLoopRunRecord]
    ) async -> Bool {
        // Refuse to write while the durable state is unknown: persisting the
        // current in-memory view would replace good rows with a partial one.
        guard !hasUnreadablePersistedState else {
            persistenceError = AppStrings.Loops.persistenceUnavailable
            return false
        }
        do {
            try await store.persistState(VibeLoopPersistedState(
                definitions: definitions,
                runtimeStates: Array(runtimeStates.values),
                runRecords: runRecords
            ))
            self.definitions = definitions
            self.runtimeStates = runtimeStates
            self.runRecords = runRecords
            persistenceError = nil
            return true
        } catch {
            persistenceError = AppStrings.Loops.persistenceUnavailable
            return false
        }
    }

    private func sortedDefinitions(_ definitions: [VibeLoopDefinition]) -> [VibeLoopDefinition] {
        definitions.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func failure(_ kind: VibeLoopFailureKind, _ detail: String) -> VibeLoopFailure {
        VibeLoopFailure(kind: kind, detail: detail, at: clock.now)
    }
}
