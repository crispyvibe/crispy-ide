import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
private final class AutomationCLIHangingWorker: VibeLaneWorkRunning {
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return VibeLaneWorkTurn(sessionRef: sessionRef, ok: false)
    }
}

@MainActor
final class CLICommandRouterAutomationHandlersTests: XCTestCase {
    private var container: AppContainer!
    private var router: CLICommandRouter!
    private var laneManager: VibeLaneTaskManager!
    private var skillStore: VibeLaneSkillStore!
    private var loopManager: VibeLoopManager!
    private var root: URL!
    private var project: URL!
    private var lane: VibeLaneDefinition!

    override func setUp() async throws {
        container = AppContainer.makeDefault(resumeVibeLaneTasks: false)
        root = try makeTempDirectory(prefix: "crispy-cli-automation")
        project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        skillStore = VibeLaneSkillStore(
            rootURL: root.appendingPathComponent("skills", isDirectory: true),
            bundledNames: []
        )
        let vibe = VibeDefinition(
            name: "Inspect",
            goal: "Inspect the project",
            verify: VibeLaneVerificationDefinition("Inspection is complete")
        )
        lane = VibeLaneDefinition(
            name: "Inspection Lane",
            checkpoints: [vibe.checkpoint(key: "inspect", order: 0)]
        )
        laneManager = VibeLaneTaskManager(
            store: InMemoryVibeLaneStore(lanes: [lane], vibes: [vibe]),
            worker: AutomationCLIHangingWorker()
        )
        await laneManager.bootstrap()
        loopManager = VibeLoopManager(
            store: InMemoryVibeLoopStore(),
            laneManager: laneManager
        )
        await loopManager.bootstrap()
        router = CLICommandRouter(shelfStore: container.shelfStore)
        router.attachVibeLaneTaskManager(laneManager)
        router.attachVibeLaneSkillStore(skillStore)
        router.attachVibeLoopManager(loopManager)
    }

    override func tearDownWithError() throws {
        loopManager.shutdown()
        laneManager.shutdown()
        router = nil
        loopManager = nil
        skillStore = nil
        laneManager = nil
        container = nil
        try? FileManager.default.removeItem(at: root)
    }

    func test_vibeDocumentValidationAndManagerMutations() async throws {
        let invalid = await router.dispatch(request("vibe.validate", [
            "document": vibeDocument(name: "Broken", goal: "", verify: ""),
        ]))
        let validation = try ok(invalid)
        XCTAssertEqual(validation["valid"]?.boolValue, false)
        XCTAssertFalse(validation["issues"]?.arrayValue?.isEmpty ?? true)

        let createdResult = try ok(await router.dispatch(request("vibe.create", [
            "document": vibeDocument(name: "Build", goal: "Build it", verify: "Build passes"),
        ])))
        let created = try XCTUnwrap(createdResult["vibe"]?.objectValue)
        let id = try XCTUnwrap(created["id"]?.stringValue)
        XCTAssertEqual(created["version"]?.intValue, 1)
        XCTAssertEqual(laneManager.vibes.count, 2)

        let staleUpdate = await router.dispatch(request("vibe.update", [
            "id": .string(id),
            "document": .object(["name": .string("Must not win")]),
            "expectedVersion": .int(99),
        ]))
        XCTAssertEqual(errorCode(staleUpdate), CLIErrorCode.conflict)
        XCTAssertEqual(laneManager.vibe(withID: try XCTUnwrap(UUID(uuidString: id)))?.name, "Build")

        let updated = try ok(await router.dispatch(request("vibe.update", [
            "id": .string(id),
            "document": .object(["name": .string("Build safely")]),
            "expectedVersion": .int(1),
        ])))
        XCTAssertEqual(updated["vibe"]?.objectValue?["version"]?.intValue, 2)
        XCTAssertEqual(updated["vibe"]?.objectValue?["name"]?.stringValue, "Build safely")

        let staleDelete = await router.dispatch(request("vibe.delete", [
            "id": .string(id),
            "expectedVersion": .int(1),
        ]))
        XCTAssertEqual(errorCode(staleDelete), CLIErrorCode.conflict)
        let deleted = try ok(await router.dispatch(request("vibe.delete", [
            "id": .string(id),
            "expectedVersion": .int(2),
        ])))
        XCTAssertEqual(deleted["deleted"]?.boolValue, true)
    }

    func test_vibeListReadinessUsesSkillAvailabilityResourcesAndRoles() async throws {
        let unavailable = try skillStore.create(VibeLaneSkillDraft(
            name: "Unavailable Tool",
            detail: "Has unavailable package dependencies",
            body: "Read [the missing guide](references/missing.md).",
            metadata: VibeLaneSkillMetadata(
                roles: [.work, .review],
                requiredCommands: ["crispy-command-that-does-not-exist"]
            )
        ))
        let workOnly = try skillStore.create(VibeLaneSkillDraft(
            name: "Work Only",
            detail: "Cannot review",
            body: "Do the work.",
            metadata: VibeLaneSkillMetadata(roles: [.work])
        ))
        let reviewOnly = try skillStore.create(VibeLaneSkillDraft(
            name: "Review Only",
            detail: "Cannot perform work",
            body: "Review the work.",
            metadata: VibeLaneSkillMetadata(roles: [.review])
        ))
        let needsSetup = [
            VibeDefinition(
                name: "Missing Skill",
                goal: "Work",
                skills: ["not-installed"],
                verify: VibeLaneVerificationDefinition("Done")
            ),
            VibeDefinition(
                name: "Unavailable Skill",
                goal: "Work",
                skills: [unavailable.reference],
                verify: VibeLaneVerificationDefinition("Done")
            ),
            VibeDefinition(
                name: "Work Skill Used For Review",
                goal: "Work",
                verify: VibeLaneVerificationDefinition("Done", reviewSkills: [workOnly.reference])
            ),
            VibeDefinition(
                name: "Review Skill Used For Work",
                goal: "Work",
                skills: [reviewOnly.reference],
                verify: VibeLaneVerificationDefinition("Done")
            ),
        ]
        for vibe in needsSetup { _ = await laneManager.createVibe(vibe) }

        let all = try ok(await router.dispatch(request("vibe.list")))
        var readiness: [String: Bool] = [:]
        for value in try XCTUnwrap(all["vibes"]?.arrayValue) {
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue,
                  let ready = object["ready"]?.boolValue else { continue }
            readiness[name] = ready
        }
        XCTAssertEqual(readiness["Inspect"], true)
        for vibe in needsSetup { XCTAssertEqual(readiness[vibe.name], false, vibe.name) }

        let ready = try ok(await router.dispatch(request("vibe.list", ["status": .string("ready")])))
        XCTAssertEqual(ready["vibes"]?.arrayValue?.count, 1)
        XCTAssertEqual(ready["vibes"]?.arrayValue?.first?.objectValue?["name"]?.stringValue, "Inspect")

        let blocked = try ok(await router.dispatch(request("vibe.list", ["status": .string("needs-setup")])))
        XCTAssertEqual(blocked["vibes"]?.arrayValue?.count, needsSetup.count)
        XCTAssertTrue(blocked["vibes"]?.arrayValue?.allSatisfy {
            $0.objectValue?["ready"]?.boolValue == false
        } ?? false)
    }

    func test_skillCopyImportsCompletePackageAndRemovalGuardsCurrentVibeReferences() async throws {
        let package = root.appendingPathComponent("external/review", isDirectory: true)
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("references", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        ---
        name: Release Review
        description: Review releases.
        ---

        Read [the checklist](references/checklist.md).
        """.write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "# Checklist".write(
            to: package.appendingPathComponent("references/checklist.md"),
            atomically: true,
            encoding: .utf8
        )

        let imported = try ok(await router.dispatch(request("skill.import", [
            "path": .string(package.path),
            "mode": .string("copy"),
        ])))
        let skill = try XCTUnwrap(imported["skills"]?.arrayValue?.first?.objectValue)
        let reference = try XCTUnwrap(skill["reference"]?.stringValue)
        XCTAssertEqual(skill["source"]?.stringValue, "personal")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: skillStore.rootURL
                .appendingPathComponent(reference)
                .appendingPathComponent("references/checklist.md")
                .path
        ))

        let acceptedNameReference = "release review"
        let validation = try ok(await router.dispatch(request("vibe.validate", [
            "document": .object([
                "name": .string("Uses release review"),
                "work": .object([
                    "goal": .string("Review"),
                    "skills": .array([.string(acceptedNameReference)]),
                ]),
                "verify": .object(["definition": .string("Reviewed")]),
            ]),
        ])))
        XCTAssertEqual(validation["valid"]?.boolValue, true)

        let usingVibe = VibeDefinition(
            name: "Uses release review",
            goal: "Review",
            skills: [acceptedNameReference],
            verify: VibeLaneVerificationDefinition("Reviewed")
        )
        _ = await laneManager.createVibe(usingVibe)
        let blocked = await router.dispatch(request("skill.remove", ["reference": .string(reference)]))
        XCTAssertEqual(errorCode(blocked), CLIErrorCode.invalidParams)
        XCTAssertNotNil(try? skillStore.skill(withReference: reference))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: skillStore.rootURL
                .appendingPathComponent(reference)
                .appendingPathComponent("references/checklist.md")
                .path
        ))
    }

    func test_directCLIAuthoringFlowPinsExactGraphAndValidationIsPure() async throws {
        let package = root.appendingPathComponent("external/automation-work", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try """
        ---
        name: Automation Work
        description: Perform deterministic automation work.
        ---

        # Automation Work

        Produce the requested evidence without changing the authoring graph.
        """.write(
            to: package.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let importedResult = try ok(await router.dispatch(request("skill.import", [
            "path": .string(package.path),
            "mode": .string("copy"),
        ])))
        let imported = try XCTUnwrap(importedResult["skills"]?.arrayValue?.first?.objectValue)
        let skillReference = try XCTUnwrap(imported["reference"]?.stringValue)

        let vibeDocument: CLIJSONValue = .object([
            "name": .string("Pinned CLI Vibe"),
            "description": .string("Expectation content owned by the central Vibe."),
            "category": .string("automation"),
            "work": .object([
                "goal": .string("Produce exact release evidence"),
                "instructions": .string("Use the imported automation procedure."),
                "skills": .array([.string(skillReference)]),
            ]),
            "verify": .object([
                "definition": .string("The exact evidence is complete"),
                "humanReview": .bool(false),
            ]),
            "bounds": .object([
                "maxAttempts": .int(4),
                "timeoutSeconds": .int(900),
                "onExhausted": .string("escalate"),
            ]),
            "engine": .object([
                "agentID": .string("test-agent"),
                "modelID": .string("test-model"),
            ]),
        ])
        let vibeValidation = try ok(await router.dispatch(request("vibe.validate", [
            "document": vibeDocument,
        ])))
        XCTAssertEqual(vibeValidation["valid"]?.boolValue, true)
        let vibeResult = try ok(await router.dispatch(request("vibe.create", [
            "document": vibeDocument,
        ])))
        let vibeJSON = try XCTUnwrap(vibeResult["vibe"]?.objectValue)
        let vibeID = try XCTUnwrap(vibeJSON["id"]?.stringValue)
        let vibeVersion = try XCTUnwrap(vibeJSON["version"]?.intValue)
        let vibeUUID = try XCTUnwrap(UUID(uuidString: vibeID))
        let exactVibe = try XCTUnwrap(laneManager.vibe(withID: vibeUUID, version: vibeVersion))

        let laneDocument: CLIJSONValue = .object([
            "name": .string("Pinned CLI Lane"),
            "description": .string("Lane owns only handoff fields."),
            "steps": .array([
                .object([
                    "key": .string("release-evidence"),
                    "vibe": .object([
                        "id": .string(vibeID),
                        "version": .int(vibeVersion),
                    ]),
                    "requires": .array([
                        .object([
                            "key": .string("release-request"),
                            "askUser": .bool(true),
                            "prompt": .string("What should be released?"),
                        ]),
                    ]),
                    "produces": .array([
                        .object([
                            "key": .string("release-evidence"),
                            "description": .string("Verified release evidence"),
                        ]),
                    ]),
                ]),
            ]),
        ])
        let laneCountBeforeValidation = laneManager.lanes.count
        let laneValidation = try ok(await router.dispatch(request("lane.validate", [
            "document": laneDocument,
        ])))
        XCTAssertEqual(laneValidation["valid"]?.boolValue, true)
        XCTAssertEqual(
            laneManager.lanes.count,
            laneCountBeforeValidation,
            "lane.validate must not persist"
        )

        let unresolvedDocument: CLIJSONValue = .object([
            "name": .string("Unresolved Lane"),
            "steps": .array([
                .object([
                    "key": .string("missing-revision"),
                    "vibe": .object([
                        "id": .string(vibeID),
                        "version": .int(vibeVersion + 99),
                    ]),
                ]),
            ]),
        ])
        let unresolved = try ok(await router.dispatch(request("lane.validate", [
            "document": unresolvedDocument,
        ])))
        XCTAssertEqual(unresolved["valid"]?.boolValue, false)
        XCTAssertTrue(unresolved["issues"]?.arrayValue?.contains {
            $0.stringValue?.contains("missing Vibe") == true
        } ?? false)
        XCTAssertEqual(laneManager.lanes.count, laneCountBeforeValidation)

        let refusedCreate = await router.dispatch(request("lane.create", [
            "document": unresolvedDocument,
        ]))
        XCTAssertEqual(errorCode(refusedCreate), CLIErrorCode.invalidParams)
        XCTAssertEqual(laneManager.lanes.count, laneCountBeforeValidation)

        let laneResult = try ok(await router.dispatch(request("lane.create", [
            "document": laneDocument,
        ])))
        let laneJSON = try XCTUnwrap(laneResult["lane"]?.objectValue)
        let laneID = try XCTUnwrap(laneJSON["id"]?.stringValue)
        let laneVersion = try XCTUnwrap(laneJSON["version"]?.intValue)
        let laneUUID = try XCTUnwrap(UUID(uuidString: laneID))
        let storedLane = try XCTUnwrap(laneManager.lane(withID: laneUUID, version: laneVersion))
        let checkpoint = try XCTUnwrap(storedLane.checkpoints.first)
        XCTAssertEqual(checkpoint.vibeID, exactVibe.id)
        XCTAssertEqual(checkpoint.vibeVersion, exactVibe.version)
        XCTAssertEqual(checkpoint.title, exactVibe.name)
        XCTAssertEqual(checkpoint.work, exactVibe.work)
        XCTAssertEqual(checkpoint.verify, exactVibe.verify)
        XCTAssertEqual(checkpoint.bounds, exactVibe.bounds)
        XCTAssertEqual(checkpoint.engine, exactVibe.engine)
        XCTAssertEqual(checkpoint.inputRequirements.first?.key, "release-request")
        XCTAssertEqual(checkpoint.outputDeclarations.first?.detail, "Verified release evidence")
        XCTAssertEqual(laneManager.vibeUsageCount(id: exactVibe.id), 1)
        XCTAssertEqual(
            laneJSON["steps"]?.arrayValue?.first?.objectValue?["vibe"]?.objectValue?["version"]?.intValue,
            vibeVersion
        )

        let scheduleDocument: CLIJSONValue = .object([
            "name": .string("Paused CLI Schedule"),
            "enabled": .bool(false),
            "projectPath": .string(project.path),
            "taskInstruction": .string("Produce release evidence."),
            "lane": .object([
                "id": .string(laneID),
                "version": .int(laneVersion),
            ]),
            "recurrence": .object([
                "kind": .string("daily"),
                "hour": .int(9),
                "minute": .int(0),
                "timeZone": .string("America/Chicago"),
            ]),
        ])
        let scheduleResult = try ok(await router.dispatch(request("schedule.create", [
            "document": scheduleDocument,
        ])))
        let scheduleJSON = try XCTUnwrap(scheduleResult["schedule"]?.objectValue)
        let scheduleID = try XCTUnwrap(scheduleJSON["id"]?.stringValue)
        let scheduleUUID = try XCTUnwrap(UUID(uuidString: scheduleID))
        let schedule = try XCTUnwrap(loopManager.definition(withID: scheduleUUID))
        XCTAssertFalse(schedule.isEnabled)
        XCTAssertEqual(schedule.laneID, storedLane.id)
        XCTAssertEqual(schedule.laneVersion, storedLane.version)
        XCTAssertEqual(schedule.laneSnapshot, storedLane)
        XCTAssertNotNil(try? skillStore.skill(withReference: skillReference))
        XCTAssertNotNil(laneManager.vibe(withID: exactVibe.id, version: exactVibe.version))
        XCTAssertNotNil(laneManager.lane(withID: storedLane.id, version: storedLane.version))
        XCTAssertEqual(loopManager.definitions.count, 1)
    }

    func test_scheduleTrustPreviewAndManagerMutations() async throws {
        let preview = try ok(await router.dispatch(request("schedule.preview", [
            "document": .object([
                "kind": .string("daily"),
                "hour": .int(9),
                "minute": .int(0),
                "timeZone": .string("America/Chicago"),
            ]),
            "after": .string("2026-07-22T14:00:00Z"),
            "count": .int(3),
        ])))
        XCTAssertEqual(preview["occurrences"]?.arrayValue?.count, 3)
        XCTAssertTrue(loopManager.definitions.isEmpty, "preview must not persist")

        var enabledDocument = scheduleDocument(enabled: true)
        let deniedCreate = await router.dispatch(request("schedule.create", ["document": enabledDocument]))
        XCTAssertEqual(errorCode(deniedCreate), CLIErrorCode.invalidParams)
        XCTAssertTrue(loopManager.definitions.isEmpty)

        enabledDocument = scheduleDocument(enabled: false)
        let created = try ok(await router.dispatch(request("schedule.create", ["document": enabledDocument])))
        let id = try XCTUnwrap(created["schedule"]?.objectValue?["id"]?.stringValue)
        XCTAssertEqual(loopManager.definitions.count, 1)
        XCTAssertFalse(loopManager.definitions[0].isEnabled)

        let deniedEnable = await router.dispatch(request("schedule.enable", ["id": .string(id)]))
        XCTAssertEqual(errorCode(deniedEnable), CLIErrorCode.invalidParams)
        XCTAssertFalse(loopManager.definitions[0].isEnabled)

        let enabled = try ok(await router.dispatch(request("schedule.enable", [
            "id": .string(id),
            "confirmFullTrust": .bool(true),
        ])))
        XCTAssertEqual(enabled["schedule"]?.objectValue?["enabled"]?.boolValue, true)

        var laneDraft = try XCTUnwrap(laneManager.lane(withID: lane.id))
        laneDraft.name = "Inspection Lane v2"
        let savedLane = await laneManager.updateLane(laneDraft)
        let latestLane = try XCTUnwrap(savedLane)
        let deniedAdoption = await router.dispatch(request("schedule.adoptLane", [
            "id": .string(id),
            "lane": .string(latestLane.id.uuidString),
        ]))
        XCTAssertEqual(errorCode(deniedAdoption), CLIErrorCode.invalidParams)
        XCTAssertNotEqual(loopManager.definitions[0].laneVersion, latestLane.version)
        let adopted = try ok(await router.dispatch(request("schedule.adoptLane", [
            "id": .string(id),
            "lane": .string(latestLane.id.uuidString),
            "confirmFullTrust": .bool(true),
        ])))
        XCTAssertEqual(adopted["schedule"]?.objectValue?["lane"]?.objectValue?["version"]?.intValue, latestLane.version)

        let deniedUpdate = await router.dispatch(request("schedule.update", [
            "id": .string(id),
            "document": .object(["name": .string("Renamed")]),
        ]))
        XCTAssertEqual(errorCode(deniedUpdate), CLIErrorCode.invalidParams)
        XCTAssertNotEqual(loopManager.definitions[0].name, "Renamed")

        let paused = try ok(await router.dispatch(request("schedule.pause", ["id": .string(id)])))
        XCTAssertEqual(paused["schedule"]?.objectValue?["enabled"]?.boolValue, false)
    }

    func test_helpIncludesAutomationDomainsAndRetainsLaneCommands() async throws {
        let help = try ok(await router.dispatch(request("help")))
        let domains = Set(help["domains"]?.arrayValue?.compactMap {
            $0.objectValue?["name"]?.stringValue
        } ?? [])
        XCTAssertTrue(domains.isSuperset(of: ["skill", "vibe", "lane", "schedule"]))
        XCTAssertNotNil(router.commandRegistry.first { $0.method == "lane.task.create" })
        XCTAssertEqual(router.commandRegistry.filter { $0.method.hasPrefix("schedule.") }.count, 13)

        let laneValidate = try XCTUnwrap(router.commandRegistry.first { $0.method == "lane.validate" })
        XCTAssertTrue(laneValidate.descriptor.params.contains {
            $0.name == "document" && $0.required
        })
        let laneCreate = try XCTUnwrap(router.commandRegistry.first { $0.method == "lane.create" })
        XCTAssertTrue(laneCreate.descriptor.params.contains { $0.name == "document" })
        XCTAssertTrue(laneCreate.descriptor.params.contains { $0.name == "steps" })
        let laneUpdate = try XCTUnwrap(router.commandRegistry.first { $0.method == "lane.update" })
        XCTAssertTrue(laneUpdate.descriptor.params.contains {
            $0.name == "expectedVersion" && $0.required
        })
        let vibeUpdate = try XCTUnwrap(router.commandRegistry.first { $0.method == "vibe.update" })
        XCTAssertTrue(vibeUpdate.descriptor.params.contains {
            $0.name == "expectedVersion" && $0.required
        })
        XCTAssertTrue(vibeUpdate.descriptor.errors.contains(CLIErrorCode.conflict))
        let skillRemove = try XCTUnwrap(router.commandRegistry.first { $0.method == "skill.remove" })
        XCTAssertFalse(skillRemove.descriptor.params.contains { $0.name == "expectedDigest" })
        let scheduleUpdate = try XCTUnwrap(router.commandRegistry.first { $0.method == "schedule.update" })
        XCTAssertFalse(scheduleUpdate.descriptor.params.contains { $0.name == "expectedRevision" })
    }

    private func vibeDocument(name: String, goal: String, verify: String) -> CLIJSONValue {
        .object([
            "name": .string(name),
            "work": .object(["goal": .string(goal)]),
            "verify": .object(["definition": .string(verify)]),
        ])
    }

    private func scheduleDocument(enabled: Bool) -> CLIJSONValue {
        .object([
            "name": .string("Daily inspection"),
            "enabled": .bool(enabled),
            "projectPath": .string(project.path),
            "taskInstruction": .string("Inspect the project"),
            "lane": .object([
                "id": .string(lane.id.uuidString),
                "version": .int(lane.version),
            ]),
            "recurrence": .object([
                "kind": .string("daily"),
                "hour": .int(9),
                "minute": .int(0),
                "timeZone": .string("America/Chicago"),
            ]),
        ])
    }

    private func request(_ method: String, _ params: [String: CLIJSONValue] = [:]) -> CLIRequest {
        CLIRequest(id: UUID().uuidString, method: method, params: params, _env: .empty)
    }

    private func ok(_ response: CLIResponse) throws -> [String: CLIJSONValue] {
        guard case .ok(_, let result) = response else {
            XCTFail("expected ok, got \(response)")
            throw XCTSkip("unreachable")
        }
        return result
    }

    private func errorCode(_ response: CLIResponse) -> String? {
        guard case .error(_, let code, _) = response else { return nil }
        return code
    }
}
