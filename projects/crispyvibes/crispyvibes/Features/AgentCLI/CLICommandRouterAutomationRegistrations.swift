import Foundation

extension CLICommandRouter {
    func automationCommandRegistrations() -> [CommandRegistration] {
        let invalid = [CLIErrorCode.invalidParams, CLIErrorCode.notConnected, CLIErrorCode.internalError]
        let versioned = [CLIErrorCode.invalidParams, CLIErrorCode.conflict, CLIErrorCode.notConnected, CLIErrorCode.internalError]
        func command(
            _ method: String,
            _ summary: String,
            params: [ParamDescriptor] = [],
            result: [ResultFieldDescriptor],
            errors: [String]? = nil,
            handler: @escaping (CLIRequest) async -> CLIResponse
        ) -> CommandRegistration {
            CommandRegistration(
                method: method,
                descriptor: CommandDescriptor(
                    summary: summary,
                    params: params,
                    result: result,
                    errors: errors ?? invalid
                ),
                handler: handler
            )
        }
        let id = ParamDescriptor(name: "id", type: "string", required: true, description: "Resource UUID or unambiguous name.")
        let reference = ParamDescriptor(name: "reference", type: "string", required: true, description: "Canonical Skill reference or unambiguous name.")
        let document = ParamDescriptor(name: "document", type: "object", required: true, description: "Complete or command-appropriate JSON resource document.")
        let expectedVersion = ParamDescriptor(name: "expectedVersion", type: "integer", required: true, description: "Current version returned by list/show; stale values return conflict.")
        let trust = ParamDescriptor(name: "confirmFullTrust", type: "boolean", required: false, description: "Explicitly acknowledges unattended Full Trust execution.", defaultValue: .bool(false))
        return [
            command(
                "vibe.list",
                "List central, versioned Vibes.",
                params: [
                    .init(name: "category", type: "string", required: false, description: "Category id or name."),
                    .init(name: "status", type: "string", required: false, description: "ready or needs-setup."),
                ],
                result: [.init(name: "vibes", type: "array", description: "Vibe definitions and readiness.")],
                handler: { [unowned self] in await self.handleVibeList($0) }
            ),
            command(
                "vibe.show",
                "Show one Vibe by UUID or unambiguous name.",
                params: [id],
                result: [.init(name: "vibe", type: "object", description: "Full Vibe definition.")],
                handler: { [unowned self] in await self.handleVibeShow($0) }
            ),
            command(
                "vibe.validate",
                "Validate a Vibe document, including Skill availability and role compatibility, without saving.",
                params: [document],
                result: [
                    .init(name: "valid", type: "boolean", description: "Whether the document is valid."),
                    .init(name: "issues", type: "array", description: "Validation diagnostics."),
                ],
                handler: { [unowned self] in await self.handleVibeValidate($0) }
            ),
            command(
                "vibe.create",
                "Create a complete Vibe from params.document.",
                params: [document],
                result: [.init(name: "vibe", type: "object", description: "Created Vibe.")],
                handler: { [unowned self] in await self.handleVibeCreate($0) }
            ),
            command(
                "vibe.update",
                "Update a Vibe from params.document and create its next manager-owned version.",
                params: [id, document, expectedVersion],
                result: [.init(name: "vibe", type: "object", description: "Updated Vibe.")],
                errors: versioned,
                handler: { [unowned self] in await self.handleVibeUpdate($0) }
            ),
            command(
                "vibe.delete",
                "Delete an unreferenced Vibe.",
                params: [id, expectedVersion],
                result: [.init(name: "deleted", type: "boolean", description: "True when deleted.")],
                errors: versioned,
                handler: { [unowned self] in await self.handleVibeDelete($0) }
            ),
            command(
                "skill.list",
                "List discovered bundled, personal, and linked Skill packages.",
                params: [
                    .init(name: "source", type: "string", required: false, description: "bundled, personal, or linked."),
                    .init(name: "role", type: "string", required: false, description: "work or review."),
                ],
                result: [.init(name: "skills", type: "array", description: "Skill package summaries.")],
                handler: { [unowned self] in await self.handleSkillList($0) }
            ),
            command(
                "skill.show",
                "Show a discovered Skill package.",
                params: [
                    reference,
                    .init(name: "includeBody", type: "boolean", required: false, description: "Include SKILL.md instructions.", defaultValue: .bool(false)),
                ],
                result: [.init(name: "skill", type: "object", description: "Skill details and resources.")],
                handler: { [unowned self] in await self.handleSkillShow($0) }
            ),
            command(
                "skill.validate",
                "Validate an installed reference or external package/collection without importing.",
                params: [
                    .init(name: "reference", type: "string", required: false, description: "Installed Skill reference."),
                    .init(name: "path", type: "string", required: false, description: "External SKILL.md, package, or collection path."),
                ],
                result: [
                    .init(name: "valid", type: "boolean", description: "Whether every package is usable."),
                    .init(name: "issues", type: "array", description: "Validation diagnostics."),
                ],
                handler: { [unowned self] in await self.handleSkillValidate($0) }
            ),
            command(
                "skill.import",
                "Copy complete Skill packages into Crispy, or explicitly link them.",
                params: [
                    .init(name: "path", type: "string", required: true, description: "SKILL.md, package, or collection path."),
                    .init(name: "mode", type: "string", required: false, description: "copy (default) or link.", defaultValue: .string("copy")),
                ],
                result: [.init(name: "skills", type: "array", description: "Imported Skill summaries.")],
                handler: { [unowned self] in await self.handleSkillImport($0) }
            ),
            command(
                "skill.duplicate",
                "Duplicate a complete Skill package into the managed personal library.",
                params: [reference],
                result: [.init(name: "skill", type: "object", description: "Duplicated Skill.")],
                handler: { [unowned self] in await self.handleSkillDuplicate($0) }
            ),
            command(
                "skill.remove",
                "Remove or unlink a Skill only when no current Vibe references it.",
                params: [reference],
                result: [.init(name: "removed", type: "boolean", description: "True when removed or unlinked.")],
                handler: { [unowned self] in await self.handleSkillRemove($0) }
            ),
            command(
                "schedule.list",
                "List Schedules and projected status.",
                params: [.init(name: "status", type: "string", required: false, description: "scheduled, active, needs-you, paused, or blocked.")],
                result: [.init(name: "schedules", type: "array", description: "Schedule summaries.")],
                handler: { [unowned self] in await self.handleScheduleList($0) }
            ),
            command(
                "schedule.show",
                "Show one Schedule and its frozen Lane snapshot identity.",
                params: [id],
                result: [.init(name: "schedule", type: "object", description: "Full Schedule definition.")],
                handler: { [unowned self] in await self.handleScheduleShow($0) }
            ),
            command(
                "schedule.create",
                "Create a Schedule from params.document; paused unless enabled is explicitly requested and confirmed.",
                params: [document, trust],
                result: [.init(name: "schedule", type: "object", description: "Created Schedule.")],
                handler: { [unowned self] in await self.handleScheduleCreate($0) }
            ),
            command(
                "schedule.update",
                "Update a Schedule from params.document; enabled results require Full Trust confirmation.",
                params: [id, document, trust],
                result: [.init(name: "schedule", type: "object", description: "Updated Schedule.")],
                handler: { [unowned self] in await self.handleScheduleUpdate($0) }
            ),
            command(
                "schedule.pause",
                "Pause future Schedule occurrences without stopping an active run.",
                params: [id],
                result: [.init(name: "schedule", type: "object", description: "Paused Schedule.")],
                handler: { [unowned self] in await self.handleSchedulePause($0) }
            ),
            command(
                "schedule.enable",
                "Enable a Schedule after explicit Full Trust confirmation.",
                params: [id, trust],
                result: [.init(name: "schedule", type: "object", description: "Enabled Schedule.")],
                handler: { [unowned self] in await self.handleScheduleEnable($0) }
            ),
            command(
                "schedule.adoptLane",
                "Replace a Schedule's frozen Lane snapshot with the current Lane revision.",
                params: [id, .init(name: "lane", type: "string", required: true, description: "Lane UUID or unambiguous name."), trust],
                result: [.init(name: "schedule", type: "object", description: "Schedule with adopted Lane.")],
                handler: { [unowned self] in await self.handleScheduleAdoptLane($0) }
            ),
            command(
                "schedule.runNow",
                "Run a Schedule immediately without moving its next recurrence.",
                params: [id],
                result: [.init(name: "run", type: "object", description: "Created or overlap-skipped run record.")],
                handler: { [unowned self] in await self.handleScheduleRunNow($0) }
            ),
            command(
                "schedule.adopt-lane",
                "Compatibility alias for schedule.adoptLane.",
                params: [id, .init(name: "lane", type: "string", required: true, description: "Lane UUID or unambiguous name."), trust],
                result: [.init(name: "schedule", type: "object", description: "Schedule with adopted Lane.")],
                handler: { [unowned self] in await self.handleScheduleAdoptLane($0) }
            ),
            command(
                "schedule.run-now",
                "Compatibility alias for schedule.runNow.",
                params: [id],
                result: [.init(name: "run", type: "object", description: "Created or overlap-skipped run record.")],
                handler: { [unowned self] in await self.handleScheduleRunNow($0) }
            ),
            command(
                "schedule.runs",
                "List retained run history for a Schedule.",
                params: [id, .init(name: "limit", type: "integer", required: false, description: "1...200 newest runs.", defaultValue: .int(50))],
                result: [.init(name: "runs", type: "array", description: "Run records, newest first.")],
                handler: { [unowned self] in await self.handleScheduleRuns($0) }
            ),
            command(
                "schedule.delete",
                "Delete a Schedule and its run history, optionally stopping its active Lane task.",
                params: [id, .init(name: "stopActive", type: "boolean", required: false, description: "Stop an active run before deleting.", defaultValue: .bool(false))],
                result: [.init(name: "deleted", type: "boolean", description: "True when deleted.")],
                handler: { [unowned self] in await self.handleScheduleDelete($0) }
            ),
            command(
                "schedule.preview",
                "Validate recurrence in params.document and calculate upcoming occurrences without persistence.",
                params: [
                    document,
                    .init(name: "count", type: "integer", required: false, description: "1...50 occurrences.", defaultValue: .int(5)),
                    .init(name: "after", type: "string", required: false, description: "ISO-8601 preview baseline."),
                ],
                result: [.init(name: "occurrences", type: "array", description: "ISO-8601 occurrence timestamps.")],
                handler: { [unowned self] in await self.handleSchedulePreview($0) }
            ),
        ]
    }
}
