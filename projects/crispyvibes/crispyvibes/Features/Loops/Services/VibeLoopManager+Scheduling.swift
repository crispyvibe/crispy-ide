import Foundation

enum VibeLoopReconciliationReason: Equatable {
    case catchUp
    case configurationChange
    case scheduledWake(expectedAt: Date)

    func isMissed(scheduledAt: Date, now: Date) -> Bool {
        switch self {
        case .catchUp:
            return true
        case .configurationChange:
            return false
        case .scheduledWake(let expectedAt):
            let grace: TimeInterval = 60
            return scheduledAt != expectedAt || now.timeIntervalSince(expectedAt) > grace
        }
    }
}

extension VibeLoopManager {
    func reconcileLaneTaskStates(_ tasks: [VibeLaneTask]) async {
        guard hasBootstrapped else { return }
        var reconciled = runRecords
        var reconciledRuntime = runtimeStates
        var runsChanged = false
        var runtimeChanged = false

        for task in tasks {
            guard let loopID = task.origin.loopID,
                  let occurrenceID = task.origin.occurrenceID,
                  let scheduledAt = task.origin.scheduledAt,
                  definition(withID: loopID) != nil else {
                continue
            }

            let index = reconciled.firstIndex {
                $0.id == occurrenceID && $0.loopID == loopID
            }
            var record = index.map { reconciled[$0] } ?? VibeLoopRunRecord(
                id: occurrenceID,
                loopID: loopID,
                scheduledAt: scheduledAt,
                triggeredAt: task.createdAt,
                disposition: .started
            )
            record.disposition = .started
            record.triggeredAt = record.triggeredAt ?? task.createdAt
            record.taskID = task.id
            record.taskState = task.state
            record.taskStopReason = task.stopReason
            record.taskUpdatedAt = task.updatedAt

            if let index {
                if record != reconciled[index] {
                    reconciled[index] = record
                    runsChanged = true
                }
            } else {
                reconciled.append(record)
                runsChanged = true
            }

            var runtime = reconciledRuntime[loopID] ?? VibeLoopRuntimeState(loopID: loopID)
            if runtime.lastTriggeredAt == nil || task.createdAt >= runtime.lastTriggeredAt! {
                runtime.lastTaskID = task.id
                runtime.lastTriggeredAt = task.createdAt
            }
            if occurrenceID == VibeLoopOccurrenceID.make(loopID: loopID, scheduledAt: scheduledAt),
               runtime.lastClaimedScheduledAt == nil || scheduledAt > runtime.lastClaimedScheduledAt! {
                runtime.lastClaimedScheduledAt = scheduledAt
            }
            if runtime != reconciledRuntime[loopID] {
                reconciledRuntime[loopID] = runtime
                runtimeChanged = true
            }
        }

        if runsChanged || runtimeChanged {
            _ = await commitState(
                definitions: definitions,
                runtimeStates: reconciledRuntime,
                runRecords: runsChanged ? retainedRuns(reconciled) : runRecords
            )
        }
    }

    func reconcileDueLoops(
        at now: Date? = nil,
        reason: VibeLoopReconciliationReason = .catchUp
    ) async {
        let timestamp = now ?? clock.now
        await recoverPendingOccurrences()
        for definition in definitions where definition.isEnabled {
            guard let due = VibeLoopScheduleCalculator.latestDueOccurrence(
                for: definition,
                runtime: runtimeStates[definition.id],
                now: timestamp
            ) else { continue }
            if definition.missedRunPolicy == .skip,
               reason.isMissed(scheduledAt: due, now: timestamp) {
                await claimSkippedMissed(definition, scheduledAt: due, now: timestamp)
            } else {
                _ = await trigger(
                    definition,
                    scheduledAt: due,
                    now: timestamp,
                    claimsSchedule: true
                )
            }
        }
    }

    @discardableResult
    func runNow(id: UUID) async -> VibeLoopRunRecord? {
        guard let definition = definition(withID: id) else { return nil }
        return await trigger(
            definition,
            occurrenceID: UUID(),
            scheduledAt: clock.now,
            now: clock.now,
            claimsSchedule: false
        )
    }

    func earliestNextRunDate() -> Date? {
        definitions
            .filter(\.isEnabled)
            .compactMap { nextRunDate(for: $0) }
            .min()
    }

    func recoverPendingOccurrences() async {
        let pending = runRecords.filter { $0.disposition == .pending }
        for record in pending {
            guard let definition = definition(withID: record.loopID),
                  definition.isEnabled else {
                continue
            }
            _ = await trigger(
                definition,
                occurrenceID: record.id,
                scheduledAt: record.scheduledAt,
                now: clock.now,
                claimsSchedule: false
            )
        }
    }

    @discardableResult
    private func trigger(
        _ definition: VibeLoopDefinition,
        occurrenceID: UUID? = nil,
        scheduledAt: Date,
        now: Date,
        claimsSchedule: Bool
    ) async -> VibeLoopRunRecord? {
        let id = occurrenceID ?? VibeLoopOccurrenceID.make(loopID: definition.id, scheduledAt: scheduledAt)
        var record: VibeLoopRunRecord
        if let existing = runRecords.first(where: { $0.id == id }) {
            guard existing.disposition == .pending else { return existing }
            if let task = laneManager.task(withOccurrenceID: id) {
                await reconcileLaneTaskStates([task])
                return runRecords.first(where: { $0.id == id }) ?? existing
            }
            record = existing
        } else {
            record = VibeLoopRunRecord(
                id: id,
                loopID: definition.id,
                scheduledAt: scheduledAt,
                disposition: .pending
            )
        }

        var pendingRuns = runRecords
        upsertRun(record, in: &pendingRuns)
        var pendingRuntime = runtimeStates
        var runtime = pendingRuntime[definition.id] ?? VibeLoopRuntimeState(loopID: definition.id)
        if claimsSchedule { runtime.lastClaimedScheduledAt = scheduledAt }
        pendingRuntime[definition.id] = runtime
        guard await commitState(
            definitions: definitions,
            runtimeStates: pendingRuntime,
            runRecords: pendingRuns
        ) else {
            return nil
        }

        if activeTask(for: definition.id) != nil {
            record.triggeredAt = now
            record.disposition = .skippedActiveRun
            record.detail = AppStrings.Loops.activeRunSkipped
            return await commitRun(record, runtime: runtime) ? record : nil
        }

        if let validationFailure = validationFailure(for: definition) {
            record.triggeredAt = now
            record.disposition = .blocked
            record.detail = validationFailure.detail
            runtime.lastFailure = validationFailure
            return await commitRun(record, runtime: runtime) ? record : nil
        }

        let origin = VibeLaneTaskOrigin.loop(
            loopID: definition.id,
            occurrenceID: id,
            scheduledAt: scheduledAt
        )
        guard let task = await laneManager.createTask(
            laneSnapshot: definition.laneSnapshot,
            title: definition.taskInstruction,
            projectPath: definition.projectPath,
            origin: origin
        ) else {
            let taskFailure = failure(.taskCreation, AppStrings.Loops.taskCreationFailed)
            record.triggeredAt = now
            record.disposition = .creationFailed
            record.detail = taskFailure.detail
            runtime.lastFailure = taskFailure
            return await commitRun(record, runtime: runtime) ? record : nil
        }

        if let reconciled = runRecords.first(where: { $0.id == id && $0.taskID == task.id }) {
            return reconciled
        }
        record.triggeredAt = now
        record.disposition = .started
        record.taskID = task.id
        record.taskState = task.state
        record.taskStopReason = task.stopReason
        record.taskUpdatedAt = task.updatedAt
        runtime.lastTaskID = task.id
        runtime.lastTriggeredAt = now
        runtime.lastFailure = nil
        return await commitRun(record, runtime: runtime) ? record : nil
    }

    private func claimSkippedMissed(
        _ definition: VibeLoopDefinition,
        scheduledAt: Date,
        now: Date
    ) async {
        let id = VibeLoopOccurrenceID.make(loopID: definition.id, scheduledAt: scheduledAt)
        guard !runRecords.contains(where: { $0.id == id }) else { return }
        var runtime = runtimeStates[definition.id] ?? VibeLoopRuntimeState(loopID: definition.id)
        runtime.lastClaimedScheduledAt = scheduledAt
        var updatedRuntime = runtimeStates
        updatedRuntime[definition.id] = runtime
        var updatedRuns = runRecords
        upsertRun(VibeLoopRunRecord(
            id: id,
            loopID: definition.id,
            scheduledAt: scheduledAt,
            triggeredAt: now,
            disposition: .skippedMissed,
            detail: AppStrings.Loops.missedRunSkipped
        ), in: &updatedRuns)
        _ = await commitState(
            definitions: definitions,
            runtimeStates: updatedRuntime,
            runRecords: updatedRuns
        )
    }

    private func commitRun(
        _ record: VibeLoopRunRecord,
        runtime: VibeLoopRuntimeState
    ) async -> Bool {
        var updatedRuntime = runtimeStates
        updatedRuntime[record.loopID] = runtime
        var updatedRuns = runRecords
        upsertRun(record, in: &updatedRuns)
        return await commitState(
            definitions: definitions,
            runtimeStates: updatedRuntime,
            runRecords: updatedRuns
        )
    }

    private func upsertRun(
        _ run: VibeLoopRunRecord,
        in records: inout [VibeLoopRunRecord]
    ) {
        records.removeAll { $0.id == run.id }
        records.append(run)
        records = retainedRuns(records)
    }

    private func retainedRuns(_ records: [VibeLoopRunRecord]) -> [VibeLoopRunRecord] {
        var retained: [VibeLoopRunRecord] = []
        var counts: [UUID: Int] = [:]
        for record in records.sorted(by: { $0.scheduledAt > $1.scheduledAt }) {
            let count = counts[record.loopID, default: 0]
            if count < 200 {
                retained.append(record)
                counts[record.loopID] = count + 1
            }
        }
        return retained
    }
}
