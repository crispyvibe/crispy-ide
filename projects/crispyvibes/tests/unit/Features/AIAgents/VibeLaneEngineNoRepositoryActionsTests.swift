import Foundation
import XCTest
@testable import CrispyVibes

// F059 — the engine performs no repository actions. Agents act; the engine
// bounds, prompts, and records. Evidence gathering is authored in a Vibe's
// Definition of done and its review skills, never collected by engine code.
//
// This previously was not true: the engine shelled out to `git status` / `git diff`
// inside a repository a full-trust agent can write to, and pasted the result into
// the reviewer prompt. Git executes commands from config (diff.external,
// diff.<driver>.textconv, core.fsmonitor, hooks), so that gave an agent a path to
// run a command inside the app's own process. The fix was deletion, not hardening.

@MainActor
final class VibeLaneEngineNoRepositoryActionsTests: XCTestCase {

    /// The reviewer prompt must carry the AUTHORED contract, not an engine-gathered
    /// snapshot of the repository.
    func test_reviewPrompt_carriesAuthoredContractAndNoEngineGatheredSnapshot() {
        let checkpoint = VibeLaneCheckpoint(
            key: "patch",
            order: 0,
            goal: "fix the bug",
            verify: VibeLaneVerificationDefinition(
                "Done when the regression test passes.",
                reviewSkills: ["code-review"]
            )
        )
        let prompt = VibeLaneACPAgentRunner.buildReviewPrompt(
            request: VibeLaneReviewRequest(
                taskTitle: "t",
                projectPath: "/tmp/p",
                checkpoint: checkpoint,
                attemptIndex: 0,
                engine: .default,
                reviewSkillsText: "code-review"
            ),
            definition: checkpoint.verify.definition
        )

        // The authored contract reaches the reviewer.
        XCTAssertTrue(prompt.contains("Done when the regression test passes."))
        XCTAssertTrue(prompt.contains("code-review"))
        // The reviewer is told to gather evidence itself.
        XCTAssertTrue(prompt.lowercased().contains("gather it yourself"))
        // No engine-gathered repository snapshot is embedded.
        XCTAssertFalse(prompt.contains("Working-tree snapshot"))
        XCTAssertFalse(prompt.contains("git status"))
        XCTAssertFalse(prompt.contains("git diff"))
    }

    /// Creating a task must not inspect the repository.
    func test_createTask_doesNotInspectTheRepository() async {
        let lane = VibeLaneCatalog.fixABug
        let store = InMemoryVibeLaneStore(lanes: [lane])
        let manager = VibeLaneTaskManager(
            store: store,
            worker: NeverRunsWorker(),
            clock: VibeLaneSystemClock(),
            maxConcurrent: 1
        )
        await manager.bootstrap(resumeRunning: false)
        defer { manager.shutdown() }

        let task = await manager.createTask(
            laneID: lane.id,
            title: "t",
            projectPath: FileManager.default.temporaryDirectory.path
        )

        XCTAssertNotNil(task)
        XCTAssertNil(
            task?.repoBaselineRef,
            "the engine must not shell out to git to capture a baseline"
        )
    }

    /// How to gather evidence in a git repository belongs to the authored review
    /// skill, so a Vibe can change it without an engine change.
    func test_gitEvidenceGuidanceLivesInTheAuthoredReviewSkill() throws {
        let skill = try XCTUnwrap(
            VibeLaneSkillLibrary.starters.first { $0.name == "code-review" }
        )
        XCTAssertTrue(skill.body.contains("git diff"), "the skill tells the reviewer how to gather the change")
        XCTAssertTrue(skill.body.lowercased().contains("untrusted"), "and to treat the change as untrusted content")
    }
}

@MainActor
private final class NeverRunsWorker: VibeLaneWorkRunning {
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        XCTFail("no work should run in this test")
        return VibeLaneWorkTurn(sessionRef: sessionRef, ok: false)
    }
}
