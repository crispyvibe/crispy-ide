import Foundation
import XCTest
@testable import CrispyVibes

private final class MutableVibeLoopClock: VibeLoopClock, @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { value }
}

@MainActor
private final class VibeLoopHangingWorker: VibeLaneWorkRunning {
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        while !_Concurrency.Task.isCancelled {
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000)
        }
        return VibeLaneWorkTurn(sessionRef: sessionRef, ok: false)
    }
}

@MainActor
final class VibeLoopTests: XCTestCase {
    private var projectURL: URL!

    override func setUpWithError() throws {
        projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("crispy-vibe-loop-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectURL)
        projectURL = nil
    }

    func test_intervalScheduleRemainsAnchored() async {
        let anchor = Date(timeIntervalSince1970: 0)
        let schedule = VibeLoopSchedule.interval(anchor: anchor, seconds: 900)

        XCTAssertEqual(
            VibeLoopScheduleCalculator.nextOccurrence(
                after: Date(timeIntervalSince1970: 1_901),
                schedule: schedule
            ),
            Date(timeIntervalSince1970: 2_700)
        )
        XCTAssertEqual(
            VibeLoopScheduleCalculator.latestOccurrence(
                onOrBefore: Date(timeIntervalSince1970: 2_699),
                schedule: schedule
            ),
            Date(timeIntervalSince1970: 1_800)
        )
    }

    func test_dailyAndWeeklySchedulesUseStoredTimeZone() async {
        let after = isoDate("2026-07-16T15:00:00Z")
        let daily = VibeLoopSchedule.daily(hour: 9, minute: 0, timeZoneID: "America/Chicago")
        let weekly = VibeLoopSchedule.weekly(
            weekdays: [2],
            hour: 9,
            minute: 0,
            timeZoneID: "America/Chicago"
        )

        XCTAssertEqual(
            VibeLoopScheduleCalculator.nextOccurrence(after: after, schedule: daily),
            isoDate("2026-07-17T14:00:00Z")
        )
        XCTAssertEqual(
            VibeLoopScheduleCalculator.nextOccurrence(after: after, schedule: weekly),
            isoDate("2026-07-20T14:00:00Z")
        )
    }

    func test_dstSkippedAndRepeatedTimesFireOnce() async {
        let skipped = VibeLoopSchedule.daily(
            hour: 2,
            minute: 30,
            timeZoneID: "America/Chicago"
        )
        let skippedResult = VibeLoopScheduleCalculator.nextOccurrence(
            after: isoDate("2026-03-08T06:00:00Z"),
            schedule: skipped
        )
        XCTAssertEqual(skippedResult, isoDate("2026-03-08T08:00:00Z"))

        let repeated = VibeLoopSchedule.daily(
            hour: 1,
            minute: 30,
            timeZoneID: "America/Chicago"
        )
        let first = VibeLoopScheduleCalculator.nextOccurrence(
            after: isoDate("2026-11-01T05:00:00Z"),
            schedule: repeated
        )
        XCTAssertEqual(first, isoDate("2026-11-01T06:30:00Z"))
        XCTAssertEqual(
            VibeLoopScheduleCalculator.nextOccurrence(after: first!, schedule: repeated),
            isoDate("2026-11-02T07:30:00Z")
        )
    }

    func test_scheduleValidationRejectsShortIntervalsAndUnknownTimeZones() async {
        XCTAssertThrowsError(
            try VibeLoopScheduleCalculator.validate(
                .interval(anchor: Date(), seconds: 899)
            )
        ) { error in
            XCTAssertEqual(error as? VibeLoopScheduleValidationError, .intervalTooShort)
        }
        XCTAssertThrowsError(
            try VibeLoopScheduleCalculator.validate(
                .daily(hour: 9, minute: 0, timeZoneID: "Mars/Olympus")
            )
        ) { error in
            XCTAssertEqual(error as? VibeLoopScheduleValidationError, .invalidTimeZone)
        }
    }

    func test_fileStoreMigratesLegacyDocumentsIntoCanonicalState() async throws {
        let directory = projectURL.appendingPathComponent("Loops", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let runtime = VibeLoopRuntimeState(
            loopID: definition.id,
            lastClaimedScheduledAt: Date(timeIntervalSince1970: 900)
        )
        let run = VibeLoopRunRecord(
            id: UUID(),
            loopID: definition.id,
            scheduledAt: Date(timeIntervalSince1970: 900),
            disposition: .skippedMissed
        )
        let expected = VibeLoopPersistedState(
            definitions: [definition],
            runtimeStates: [runtime],
            runRecords: [run]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(expected.definitions)
            .write(to: directory.appendingPathComponent("definitions.json"))
        try encoder.encode(expected.runtimeStates)
            .write(to: directory.appendingPathComponent("runtime.json"))
        try encoder.encode(expected.runRecords)
            .write(to: directory.appendingPathComponent("runs.json"))

        let migrated = try FileVibeLoopStore(directory: directory).loadState()

        XCTAssertEqual(migrated, expected)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("state.json").path
            )
        )
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("definitions.json")
        )
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("runtime.json")
        )
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("runs.json")
        )
        XCTAssertEqual(
            try FileVibeLoopStore(directory: directory).loadState(),
            expected
        )
    }

    func test_fileStoreRejectsCorruptCanonicalState() async throws {
        let directory = projectURL.appendingPathComponent("Loops", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not-json".utf8)
            .write(to: directory.appendingPathComponent("state.json"))

        XCTAssertThrowsError(
            try FileVibeLoopStore(directory: directory).loadState()
        )
    }

    func test_occurrenceIDIsDeterministic() async {
        let loopID = UUID(uuidString: "79A752B5-63E1-4760-806E-10D67DBF9B22")!
        let date = Date(timeIntervalSince1970: 1_234)

        let first = VibeLoopOccurrenceID.make(loopID: loopID, scheduledAt: date)
        XCTAssertEqual(first, VibeLoopOccurrenceID.make(loopID: loopID, scheduledAt: date))
        XCTAssertNotEqual(
            first,
            VibeLoopOccurrenceID.make(loopID: loopID, scheduledAt: date.addingTimeInterval(1))
        )
    }

    func test_reconcileRunsLatestMissedOccurrenceOnce() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 3_700))
        let setup = await makeManagers(
            clock: clock,
            definitions: [makeDefinition(createdAt: Date(timeIntervalSince1970: 100))]
        )
        defer { setup.laneManager.shutdown() }

        await setup.loopManager.reconcileDueLoops()

        XCTAssertEqual(setup.loopManager.runRecords.count, 1)
        XCTAssertEqual(
            setup.loopManager.runRecords.first?.scheduledAt,
            Date(timeIntervalSince1970: 3_600)
        )
        XCTAssertEqual(setup.loopManager.runRecords.first?.disposition, .started)
        XCTAssertEqual(setup.laneManager.tasks.count, 1)
    }

    func test_skipMissedClaimsOccurrenceWithoutCreatingTask() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 3_700))
        var definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        definition.missedRunPolicy = .skip
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }

        await setup.loopManager.reconcileDueLoops()

        XCTAssertTrue(setup.laneManager.tasks.isEmpty)
        XCTAssertEqual(setup.loopManager.runRecords.first?.disposition, .skippedMissed)
        XCTAssertEqual(
            setup.loopManager.runtimeStates[definition.id]?.lastClaimedScheduledAt,
            Date(timeIntervalSince1970: 3_600)
        )
    }

    func test_skipPolicyStillRunsAnOnTimeScheduledWake() async {
        let scheduledAt = Date(timeIntervalSince1970: 900)
        let clock = MutableVibeLoopClock(scheduledAt)
        var definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        definition.missedRunPolicy = .skip
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }

        await setup.loopManager.reconcileDueLoops(
            reason: .scheduledWake(expectedAt: scheduledAt)
        )

        XCTAssertEqual(setup.laneManager.tasks.count, 1)
        XCTAssertEqual(setup.loopManager.runRecords.first?.disposition, .started)
        XCTAssertEqual(setup.loopManager.runRecords.first?.scheduledAt, scheduledAt)
    }

    func test_configurationChangeDoesNotClassifyOnTimeRunAsMissed() async {
        let scheduledAt = Date(timeIntervalSince1970: 900)
        let clock = MutableVibeLoopClock(scheduledAt)
        var definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        definition.missedRunPolicy = .skip
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }

        await setup.loopManager.reconcileDueLoops(
            reason: .configurationChange
        )

        XCTAssertEqual(setup.laneManager.tasks.count, 1)
        XCTAssertEqual(setup.loopManager.runRecords.first?.disposition, .started)
    }

    func test_failedOccurrenceClaimDoesNotCreateTask() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        let store = setup.loopManager.store as! InMemoryVibeLoopStore
        store.shouldFailSaves = true

        await setup.loopManager.reconcileDueLoops()

        XCTAssertTrue(setup.laneManager.tasks.isEmpty)
        XCTAssertTrue(setup.loopManager.runRecords.isEmpty)
        XCTAssertNil(setup.loopManager.runtimeStates[definition.id])
        XCTAssertEqual(
            setup.loopManager.persistenceError,
            AppStrings.Loops.persistenceUnavailable
        )
    }

    func test_schedulerWakeRunsSkipPolicyLoopOnTime() async {
        let scheduledAt = Date(timeIntervalSince1970: 900)
        let clock = MutableVibeLoopClock(scheduledAt.addingTimeInterval(-0.05))
        var definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        definition.missedRunPolicy = .skip
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        let scheduler = VibeLoopScheduler(manager: setup.loopManager, clock: clock)
        scheduler.start()
        defer { scheduler.shutdown() }

        // Let the initial catch-up pass schedule the live 900-second wake
        // before advancing the test clock to that occurrence.
        try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        clock.value = scheduledAt
        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(setup.laneManager.tasks.count, 1)
        XCTAssertEqual(setup.loopManager.runRecords.first?.disposition, .started)
        XCTAssertEqual(setup.loopManager.runRecords.first?.scheduledAt, scheduledAt)
    }

    func test_activeAndNeedsInputRunsPreventOverlap() async {
        for needsInput in [false, true] {
            let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
            let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
            let setup = await makeManagers(clock: clock, definitions: [definition])
            defer { setup.laneManager.shutdown() }
            let task = await setup.laneManager.createTask(
                laneSnapshot: setup.lane,
                title: "Existing",
                projectPath: projectURL.path,
                origin: .loop(
                    loopID: definition.id,
                    occurrenceID: UUID(),
                    scheduledAt: Date(timeIntervalSince1970: 0)
                )
            )!
            if needsInput {
                var paused = task
                paused.state = .needsInput
                setup.laneManager.upsert(paused)
            }

            await setup.loopManager.reconcileDueLoops()

            XCTAssertEqual(setup.laneManager.tasks.count, 1)
            XCTAssertEqual(setup.loopManager.runRecords.first?.disposition, .skippedActiveRun)
        }
    }

    func test_laneTaskLifecycleIsReconciledIntoLoopStatusAndHistory() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        let run = await setup.loopManager.runNow(id: definition.id)
        var task = setup.laneManager.task(withID: run!.taskID!)!

        XCTAssertEqual(setup.loopManager.status(for: definition), .running)
        XCTAssertEqual(setup.loopManager.runRecords.first?.taskState, .running)
        setup.laneManager.shutdown()

        task.state = .needsInput
        task.stopReason = .timeout
        setup.laneManager.upsert(task)
        await setup.loopManager.reconcileLaneTaskStates([task])

        XCTAssertEqual(setup.loopManager.status(for: definition), .needsInput)
        XCTAssertEqual(setup.loopManager.runRecords.first?.taskState, .needsInput)
        XCTAssertEqual(setup.loopManager.runRecords.first?.taskStopReason, .timeout)
        XCTAssertEqual(setup.loopManager.runRecords.first?.taskUpdatedAt, task.updatedAt)
        let persisted = try? await setup.loopManager.store.loadPersistedState()
        XCTAssertEqual(persisted?.runRecords.first?.taskState, .needsInput)

        task.state = .done
        task.stopReason = .done
        setup.laneManager.upsert(task)
        await setup.loopManager.reconcileLaneTaskStates([task])

        XCTAssertEqual(setup.loopManager.status(for: definition), .scheduled)
        XCTAssertEqual(setup.loopManager.runRecords.first?.taskState, .done)
        XCTAssertEqual(setup.loopManager.runRecords.first?.statusTitle, AppStrings.Loops.runCompleted)

        task.state = .running
        task.stopReason = nil
        setup.laneManager.upsert(task)
        await setup.laneManager.delete(id: task.id)

        XCTAssertEqual(setup.loopManager.status(for: definition), .scheduled)
    }

    func test_pausedScheduleWithActiveTaskReportsRunningAndPausedSchedule() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        _ = await setup.loopManager.runNow(id: definition.id)

        let didPause = await setup.loopManager.setEnabled(false, id: definition.id)
        XCTAssertTrue(didPause)

        let state = setup.loopManager.state(
            for: setup.loopManager.definition(withID: definition.id)!
        )
        XCTAssertEqual(state.schedule, .paused)
        XCTAssertEqual(state.execution, .running)
        XCTAssertEqual(state.status, .running)
        XCTAssertNotNil(state.activeTaskID)
        XCTAssertNil(
            setup.loopManager.nextRunDate(
                for: setup.loopManager.definition(withID: definition.id)!
            )
        )
        XCTAssertTrue(VibeLoopFilter.paused.includes(state))
        XCTAssertTrue(VibeLoopFilter.active.includes(state))
    }

    func test_secondTaskForSameProjectReportsQueued() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let first = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        var second = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        second.name = "Second project health"
        let setup = await makeManagers(clock: clock, definitions: [first, second])
        defer { setup.laneManager.shutdown() }

        let firstTaskID = await setup.loopManager.runNow(id: first.id)?.taskID
        let secondTaskID = await setup.loopManager.runNow(id: second.id)?.taskID
        XCTAssertNotNil(firstTaskID)
        XCTAssertNotNil(secondTaskID)

        let secondState = setup.loopManager.state(for: second)
        XCTAssertEqual(secondState.execution, .queued)
        XCTAssertEqual(secondState.status, .queued)
    }

    func test_loopStateProjectionTransitionMatrix() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }

        assertState(
            setup.loopManager,
            loopID: definition.id,
            schedule: .enabled,
            execution: .idle,
            status: .scheduled
        )

        setup.loopManager.setRuntimeStateForTesting(
            VibeLoopRuntimeState(
                loopID: definition.id,
                lastFailure: VibeLoopFailure(
                    kind: .taskCreation,
                    detail: "Failed",
                    at: clock.now
                )
            ),
            id: definition.id
        )
        assertState(
            setup.loopManager,
            loopID: definition.id,
            schedule: .blocked,
            execution: .idle,
            status: .blocked
        )
        setup.loopManager.setRuntimeStateForTesting(
            clearingFailure(setup.loopManager, id: definition.id),
            id: definition.id
        )

        let run = await setup.loopManager.runNow(id: definition.id)!
        assertState(
            setup.loopManager,
            loopID: definition.id,
            schedule: .enabled,
            execution: .running,
            status: .running,
            activeTaskID: run.taskID
        )

        setup.loopManager.setRuntimeStateForTesting(
            VibeLoopRuntimeState(
                loopID: definition.id,
                lastFailure: VibeLoopFailure(
                    kind: .taskCreation,
                    detail: "Failed",
                    at: clock.now
                )
            ),
            id: definition.id
        )
        assertState(
            setup.loopManager,
            loopID: definition.id,
            schedule: .blocked,
            execution: .running,
            status: .running,
            activeTaskID: run.taskID
        )
        setup.loopManager.setRuntimeStateForTesting(
            clearingFailure(setup.loopManager, id: definition.id),
            id: definition.id
        )

        let didPause = await setup.loopManager.setEnabled(false, id: definition.id)
        XCTAssertTrue(didPause)
        assertState(
            setup.loopManager,
            loopID: definition.id,
            schedule: .paused,
            execution: .running,
            status: .running,
            activeTaskID: run.taskID
        )

        var task = setup.laneManager.task(withID: run.taskID!)!
        task.state = .needsInput
        setup.laneManager.upsert(task)
        assertState(
            setup.loopManager,
            loopID: definition.id,
            schedule: .paused,
            execution: .needsInput,
            status: .needsInput,
            activeTaskID: task.id
        )

        await setup.laneManager.stop(id: task.id)
        assertState(
            setup.loopManager,
            loopID: definition.id,
            schedule: .paused,
            execution: .idle,
            status: .paused
        )
    }

    func test_stopCurrentRunLeavesScheduleEnabledAndNextOccurrenceStarts() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 894))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        _ = await setup.loopManager.runNow(id: definition.id)
        let firstTask = setup.loopManager.activeTask(for: definition.id)!

        let didStop = await setup.loopManager.stopRun(
            loopID: definition.id,
            taskID: firstTask.id,
            pauseLoop: false
        )
        XCTAssertTrue(didStop)
        XCTAssertEqual(setup.laneManager.task(withID: firstTask.id)?.state, .stopped)
        XCTAssertEqual(setup.loopManager.status(for: definition), .scheduled)
        XCTAssertEqual(setup.loopManager.definition(withID: definition.id)?.isEnabled, true)

        clock.value = Date(timeIntervalSince1970: 900)
        await setup.loopManager.reconcileDueLoops(
            reason: .scheduledWake(expectedAt: clock.now)
        )

        XCTAssertEqual(setup.laneManager.tasks.count, 2)
        XCTAssertNotEqual(setup.loopManager.activeTask(for: definition.id)?.id, firstTask.id)
        XCTAssertEqual(setup.loopManager.status(for: definition), .running)
    }

    func test_stopAndPauseIsAtomicAndPreventsNextOccurrence() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 894))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        _ = await setup.loopManager.runNow(id: definition.id)
        let task = setup.loopManager.activeTask(for: definition.id)!

        let didStopAndPause = await setup.loopManager.stopRun(
            loopID: definition.id,
            taskID: task.id,
            pauseLoop: true
        )
        XCTAssertTrue(didStopAndPause)

        let paused = setup.loopManager.definition(withID: definition.id)!
        XCTAssertFalse(paused.isEnabled)
        XCTAssertEqual(setup.laneManager.task(withID: task.id)?.state, .stopped)
        XCTAssertEqual(setup.loopManager.state(for: paused).schedule, .paused)
        XCTAssertEqual(setup.loopManager.state(for: paused).execution, .idle)
        XCTAssertEqual(setup.loopManager.status(for: paused), .paused)

        clock.value = Date(timeIntervalSince1970: 900)
        await setup.loopManager.reconcileDueLoops(
            reason: .scheduledWake(expectedAt: clock.now)
        )

        XCTAssertEqual(setup.laneManager.tasks.count, 1)
        XCTAssertNil(setup.loopManager.activeTask(for: definition.id))
    }

    func test_validEditClearsPersistedBlockedState() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        setup.loopManager.setRuntimeStateForTesting(
            VibeLoopRuntimeState(
                loopID: definition.id,
                lastFailure: VibeLoopFailure(
                    kind: .invalidProject,
                    detail: "Missing",
                    at: clock.now
                )
            ),
            id: definition.id
        )
        var edited = definition
        edited.name = "Recovered"

        let didSave = await setup.loopManager.save(edited)
        XCTAssertTrue(didSave)

        XCTAssertNil(setup.loopManager.runtimeStates[definition.id]?.lastFailure)
        XCTAssertEqual(
            setup.loopManager.status(
                for: setup.loopManager.definition(withID: definition.id)!
            ),
            .scheduled
        )
    }

    func test_failedSaveDoesNotMutatePublishedDefinition() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        let store = setup.loopManager.store as! InMemoryVibeLoopStore
        store.shouldFailSaves = true
        var edited = definition
        edited.name = "Should not commit"

        let didSave = await setup.loopManager.save(edited)
        XCTAssertFalse(didSave)
        XCTAssertEqual(
            setup.loopManager.definition(withID: definition.id)?.name,
            definition.name
        )
        XCTAssertNotNil(setup.loopManager.persistenceError)
    }

    func test_taskCreationRequiresDurableTaskAndRevisionWrites() async {
        let lane = makeLane()
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = VibeLaneTaskManager(
            store: store,
            worker: VibeLoopHangingWorker()
        )
        await manager.bootstrap(resumeRunning: false)
        defer { manager.shutdown() }
        store.shouldFailTaskSaves = true

        let taskWithoutPersistence = await manager.createTask(
            laneSnapshot: lane,
            title: "Must persist",
            projectPath: projectURL.path,
            origin: .manual
        )
        XCTAssertNil(taskWithoutPersistence)
        XCTAssertTrue(manager.tasks.isEmpty)

        store.shouldFailTaskSaves = false
        var unknownRevision = lane
        unknownRevision.version += 1
        let taskWithoutRevision = await manager.createTask(
            laneSnapshot: unknownRevision,
            title: "Must archive",
            projectPath: projectURL.path,
            origin: .manual
        )
        XCTAssertNil(taskWithoutRevision)
        XCTAssertTrue(manager.tasks.isEmpty)
    }

    func test_deleteCanStopActiveRunBeforeRemovingSchedule() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        let taskID = await setup.loopManager.runNow(id: definition.id)!.taskID!

        let didDelete = await setup.loopManager.delete(
            id: definition.id,
            stopActiveRun: true
        )
        XCTAssertTrue(didDelete)

        XCTAssertNil(setup.loopManager.definition(withID: definition.id))
        XCTAssertEqual(setup.laneManager.task(withID: taskID)?.state, .stopped)
        XCTAssertEqual(
            setup.laneManager.task(withID: taskID)?.stopReason,
            .stoppedByUser
        )
    }

    func test_failedStopAndDeleteKeepsLoopPausedAndTaskActive() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        let taskID = await setup.loopManager.runNow(id: definition.id)!.taskID!
        let laneStore = setup.laneManager.store as! InMemoryVibeLaneStore
        laneStore.shouldFailTaskSaves = true

        let didDelete = await setup.loopManager.delete(
            id: definition.id,
            stopActiveRun: true
        )
        XCTAssertFalse(didDelete)

        XCTAssertEqual(
            setup.loopManager.definition(withID: definition.id)?.isEnabled,
            false
        )
        XCTAssertEqual(setup.laneManager.task(withID: taskID)?.state, .running)
        XCTAssertNotNil(setup.loopManager.activeTask(for: definition.id))
    }

    func test_bootstrapBackfillsLegacyStartedRunFromLinkedLaneTask() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let occurrenceID = UUID()
        let task = VibeLaneTask(
            projectPath: projectURL.path,
            title: definition.taskInstruction,
            laneID: definition.laneSnapshot.id,
            laneVersion: definition.laneSnapshot.version,
            origin: .loop(
                loopID: definition.id,
                occurrenceID: occurrenceID,
                scheduledAt: clock.now
            ),
            state: .stopped,
            stopReason: .error,
            currentCheckpointKey: definition.laneSnapshot.firstCheckpoint!.key,
            checkpointRuns: [
                VibeLaneCheckpointRun(
                    checkpointKey: definition.laneSnapshot.firstCheckpoint!.key,
                    status: .stopped,
                    stopReason: .error
                )
            ]
        )
        let laneManager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(
                lanes: [definition.laneSnapshot],
                tasks: [task]
            ),
            worker: VibeLoopHangingWorker()
        )
        await laneManager.bootstrap(resumeRunning: false)
        defer { laneManager.shutdown() }
        let store = InMemoryVibeLoopStore(
            definitions: [definition],
            runRecords: [
                VibeLoopRunRecord(
                    id: occurrenceID,
                    loopID: definition.id,
                    scheduledAt: clock.now,
                    triggeredAt: clock.now,
                    disposition: .started,
                    taskID: task.id
                )
            ]
        )
        let manager = VibeLoopManager(store: store, laneManager: laneManager, clock: clock)

        await manager.bootstrap()

        XCTAssertEqual(manager.runRecords.first?.taskState, .stopped)
        XCTAssertEqual(manager.runRecords.first?.taskStopReason, .error)
        XCTAssertEqual(store.loadRunRecords().first?.taskState, .stopped)
    }

    func test_bootstrapRetriesClaimedPendingOccurrenceWithoutTask() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let scheduledAt = Date(timeIntervalSince1970: 900)
        let occurrenceID = VibeLoopOccurrenceID.make(
            loopID: definition.id,
            scheduledAt: scheduledAt
        )
        let laneManager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(lanes: [definition.laneSnapshot]),
            worker: VibeLoopHangingWorker()
        )
        await laneManager.bootstrap(resumeRunning: false)
        defer { laneManager.shutdown() }
        let store = InMemoryVibeLoopStore(
            definitions: [definition],
            runtimeStates: [
                VibeLoopRuntimeState(
                    loopID: definition.id,
                    lastClaimedScheduledAt: scheduledAt
                )
            ],
            runRecords: [
                VibeLoopRunRecord(
                    id: occurrenceID,
                    loopID: definition.id,
                    scheduledAt: scheduledAt,
                    disposition: .pending
                )
            ]
        )
        let manager = VibeLoopManager(store: store, laneManager: laneManager, clock: clock)

        await manager.bootstrap()

        XCTAssertEqual(laneManager.tasks.count, 1)
        XCTAssertEqual(manager.runRecords.first?.disposition, .started)
        XCTAssertEqual(manager.runRecords.first?.taskState, .running)
        XCTAssertEqual(manager.runRecords.first?.taskID, laneManager.tasks.first?.id)
    }

    func test_pausedPendingOccurrenceWaitsForExplicitResume() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        var definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        definition.isEnabled = false
        let scheduledAt = Date(timeIntervalSince1970: 900)
        let occurrenceID = VibeLoopOccurrenceID.make(
            loopID: definition.id,
            scheduledAt: scheduledAt
        )
        let laneManager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(lanes: [definition.laneSnapshot]),
            worker: VibeLoopHangingWorker()
        )
        await laneManager.bootstrap(resumeRunning: false)
        defer { laneManager.shutdown() }
        let store = InMemoryVibeLoopStore(
            definitions: [definition],
            runtimeStates: [
                VibeLoopRuntimeState(
                    loopID: definition.id,
                    lastClaimedScheduledAt: scheduledAt
                )
            ],
            runRecords: [
                VibeLoopRunRecord(
                    id: occurrenceID,
                    loopID: definition.id,
                    scheduledAt: scheduledAt,
                    disposition: .pending
                )
            ]
        )
        let manager = VibeLoopManager(store: store, laneManager: laneManager, clock: clock)

        await manager.bootstrap()

        XCTAssertTrue(laneManager.tasks.isEmpty)
        XCTAssertEqual(manager.runRecords.first?.disposition, .pending)

        let didResume = await manager.setEnabled(
            true,
            id: definition.id,
            confirmsFullTrust: true
        )
        XCTAssertTrue(didResume)
        await manager.reconcileDueLoops()

        XCTAssertEqual(laneManager.tasks.count, 1)
        XCTAssertEqual(manager.runRecords.first?.disposition, .started)
        XCTAssertEqual(manager.runRecords.first?.taskID, laneManager.tasks.first?.id)
    }

    func test_bootstrapSynthesizesMissingRunRecordFromCanonicalLaneTask() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let scheduledAt = Date(timeIntervalSince1970: 900)
        let occurrenceID = VibeLoopOccurrenceID.make(
            loopID: definition.id,
            scheduledAt: scheduledAt
        )
        let laneManager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(lanes: [definition.laneSnapshot]),
            worker: VibeLoopHangingWorker()
        )
        await laneManager.bootstrap(resumeRunning: false)
        defer { laneManager.shutdown() }
        let task = await laneManager.createTask(
            laneSnapshot: definition.laneSnapshot,
            title: definition.taskInstruction,
            projectPath: projectURL.path,
            origin: .loop(
                loopID: definition.id,
                occurrenceID: occurrenceID,
                scheduledAt: scheduledAt
            )
        )!
        let store = InMemoryVibeLoopStore(definitions: [definition])
        let manager = VibeLoopManager(store: store, laneManager: laneManager, clock: clock)

        await manager.bootstrap()

        XCTAssertEqual(manager.runRecords.count, 1)
        XCTAssertEqual(manager.runRecords.first?.id, occurrenceID)
        XCTAssertEqual(manager.runRecords.first?.taskID, task.id)
        XCTAssertEqual(manager.runRecords.first?.taskState, .running)
        XCTAssertEqual(
            manager.runtimeStates[definition.id]?.lastClaimedScheduledAt,
            scheduledAt
        )
    }

    func test_runNowDoesNotMoveScheduledClaim() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }

        let run = await setup.loopManager.runNow(id: definition.id)

        XCTAssertEqual(run?.disposition, .started)
        XCTAssertNil(setup.loopManager.runtimeStates[definition.id]?.lastClaimedScheduledAt)
        XCTAssertEqual(
            setup.loopManager.nextRunDate(for: definition),
            Date(timeIntervalSince1970: 900)
        )
    }

    func test_invalidTargetCanAlwaysBePaused() async throws {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        try FileManager.default.removeItem(at: projectURL)

        let didPause = await setup.loopManager.setEnabled(false, id: definition.id)
        XCTAssertTrue(didPause)
        XCTAssertEqual(setup.loopManager.definition(withID: definition.id)?.isEnabled, false)
        XCTAssertEqual(
            setup.loopManager.validationFailure(for: definition)?.kind,
            .invalidProject
        )
    }

    func test_everyLoopRequiresFullTrustConfirmationBeforeQuickEnable() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        var definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        definition.isEnabled = false
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }

        let enabledWithoutConfirmation = await setup.loopManager.setEnabled(
            true,
            id: definition.id
        )
        XCTAssertFalse(enabledWithoutConfirmation)
        XCTAssertEqual(setup.loopManager.definition(withID: definition.id)?.isEnabled, false)
        let enabledWithConfirmation = await setup.loopManager.setEnabled(
            true,
            id: definition.id,
            confirmsFullTrust: true
        )
        XCTAssertTrue(enabledWithConfirmation)
        XCTAssertEqual(setup.loopManager.definition(withID: definition.id)?.isEnabled, true)
    }

    func test_clockRollbackDoesNotRepeatClaimedOccurrence() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }

        await setup.loopManager.reconcileDueLoops()
        clock.value = Date(timeIntervalSince1970: 950)
        await setup.loopManager.reconcileDueLoops()

        XCTAssertEqual(setup.loopManager.runRecords.count, 1)
    }

    func test_pendingRecoveryLinksExistingOccurrenceTask() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let laneStore = InMemoryVibeLaneStore(lanes: [definition.laneSnapshot])
        let laneManager = VibeLaneTaskManager(
            store: laneStore,
            worker: VibeLoopHangingWorker()
        )
        await laneManager.bootstrap(resumeRunning: false)
        defer { laneManager.shutdown() }
        let scheduledAt = Date(timeIntervalSince1970: 900)
        let occurrenceID = VibeLoopOccurrenceID.make(loopID: definition.id, scheduledAt: scheduledAt)
        let task = await laneManager.createTask(
            laneSnapshot: definition.laneSnapshot,
            title: definition.taskInstruction,
            projectPath: projectURL.path,
            origin: .loop(
                loopID: definition.id,
                occurrenceID: occurrenceID,
                scheduledAt: scheduledAt
            )
        )!
        let loopStore = InMemoryVibeLoopStore(
            definitions: [definition],
            runRecords: [
                VibeLoopRunRecord(
                    id: occurrenceID,
                    loopID: definition.id,
                    scheduledAt: scheduledAt,
                    disposition: .pending
                )
            ]
        )
        let manager = VibeLoopManager(store: loopStore, laneManager: laneManager, clock: clock)

        await manager.bootstrap()

        XCTAssertEqual(manager.runRecords.first?.disposition, .started)
        XCTAssertEqual(manager.runRecords.first?.taskID, task.id)
        XCTAssertEqual(laneManager.tasks.count, 1)
    }

    func test_loopRunsFrozenLaneSnapshotUntilExplicitUpdate() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        var edited = setup.lane
        edited.name = "Updated lane"
        guard let latest = await setup.laneManager.updateLane(edited) else {
            return XCTFail("Expected lane update to persist")
        }

        XCTAssertTrue(setup.loopManager.hasLaneUpdate(for: definition))
        let run = await setup.loopManager.runNow(id: definition.id)
        let task = run?.taskID.flatMap(setup.laneManager.task(withID:))

        XCTAssertEqual(task?.laneVersion, definition.laneVersion)
        XCTAssertNotEqual(task?.laneVersion, latest.version)
        XCTAssertEqual(task.flatMap(setup.laneManager.resolvedLane(for:))?.name, definition.laneSnapshot.name)
    }

    func test_legacyVibeLaneTaskDecodesManualOrigin() async throws {
        let lane = makeLane()
        let task = VibeLaneTask(
            projectPath: projectURL.path,
            title: "Legacy",
            laneID: lane.id,
            laneVersion: lane.version,
            currentCheckpointKey: lane.firstCheckpoint!.key
        )
        let encoded = try JSONEncoder().encode(task)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "origin")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(VibeLaneTask.self, from: legacy)

        XCTAssertEqual(decoded.origin, .manual)
    }

    func test_automationSurfaceIsGlobalWithoutVibeSpace() async {
        let store = AppShellStore()
        let context = HomeShellContext(store: store)

        context.presentAutomation()

        XCTAssertEqual(store.activeSurface, .automation)
        XCTAssertFalse(store.isShowingHome)
        XCTAssertEqual(AppSideMenuItem.automation.title, AppStrings.Automation.title)
        XCTAssertEqual(
            context.activeAppSideMenuItem(
                hasAnyVibeSpace: false,
                showsVibeSpaceSidebar: false,
                walkthroughPresented: false
            ),
            .automation
        )
    }

    // MARK: - Unreadable durable state must not be overwritten

    /// Regression: a failed load used to reset the published collections to empty,
    /// so Automation looked like "no schedules yet" and the next save persisted
    /// that empty view over the durable rows. The state is now preserved and
    /// writes are refused until a load succeeds.
    func test_bootstrapLoadFailure_preservesStateAndRefusesWrites() async {
        let clock = MutableVibeLoopClock(Date(timeIntervalSince1970: 1_000))
        let definition = makeDefinition(createdAt: Date(timeIntervalSince1970: 100))
        let setup = await makeManagers(clock: clock, definitions: [definition])
        defer { setup.laneManager.shutdown() }
        defer { setup.loopManager.shutdown() }
        let store = setup.loopManager.store as! InMemoryVibeLoopStore
        XCTAssertEqual(setup.loopManager.definitions.count, 1)

        store.shouldFailLoads = true
        await setup.loopManager.bootstrap()

        XCTAssertEqual(
            setup.loopManager.definitions.map(\.id),
            [definition.id],
            "a failed load must not clear the in-memory schedules"
        )
        XCTAssertNotNil(setup.loopManager.persistenceError)

        // Any write while the durable state is unknown must be refused, so a
        // partial view can never replace good rows.
        var edited = definition
        edited.name = "Renamed during outage"
        let didSave = await setup.loopManager.save(edited)
        XCTAssertFalse(didSave, "writes must be refused while durable state is unreadable")
        XCTAssertEqual(store.loadDefinitions().first?.name, definition.name)

        // Recovering re-enables writes.
        store.shouldFailLoads = false
        await setup.loopManager.bootstrap()
        XCTAssertNil(setup.loopManager.persistenceError)
        let didSaveAfterRecovery = await setup.loopManager.save(edited)
        XCTAssertTrue(didSaveAfterRecovery)
        XCTAssertEqual(store.loadDefinitions().first?.name, "Renamed during outage")
    }

    /// Clear only `lastFailure`, preserving the rest of the runtime projection
    /// (the original test mutated the field in place through the published
    /// dictionary).
    private func clearingFailure(_ manager: VibeLoopManager, id: UUID) -> VibeLoopRuntimeState {
        var runtime = manager.runtimeStates[id] ?? VibeLoopRuntimeState(loopID: id)
        runtime.lastFailure = nil
        return runtime
    }

    private func makeManagers(
        clock: MutableVibeLoopClock,
        definitions: [VibeLoopDefinition]
    ) async -> (        lane: VibeLaneDefinition,
        laneManager: VibeLaneTaskManager,
        loopManager: VibeLoopManager
    ) {
        let lane = definitions.first?.laneSnapshot ?? makeLane()
        let lanes = definitions.isEmpty ? [lane] : definitions.map(\.laneSnapshot)
        let laneManager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(lanes: lanes),
            worker: VibeLoopHangingWorker()
        )
        await laneManager.bootstrap(resumeRunning: false)
        let loopManager = VibeLoopManager(
            store: InMemoryVibeLoopStore(definitions: definitions),
            laneManager: laneManager,
            clock: clock
        )
        await loopManager.bootstrap()
        return (lane, laneManager, loopManager)
    }

    private func assertState(
        _ manager: VibeLoopManager,
        loopID: UUID,
        schedule: VibeLoopScheduleState,
        execution: VibeLoopExecutionState,
        status: VibeLoopStatus,
        activeTaskID: UUID? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let definition = manager.definition(withID: loopID) else {
            XCTFail("Missing Loop definition", file: file, line: line)
            return
        }
        let state = manager.state(for: definition)
        XCTAssertEqual(state.schedule, schedule, file: file, line: line)
        XCTAssertEqual(state.execution, execution, file: file, line: line)
        XCTAssertEqual(state.status, status, file: file, line: line)
        XCTAssertEqual(state.activeTaskID, activeTaskID, file: file, line: line)
    }

    private func makeDefinition(createdAt: Date) -> VibeLoopDefinition {
        VibeLoopDefinition(
            name: "Project health",
            projectPath: projectURL.path,
            taskInstruction: "Review the project",
            laneSnapshot: makeLane(),
            schedule: .interval(
                anchor: Date(timeIntervalSince1970: 0),
                seconds: 900
            ),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeLane() -> VibeLaneDefinition {
        VibeLaneDefinition(
            name: "Review lane",
            checkpoints: [
                VibeLaneCheckpoint(
                    key: "review",
                    order: 0,
                    goal: "Review the project",
                    verify: VibeLaneVerificationDefinition("The review is complete")
                )
            ]
        )
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
