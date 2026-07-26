import Foundation

/// F059 — handlers for the Vibe Lanes CLI: lane authoring (`lane.*`) and task
/// control (`lane.task.*`). Every command is a thin passthrough to the same
/// `VibeLaneTaskManager` the UI observes, so the one-writer invariants (single
/// open request, pinned lane versions, notification chokepoint) hold for both
/// callers. The CLI never reaches into the engine or the store directly.
extension CLICommandRouter {

    // MARK: - lane.list / lane.show

    func handleLaneList(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        let lanes = manager.lanes
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { Self.laneSummaryJSON($0) }
        return .ok(id: request.id, result: ["lanes": .array(lanes)])
    }

    func handleLaneShow(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        switch resolvedLane(from: request, manager: manager) {
        case .success(let lane):
            return .ok(id: request.id, result: ["lane": Self.laneDetailJSON(lane)])
        case .failure(let response):
            return response
        }
    }

    // MARK: - lane.create / lane.update / lane.delete / lane.restoreStarters

    func handleLaneCreate(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        guard let name = request.params?["name"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return laneInvalidParams(request, "`name` is required")
        }
        var checkpoints: [VibeLaneCheckpoint]?
        if let raw = request.params?["checkpoints"] {
            guard let decoded = Self.decodeCheckpoints(raw) else {
                return laneInvalidParams(request, "`checkpoints` does not match the lane checkpoint schema")
            }
            checkpoints = decoded
        }
        // Validate EVERY field before the first write. Creating the lane and then
        // rejecting a later parameter would leave a persisted lane behind after
        // an error response.
        let detail = request.params?["description"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let steerLimit = request.params?["steerLimit"]?.intValue
        if let steerLimit, steerLimit < 0 {
            return laneInvalidParams(request, "`steerLimit` must be >= 0")
        }
        guard var lane = await manager.createLane(name: name) else {
            return lanePersistenceFailed(request, manager: manager)
        }
        if checkpoints != nil || (detail?.isEmpty == false) || steerLimit != nil {
            if let checkpoints { lane.checkpoints = checkpoints }
            if let detail, !detail.isEmpty { lane.detail = detail }
            if let steerLimit { lane.steerLimit = steerLimit }
            guard let updated = await manager.updateLane(lane) else {
                return lanePersistenceFailed(request, manager: manager)
            }
            lane = updated
        }
        return .ok(id: request.id, result: ["lane": Self.laneDetailJSON(lane)])
    }

    func handleLaneUpdate(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        var lane: VibeLaneDefinition
        switch resolvedLane(from: request, manager: manager) {
        case .success(let resolved): lane = resolved
        case .failure(let response): return response
        }
        var changed = false
        if let name = request.params?["name"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !name.isEmpty else { return laneInvalidParams(request, "`name` cannot be empty") }
            lane.name = name
            changed = true
        }
        if let detail = request.params?["description"]?.stringValue {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            lane.detail = trimmed.isEmpty ? nil : trimmed
            changed = true
        }
        if let steerLimit = request.params?["steerLimit"]?.intValue {
            guard steerLimit >= 0 else { return laneInvalidParams(request, "`steerLimit` must be >= 0") }
            lane.steerLimit = steerLimit
            changed = true
        }
        if let raw = request.params?["checkpoints"] {
            guard let decoded = Self.decodeCheckpoints(raw), !decoded.isEmpty else {
                return laneInvalidParams(request, "`checkpoints` does not match the lane checkpoint schema")
            }
            lane.checkpoints = decoded
            changed = true
        }
        guard changed else {
            return laneInvalidParams(request, "nothing to update: provide `name`, `description`, `steerLimit`, or `checkpoints`")
        }
        guard let updated = await manager.updateLane(lane) else {
            return lanePersistenceFailed(request, manager: manager)
        }
        return .ok(id: request.id, result: ["lane": Self.laneDetailJSON(updated)])
    }

    func handleLaneDelete(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        switch resolvedLane(from: request, manager: manager) {
        case .success(let lane):
            await manager.deleteLane(id: lane.id)
            if manager.lane(withID: lane.id) != nil {
                return lanePersistenceFailed(request, manager: manager)
            }
            return .ok(id: request.id, result: ["deleted": .bool(true), "id": .string(lane.id.uuidString)])
        case .failure(let response):
            return response
        }
    }

    func handleLaneRestoreStarters(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        await manager.restoreStarterLanes()
        let lanes = manager.lanes
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { Self.laneSummaryJSON($0) }
        return .ok(id: request.id, result: ["lanes": .array(lanes)])
    }

    // MARK: - lane.task.create

    func handleLaneTaskCreate(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        let lane: VibeLaneDefinition
        switch resolvedLane(from: request, manager: manager) {
        case .success(let resolved): lane = resolved
        case .failure(let response): return response
        }
        guard let input = request.params?["input"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return laneInvalidParams(request, "`input` is required (the task's per-run instruction)")
        }
        let explicitProject = request.params?["project"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let envProject = request._env?.project_path?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawProject = (explicitProject?.isEmpty == false ? explicitProject : nil)
            ?? envProject
            ?? ""
        guard !rawProject.isEmpty else {
            return laneInvalidParams(request, "`project` is required (no CRISPY_PROJECT_PATH in the caller's environment)")
        }
        let projectPath = URL(fileURLWithPath: rawProject).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return laneInvalidParams(request, "`project` is not a directory: \(projectPath)")
        }
        var initialCarryForward: [String: String] = [:]
        if case .object(let inputObject)? = request.params?["inputs"] {
            for (key, value) in inputObject {
                if let string = value.stringValue { initialCarryForward[key] = string }
            }
        }
        let agentID = request.params?["agent"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let task = await manager.createTask(
            laneID: lane.id,
            title: input,
            projectPath: projectPath,
            agentID: (agentID?.isEmpty == false) ? agentID : nil,
            initialCarryForward: initialCarryForward.isEmpty ? nil : initialCarryForward
        ) else {
            guard lane.isRunnable else {
                return laneInvalidParams(
                    request,
                    "lane needs setup before it can run: \(Self.laneIssueSummary(lane))"
                )
            }
            return .error(id: request.id, code: CLIErrorCode.internalError,
                          message: "task creation failed")
        }
        return .ok(id: request.id, result: ["task": Self.taskSummaryJSON(task, manager: manager)])
    }

    // MARK: - lane.task.list / lane.task.show

    func handleLaneTaskList(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        var filterState: VibeLaneTaskState?
        if let raw = request.params?["state"]?.stringValue, !raw.isEmpty {
            guard let state = VibeLaneTaskState(rawValue: raw) else {
                return laneInvalidParams(request, "`state` must be one of: running, needsInput, stopped, done")
            }
            filterState = state
        }
        let filterProject = request.params?["project"]?.stringValue.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        // Needs-you first, then most recently updated (F059-R09 dashboard order).
        let tasks = manager.tasks
            .filter { filterState == nil || $0.state == filterState }
            .filter { filterProject == nil || $0.projectPath == filterProject }
            .sorted {
                if ($0.state == .needsInput) != ($1.state == .needsInput) {
                    return $0.state == .needsInput
                }
                return $0.updatedAt > $1.updatedAt
            }
            .map { Self.taskSummaryJSON($0, manager: manager) }
        return .ok(id: request.id, result: [
            "tasks": .array(tasks),
            "counts": .object([
                "running": .int(manager.runningCount),
                "needsInput": .int(manager.needsInputCount),
                "stopped": .int(manager.stoppedCount),
                "done": .int(manager.doneCount),
            ]),
        ])
    }

    func handleLaneTaskShow(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        switch resolvedTask(from: request, manager: manager) {
        case .success(let task):
            return .ok(id: request.id, result: ["task": Self.taskDetailJSON(task, manager: manager)])
        case .failure(let response):
            return response
        }
    }

    // MARK: - lane.task.answer

    func handleLaneTaskAnswer(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        let task: VibeLaneTask
        switch resolvedTask(from: request, manager: manager) {
        case .success(let resolved): task = resolved
        case .failure(let response): return response
        }
        guard task.state == .needsInput, let open = task.openInputRequest else {
            return laneInvalidParams(request, "task has no open input request")
        }
        let answered: VibeLaneTask?
        switch open.kind {
        case .supply:
            guard case .object(let raw)? = request.params?["values"] else {
                return laneInvalidParams(request, "open request is Supply: pass `values` for keys: \(open.missingKeys.joined(separator: ", "))")
            }
            var values: [String: String] = [:]
            for (key, value) in raw {
                if let string = value.stringValue { values[key] = string }
            }
            answered = await manager.answerInput(
                id: task.id,
                requestID: open.id,
                values: values
            )
            if answered == nil {
                return laneInvalidParams(request, "supply refused: every missing key needs a non-empty value (\(open.missingKeys.joined(separator: ", ")))")
            }
        case .steer:
            guard let guidance = request.params?["guidance"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines), !guidance.isEmpty else {
                return laneInvalidParams(request, "open request is Steer: pass non-empty `guidance`")
            }
            answered = await manager.answerInput(
                id: task.id,
                requestID: open.id,
                guidance: guidance
            )
            if answered == nil {
                return laneInvalidParams(request, "steer refused (request may have changed; re-run lane.task.show)")
            }
        case .review:
            guard let approve = request.params?["approve"]?.boolValue else {
                return laneInvalidParams(request, "open request is Review: pass `approve` (true|false), with `feedback` when rejecting")
            }
            let feedback = request.params?["feedback"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !approve, feedback?.isEmpty != false {
                return laneInvalidParams(request, "rejection requires non-empty `feedback` (F059-R07)")
            }
            answered = await manager.answerInput(
                id: task.id,
                requestID: open.id,
                approved: approve,
                feedback: feedback
            )
            if answered == nil {
                return laneInvalidParams(request, "review verdict refused (request may have changed; re-run lane.task.show)")
            }
        }
        guard let resumed = answered else {
            return .error(id: request.id, code: CLIErrorCode.internalError, message: "answer was not applied")
        }
        return .ok(id: request.id, result: ["task": Self.taskSummaryJSON(resumed, manager: manager)])
    }

    // MARK: - lane.task.stop / lane.task.delete

    func handleLaneTaskStop(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        switch resolvedTask(from: request, manager: manager) {
        case .success(let task):
            guard !task.isTerminal else {
                return laneInvalidParams(request, "task is already \(task.state.rawValue)")
            }
            guard await manager.stop(id: task.id) else {
                return .error(
                    id: request.id,
                    code: CLIErrorCode.internalError,
                    message: "task stop could not be persisted"
                )
            }
            guard let stopped = manager.task(withID: task.id) else {
                return .error(id: request.id, code: CLIErrorCode.internalError, message: "task disappeared while stopping")
            }
            return .ok(id: request.id, result: ["task": Self.taskSummaryJSON(stopped, manager: manager)])
        case .failure(let response):
            return response
        }
    }

    func handleLaneTaskDelete(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return laneNotConnected(request) }
        switch resolvedTask(from: request, manager: manager) {
        case .success(let task):
            guard await manager.delete(id: task.id) else {
                return lanePersistenceFailed(request, manager: manager)
            }
            return .ok(id: request.id, result: ["deleted": .bool(true), "id": .string(task.id.uuidString)])
        case .failure(let response):
            return response
        }
    }

    // MARK: - Resolution helpers

    /// Local either-type: `Result` requires `Error` conformance, which
    /// `CLIResponse` intentionally is not.
    enum LaneLookup<Value> {
        case success(Value)
        case failure(CLIResponse)
    }

    private func resolvedLane(
        from request: CLIRequest,
        manager: VibeLaneTaskManager
    ) -> LaneLookup<VibeLaneDefinition> {
        guard let reference = request.params?["lane"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty else {
            return .failure(laneInvalidParams(request, "`lane` is required (name or id)"))
        }
        switch manager.resolveLaneReference(reference) {
        case .resolved(let id):
            guard let lane = manager.lane(withID: id) else {
                return .failure(laneInvalidParams(request, "lane not found"))
            }
            return .success(lane)
        case .ambiguous(let names):
            return .failure(laneInvalidParams(request, "lane name is ambiguous: \(names.joined(separator: ", "))"))
        case .notFound:
            return .failure(laneInvalidParams(request, "lane not found: \(reference)"))
        }
    }

    private func resolvedTask(
        from request: CLIRequest,
        manager: VibeLaneTaskManager
    ) -> LaneLookup<VibeLaneTask> {
        guard let raw = request.params?["id"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure(laneInvalidParams(request, "`id` is required"))
        }
        guard let id = UUID(uuidString: CLITaggedID.extractID(from: raw, expectedKind: "lanetask")) else {
            return .failure(laneInvalidParams(request, "`id` is not a UUID: \(raw)"))
        }
        guard let task = manager.task(withID: id) else {
            return .failure(laneInvalidParams(request, "task not found: \(id.uuidString)"))
        }
        return .success(task)
    }

    /// Decode a `checkpoints` param (CLI JSON) into lane checkpoints by
    /// round-tripping through the Codable lane schema, then normalizing keys
    /// exactly like the UI editor save path (F059-R01).
    static func decodeCheckpoints(_ raw: CLIJSONValue) -> [VibeLaneCheckpoint]? {
        guard case .array = raw else { return nil }
        guard let data = try? JSONEncoder().encode(raw),
              let decoded = try? JSONDecoder().decode([VibeLaneCheckpoint].self, from: data) else {
            return nil
        }
        return VibeLaneTaskManager.normalizedCheckpoints(decoded)
    }

    // MARK: - Serialization

    private static let laneDateFormatter = ISO8601DateFormatter()

    private static func dateString(_ date: Date) -> CLIJSONValue {
        .string(laneDateFormatter.string(from: date))
    }

    /// Machine-readable reason a lane is not runnable, for CLI error messages.
    static func laneIssueSummary(_ lane: VibeLaneDefinition) -> String {
        let issues = lane.validationIssues.map { issue -> String in
            switch issue {
            case .missingLaneName: "missing name"
            case .missingCheckpoints: "no steps"
            case .invalidSteerLimit: "invalid steerLimit"
            case .emptyCheckpointKey(let index): "step \(index + 1) has an empty key"
            case .duplicateCheckpointKey(let index): "step \(index + 1) has a duplicate key"
            case .missingGoal(let index): "step \(index + 1) has no goal"
            case .missingVerification(let index): "step \(index + 1) has no verification"
            case .invalidBounds(let index): "step \(index + 1) has invalid bounds"
            case .emptyInputKey(let index): "step \(index + 1) has an empty input key"
            case .duplicateInputKey(let index, let key): "step \(index + 1) repeats input `\(key)`"
            case .emptyOutputKey(let index): "step \(index + 1) has an empty output key"
            case .duplicateOutputKey(let index, let key): "step \(index + 1) repeats output `\(key)`"
            case .unsatisfiedInput(let index, let key): "step \(index + 1) needs unavailable input `\(key)`"
            case .unresolvedVibeReference(let index, let vibeID, let version):
                "step \(index + 1) points at missing Vibe \(vibeID.uuidString) v\(version)"
            }
        }
        return issues.isEmpty ? "unknown" : issues.joined(separator: "; ")
    }

    static func laneSummaryJSON(_ lane: VibeLaneDefinition) -> CLIJSONValue {
        var obj: [String: CLIJSONValue] = [
            "id": .string(lane.id.uuidString),
            "name": .string(lane.name),
            "version": .int(lane.version),
            "steerLimit": .int(lane.steerLimit),
            "checkpointCount": .int(lane.checkpoints.count),
            "route": .string(lane.routeSummary),
            "starter": .bool(lane.seededFingerprint != nil),
        ]
        if let detail = lane.detail { obj["description"] = .string(detail) }
        return .object(obj)
    }

    static func laneDetailJSON(_ lane: VibeLaneDefinition) -> CLIJSONValue {
        guard case .object(var obj) = laneSummaryJSON(lane) else { return .null }
        obj["checkpoints"] = .array(lane.orderedCheckpoints.map { checkpointJSON($0) })
        return .object(obj)
    }

    private static func checkpointJSON(_ checkpoint: VibeLaneCheckpoint) -> CLIJSONValue {
        var verification: [String: CLIJSONValue] = [
            "definition": .string(checkpoint.verify.definition),
            "humanReview": .bool(checkpoint.verify.humanReview),
        ]
        if !checkpoint.verify.reviewSkills.isEmpty {
            verification["reviewSkills"] = .array(
                checkpoint.verify.reviewSkills.map { .string($0) }
            )
        }
        var obj: [String: CLIJSONValue] = [
            "key": .string(checkpoint.key),
            "order": .int(checkpoint.order),
            "goal": .string(checkpoint.goal),
            "verify": .object(verification),
            "bounds": .object([
                "maxAttempts": .int(checkpoint.bounds.maxAttempts),
                "timeoutSeconds": .int(checkpoint.bounds.timeoutSeconds),
                "onExhausted": .string(checkpoint.bounds.onExhausted.rawValue),
            ]),
        ]
        if let title = checkpoint.title { obj["title"] = .string(title) }
        if !checkpoint.instructions.isEmpty { obj["instructions"] = .string(checkpoint.instructions) }
        if !checkpoint.skills.isEmpty { obj["skills"] = .array(checkpoint.skills.map { .string($0) }) }
        if !checkpoint.inputRequirements.isEmpty {
            obj["requires"] = .array(checkpoint.inputRequirements.map {
                .object(["key": .string($0.key), "askUser": .bool($0.askUser)])
            })
        }
        if !checkpoint.outputDeclarations.isEmpty {
            obj["produces"] = .array(checkpoint.outputDeclarations.map { .string($0.key) })
        }
        return .object(obj)
    }

    static func taskSummaryJSON(_ task: VibeLaneTask, manager: VibeLaneTaskManager) -> CLIJSONValue {
        var obj: [String: CLIJSONValue] = [
            "id": .string(task.id.uuidString),
            "title": .string(task.title),
            "state": .string(task.state.rawValue),
            "projectPath": .string(task.projectPath),
            "laneId": .string(task.laneID.uuidString),
            "laneVersion": .int(task.laneVersion),
            "currentCheckpoint": .string(task.currentCheckpointKey),
            "attemptsOnCurrentCheckpoint": .int(task.attemptsOnCurrentCheckpoint),
            "createdAt": dateString(task.createdAt),
            "updatedAt": dateString(task.updatedAt),
        ]
        if let lane = manager.resolvedLane(for: task) { obj["lane"] = .string(lane.name) }
        if let reason = task.stopReason { obj["stopReason"] = .string(reason.rawValue) }
        if let activity = task.currentActivity { obj["currentActivity"] = .string(activity) }
        if let request = task.openInputRequest { obj["openRequest"] = inputRequestJSON(request) }
        return .object(obj)
    }

    static func taskDetailJSON(_ task: VibeLaneTask, manager: VibeLaneTaskManager) -> CLIJSONValue {
        guard case .object(var obj) = taskSummaryJSON(task, manager: manager) else { return .null }
        if let lane = manager.resolvedLane(for: task) { obj["route"] = .string(lane.routeSummary) }
        if let agentID = task.agentID { obj["agent"] = .string(agentID) }
        if let carried = task.carryForward, !carried.isEmpty {
            obj["carryForward"] = .object(carried.mapValues { .string($0) })
        }
        if let verification = task.lastVerification {
            var verify: [String: CLIJSONValue] = ["passed": .bool(verification.passed)]
            if let detail = verification.detail { verify["detail"] = .string(detail) }
            if let feedback = verification.feedback { verify["feedback"] = .string(feedback) }
            obj["lastVerification"] = .object(verify)
        }
        if let outcome = task.outcomeSummary { obj["outcome"] = .string(outcome) }
        obj["steerCount"] = .int(task.steerCount)
        obj["checkpointRuns"] = .array(task.checkpointRuns.map { run in
            var runObj: [String: CLIJSONValue] = [
                "checkpoint": .string(run.checkpointKey),
                "status": .string(run.status.rawValue),
                "attempts": .int(run.attempts.count),
            ]
            if let reason = run.stopReason { runObj["stopReason"] = .string(reason.rawValue) }
            if let summary = run.summary { runObj["summary"] = .string(summary) }
            return .object(runObj)
        })
        return .object(obj)
    }

    private static func inputRequestJSON(_ request: VibeLaneInputRequest) -> CLIJSONValue {
        var obj: [String: CLIJSONValue] = [
            "id": .string(request.id.uuidString),
            "kind": .string(request.kind.rawValue),
            "checkpoint": .string(request.checkpointKey),
            "prompt": .string(request.prompt),
        ]
        if !request.missingKeys.isEmpty {
            obj["missingKeys"] = .array(request.missingKeys.map { .string($0) })
        }
        if let feedback = request.lastFeedback { obj["lastFeedback"] = .string(feedback) }
        if let reason = request.reason { obj["reason"] = .string(reason.rawValue) }
        return .object(obj)
    }

    // MARK: - Error helpers

    private func laneInvalidParams(_ request: CLIRequest, _ message: String) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.invalidParams, message: message)
    }

    private func laneNotConnected(_ request: CLIRequest) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.notConnected, message: "vibe lanes unavailable")
    }

    private func lanePersistenceFailed(
        _ request: CLIRequest,
        manager: VibeLaneTaskManager
    ) -> CLIResponse {
        .error(
            id: request.id,
            code: CLIErrorCode.internalError,
            message: manager.persistenceError ?? "Vibe Lane persistence failed"
        )
    }
}
