import Foundation

/// CLI adapters for central Vibe definitions. Mutations always pass through
/// `VibeLaneTaskManager`; validation additionally uses the attached Skill store.
extension CLICommandRouter {
    func handleVibeList(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return automationUnavailable(request, "vibes") }
        guard let skillStore = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        let category = request.params?["category"]?.stringValue
        let status = request.params?["status"]?.stringValue
        if let status, !["ready", "needs-setup"].contains(status) {
            return automationInvalid(request, "`status` must be ready or needs-setup")
        }
        let vibes = manager.vibes
            .filter { vibe in
                guard let category else { return true }
                return vibe.category.id == category
                    || vibe.category.name.localizedCaseInsensitiveCompare(category) == .orderedSame
            }
            .filter { vibe in
                guard let status else { return true }
                let isReady = Self.vibeValidationIssues(vibe, skillStore: skillStore).isEmpty
                return (status == "ready") == isReady
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { Self.vibeJSON($0, manager: manager, skillStore: skillStore) }
        return .ok(id: request.id, result: ["vibes": .array(vibes)])
    }

    func handleVibeShow(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return automationUnavailable(request, "vibes") }
        guard let skillStore = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        guard let vibe = resolvedVibe(request, manager: manager) else {
            return automationInvalid(request, "vibe not found or ambiguous")
        }
        return .ok(
            id: request.id,
            result: ["vibe": Self.vibeJSON(vibe, manager: manager, skillStore: skillStore)]
        )
    }

    func handleVibeValidate(_ request: CLIRequest) async -> CLIResponse {
        guard vibeLaneTaskManager != nil else { return automationUnavailable(request, "vibes") }
        guard let skillStore = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        do {
            let vibe = try Self.decodeVibeDocument(request.params?["document"])
            let issues = Self.vibeValidationIssues(vibe, skillStore: skillStore)
            return .ok(id: request.id, result: Self.validationResult(issues))
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleVibeCreate(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return automationUnavailable(request, "vibes") }
        guard let skillStore = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        do {
            var vibe = try Self.decodeVibeDocument(request.params?["document"])
            vibe.version = 1
            let issues = Self.vibeValidationIssues(vibe, skillStore: skillStore)
            guard issues.isEmpty else { return automationInvalid(request, issues.joined(separator: "; ")) }
            guard manager.vibe(withID: vibe.id) == nil else {
                return automationInvalid(request, "a vibe with id `\(vibe.id.uuidString)` already exists")
            }
            guard let created = await manager.createVibe(vibe) else {
                return automationPersistenceFailed(request, manager.persistenceError)
            }
            return .ok(
                id: request.id,
                result: ["vibe": Self.vibeJSON(created, manager: manager, skillStore: skillStore)]
            )
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleVibeUpdate(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return automationUnavailable(request, "vibes") }
        guard let skillStore = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        guard let current = resolvedVibe(request, manager: manager) else {
            return automationInvalid(request, "vibe not found or ambiguous")
        }
        if let failure = expectedVersionFailure(
            request,
            currentVersion: current.version,
            resource: "vibe `\(current.id.uuidString)`"
        ) {
            return failure
        }
        do {
            var proposed = try Self.decodeVibeDocument(request.params?["document"], base: current)
            proposed.id = current.id
            proposed.version = current.version
            let issues = Self.vibeValidationIssues(proposed, skillStore: skillStore)
            guard issues.isEmpty else { return automationInvalid(request, issues.joined(separator: "; ")) }
            guard let updated = await manager.updateVibe(proposed) else {
                return automationPersistenceFailed(request, manager.persistenceError)
            }
            return .ok(
                id: request.id,
                result: ["vibe": Self.vibeJSON(updated, manager: manager, skillStore: skillStore)]
            )
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleVibeDelete(_ request: CLIRequest) async -> CLIResponse {
        guard let manager = vibeLaneTaskManager else { return automationUnavailable(request, "vibes") }
        guard let vibe = resolvedVibe(request, manager: manager) else {
            return automationInvalid(request, "vibe not found or ambiguous")
        }
        if let failure = expectedVersionFailure(
            request,
            currentVersion: vibe.version,
            resource: "vibe `\(vibe.id.uuidString)`"
        ) {
            return failure
        }
        guard manager.vibeUsageCount(id: vibe.id) == 0 else {
            return automationInvalid(request, "vibe is referenced by current lanes")
        }
        guard await manager.deleteVibe(id: vibe.id) else {
            return automationPersistenceFailed(request, manager.persistenceError)
        }
        return .ok(id: request.id, result: ["deleted": .bool(true), "id": .string(vibe.id.uuidString)])
    }

    private func resolvedVibe(_ request: CLIRequest, manager: VibeLaneTaskManager) -> VibeDefinition? {
        let raw = request.params?["id"]?.stringValue
            ?? request.params?["vibe"]?.stringValue
        guard let reference = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty else {
            return nil
        }
        if let id = UUID(uuidString: reference) { return manager.vibe(withID: id) }
        let matches = manager.vibes.filter {
            $0.name.localizedCaseInsensitiveCompare(reference) == .orderedSame
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func decodeVibeDocument(_ raw: CLIJSONValue?, base: VibeDefinition? = nil) throws -> VibeDefinition {
        guard case .object(let object)? = raw else { throw AutomationCLIInputError("`document` must be an object") }
        let name = object["name"]?.stringValue ?? base?.name ?? ""
        let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? base?.id ?? UUID()
        let version = object["version"]?.intValue ?? base?.version ?? 1
        let detail: String?
        if let value = object["description"] ?? object["detail"] {
            detail = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).automationNonEmpty
        } else {
            detail = base?.detail
        }
        let categoryID = object["category"]?.stringValue ?? base?.category.id ?? VibeCategory.general.id
        let category = VibeCategory.resolved(
            id: categoryID,
            name: object["categoryName"]?.stringValue ?? base?.category.name,
            systemImage: object["categoryIcon"]?.stringValue ?? base?.category.systemImage
        )
        let workObject = object["work"]?.objectValue
        let work = VibeLaneWorkDefinition(
            goal: workObject?["goal"]?.stringValue ?? base?.work.goal ?? "",
            instructions: workObject?["instructions"]?.stringValue ?? base?.work.instructions ?? "",
            skills: workObject?["skills"]?.arrayValue?.compactMap(\.stringValue) ?? base?.work.skills ?? []
        )
        let verifyObject = object["verify"]?.objectValue
        let verify = VibeLaneVerificationDefinition(
            verifyObject?["definition"]?.stringValue ?? base?.verify.definition ?? "",
            reviewSkills: verifyObject?["reviewSkills"]?.arrayValue?.compactMap(\.stringValue) ?? base?.verify.reviewSkills ?? [],
            humanReview: verifyObject?["humanReview"]?.boolValue ?? base?.verify.humanReview ?? false
        )
        let bounds = try (object["bounds"]?.decode(VibeLaneBounds.self)) ?? base?.bounds ?? .default
        let engine = try (object["engine"]?.decode(VibeLaneEngineConfiguration.self)) ?? base?.engine ?? .default
        return VibeDefinition(
            id: id,
            version: version,
            name: name,
            detail: detail,
            category: category,
            work: work,
            verify: verify,
            bounds: bounds,
            engine: engine
        )
    }

    static func vibeValidationIssues(
        _ vibe: VibeDefinition,
        skillStore: VibeLaneSkillStore
    ) -> [String] {
        var issues: [String] = []
        if vibe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("name is required") }
        if vibe.work.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("work.goal is required") }
        if vibe.verify.isEmpty { issues.append("verify.definition is required") }
        if vibe.bounds.maxAttempts <= 0 { issues.append("bounds.maxAttempts must be positive") }
        if vibe.bounds.timeoutSeconds <= 0 { issues.append("bounds.timeoutSeconds must be positive") }
        for (reference, role) in vibe.work.skills.map({ ($0, VibeLaneSkillRole.work) })
            + vibe.verify.reviewSkills.map({ ($0, VibeLaneSkillRole.review) }) {
            guard let skill = Self.resolveSkill(reference, in: skillStore.skills) else {
                issues.append("skill not found: \(reference)")
                continue
            }
            if !skill.isAssignable(to: role) {
                issues.append("skill `\(reference)` is not assignable to \(role.rawValue)")
            }
        }
        return issues
    }

    static func resolveSkill(_ reference: String, in skills: [VibeLaneSkillDefinition]) -> VibeLaneSkillDefinition? {
        if let exact = skills.first(where: { $0.reference == reference || $0.fileURL.path == reference }) {
            return exact
        }
        let matches = skills.filter { $0.name.localizedCaseInsensitiveCompare(reference) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    static func vibeJSON(
        _ vibe: VibeDefinition,
        manager: VibeLaneTaskManager,
        skillStore: VibeLaneSkillStore
    ) -> CLIJSONValue {
        var object = (try? CLIJSONValue.encode(vibe).objectValue) ?? [:]
        if let detail = object.removeValue(forKey: "detail") { object["description"] = detail }
        object["ready"] = .bool(vibeValidationIssues(vibe, skillStore: skillStore).isEmpty)
        object["usageCount"] = .int(manager.vibeUsageCount(id: vibe.id))
        return .object(object)
    }
}
