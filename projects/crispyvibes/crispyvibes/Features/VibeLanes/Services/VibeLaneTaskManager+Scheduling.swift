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
        guard task.state == .running else { return }
        if canStart(task) {
            start(task)
        }
    }

    /// Start any queued (`.running` but not yet executing) tasks that now fit
    /// within the global cap and their project's single-task budget.
    func scheduleQueued() {
        guard running.count < maxConcurrent else { return }
        let queued = tasks.filter { $0.state == .running && running[$0.id] == nil }
        for task in queued {
            if running.count >= maxConcurrent { break }
            if canStart(task) { start(task) }
        }
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
        guard task.state == .running, running[task.id] == nil, let lane = resolvedLane(for: task) else { return }
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
                self?.applyEngineTransition(updated, generation: g)
            }
        )
        let job = _Concurrency.Task { [weak self] in
            let result = await engine.run(task)
            await MainActor.run {
                guard let self else { return }
                self.applyEngineTransition(result, generation: g)
                // Only the current run may finalize this task's slot/sessions.
                guard self.generation[task.id] == g else {
                    self.running[task.id] = nil
                    self.scheduleQueued()
                    return
                }
                if result.isTerminal {
                    self.releaseSessions(for: result)
                }
                self.running[task.id] = nil
                self.scheduleQueued()
            }
        }
        running[task.id] = job
    }

    /// Apply an engine-produced transition only if it belongs to the task's
    /// current run and the task still exists (so stop/delete/resume can't be
    /// undone by a superseded engine, and a deleted task can't be resurrected).
    private func applyEngineTransition(_ task: VibeLaneTask, generation g: Int) {
        guard generation[task.id] == g else { return }
        guard tasks.contains(where: { $0.id == task.id }) else { return }
        upsert(task)
        store.saveTask(task)
    }
}
