import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
private final class FailingSkillReferenceStore: AutomationSkillReferencePersisting {
    func loadSkillReferences() async throws -> [AutomationSkillReferenceRecord] {
        []
    }

    func persistSkillReferences(
        _ records: [AutomationSkillReferenceRecord]
    ) async throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

@MainActor
final class VibeLaneSkillStoreTests: XCTestCase {
    func test_discoversBundledAndManagesPersonalSkills() async throws {
        let root = temporaryDirectory("managed")
        defer { try? FileManager.default.removeItem(at: root) }
        VibeLaneSkillLibrary.install(into: root)
        let store = VibeLaneSkillStore(rootURL: root)

        XCTAssertEqual(
            store.skills.filter { $0.source == .bundled }.count,
            VibeLaneSkillLibrary.starters.count
        )

        let created = try store.create(
            name: "Accessibility Review",
            detail: "Check keyboard and assistive technology behavior.",
            body: "# Accessibility Review\n\nRun the accessibility checks."
        )
        XCTAssertEqual(created.reference, "accessibility-review")
        XCTAssertEqual(created.source, .personal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.fileURL.path))

        let updated = try store.update(
            created,
            name: "Accessibility Review",
            detail: "Updated description.",
            body: "# Accessibility Review\n\nUpdated instructions."
        )
        XCTAssertEqual(updated.detail, "Updated description.")
        XCTAssertTrue(updated.body.contains("Updated instructions."))

        let copy = try store.duplicate(updated)
        XCTAssertEqual(copy.source, .personal)
        XCTAssertNotEqual(copy.reference, updated.reference)

        try await store.remove(updated)
        XCTAssertFalse(store.skills.contains { $0.reference == updated.reference })
    }

    func test_linkedSkillPersistsWithoutCopyingSourceFile() async throws {
        let root = temporaryDirectory("library")
        let external = temporaryDirectory("external")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let sourceFile = external.appendingPathComponent("SKILL.md")
        try """
        ---
        name: Project Conventions
        description: Follow this repository's conventions.
        ---

        # Project Conventions

        Read AGENTS.md before changing code.
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let referencePersistence = InMemoryAutomationSkillReferenceStore()
        let store = VibeLaneSkillStore(
            rootURL: root,
            bundledNames: [],
            referencePersistence: referencePersistence,
            fileManager: .default
        )
        await store.bootstrap()
        let linked = try await store.link(external)

        XCTAssertEqual(linked.source, .linked)
        XCTAssertEqual(linked.reference, sourceFile.path)
        XCTAssertEqual(linked.fileURL, sourceFile)

        let reopened = VibeLaneSkillStore(
            rootURL: root,
            bundledNames: [],
            referencePersistence: referencePersistence,
            fileManager: .default
        )
        await reopened.bootstrap()
        XCTAssertEqual(reopened.skills.first?.reference, sourceFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))

        let reopenedSkill = try XCTUnwrap(reopened.skills.first)
        try await reopened.remove(reopenedSkill)
        XCTAssertTrue(reopened.skills.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    func test_duplicateCopiesEntireSkillPackage() async throws {
        let root = temporaryDirectory("duplicate")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VibeLaneSkillStore(rootURL: root, bundledNames: [])
        let created = try store.create(
            VibeLaneSkillDraft(
                name: "Release Review",
                detail: "Review a release.",
                body: "# Release Review\n\nRead [the checklist](references/checklist.md).",
                metadata: VibeLaneSkillMetadata(
                    category: "Release",
                    roles: [.review],
                    requiredCommands: ["git"]
                )
            )
        )
        let referenceDirectory = created.rootURL.appendingPathComponent(
            "references",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: referenceDirectory,
            withIntermediateDirectories: true
        )
        try "# Checklist\n".write(
            to: referenceDirectory.appendingPathComponent("checklist.md"),
            atomically: true,
            encoding: .utf8
        )
        store.reload()

        let copy = try store.duplicate(try store.skill(withReference: created.reference))

        XCTAssertEqual(copy.category, "Release")
        XCTAssertEqual(copy.roles, [.review])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: copy.rootURL
                    .appendingPathComponent("references/checklist.md")
                    .path
            )
        )
        XCTAssertEqual(copy.resources.map(\.relativePath), ["references/checklist.md"])
    }

    func test_linkFailureDoesNotPublishSkillReference() async throws {
        let root = temporaryDirectory("failed-link-library")
        let external = temporaryDirectory("failed-link-source")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        try FileManager.default.createDirectory(
            at: external,
            withIntermediateDirectories: true
        )
        try """
        ---
        name: Uncommitted Skill
        description: This reference must not publish before persistence.
        ---

        # Uncommitted Skill
        """.write(
            to: external.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = VibeLaneSkillStore(
            rootURL: root,
            bundledNames: [],
            referencePersistence: FailingSkillReferenceStore()
        )
        await store.bootstrap()

        do {
            _ = try await store.link(external)
            XCTFail("Expected linked-reference persistence to fail")
        } catch {
            XCTAssertTrue(store.skills.isEmpty)
            XCTAssertNotNil(store.persistenceError)
        }
    }

    func test_importCollectionFindsNestedPackagesAndMultilineDescription() async throws {
        let root = temporaryDirectory("collection-library")
        let external = temporaryDirectory("collection-source")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let engineering = external.appendingPathComponent("skills/engineering/tdd")
        let review = external.appendingPathComponent("skills/review/code-review")
        try FileManager.default.createDirectory(at: engineering, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        try """
        ---
        name: tdd
        description: |
          Test behavior through public seams.
          Use one red-green cycle at a time.
        ---

        # TDD
        """.write(
            to: engineering.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        name: code-review
        description: Review a diff independently.
        ---

        # Code Review
        """.write(
            to: review.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = VibeLaneSkillStore(rootURL: root, bundledNames: [])

        let imported = try await store.linkCollection(external)

        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(Set(imported.map(\.category)), ["Engineering", "Review"])
        XCTAssertTrue(
            imported.first(where: { $0.name == "tdd" })?.detail
                .contains("Use one red-green cycle") == true
        )
    }

    func test_validationReportsMissingReferencesAndCommands() async throws {
        let root = temporaryDirectory("validation")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VibeLaneSkillStore(rootURL: root, bundledNames: [])

        let skill = try store.create(
            VibeLaneSkillDraft(
                name: "Broken Skill",
                detail: "Intentionally incomplete.",
                body: "# Broken\n\nRead [missing](references/missing.md).",
                metadata: VibeLaneSkillMetadata(
                    requiredCommands: ["crispy-command-that-does-not-exist"]
                )
            )
        )

        XCTAssertEqual(skill.validationState, .unavailable)
        XCTAssertTrue(skill.issues.contains(.missingReference("references/missing.md")))
        XCTAssertTrue(
            skill.issues.contains(.missingCommand("crispy-command-that-does-not-exist"))
        )
    }

    func test_starterVibesUseSkillsOnlyInSupportedRoles() async {
        let skills = Dictionary(
            uniqueKeysWithValues: VibeLaneSkillLibrary.starters.map {
                ($0.name, $0.metadata)
            }
        )

        for lane in VibeLaneCatalog.starterLanes {
            for checkpoint in lane.checkpoints {
                for name in checkpoint.work.skills {
                    XCTAssertTrue(
                        skills[name]?.roles.contains(.work) == true,
                        "\(lane.name)/\(checkpoint.key) uses \(name) as an unsupported Work skill"
                    )
                }
                for name in checkpoint.verify.reviewSkills {
                    XCTAssertTrue(
                        skills[name]?.roles.contains(.review) == true,
                        "\(lane.name)/\(checkpoint.key) uses \(name) as an unsupported Review skill"
                    )
                }
            }
        }
    }

    // MARK: - Assignment eligibility

    /// Regression: eligibility used to live only in the installed-skill menu's
    /// `.disabled`, so a hand-typed reference could assign an unavailable skill
    /// or an interactive skill as a Review skill. The rule now lives on the model
    /// and is enforced at every assignment path.
    func test_isAssignable_rejectsUnavailableAndInteractiveReviewSkills() {
        let unavailable = makeSkill(
            reference: "needs-jq",
            roles: [.work, .review],
            interaction: .unattended,
            issues: [.missingCommand("jq")]
        )
        XCTAssertEqual(unavailable.validationState, .unavailable)
        XCTAssertFalse(unavailable.isAssignable(to: .work))
        XCTAssertFalse(unavailable.isAssignable(to: .review))
        XCTAssertEqual(unavailable.assignmentRefusal(for: .work), .unavailable)

        let interactive = makeSkill(
            reference: "asks-questions",
            roles: [.work, .review],
            interaction: .interactive
        )
        XCTAssertTrue(interactive.isAssignable(to: .work), "interactive work skills stay allowed")
        XCTAssertFalse(interactive.isAssignable(to: .review), "review runs unattended")
        XCTAssertEqual(interactive.assignmentRefusal(for: .review), .interactiveReview)

        let workOnly = makeSkill(reference: "work-only", roles: [.work], interaction: .unattended)
        XCTAssertFalse(workOnly.isAssignable(to: .review))
        XCTAssertEqual(workOnly.assignmentRefusal(for: .review), .roleNotSupported)

        let ready = makeSkill(reference: "ready", roles: [.work, .review], interaction: .unattended)
        XCTAssertTrue(ready.isAssignable(to: .work))
        XCTAssertTrue(ready.isAssignable(to: .review))
        XCTAssertNil(ready.assignmentRefusal(for: .review))
    }

    private func makeSkill(
        reference: String,
        roles: [VibeLaneSkillRole],
        interaction: VibeLaneSkillInteraction,
        issues: [VibeLaneSkillIssue] = []
    ) -> VibeLaneSkillDefinition {
        VibeLaneSkillDefinition(
            reference: reference,
            name: reference,
            detail: "",
            body: "instructions",
            source: .personal,
            rootURL: URL(fileURLWithPath: "/tmp/\(reference)"),
            fileURL: URL(fileURLWithPath: "/tmp/\(reference)/SKILL.md"),
            metadata: VibeLaneSkillMetadata(
                category: "General",
                roles: roles,
                interaction: interaction,
                requiredCommands: []
            ),
            resources: [],
            issues: issues
        )
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "crispy-vibe-lane-skill-\(suffix)-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
