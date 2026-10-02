import Foundation

/// CLI adapters for discovered Skill packages. Package mutations remain owned
/// by `VibeLaneSkillStore`, including link persistence and complete copy import.
extension CLICommandRouter {
    func handleSkillList(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        let sourceRaw = request.params?["source"]?.stringValue
        let roleRaw = request.params?["role"]?.stringValue
        let source = sourceRaw.flatMap(VibeLaneSkillSource.init(rawValue:))
        let role = roleRaw.flatMap(VibeLaneSkillRole.init(rawValue:))
        if sourceRaw != nil && source == nil {
            return automationInvalid(request, "`source` must be bundled, personal, or linked")
        }
        if roleRaw != nil && role == nil {
            return automationInvalid(request, "`role` must be work or review")
        }
        let skills = store.skills
            .filter { source == nil || $0.source == source }
            .filter { role == nil || $0.supports(role!) }
            .map { Self.skillJSON($0, includeBody: false) }
        return .ok(id: request.id, result: ["skills": .array(skills)])
    }

    func handleSkillShow(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        guard let skill = resolvedSkill(request, store: store) else {
            return automationInvalid(request, "skill not found or ambiguous")
        }
        let includeBody = request.params?["includeBody"]?.boolValue ?? false
        return .ok(id: request.id, result: ["skill": Self.skillJSON(skill, includeBody: includeBody)])
    }

    func handleSkillValidate(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        if let skill = resolvedSkill(request, store: store) {
            return .ok(id: request.id, result: Self.validationResult(Self.skillIssues(skill)))
        }
        guard let path = request.params?["path"]?.stringValue
            ?? request.params?["reference"]?.stringValue else {
            return automationInvalid(request, "`path` or `reference` is required")
        }
        do {
            let url = resolvedURL(forPath: path, env: request._env ?? .empty)
            let skills = try store.validateCollection(at: url)
            let issues = skills.flatMap(Self.skillIssues)
            var result = Self.validationResult(issues)
            result["skills"] = .array(skills.map { Self.skillJSON($0, includeBody: false) })
            return .ok(id: request.id, result: result)
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleSkillImport(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        guard let path = request.params?["path"]?.stringValue else {
            return automationInvalid(request, "`path` is required")
        }
        let mode = request.params?["mode"]?.stringValue
            ?? ((request.params?["link"]?.boolValue ?? false) ? "link" : "copy")
        guard mode == "copy" || mode == "link" else {
            return automationInvalid(request, "`mode` must be copy or link")
        }
        do {
            let url = resolvedURL(forPath: path, env: request._env ?? .empty)
            let imported = mode == "link"
                ? try await store.linkCollection(url)
                : try store.copyCollection(url)
            return .ok(id: request.id, result: [
                "mode": .string(mode),
                "skills": .array(imported.map { Self.skillJSON($0, includeBody: false) }),
            ])
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleSkillDuplicate(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        guard let skill = resolvedSkill(request, store: store) else {
            return automationInvalid(request, "skill not found or ambiguous")
        }
        do {
            let duplicate = try store.duplicate(skill)
            return .ok(id: request.id, result: ["skill": Self.skillJSON(duplicate, includeBody: false)])
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    func handleSkillRemove(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibeLaneSkillStore else { return automationUnavailable(request, "skills") }
        guard let manager = vibeLaneTaskManager else { return automationUnavailable(request, "vibes") }
        guard let skill = resolvedSkill(request, store: store) else {
            return automationInvalid(request, "skill not found or ambiguous")
        }
        let users = manager.vibes.filter { vibe in
            let references = vibe.work.skills + vibe.verify.reviewSkills
            return references.contains { reference in
                if Self.resolveSkill(reference, in: store.skills)?.reference == skill.reference {
                    return true
                }
                return reference == skill.rootURL.path
            }
        }
        guard users.isEmpty else {
            return automationInvalid(
                request,
                "skill is referenced by current Vibes: \(users.map(\.name).sorted().joined(separator: ", "))"
            )
        }
        do {
            try await store.remove(skill)
            return .ok(id: request.id, result: ["removed": .bool(true), "reference": .string(skill.reference)])
        } catch {
            return automationInvalid(request, error.localizedDescription)
        }
    }

    private func resolvedSkill(
        _ request: CLIRequest,
        store: VibeLaneSkillStore
    ) -> VibeLaneSkillDefinition? {
        guard let reference = request.params?["reference"]?.stringValue
            ?? request.params?["skill"]?.stringValue else { return nil }
        return Self.resolveSkill(reference, in: store.skills)
    }

    static func skillJSON(_ skill: VibeLaneSkillDefinition, includeBody: Bool) -> CLIJSONValue {
        var object: [String: CLIJSONValue] = [
            "reference": .string(skill.reference),
            "name": .string(skill.name),
            "description": .string(skill.detail),
            "source": .string(skill.source.rawValue),
            "rootPath": .string(skill.rootURL.path),
            "filePath": .string(skill.fileURL.path),
            "category": .string(skill.category),
            "roles": .array(skill.roles.map { .string($0.rawValue) }),
            "interaction": .string(skill.interaction.rawValue),
            "requiredCommands": .array(skill.requiredCommands.map { .string($0) }),
            "validation": .string(skill.validationState.rawValue),
            "issues": .array(Self.skillIssues(skill).map { .string($0) }),
            "resources": .array(skill.resources.map { resource in
                .object([
                    "path": .string(resource.relativePath),
                    "kind": .string(resource.kind.rawValue),
                    "bytes": .int(resource.byteCount),
                ])
            }),
        ]
        if includeBody { object["body"] = .string(skill.body) }
        return .object(object)
    }

    static func skillIssues(_ skill: VibeLaneSkillDefinition) -> [String] {
        skill.issues.map { issue in
            switch issue {
            case .emptyInstructions: "instructions are empty"
            case .missingCommand(let command): "required command is unavailable: \(command)"
            case .missingReference(let path): "referenced package file is missing: \(path)"
            case .resourceScanLimit(let limit): "resource scan stopped at \(limit) files"
            }
        }.sorted()
    }
}
