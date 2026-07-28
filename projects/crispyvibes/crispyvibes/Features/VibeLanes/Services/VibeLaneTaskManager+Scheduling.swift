import Foundation

// F059 — VibeLaneTaskManager scheduling. Decides which tasks run and when: the
// global concurrency cap, per-project serialization (at most one running task
// per project path), engine startup, and the per-run generation guard that keeps
// a superseded run from clobbering a task. Split from the core type per
// coding-guidelines ("types over 200 LOC: split impl into extensions").

extension VibeLaneTaskManager {

    /// Start `task` now if capacity allows; otherwise it stays `.running` in state
    /// and is picked up later by `scheduleQueued()`.
    func startIfCapacity(_ task: VibeLaneTask) {
        guard !isShuttingDown, task.state == .running else { return }
        ensureTimeoutMonitor()
        if canStart(task) {
            start(task)
        }
    }

    /// Start any queued (`.running` but not yet executing) tasks that now fit
    /// within the global cap and their project's single-task budget.
    func scheduleQueued() {
        guard !isShuttingDown, running.count < maxConcurrent else { return }
        let queued = tasks.filter { $0.state == .running && running[$0.id] == nil }
        for task in queued {
            if running.count >= maxConcurrent { break }
            if canStart(task) { start(task) }
        }
    }

    /// Rerun one previously attempted step with an attempt-local engine
    /// override. The lane revision and authored engine are not changed.
    @discardableResult
    func rerunStep(
        id: UUID,
        checkpointKey: String,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneTask? {
        guard var task = task(withID: id),
              task.isTerminal,
              task.rerunRequest == nil,
              let lane = resolvedLane(for: task),
              let checkpoint = lane.checkpoint(forKey: checkpointKey),
              var run = task.run(forKey: checkpointKey),
              // A step that died before verification (worker/tool error, missing
              // skill, or another pre-verification error) records no attempt, but it did
              // run — it must still be rerunnable, or the task is unrecoverable.
              run.startedAt != nil || !run.attempts.isEmpty else {
            return nil
        }

        generation[id] = (generation[id] ?? 0) + 1
        running[id]?.cancel()
        running[id] = nil
        releaseSessions(for: task)

        let now = clock.now
        task.rerunRequest = VibeLaneRerunRequest(
            checkpointKey: checkpointKey,
            visit: run.visit,
            engine: engine,
            previousState: task.state,
            previousStopReason: task.stopReason,
            previousCheckpointKey: task.currentCheckpointKey,
            previousVisit: task.currentVisit,
            previousActiveLoop: task.activeLoop,
            requestedAt: now
        )
        task.currentCheckpointKey = checkpointKey
        task.currentVisit = run.visit
        task.activeLoop = nil
        task.state = .running
        task.stopReason = nil
        task.openInputRequest = nil
        task.pendingHumanVerdict = nil
        task.pendingHumanEngine = nil
        task.pendingSteerGuidance = nil
        task.lastRerunCheckpointKey = nil

        run.budgetEpoch += 1
        run.rerunEpochCount += 1
        run.status = .running
        run.stopReason = nil
        run.endedAt = nil
        run.activeWindowStartedAt = now
        run.activeEngine = nil
        replace(run: run, in: &task)

        let activity = AppStrings.VibeLanes.activityRerunning(checkpoint.displayTitle)
        task.currentActivity = activity
        var log = task.activityLog ?? []
        log.append(VibeLaneActivityLogEntry(at: now, kind: .system, message: activity))
        task.activityLog = log
        task.updatedAt = now
        taskCommandPersistence.insert(id)
        do {
            try await store.persistTask(task)
        } catch {
            taskCommandPersistence.remove(id)
            recordPersistenceResult(error)
            return nil
        }
        recordPersistenceResult(nil)
        upsert(task)
        taskCommandPersistence.remove(id)
        startIfCapacity(task)
        return task
    }

    /// A task may start only if the global budget allows AND no other task is
    /// already running against the same project path. Per-project serialization
    /// keeps two unattended agents from mutating the same project at once.
    private func canStart(_ task: VibeLaneTask) -> Bool {
        guard task.state == .running else { return false }
        guard running.count < maxConcurrent else { return false }
        return !isProjectBusy(task.projectPath, excluding: task.id)
    }

    private func isProjectBusy(_ projectPath: String, excluding id: UUID) -> Bool {
        running.keys.contains { runningID in
            runningID != id && self.task(withID: runningID)?.projectPath == projectPath
        }
    }

    private func start(_ task: VibeLaneTask) {
        guard !isShuttingDown,
              task.state == .running,
              running[task.id] == nil,
              let lane = resolvedLane(for: task) else {
            return
        }
        // Fail closed at the single execution choke point. `createTask` already
        // refuses a non-runnable lane, but a resumed or queued task can reach
        // here after its pinned Vibe revision became unresolvable — which would
        // otherwise run a full-trust agent against an empty goal with no
        // verification. Covers bootstrap resume, scheduleQueued, and rerun.
        guard lane.isRunnable else {
            logger.warning(
                "vibelane task \(task.id.uuidString, privacy: .public) not started: pinned lane revision is not runnable"
            )
            return
        }
        let g = (generation[task.id] ?? 0) + 1
        generation[task.id] = g
        let engine = VibeLaneEngine(
            lane: lane,
            worker: worker,
            reviewer: reviewer,
            skillsRoot: skillsRoot,
            handoffRoot: handoffRoot,
            clock: clock,
            onTransition: { [weak self] updated in
                guard let self else { return }
                try await self.applyEngineTransition(updated, generation: g)
            }
        )
        let job = _Concurrency.Task { [weak self] in
            let result = await engine.run(task)
            guard let self else { return }
            // The engine has already halted; a failure here is recorded as a
            // persistence error and the task keeps its terminal in-memory state.
            try? await self.applyEngineTransition(result, generation: g)
            // Only the current run may finalize this task's slot/sessions.
            guard self.generation[task.id] == g else {
                return
            }
            if result.isTerminal {
                self.releaseSessions(for: result)
            }
            self.running[task.id] = nil
            self.scheduleQueued()
        }
        running[task.id] = job
    }

    /// Apply an engine-produced transition only if it belongs to the task's
    /// current run and the task still exists (so stop/delete/resume can't be
    /// undone by a superseded engine, and a deleted task can't be resurrected).
    ///
    /// Rethrows a persistence failure so the engine halts instead of running the
    /// next agent turn against a state it could not record.
    private func applyEngineTransition(
        _ task: VibeLaneTask,
        generation g: Int
    ) async throws {
        guard generation[task.id] == g else { return }
        guard tasks.contains(where: { $0.id == task.id }) else { return }
        do {
            try await store.persistTask(task)
        } catch {
            recordPersistenceResult(error)
            throw error
        }
        guard generation[task.id] == g,
              tasks.contains(where: { $0.id == task.id }) else {
            await restoreAuthoritativeTaskState(id: task.id)
            return
        }
        recordPersistenceResult(nil)
        upsert(task)
    }

    /// A command can invalidate a run while its previous transition is awaiting
    /// persistence. Repair the durable row after that stale write returns so it
    /// cannot resurrect a deleted task or overwrite a Stop/Delete decision.
    private func restoreAuthoritativeTaskState(id: UUID) async {
        while taskCommandPersistence.contains(id) {
            await _Concurrency.Task.yield()
        }
        do {
            if let current = task(withID: id) {
                try await store.persistTask(current)
            } else {
                try await store.removeTask(id: id)
            }
            recordPersistenceResult(nil)
        } catch {
            recordPersistenceResult(error)
        }
    }

    /// ACP intentionally allows long-running prompt requests, so checkpoint
    /// deadlines cannot depend on an agent turn returning. This monitor remains
    /// outside the engine await and can therefore cancel a wedged session.
    func ensureTimeoutMonitor() {
        guard !isShuttingDown,
              timeoutMonitor == nil,
              tasks.contains(where: { $0.state == .running }) else {
            return
        }
        timeoutMonitor = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                do {
                    try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard let self else { return }
                await self.enforceCheckpointTimeouts()
                if !self.tasks.contains(where: { $0.state == .running }) {
                    self.timeoutMonitor = nil
                    return
                }
            }
        }
    }

    /// Exposed internally for deterministic lifecycle tests and bootstrap
    /// recovery. The normal caller is the timeout monitor above.
    func enforceCheckpointTimeouts(at date: Date? = nil) async {
        guard !isShuttingDown else { return }
        let now = date ?? clock.now
        let expired = tasks.compactMap { task -> (VibeLaneTask, VibeLaneDefinition, VibeLaneCheckpoint)? in
            guard task.state == .running,
                  let lane = resolvedLane(for: task),
                  let checkpoint = lane.checkpoint(forKey: task.currentCheckpointKey),
                  let run = task.currentRun,
                  run.checkpointKey == checkpoint.key,
                  run.status == .running,
                  let startedAt = run.activeWindowStartedAt ?? run.startedAt,
                  now.timeIntervalSince(startedAt) > Double(checkpoint.bounds.timeoutSeconds) else {
                return nil
            }
            return (task, lane, checkpoint)
        }

        for (task, lane, checkpoint) in expired {
            await expire(task, lane: lane, checkpoint: checkpoint, at: now)
        }
        if !expired.isEmpty {
            scheduleQueued()
        }
    }

    private func expire(
        _ original: VibeLaneTask,
        lane: VibeLaneDefinition,
        checkpoint: VibeLaneCheckpoint,
        at now: Date
    ) async {
        guard var task = task(withID: original.id),
              task.state == .running,
              var run = task.currentRun,
              run.checkpointKey == checkpoint.key else {
            return
        }

        generation[task.id] = (generation[task.id] ?? 0) + 1
        running[task.id]?.cancel()
        running[task.id] = nil
        releaseSessions(for: task)

        run.endedAt = now
        run.stopReason = .timeout
        if checkpoint.bounds.onExhausted == .escalate,
           task.steerCount < lane.steerLimit {
            run.status = .needsInput
            replace(run: run, in: &task)
            task.state = .needsInput
            task.stopReason = nil
            task.pendingHumanEngine = nil
            task.openInputRequest = VibeLaneInputRequest(
                kind: .steer,
                checkpointKey: checkpoint.key,
                visit: task.currentVisit,
                createdAt: now,
                prompt: AppStrings.VibeLanes.steerRequestPrompt(
                    checkpoint: checkpoint.displayTitle,
                    reason: AppStrings.VibeLanes.reasonTimedOut
                ),
                lastFeedback: run.attempts.last?.result?.feedback,
                reason: .timeout
            )
            recordActivity(
                AppStrings.VibeLanes.needsYou,
                kind: .input,
                at: now,
                in: &task
            )
        } else {
            let reason: VibeLaneStopReason = checkpoint.bounds.onExhausted == .escalate
                ? .steerLimitReached
                : .timeout
            run.status = .stopped
            run.stopReason = reason
            replace(run: run, in: &task)
            task.state = .stopped
            task.stopReason = reason
            task.openInputRequest = nil
            task.pendingHumanEngine = nil
            task.rerunRequest = nil
            recordActivity(
                AppStrings.VibeLanes.activityStopped(timeoutReasonLabel(reason)),
                kind: .system,
                at: now,
                in: &task
            )
        }
        taskCommandPersistence.insert(task.id)
        do {
            try await store.persistTask(task)
        } catch {
            taskCommandPersistence.remove(task.id)
            recordPersistenceResult(error)
            return
        }
        recordPersistenceResult(nil)
        upsert(task)
        taskCommandPersistence.remove(task.id)
    }

    private func recordActivity(
        _ message: String,
        kind: VibeLaneActivityKind,
        at now: Date,
        in task: inout VibeLaneTask
    ) {
        task.currentActivity = message
        var log = task.activityLog ?? []
        if log.last?.message != message || log.last?.kind != kind {
            log.append(VibeLaneActivityLogEntry(at: now, kind: kind, message: message))
        }
        if log.count > 120 {
            log.removeFirst(log.count - 120)
        }
        task.activityLog = log
        task.updatedAt = now
    }

    private func timeoutReasonLabel(_ reason: VibeLaneStopReason) -> String {
        reason == .steerLimitReached
            ? AppStrings.VibeLanes.reasonSteerLimitReached
            : AppStrings.VibeLanes.reasonTimedOut
    }
}
