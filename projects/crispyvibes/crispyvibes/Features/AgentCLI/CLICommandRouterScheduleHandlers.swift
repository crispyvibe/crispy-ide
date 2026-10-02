import Foundation

/// CLI adapters for Schedules (internally `VibeLoopDefinition`). Enabled
/// mutations require explicit Full Trust acknowledgement before manager calls.
extension CLICommandRouter {
    func handleScheduleList(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        let filter = request.params?["status"]?.stringValue
        let allowed = ["scheduled", "active", "needs-you", "paused", "blocked"]
        if let filter, !allowed.contains(filter) {
            return automationInvalid(request, "`status` must be one of: \(allowed.joined(separator: ", "))")
        }
        let schedules = manager.definitions
            .filter { filter == nil || Self.scheduleStatus($0, manager: manager) == filter }
            .map { Self.scheduleJSON($0, manager: manager) }
        return .ok(id: request.id, result: ["schedules": .array(schedules)])
    }

    func handleScheduleShow(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard let schedule = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        return .ok(id: request.id, result: ["schedule": Self.scheduleJSON(schedule, manager: manager)])
    }

    func handleScheduleCreate(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        do {
            let schedule = try Self.decodeScheduleDocument(request.params?["document"], manager: manager)
            guard manager.definition(withID: schedule.id) == nil else {
                return automationInvalid(request, "a schedule with id `\(schedule.id.uuidString)` already exists")
            }
            if schedule.isEnabled && !confirmsFullTrust(request) { return fullTrustRequired(request) }
            if let failure = manager.validationFailure(for: schedule) {
                return automationInvalid(request, failure.detail)
            }
            guard await manager.save(schedule) else {
                return automationPersistenceFailed(request, manager.persistenceError)
            }
            let saved = manager.definition(withID: schedule.id) ?? schedule
            return .ok(id: request.id, result: ["schedule": Self.scheduleJSON(saved, manager: manager)])
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleScheduleUpdate(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard let current = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        do {
            var proposed = try Self.decodeScheduleDocument(request.params?["document"], base: current, manager: manager)
            proposed.id = current.id
            proposed.createdAt = current.createdAt
            if proposed.isEnabled && !confirmsFullTrust(request) { return fullTrustRequired(request) }
            if let failure = manager.validationFailure(for: proposed) {
                return automationInvalid(request, failure.detail)
            }
            guard await manager.save(proposed) else {
                return automationPersistenceFailed(request, manager.persistenceError)
            }
            let saved = manager.definition(withID: current.id) ?? proposed
            return .ok(id: request.id, result: ["schedule": Self.scheduleJSON(saved, manager: manager)])
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleSchedulePause(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard let schedule = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        guard await manager.setEnabled(false, id: schedule.id) else {
            return automationPersistenceFailed(request, manager.persistenceError)
        }
        guard let updated = manager.definition(withID: schedule.id) else {
            return automationPersistenceFailed(request, "schedule disappeared after mutation")
        }
        return .ok(id: request.id, result: ["schedule": Self.scheduleJSON(updated, manager: manager)])
    }

    func handleScheduleEnable(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard let schedule = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        guard confirmsFullTrust(request) else { return fullTrustRequired(request) }
        guard await manager.setEnabled(true, id: schedule.id, confirmsFullTrust: true) else {
            return automationPersistenceFailed(request, manager.persistenceError)
        }
        guard let updated = manager.definition(withID: schedule.id) else {
            return automationPersistenceFailed(request, "schedule disappeared after mutation")
        }
        return .ok(id: request.id, result: ["schedule": Self.scheduleJSON(updated, manager: manager)])
    }

    func handleScheduleAdoptLane(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard var schedule = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        guard let laneReference = request.params?["lane"]?.stringValue,
              let lane = Self.resolveLane(laneReference, manager: manager.laneManager) else {
            return automationInvalid(request, "lane not found or ambiguous")
        }
        if schedule.isEnabled && !confirmsFullTrust(request) { return fullTrustRequired(request) }
        schedule.updateLaneSnapshot(lane)
        guard await manager.save(schedule) else {
            return automationPersistenceFailed(request, manager.persistenceError)
        }
        guard let updated = manager.definition(withID: schedule.id) else {
            return automationPersistenceFailed(request, "schedule disappeared after mutation")
        }
        return .ok(id: request.id, result: ["schedule": Self.scheduleJSON(updated, manager: manager)])
    }

    func handleScheduleRunNow(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard let schedule = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        guard let run = await manager.runNow(id: schedule.id) else {
            return automationPersistenceFailed(request, manager.persistenceError)
        }
        return .ok(id: request.id, result: ["run": Self.runJSON(run)])
    }

    func handleScheduleRuns(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard let schedule = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        let limit = request.params?["limit"]?.intValue ?? 50
        guard (1...200).contains(limit) else { return automationInvalid(request, "`limit` must be between 1 and 200") }
        return .ok(id: request.id, result: [
            "runs": .array(manager.runs(for: schedule.id).prefix(limit).map(Self.runJSON)),
        ])
    }

    func handleScheduleDelete(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLoopManager else { return automationUnavailable(request, "schedules") }
        guard let schedule = resolvedSchedule(request, manager: manager) else {
            return automationInvalid(request, "schedule not found or ambiguous")
        }
        let stopActive = request.params?["stopActive"]?.boolValue ?? false
        guard await manager.delete(id: schedule.id, stopActiveRun: stopActive) else {
            return automationPersistenceFailed(request, manager.persistenceError)
        }
        return .ok(id: request.id, result: ["deleted": .bool(true), "id": .string(schedule.id.uuidString)])
    }

    func handleSchedulePreview(_ request: CLIRequest) async -> CLIResponse {
        do {
            guard case .object(let document)? = request.params?["document"] else {
                throw AutomationCLIInputError("`document` must be a recurrence object or contain `recurrence`")
            }
            let recurrence = document["recurrence"] ?? .object(document)
            let schedule = try Self.decodeRecurrence(recurrence)
            try VibeLoopScheduleCalculator.validate(schedule)
            let count = request.params?["count"]?.intValue ?? document["count"]?.intValue ?? 5
            guard (1...50).contains(count) else { throw AutomationCLIInputError("`count` must be between 1 and 50") }
            let afterRaw = request.params?["after"]?.stringValue ?? document["after"]?.stringValue
            let after = try afterRaw.map(Self.parseDate) ?? Date()
            var cursor = after
            var dates: [CLIJSONValue] = []
            for _ in 0..<count {
                guard let next = VibeLoopScheduleCalculator.nextOccurrence(after: cursor, schedule: schedule) else { break }
                dates.append(.string(Self.automationDateString(next)))
                cursor = next
            }
            return .ok(id: request.id, result: ["occurrences": .array(dates)])
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    private func resolvedSchedule(_ request: CLIRequest, manager: VibeLoopManager) -> VibeLoopDefinition? {
        guard let reference = request.params?["id"]?.stringValue
            ?? request.params?["schedule"]?.stringValue else { return nil }
        if let id = UUID(uuidString: reference) { return manager.definition(withID: id) }
        let matches = manager.definitions.filter { $0.name.localizedCaseInsensitiveCompare(reference) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    private func confirmsFullTrust(_ request: CLIRequest) -> Bool {
        request.params?["confirmFullTrust"]?.boolValue == true
    }

    private func fullTrustRequired(_ request: CLIRequest) -> CLIResponse {
        automationInvalid(request, "`confirmFullTrust: true` is required when the resulting schedule is enabled")
    }

    static func decodeScheduleDocument(
        _ raw: CLIJSONValue?,
        base: VibeLoopDefinition? = nil,
        manager: VibeLoopManager
    ) throws -> VibeLoopDefinition {
        guard case .object(let object)? = raw else { throw AutomationCLIInputError("`document` must be an object") }
        let lane: VibeLaneDefinition
        if let laneValue = object["lane"] {
            let laneObject = laneValue.objectValue
            let reference = laneValue.stringValue ?? laneObject?["id"]?.stringValue ?? ""
            guard let resolved = resolveLane(reference, manager: manager.laneManager) else {
                throw AutomationCLIInputError("document lane was not found or is ambiguous")
            }
            if let version = laneObject?["version"]?.intValue, version != resolved.version {
                throw AutomationCLIInputError("document lane version \(version) is not current (current: \(resolved.version))")
            }
            lane = resolved
        } else if let base {
            lane = base.laneSnapshot
        } else {
            throw AutomationCLIInputError("document.lane is required")
        }
        let recurrence = try object["recurrence"].map(decodeRecurrence) ?? base?.schedule
        guard let recurrence else { throw AutomationCLIInputError("document.recurrence is required") }
        let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? base?.id ?? UUID()
        return VibeLoopDefinition(
            id: id,
            name: object["name"]?.stringValue ?? base?.name ?? "",
            isEnabled: object["enabled"]?.boolValue ?? object["isEnabled"]?.boolValue ?? base?.isEnabled ?? false,
            projectPath: object["projectPath"]?.stringValue ?? base?.projectPath ?? "",
            taskInstruction: object["taskInstruction"]?.stringValue ?? base?.taskInstruction ?? "",
            laneSnapshot: lane,
            schedule: recurrence,
            missedRunPolicy: try object["missedRunPolicy"]?.stringValue.map {
                guard let value = VibeLoopMissedRunPolicy(rawValue: $0) else {
                    throw AutomationCLIInputError("invalid missedRunPolicy: \($0)")
                }
                return value
            } ?? base?.missedRunPolicy ?? .runLatestOnce,
            createdAt: base?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    static func decodeRecurrence(_ raw: CLIJSONValue) throws -> VibeLoopSchedule {
        guard let object = raw.objectValue, let kind = object["kind"]?.stringValue else {
            throw AutomationCLIInputError("recurrence.kind is required")
        }
        switch kind {
        case "interval":
            guard let seconds = object["seconds"]?.intValue else { throw AutomationCLIInputError("recurrence.seconds is required") }
            let anchor = try object["anchor"]?.stringValue.map(parseDate) ?? Date()
            return .interval(anchor: anchor, seconds: seconds)
        case "daily":
            guard let hour = object["hour"]?.intValue, let minute = object["minute"]?.intValue else {
                throw AutomationCLIInputError("daily recurrence requires hour and minute")
            }
            let zone = object["timeZone"]?.stringValue ?? object["timeZoneID"]?.stringValue ?? ""
            return .daily(hour: hour, minute: minute, timeZoneID: zone)
        case "weekly":
            guard let hour = object["hour"]?.intValue, let minute = object["minute"]?.intValue else {
                throw AutomationCLIInputError("weekly recurrence requires hour and minute")
            }
            let values = object["weekdays"]?.arrayValue ?? []
            let weekdays = try Set(values.map { value -> Int in
                if let number = value.intValue { return number }
                guard let name = value.stringValue?.lowercased(), let number = weekdayNumbers[name] else {
                    throw AutomationCLIInputError("invalid weekday")
                }
                return number
            })
            let zone = object["timeZone"]?.stringValue ?? object["timeZoneID"]?.stringValue ?? ""
            return .weekly(weekdays: weekdays, hour: hour, minute: minute, timeZoneID: zone)
        default:
            throw AutomationCLIInputError("recurrence.kind must be interval, daily, or weekly")
        }
    }

    static func resolveLane(_ reference: String, manager: VibeLaneTaskManager) -> VibeLaneDefinition? {
        switch manager.resolveLaneReference(reference) {
        case .resolved(let id): manager.lane(withID: id)
        case .ambiguous, .notFound: nil
        }
    }

    static func scheduleStatus(_ definition: VibeLoopDefinition, manager: VibeLoopManager) -> String {
        let state = manager.state(for: definition)
        switch state.status {
        case .scheduled: return "scheduled"
        case .queued, .running: return "active"
        case .needsInput: return "needs-you"
        case .paused: return "paused"
        case .blocked: return "blocked"
        }
    }

    static func scheduleJSON(_ definition: VibeLoopDefinition, manager: VibeLoopManager) -> CLIJSONValue {
        .object([
            "id": .string(definition.id.uuidString),
            "name": .string(definition.name),
            "enabled": .bool(definition.isEnabled),
            "status": .string(scheduleStatus(definition, manager: manager)),
            "projectPath": .string(definition.projectPath),
            "taskInstruction": .string(definition.taskInstruction),
            "lane": .object([
                "id": .string(definition.laneID.uuidString),
                "version": .int(definition.laneVersion),
                "name": .string(definition.laneSnapshot.name),
            ]),
            "recurrence": recurrenceJSON(definition.schedule),
            "missedRunPolicy": .string(definition.missedRunPolicy.rawValue),
            "createdAt": .string(automationDateString(definition.createdAt)),
            "updatedAt": .string(automationDateString(definition.updatedAt)),
            "nextRunAt": manager.nextRunDate(for: definition).map { .string(automationDateString($0)) } ?? .null,
        ])
    }

    static func recurrenceJSON(_ schedule: VibeLoopSchedule) -> CLIJSONValue {
        switch schedule {
        case .interval(let anchor, let seconds):
            .object(["kind": .string("interval"), "anchor": .string(automationDateString(anchor)), "seconds": .int(seconds)])
        case .daily(let hour, let minute, let zone):
            .object(["kind": .string("daily"), "hour": .int(hour), "minute": .int(minute), "timeZone": .string(zone)])
        case .weekly(let weekdays, let hour, let minute, let zone):
            .object([
                "kind": .string("weekly"),
                "weekdays": .array(weekdays.sorted().map { .string(weekdayNames[$0] ?? String($0)) }),
                "hour": .int(hour), "minute": .int(minute), "timeZone": .string(zone),
            ])
        }
    }

    static func runJSON(_ run: VibeLoopRunRecord) -> CLIJSONValue {
        var object: [String: CLIJSONValue] = [
            "id": .string(run.id.uuidString),
            "scheduleId": .string(run.loopID.uuidString),
            "scheduledAt": .string(automationDateString(run.scheduledAt)),
            "disposition": .string(run.disposition.rawValue),
        ]
        if let date = run.triggeredAt { object["triggeredAt"] = .string(automationDateString(date)) }
        if let taskID = run.taskID { object["taskId"] = .string(taskID.uuidString) }
        if let state = run.taskState { object["taskState"] = .string(state.rawValue) }
        if let reason = run.taskStopReason { object["taskStopReason"] = .string(reason.rawValue) }
        if let detail = run.detail { object["detail"] = .string(detail) }
        return .object(object)
    }

    static let weekdayNumbers = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
    static let weekdayNames = Dictionary(uniqueKeysWithValues: weekdayNumbers.map { ($0.value, $0.key) })
}
