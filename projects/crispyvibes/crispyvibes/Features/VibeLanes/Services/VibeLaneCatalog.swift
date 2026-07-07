import Foundation

// F059 — prebuilt starter lanes shipped as editable templates. Stable UUIDs so
// persisted tasks keep referring to the same lane across launches.
//
// Design rules for every starter checkpoint:
//   • Goal — one sharp sentence naming the deliverable.
//   • Instructions — a numbered working process ending in a concrete deliverable.
//   • Verification — a "done when ALL of:" checklist the reviewer can actually
//     check against the repository, never a vibe. High-stakes judgment steps
//     (legal claims, release sign-off, decision acceptance) are verified BY THE
//     USER (humanReview) — an agent auditing its own prose is circular.
//   • Contract — requires/produces declared wherever a step hands work forward,
//     with descriptions, so carry-forward is exercised end to end.
//   • Bounds — escalate (Steer) on the expensive or judgment-heavy steps, and
//     time budgets sized to the attempt cap (a real agent turn runs 5–15 min;
//     a 60-minute window on 14 attempts would make the cap decorative).
//   • Stack-agnostic — steps discover the project's own tooling; no npm-isms.
//
// Skills are referenced by bare name from the shipped starter library
// (VibeLaneSkillLibrary); users add their own skills by path in the editor.

enum VibeLaneCatalog {
    static let fixABugLaneID = UUID(uuidString: "F0590001-0000-0000-0000-000000000001")!
    static let smallFeatureLaneID = UUID(uuidString: "F0590002-0000-0000-0000-000000000002")!
    static let fullFeatureLaneID = UUID(uuidString: "F0590003-0000-0000-0000-000000000003")!
    static let incidentResponseLaneID = UUID(uuidString: "F0590004-0000-0000-0000-000000000004")!
    static let libraryReleaseLaneID = UUID(uuidString: "F0590005-0000-0000-0000-000000000005")!
    static let productLaunchLaneID = UUID(uuidString: "F0590006-0000-0000-0000-000000000006")!
    static let researchMemoLaneID = UUID(uuidString: "F0590007-0000-0000-0000-000000000007")!

    static var starterLanes: [VibeLaneDefinition] {
        [fixABug, smallFeature, fullFeatureDelivery, incidentResponse, libraryRelease, productLaunch, researchMemo]
    }

    static func lane(withID id: UUID) -> VibeLaneDefinition? {
        starterLanes.first { $0.id == id }
    }

    // MARK: - Builder helpers

    private static func req(_ key: String) -> VibeLaneInputRequirement {
        VibeLaneInputRequirement(key: key)
    }

    private static func ask(_ key: String, _ prompt: String) -> VibeLaneInputRequirement {
        VibeLaneInputRequirement(key: key, askUser: true, prompt: prompt)
    }

    private static func out(_ key: String, _ detail: String) -> VibeLaneOutputDeclaration {
        VibeLaneOutputDeclaration(key: key, detail: detail)
    }

    private static func cp(
        _ key: String, _ order: Int,
        goal: String, instructions: String,
        skills: [String] = [],
        verify: String,
        humanVerify: Bool = false,
        attempts: Int, minutes: Int,
        onExhausted: VibeLaneBoundBehavior = .stop,
        requires: [VibeLaneInputRequirement] = [],
        produces: [VibeLaneOutputDeclaration] = []
    ) -> VibeLaneCheckpoint {
        VibeLaneCheckpoint(
            key: key, order: order,
            work: VibeLaneWorkDefinition(goal: goal, instructions: instructions, skills: skills),
            verify: VibeLaneVerificationDefinition(verify, humanReview: humanVerify),
            bounds: VibeLaneBounds(maxAttempts: attempts, timeoutSeconds: minutes * 60, onExhausted: onExhausted),
            requires: requires.isEmpty ? nil : requires,
            produces: produces.isEmpty ? nil : produces
        )
    }

    // MARK: - Fix a bug

    static var fixABug: VibeLaneDefinition {
        VibeLaneDefinition(
            id: fixABugLaneID,
            name: "Fix a bug",
            detail: "Reproduce, patch minimally, verify, then summarize the handoff.",
            steerLimit: 2,
            checkpoints: [
                cp("reproduce", 0,
                   goal: "Reproduce the bug with the smallest reliable failing check.",
                   instructions: """
                   1. Read the report and trace the failing behavior to the code paths involved. Do not edit product code yet.
                   2. Discover how this project runs its checks (test runner, build commands, scripts) and use those.
                   3. Write the smallest reproduction that fails BECAUSE of this bug — a focused regression test is best; \
                   a minimal script is acceptable when a test is impossible.
                   4. Run it several times to confirm it fails deterministically, and shrink it until nothing is removable.

                   Deliverable: a runnable reproduction in the working tree, plus the exact command that runs it.
                   """,
                   skills: ["diagnosing-bugs", "tdd"],
                   verify: """
                   Done when ALL of:
                   - A reproduction exists in the working tree as a runnable test or minimal script.
                   - Running it fails deterministically, and the failure is the reported bug (not setup or environment noise).
                   - It is minimal: no unrelated fixtures, setup, or assertions.
                   - The exact command to run it is stated.
                   """,
                   attempts: 5, minutes: 20,
                   onExhausted: .escalate,
                   produces: [out("repro", "path to the reproduction and the exact command that runs it")]),
                cp("patch", 1,
                   goal: "Fix the confirmed root cause with the smallest safe change.",
                   instructions: """
                   1. Run `repro` first and read the failure carefully — fix the cause it points at, not the symptom.
                   2. Trace to the root cause before editing. If your fix makes the test pass without explaining WHY it \
                   failed, you have not found the root cause.
                   3. Make the smallest change that fixes it. Do not refactor unrelated code, change public APIs, or \
                   weaken/delete any test to go green.
                   4. Re-run `repro` and the tests near your change until green.

                   Deliverable: the fix in the working tree, matching the project's existing style.
                   """,
                   skills: ["diagnosing-bugs", "tdd"],
                   verify: """
                   Done when ALL of:
                   - The reproduction from `repro` now passes, and passes repeatedly (not flakily).
                   - The diff fixes the root cause — the change explains the original failure.
                   - The diff is minimal: no unrelated edits, no debug leftovers, no weakened or deleted tests.
                   - Tests adjacent to the changed code still pass.
                   """,
                   attempts: 6, minutes: 45,
                   onExhausted: .escalate,
                   requires: [req("repro")],
                   produces: [out("fix", "one-line root cause plus the files changed")]),
                cp("verify", 2,
                   goal: "Verify the fix against the full relevant checks and audit the diff.",
                   instructions: """
                   1. Run the reproduction from `repro`, then the project's full relevant test suite with its own tooling.
                   2. Read the complete diff line by line: flag unrelated edits, debug leftovers, weakened assertions, \
                   and missing edge-case coverage. Tighten anything that does not directly serve the fix.
                   3. If the bug class could recur elsewhere (copy-pasted logic, sibling code paths), check those too and \
                   note what you found.

                   Deliverable: a green verification run and a clean, reviewed diff.
                   """,
                   skills: ["code-review"],
                   verify: """
                   Done when ALL of:
                   - The reproduction and the project's relevant test suite pass, using the project's own commands.
                   - The final diff contains only changes that serve this fix.
                   - No test was weakened, skipped, or deleted to achieve green.
                   - Sibling code paths with the same bug shape were checked, with the result noted.
                   """,
                   attempts: 4, minutes: 20,
                   requires: [req("repro"), req("fix")],
                   produces: [out("verification", "the suites/commands run and their results")]),
                cp("summarize", 3,
                   goal: "Write the bug-fix handoff a reviewer can act on in one read.",
                   instructions: """
                   Write the final summary with these sections, concrete and scannable:
                   1. The bug — observed behavior and trigger.
                   2. Root cause — why it happened, in one or two sentences.
                   3. The fix — files changed and the approach.
                   4. Verification — evidence from `verification` (commands, results).
                   5. Residual risk — anything a reviewer should double-check.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The summary states the bug, root cause, fix, verification evidence, and residual risk as separate points.
                   - Every claim is backed by something in the working tree or the recorded verification.
                   - A reviewer could act on it without asking follow-up questions.
                   """,
                   attempts: 2, minutes: 5,
                   requires: [req("fix"), req("verification")]),
            ]
        )
    }

    // MARK: - Small feature

    static var smallFeature: VibeLaneDefinition {
        VibeLaneDefinition(
            id: smallFeatureLaneID,
            name: "Small feature",
            detail: "Implement a well-scoped feature test-first, then verify the result end to end.",
            steerLimit: 1,
            checkpoints: [
                cp("implement", 0,
                   goal: "Implement the requested feature, test-first, at the smallest size that satisfies it.",
                   instructions: """
                   1. Restate the expected behavior from the task in your own words, including edge cases, BEFORE coding. \
                   If the task is ambiguous, pick the most conservative reading and note the assumption.
                   2. Discover the project's structure, conventions, and test/build tooling, and follow them exactly.
                   3. Work red-green-refactor: failing test that captures the behavior, smallest change to pass, tidy.
                   4. Build only what the task asks. Leave a TODO note for anything you deliberately defer.

                   Deliverable: the working feature with tests, in the working tree.
                   """,
                   skills: ["tdd"],
                   verify: """
                   Done when ALL of:
                   - The feature behaves as the task describes, including the edge cases the implementation notes name.
                   - New behavior is covered by tests that fail without the change.
                   - The project's own test suite passes, run with the project's own tooling.
                   - The diff follows project conventions and contains no unrelated changes or scope creep.
                   """,
                   attempts: 10, minutes: 75,
                   onExhausted: .escalate,
                   produces: [out("implementation", "files changed plus how to exercise the feature")]),
                cp("verify", 1,
                   goal: "Audit the diff and prove the feature holds up beyond the happy path.",
                   instructions: """
                   1. Exercise the feature the way a user would, following `implementation`, including at least two \
                   non-happy-path cases (empty input, boundary, error path).
                   2. Run the project's full test suite.
                   3. Read the whole diff: naming, conventions, dead code, debug leftovers, missing tests. Fix what you find.

                   Deliverable: a verified feature and a diff you would approve as a reviewer.
                   """,
                   skills: ["code-review"],
                   verify: """
                   Done when ALL of:
                   - The feature was exercised end to end, including at least two non-happy-path cases, with results noted.
                   - The full test suite passes.
                   - The diff is clean: conventional, minimal, no leftovers, and every new behavior has a test.
                   """,
                   attempts: 4, minutes: 15,
                   requires: [req("implementation")]),
            ]
        )
    }

    // MARK: - Full feature delivery

    static var fullFeatureDelivery: VibeLaneDefinition {
        VibeLaneDefinition(
            id: fullFeatureLaneID,
            name: "Full feature delivery",
            detail: "Align, plan, implement test-first, review design, gate on security + quality, open a PR.",
            steerLimit: 2,
            checkpoints: [
                cp("align", 0,
                   goal: "Pin down scope, non-goals, and testable acceptance criteria before any code.",
                   instructions: """
                   1. Interrogate the request on the requester's behalf: what problem, for whom, and what is explicitly \
                   out of scope? Answer from the task and the repository's existing docs.
                   2. Write concrete, testable acceptance criteria — each one checkable by running or inspecting something.
                   3. Record scope, non-goals, and the criteria in CONTEXT.md at the repository root (create it if missing). \
                   Define any new domain terms so later steps use consistent language.
                   4. Do not start implementing.
                   """,
                   skills: ["scoping-and-planning", "writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - CONTEXT.md exists and states the problem, audience, scope, and explicit non-goals.
                   - Every acceptance criterion is testable — it names what to run or inspect and what result counts as met.
                   - No implementation has begun (no product code changed).
                   """,
                   attempts: 3, minutes: 15,
                   produces: [out("acceptance_criteria", "path to CONTEXT.md and the number of criteria recorded")]),
                cp("plan", 1,
                   goal: "Slice the work into independently verifiable, ordered pieces.",
                   instructions: """
                   1. From `acceptance_criteria`, write a short PRD: problem, users, criteria, risks.
                   2. Break the work into vertical slices that each deliver observable value and can be tested on their own.
                   3. Order the slices so each builds on the last, and map every slice to the criteria it satisfies.
                   4. No code yet — the plan is the deliverable. Save it alongside CONTEXT.md.
                   """,
                   skills: ["scoping-and-planning"],
                   verify: """
                   Done when ALL of:
                   - A PRD exists with problem, users, acceptance criteria, and risks.
                   - The work is sliced; each slice is independently testable and delivers value on its own.
                   - Every acceptance criterion maps to at least one slice, and the slice order is explicit.
                   """,
                   attempts: 3, minutes: 15,
                   requires: [req("acceptance_criteria")],
                   produces: [out("prd", "path to the PRD"), out("slices", "the ordered slice list, one line each")]),
                cp("implement", 2,
                   goal: "Build every slice test-first, keeping the suite green between slices.",
                   instructions: """
                   1. Take the slices from `slices` one at a time, in order.
                   2. For each: failing test that captures the slice, smallest change to green, refactor, full suite green, \
                   then move on. Use the project's own tooling throughout.
                   3. Tie each slice back to its acceptance criterion as you finish it.
                   4. Touch nothing outside the planned scope; note deliberate deferrals as TODOs.
                   """,
                   skills: ["tdd"],
                   verify: """
                   Done when ALL of:
                   - Every acceptance criterion in the PRD is implemented and covered by at least one test.
                   - The project's full test suite passes with its own tooling.
                   - The diff contains no unrelated changes, and every slice from the plan is accounted for (done or TODO-with-reason).
                   """,
                   attempts: 14, minutes: 120,
                   onExhausted: .escalate,
                   requires: [req("prd"), req("slices")],
                   produces: [out("implementation", "files changed and how to exercise the feature")]),
                cp("architecture-review", 3,
                   goal: "Leave the design better than the diff found it: deep modules, small interfaces.",
                   instructions: """
                   1. Read the whole diff from `implementation` as a reviewer, not as its author.
                   2. Hunt for: shallow modules, wide or leaky interfaces, duplicated logic, and complexity the PRD does \
                   not justify.
                   3. Where a seam is wrong, refactor now while preserving behavior — the suite must stay green.
                   4. Record the review: what you checked, what you changed, what you deliberately left.
                   """,
                   skills: ["code-review"],
                   verify: """
                   Done when ALL of:
                   - A written design review exists covering module depth, interfaces, duplication, and complexity.
                   - Refactors preserved behavior: the full suite still passes.
                   - Remaining design debt is listed explicitly rather than silently left.
                   """,
                   attempts: 5, minutes: 25,
                   requires: [req("implementation")],
                   produces: [out("design_review", "what was checked, changed, and deliberately left")]),
                cp("security-gate", 4,
                   goal: "Clear the change of security findings, with evidence.",
                   instructions: """
                   1. If the project has security scanning or dependency audit tooling configured, run it.
                   2. Regardless of tooling, review the changed code for: input validation, authorization checks, secret \
                   handling, injection surfaces, and unsafe deserialization.
                   3. Fix every real finding on the changed code. For false positives, document why, in writing.
                   4. Never suppress or silence a finding just to pass.
                   """,
                   skills: ["security-review"],
                   verify: """
                   Done when ALL of:
                   - The project's security tooling (if any) was run, with results recorded; if none exists, that is stated.
                   - The changed code was reviewed for input handling, authorization, secrets, and injection, with notes.
                   - No unresolved high-severity finding remains on the change; each false positive has a written justification.
                   """,
                   attempts: 6, minutes: 30,
                   requires: [req("implementation")],
                   produces: [out("security_report", "findings, fixes, and justified false positives")]),
                cp("quality-budgets", 5,
                   goal: "Meet the project's quality budgets — or establish the baseline honestly.",
                   instructions: """
                   1. Find the project's quality budgets: accessibility standards, performance targets, bundle/binary size \
                   limits — wherever they are defined (docs, CI config, lint rules).
                   2. Measure the change against each budget that exists and record before/after numbers.
                   3. If over budget, shrink the change until it fits — do not raise the budget.
                   4. If the project defines no budgets, say so, and check the basics on changed surfaces: keyboard/screen-reader \
                   access for UI, and no obviously pathological performance in new code paths.
                   """,
                   verify: """
                   Done when ALL of:
                   - Each existing budget was measured with before/after numbers recorded — or the absence of budgets is stated.
                   - Nothing is over budget, and no budget was raised to pass.
                   - Changed UI surfaces were checked for basic accessibility where applicable.
                   """,
                   attempts: 5, minutes: 25,
                   requires: [req("implementation")],
                   produces: [out("quality_report", "budgets checked and before/after numbers")]),
                cp("open-pr", 6,
                   goal: "Open a pull request a reviewer can approve without archaeology.",
                   instructions: """
                   1. Push the branch and open a PR using the project's normal flow.
                   2. The description must link the PRD and include the test, security (`security_report`), and quality \
                   (`quality_report`) results.
                   3. Summarize what changed and why, and call out exactly what reviewers should scrutinize.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - A PR (or equivalent reviewable branch) exists.
                   - Its description links the PRD and includes the test, security, and quality gate results.
                   - It names the specific areas reviewers should focus on.
                   """,
                   attempts: 3, minutes: 10,
                   requires: [req("prd"), req("security_report"), req("quality_report")],
                   produces: [out("pr", "PR URL, or branch name if no forge is configured")]),
                cp("release-handoff", 7,
                   goal: "Write the reviewer + release wrap-up.",
                   instructions: """
                   Summarize in under ~15 lines: what changed, what is verified (with evidence), residual risks, and \
                   exactly what a reviewer must check before merging `pr`.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The wrap-up states what changed, what is verified with evidence, residual risks, and reviewer must-checks.
                   - It is under ~20 lines and every claim is backed by an earlier step's output.
                   """,
                   attempts: 2, minutes: 5,
                   requires: [req("pr")]),
            ]
        )
    }

    // MARK: - Incident response

    static var incidentResponse: VibeLaneDefinition {
        VibeLaneDefinition(
            id: incidentResponseLaneID,
            name: "Incident response (hotfix)",
            detail: "Reproduce, root-cause from evidence, hotfix, lock a regression test, ship, postmortem.",
            steerLimit: 3,
            checkpoints: [
                cp("reproduce", 0,
                   goal: "Reproduce the incident reliably and minimally.",
                   instructions: """
                   1. Establish a dependable reproduction first: an automated test (or minimal script) that fails because \
                   of the incident, using the project's own tooling.
                   2. Shrink it to the smallest input that still fails, and run it repeatedly to prove determinism.
                   3. Do not attempt a fix yet — a confirmed, minimal failure is the deliverable.
                   """,
                   skills: ["diagnosing-bugs", "tdd"],
                   verify: """
                   Done when ALL of:
                   - A runnable reproduction exists and fails deterministically because of the incident.
                   - It is minimal — nothing more can be removed and still fail.
                   - The exact command to run it is stated.
                   """,
                   attempts: 6, minutes: 25,
                   onExhausted: .escalate,
                   produces: [out("repro", "path to the reproduction and the command that runs it")]),
                cp("root-cause", 1,
                   goal: "Find the true root cause from evidence, not guesswork.",
                   instructions: """
                   1. Form one falsifiable hypothesis from the `repro` failure and test it with evidence: logs, stack \
                   traces, diffs, instrumentation.
                   2. Change one variable at a time; if a hypothesis dies, widen the evidence rather than guessing again.
                   3. Distinguish cause from symptom: the root cause must explain the entire observed failure.
                   4. State the root cause and the evidence chain that supports it.
                   """,
                   skills: ["diagnosing-bugs"],
                   verify: """
                   Done when ALL of:
                   - The stated root cause explains the observed failure end to end.
                   - It is supported by concrete recorded evidence (logs, traces, commits), not narrative.
                   - Symptom and cause are clearly distinguished.
                   """,
                   attempts: 5, minutes: 25,
                   onExhausted: .escalate,
                   requires: [req("repro")],
                   produces: [out("root_cause", "one-paragraph cause plus the evidence that proves it")]),
                cp("hotfix", 2,
                   goal: "Apply the smallest safe fix for the confirmed cause.",
                   instructions: """
                   1. Fix exactly the `root_cause` — no drive-by refactors under incident pressure.
                   2. Keep the change easy to review and easy to revert.
                   3. Re-run `repro` and the surrounding test suite until green, repeatedly.
                   """,
                   skills: ["tdd"],
                   verify: """
                   Done when ALL of:
                   - The reproduction now passes, repeatedly.
                   - The full relevant test suite passes.
                   - The diff is minimal, reviewable, and trivially revertible.
                   """,
                   attempts: 8, minutes: 45,
                   onExhausted: .escalate,
                   requires: [req("repro"), req("root_cause")],
                   produces: [out("hotfix", "files changed and the fix approach in one line")]),
                cp("regression-lock", 3,
                   goal: "Make this incident structurally unable to return silently.",
                   instructions: """
                   1. Turn the reproduction into a permanent, clearly named regression test that references the incident.
                   2. Prove it locks the fix: it must fail with the fix reverted and pass with it applied.
                   3. Place it where the project's suite will always run it.
                   """,
                   skills: ["tdd"],
                   verify: """
                   Done when ALL of:
                   - A permanent regression test exists, clearly named and referencing the incident.
                   - It demonstrably fails without the fix and passes with it.
                   - It runs as part of the project's normal test suite.
                   """,
                   attempts: 4, minutes: 15,
                   requires: [req("root_cause"), req("hotfix")],
                   produces: [out("regression_test", "path to the regression test")]),
                cp("ship", 4,
                   goal: "Open the expedited hotfix PR.",
                   instructions: """
                   1. Open a hotfix PR linked to the incident, using the project's normal flow.
                   2. Describe impact, the root cause, the fix, and the regression lock.
                   3. Mark it for expedited review per the project's conventions.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - A hotfix PR (or reviewable branch) exists and is linked to the incident.
                   - Its description covers impact, root cause, fix, and the regression test.
                   """,
                   attempts: 3, minutes: 10,
                   requires: [req("hotfix"), req("regression_test")],
                   produces: [out("pr", "PR URL, or branch name if no forge is configured")]),
                cp("postmortem", 5,
                   goal: "Write a blameless postmortem that prevents the next incident.",
                   instructions: """
                   Write a blameless postmortem with:
                   1. Impact and timeline.
                   2. The root cause (from `root_cause`) in plain language.
                   3. What went well and what went poorly in the response.
                   4. Concrete preventive action items, each with an owner.
                   Focus on systems and process, never on people.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The postmortem states impact, timeline, and root cause in plain language.
                   - Every preventive action item is concrete and has a named owner.
                   - The text is blameless — it examines systems, not people.
                   """,
                   attempts: 4, minutes: 20,
                   requires: [req("root_cause"), req("pr")]),
            ]
        )
    }

    // MARK: - Library release

    static var libraryRelease: VibeLaneDefinition {
        VibeLaneDefinition(
            id: libraryReleaseLaneID,
            name: "Public library release",
            detail: "Implement, diff the public API, choose semver, write migrations, dry-run the publish.",
            steerLimit: 1,
            checkpoints: [
                cp("implement", 0,
                   goal: "Land the change behind a deliberate public API.",
                   instructions: """
                   1. Implement the change keeping the public surface intentional: expose only what is needed, keep \
                   existing names stable wherever possible.
                   2. Use the project's own test and type-check tooling; keep everything green.
                   3. Note every public-surface addition, removal, or signature change as you make it.
                   """,
                   skills: ["tdd"],
                   verify: """
                   Done when ALL of:
                   - The change is implemented and the project's tests and type checks pass with its own tooling.
                   - Every public-surface change is deliberate and listed by the worker.
                   - Nothing internal leaked into the public surface.
                   """,
                   attempts: 12, minutes: 90,
                   onExhausted: .escalate,
                   produces: [out("implementation", "files changed and the public-surface changes made")]),
                cp("api-diff", 1,
                   goal: "Produce a reviewable diff of the public API.",
                   instructions: """
                   1. Generate a diff of the public API between the last release and now — use the ecosystem's API-report \
                   tooling if the project has it, otherwise construct it from exports/headers/declarations.
                   2. Classify every entry: addition, removal, or signature change.
                   3. Save the report as a file in the repository so later steps can read it.
                   """,
                   skills: ["semantic-versioning"],
                   verify: """
                   Done when ALL of:
                   - A saved API diff file exists listing additions, removals, and signature changes.
                   - It is consistent with the public-surface notes from `implementation` — nothing missing, nothing extra.
                   """,
                   attempts: 5, minutes: 20,
                   requires: [req("implementation")],
                   produces: [out("api_diff", "path to the saved API diff report")]),
                cp("semver-decision", 2,
                   goal: "Choose the version bump the API diff actually requires.",
                   instructions: """
                   1. Apply the rule to `api_diff`: any removal or breaking signature change = major; additive-only = \
                   minor; internal-only = patch.
                   2. Name the specific diff entries that drive the decision.
                   3. When in doubt between two bumps, choose the larger one and say why.
                   """,
                   skills: ["semantic-versioning"],
                   verify: """
                   Done when ALL of:
                   - The chosen bump (major/minor/patch) matches the breaking-vs-additive reality of the API diff.
                   - The specific driving changes are named.
                   - Any judgment call is stated with its reasoning.
                   """,
                   attempts: 4, minutes: 20,
                   requires: [req("api_diff")],
                   produces: [out("semver_decision", "major|minor|patch plus the driving changes")]),
                cp("migration-notes", 3,
                   goal: "Write the changelog and a migration a consumer can follow.",
                   instructions: """
                   1. Update the changelog to match `api_diff` exactly — no missing entries, no invented ones.
                   2. For every breaking change, write a concrete migration step with a before/after code example.
                   3. Write for a consumer who has never read this codebase.
                   """,
                   skills: ["semantic-versioning", "writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The changelog matches the API diff one-to-one.
                   - Every breaking change has a migration step with a before/after example a consumer can follow.
                   """,
                   attempts: 5, minutes: 25,
                   requires: [req("api_diff"), req("semver_decision")],
                   produces: [out("changelog", "path to the updated changelog")]),
                cp("publish-dryrun", 4,
                   goal: "Prove the publish is clean before anyone tags it.",
                   instructions: """
                   1. Run the package manager's publish dry-run (or pack) for this ecosystem.
                   2. Inspect the artifact contents and metadata: no stray files, correct entry points, and the version \
                   matching `semver_decision`.
                   3. Record what was inspected and the result.
                   """,
                   verify: """
                   Done when ALL of:
                   - The dry-run/pack succeeds with the project's own tooling.
                   - The artifact contains no stray files and its entry points and metadata are correct.
                   - The staged version matches the semver decision.
                   """,
                   attempts: 4, minutes: 15,
                   requires: [req("semver_decision")],
                   produces: [out("dryrun_report", "what was inspected in the artifact and the result")]),
                cp("release-handoff", 5,
                   goal: "Assemble the release packet and get the maintainer's sign-off.",
                   instructions: """
                   Assemble the packet: the chosen version and why, a summary of changes from `changelog`, the consumer \
                   migration, and the `dryrun_report` result. Present it so the maintainer (the user) can approve the \
                   release in one read — tagging and publishing stay theirs. If they request changes, address exactly \
                   what they raised.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   You are signing off this release. Approve only if ALL of:
                   - The packet states the version with its reasoning, the change summary, the migration, and the dry-run result.
                   - You agree the semver decision matches the API diff.
                   - You could tag and publish from this packet without reading the code.
                   """,
                   humanVerify: true,
                   attempts: 3, minutes: 15,
                   requires: [req("semver_decision"), req("changelog"), req("dryrun_report")]),
            ]
        )
    }

    // MARK: - Product launch

    static var productLaunch: VibeLaneDefinition {
        VibeLaneDefinition(
            id: productLaunchLaneID,
            name: "Product launch",
            detail: "Positioning, key messages, blog, social, a claims review, then a publisher handoff.",
            steerLimit: 1,
            checkpoints: [
                cp("positioning", 0,
                   goal: "Define exactly who this is for, the problem it solves, and the one-line promise.",
                   instructions: """
                   1. Decide the audience — specific enough that someone is excluded.
                   2. Name the problem it solves for them, in their words.
                   3. Write the single most compelling promise. It must be concrete and falsifiable — if it could appear \
                   in any competitor's launch, sharpen it.
                   4. Save the positioning where the rest of the launch work can read it.
                   """,
                   skills: ["positioning-messaging", "writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The audience is specific enough to exclude someone.
                   - The problem is stated in the audience's words, not the builder's.
                   - The promise is one line, concrete, falsifiable, and consistent with the audience and problem.
                   """,
                   attempts: 4, minutes: 20,
                   produces: [out("positioning", "audience + problem + the one-line promise")]),
                cp("key-messages", 1,
                   goal: "Derive 3–5 key messages that each carry the promise on their own.",
                   instructions: """
                   1. From `positioning`, derive 3–5 messages that each support the promise and stand alone.
                   2. No overlap, no filler — delete any message whose removal loses nothing.
                   3. For each message, note the evidence that makes it defensible.
                   """,
                   skills: ["positioning-messaging", "writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - There are 3–5 messages, each laddering up to the promise.
                   - No two messages overlap, and none is filler.
                   - Each message lists the evidence that defends it.
                   """,
                   attempts: 4, minutes: 20,
                   requires: [req("positioning")],
                   produces: [out("key_messages", "the messages, one line each, with evidence noted")]),
                cp("blog-draft", 2,
                   goal: "Write the announcement post to the messages, in the brand voice.",
                   instructions: """
                   1. Structure: a hook, the problem, the solution, and one clear call to action.
                   2. Every claim must trace to `key_messages` and its evidence — nothing unsupportable.
                   3. Match the brand voice from existing published material; when unsure, plainer wins.
                   4. Cut anything that does not earn its place. Save the draft as a file.
                   """,
                   skills: ["positioning-messaging", "writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The draft has a hook, problem, solution, and exactly one clear call to action.
                   - Every claim traces to a key message and its evidence.
                   - The voice matches existing published material, and nothing in it is filler.
                   """,
                   attempts: 6, minutes: 30,
                   onExhausted: .escalate,
                   requires: [req("positioning"), req("key_messages")],
                   produces: [out("blog_draft", "path to the draft post")]),
                cp("social-variants", 3,
                   goal: "Adapt the post into platform-native variants without diluting the message.",
                   instructions: """
                   1. Adapt `blog_draft` for each target platform, respecting its length and format constraints.
                   2. Each variant must lead with a key message, not a summary of the post.
                   3. Keep the core promise intact in every variant.
                   """,
                   skills: ["positioning-messaging", "writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - Variants exist for the target platforms and meet each platform's length/format limits.
                   - Each variant leads with a key message and preserves the promise.
                   """,
                   attempts: 4, minutes: 15,
                   requires: [req("key_messages"), req("blog_draft")],
                   produces: [out("variants", "where the platform variants live")]),
                cp("claims-review", 4,
                   goal: "Prepare the claim audit for your accuracy and legal-safety sign-off.",
                   instructions: """
                   1. Extract every factual claim from the draft and the variants into a checkable list.
                   2. For each claim, note the supporting evidence, and pre-flag anything that risks overclaiming, \
                   unsupported metrics, competitor disparagement, or a missing disclaimer.
                   3. Fix or cut what is clearly unsafe, and present the full claim list with verdicts so the reviewer \
                   (the user) can sign off quickly. Legal safety is their call, not yours.
                   """,
                   skills: ["red-teaming"],
                   verify: """
                   You are the accuracy and legal-safety gate. Approve only if ALL of:
                   - Every factual claim in the draft and variants is listed with its evidence.
                   - You judge no claim overclaims, cites unsupported metrics, or disparages a competitor.
                   - Required disclaimers are present for your market.
                   """,
                   humanVerify: true,
                   attempts: 4, minutes: 25,
                   requires: [req("blog_draft"), req("variants")],
                   produces: [out("claims_review", "the claim list with verdicts and fixes")]),
                cp("assets-bundle", 5,
                   goal: "Assemble the launch assets with a complete manifest.",
                   instructions: """
                   1. Gather every asset the launch references: images, links, docs, demo URLs.
                   2. Verify each exists and resolves.
                   3. Assemble the bundle with a manifest listing every item and where it is used.
                   """,
                   verify: """
                   Done when ALL of:
                   - Every referenced asset exists and resolves.
                   - The manifest lists each asset and where the launch uses it.
                   """,
                   attempts: 3, minutes: 15,
                   requires: [req("blog_draft")],
                   produces: [out("asset_manifest", "path to the manifest")]),
                cp("publish-handoff", 6,
                   goal: "Hand the publisher a runbook they can execute without asking questions.",
                   instructions: """
                   Produce the launch runbook: what publishes where and when (anchored on the supplied launch date), the \
                   owner of each piece, links into `asset_manifest`, and any pending sign-off from `claims_review`.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The runbook states what publishes where and when, anchored on the launch date.
                   - Every piece has an owner, and pending sign-offs are listed.
                   - A publisher could execute it without follow-up questions.
                   """,
                   attempts: 2, minutes: 10,
                   requires: [
                       req("claims_review"),
                       req("asset_manifest"),
                       ask("launch_date", "When does this launch go live? Date, time, and timezone."),
                   ],
                   produces: [out("runbook", "path to the launch runbook")]),
            ]
        )
    }

    // MARK: - Research memo

    static var researchMemo: VibeLaneDefinition {
        VibeLaneDefinition(
            id: researchMemoLaneID,
            name: "Research → decision memo",
            detail: "Frame the decision, gather sourced data, analyze, red-team, then a board memo.",
            steerLimit: 2,
            checkpoints: [
                cp("frame", 0,
                   goal: "Frame the decision so the research can actually change it.",
                   instructions: """
                   1. State the decision to be made and the realistic options (including \"do nothing\" where honest).
                   2. List the specific questions whose answers would change the choice — if an answer would not move \
                   the decision, cut the question.
                   3. For each question, note where it can be answered from.
                   4. Do not gather data yet.
                   """,
                   skills: ["sourcing-research", "writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The decision and its realistic options are explicit.
                   - Every listed question is decision-relevant — its answer would change the choice.
                   - Each question names where it can be answered from.
                   """,
                   attempts: 4, minutes: 20,
                   produces: [out("decision_frame", "the decision, options, and deciding questions")]),
                cp("gather", 1,
                   goal: "Collect a structured dataset that can answer the deciding questions.",
                   instructions: """
                   1. Collect data against each question in `decision_frame` — stop gathering what no question needs.
                   2. Structure the dataset (table/JSON/CSV) and cite the source on every record.
                   3. Note coverage per question and every gap you could not fill.
                   4. Save the dataset as a file and validate its structure before moving on.
                   """,
                   skills: ["sourcing-research"],
                   verify: """
                   Done when ALL of:
                   - A structured dataset file exists and parses/validates.
                   - Every record cites its source.
                   - Coverage is noted per deciding question, and gaps are listed honestly.
                   """,
                   attempts: 6, minutes: 40,
                   onExhausted: .escalate,
                   requires: [req("decision_frame")],
                   produces: [out("dataset", "path to the structured dataset")]),
                cp("analyze", 2,
                   goal: "Turn the data into findings that answer the deciding questions.",
                   instructions: """
                   1. Produce findings, each tied to one question from `decision_frame` and grounded in `dataset`.
                   2. Separate cited fact from inference, visibly, in every finding.
                   3. Where the data is insufficient to answer a question, say so — do not reach.
                   4. No recommendation yet: establish what the data shows.
                   """,
                   skills: ["sourcing-research"],
                   verify: """
                   Done when ALL of:
                   - Every finding maps to a deciding question and cites records from the dataset.
                   - Fact and inference are visibly separated in each finding.
                   - Unanswerable questions are declared rather than reached for.
                   """,
                   attempts: 6, minutes: 35,
                   requires: [req("decision_frame"), req("dataset")],
                   produces: [out("findings", "the findings list, each tied to a question")]),
                cp("red-team", 3,
                   goal: "Attack the conclusions until only defensible ones remain.",
                   instructions: """
                   1. Try to break the leading recommendation: hunt for bias, cherry-picking, data gaps, and alternative \
                   readings of the same data.
                   2. Steelman the strongest opposing conclusion from the same dataset.
                   3. Revise anything that does not survive; document every challenge you ran and its outcome.
                   """,
                   skills: ["red-teaming"],
                   verify: """
                   Done when ALL of:
                   - The challenges run (bias, cherry-picking, gaps, alternative readings) are documented with outcomes.
                   - The strongest opposing conclusion was steelmanned in writing.
                   - The surviving recommendation was revised where challenges landed.
                   """,
                   attempts: 5, minutes: 30,
                   onExhausted: .escalate,
                   requires: [req("findings")],
                   produces: [out("red_team_notes", "challenges run, outcomes, and revisions made")]),
                cp("memo", 4,
                   goal: "Write the board memo: recommendation first, evidence behind it.",
                   instructions: """
                   1. Lead with the recommendation in the first lines.
                   2. Follow with the rationale tied to `findings`, the key risks, and what new information would change \
                   the answer.
                   3. Be concise and decision-oriented; save the memo as a file.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   Done when ALL of:
                   - The memo leads with a clear recommendation.
                   - The rationale ties to specific findings; risks and would-change-the-answer conditions are stated.
                   - It is concise enough to read in one sitting and is saved as a file.
                   """,
                   attempts: 5, minutes: 30,
                   requires: [req("findings"), req("red_team_notes")],
                   produces: [out("memo", "path to the memo")]),
                cp("exec-handoff", 5,
                   goal: "Deliver the decision packet and get the decision-maker's acceptance.",
                   instructions: """
                   Assemble the packet: the recommendation, your confidence level and why, the open questions for the \
                   decision-maker, and references to the full trail (frame → dataset → findings → red-team → memo). \
                   The decision-maker (the user) accepts or sends it back — answer exactly what they challenge.
                   """,
                   skills: ["writing-clearly"],
                   verify: """
                   You are the decision-maker. Accept only if ALL of:
                   - The recommendation is clear and the confidence level is honest about the evidence behind it.
                   - The open questions are ones you can carry, not gaps the research should have closed.
                   - Every claim you spot-check traces back through the research trail.
                   """,
                   humanVerify: true,
                   attempts: 3, minutes: 15,
                   requires: [req("memo")]),
            ]
        )
    }
}


// MARK: - Starter skill library

/// Ships a few starter Agent Skills (SKILL.md folders) to a managed directory so
/// lane checkpoints can reference them by bare name (e.g. "tdd"). The worker reads
/// each skill's SKILL.md on demand. Users add their own skills (by path) in lanes.
enum VibeLaneSkillLibrary {
    struct Skill {
        let name: String
        let description: String
        let body: String
    }

    static let starters: [Skill] = [
        Skill(
            name: "tdd",
            description: "Test-driven development with a red-green-refactor loop. Use when implementing a feature or fixing a bug in code that can be covered by automated tests.",
            body: """
            # Test-Driven Development

            ## When to use
            Any code change whose behavior can be captured by an automated test.

            ## Loop
            1. RED — write the smallest failing test that captures the desired behavior; run it and confirm it fails for the right reason.
            2. GREEN — write the least code that makes it pass; add no untested behavior.
            3. REFACTOR — remove duplication and improve names while the suite stays green.
            4. Repeat one behavior at a time.

            ## Rules
            - One behavior per test, with a name that describes the behavior.
            - Never weaken or delete a test to go green.
            - Keep the whole suite green between steps.
            - Test through the public interface, not internals.
            """
        ),
        Skill(
            name: "diagnosing-bugs",
            description: "A disciplined loop for diagnosing hard bugs and performance regressions from evidence. Use when a defect's cause is unknown and must be found, not guessed.",
            body: """
            # Diagnosing Bugs

            ## Loop
            1. Reproduce — get a reliable, minimal reproduction (ideally a failing test).
            2. Observe — gather evidence: logs, stack traces, diffs, metrics.
            3. Hypothesize — state one falsifiable hypothesis for the cause.
            4. Test it — run the smallest experiment that confirms or kills the hypothesis.
            5. Fix the confirmed root cause (not the symptom) and add a regression test.

            ## Rules
            - Change one variable at a time.
            - Distinguish cause from symptom; don't fix what you can't explain.
            - If several hypotheses fail, widen the evidence rather than keep guessing.
            """
        ),
        Skill(
            name: "code-review",
            description: "Review a code change for correctness, minimality, and design. Use when verifying that a diff does what was asked without collateral damage.",
            body: """
            # Code Review

            ## Check
            - Correctness — does the change do what the task asked? Are edge cases handled?
            - Minimality — only necessary changes; no unrelated edits, dead code, or debug leftovers.
            - Design — deep modules with small interfaces; no needless complexity or duplication.
            - Tests — meaningful tests that would fail without the change; none weakened.
            - Conventions — matches the project's style and patterns.

            ## Output
            State PASS or FAIL with specific, actionable feedback tied to files or lines.
            """
        ),
        Skill(
            name: "writing-clearly",
            description: "Write clear, concise, on-message prose: docs, posts, memos, summaries. Use when drafting or editing any written content for a human audience.",
            body: """
            # Writing Clearly

            ## Principles
            - Lead with the point; put the conclusion first.
            - One idea per paragraph; cut anything that doesn't earn its place.
            - Concrete over abstract; show, don't just claim.
            - Match the audience's vocabulary; define jargon or drop it.
            - Every claim must be supportable.

            ## Process
            1. Outline the arc before drafting.
            2. Draft fast, then cut ~20%.
            3. Read it aloud and fix anything that stumbles.
            """
        ),
        Skill(
            name: "scoping-and-planning",
            description: "Turn a feature request into testable acceptance criteria and an ordered slice plan. Use before implementing any multi-step piece of work.",
            body: """
            # Scoping & Planning

            ## Process
            1. Interrogate the request: what problem, for whom, and what changes for them when it ships?
            2. Write acceptance criteria as observable checks — each names what to run or inspect and the expected result.
            3. Name the non-goals out loud; scope creep starts where non-goals stay implicit.
            4. Slice vertically: each slice crosses the stack and delivers observable value on its own.
            5. Order slices so each builds on the last, and map every criterion to a slice.

            ## Rules
            - A criterion you cannot check by running or inspecting something is an opinion, not a criterion.
            - Slices that only make sense together are one slice.
            - If a slice cannot be verified independently, split or restructure it.
            """
        ),
        Skill(
            name: "security-review",
            description: "Review a code change for security impact, with or without scanner tooling. Use on any change that touches input handling, authorization, secrets, or new dependencies.",
            body: """
            # Security Review

            ## Check the changed code for
            - Input validation — every external input parsed, bounded, and rejected loudly.
            - Authorization — every new path checks WHO may do this, not just whether someone is logged in.
            - Secrets — nothing sensitive in code, logs, error messages, or test fixtures.
            - Injection — SQL/shell/HTML/path traversal wherever strings meet interpreters or filesystems.
            - Deserialization and file handling — no untrusted data driving types, paths, or execution.

            ## Process
            1. Run the project's scanners and dependency audits if configured; record the results either way.
            2. Walk the diff with the checklist above; follow tainted data from source to sink.
            3. Fix real findings. Document false positives in writing — never suppress a finding to pass.
            """
        ),
        Skill(
            name: "semantic-versioning",
            description: "Classify public-API changes, choose the right semver bump, and write consumer migrations. Use when releasing or evolving a published library.",
            body: """
            # Semantic Versioning & API Evolution

            ## Rules
            - Removal or breaking signature change on the public surface → MAJOR.
            - Additive-only public change → MINOR. Internal-only change → PATCH.
            - Behavior changes consumers can observe count as API changes, even with identical signatures.
            - When torn between two bumps, take the larger and say why.

            ## Process
            1. Diff the public surface (exports/declarations/headers) between the last release and now.
            2. Classify every entry: added / removed / changed-signature / internal.
            3. For each breaking entry, write the consumer migration with a before/after code example.
            4. The changelog matches the diff one-to-one — nothing missing, nothing invented.
            """
        ),
        Skill(
            name: "sourcing-research",
            description: "Collect structured, cited data and turn it into findings that separate fact from inference. Use for research, competitive analysis, and any evidence-based recommendation.",
            body: """
            # Sourced Research

            ## Process
            1. Start from the deciding questions: gather only what some question needs.
            2. Structure records (table/JSON/CSV) and cite the source on every record.
            3. Track coverage per question; list gaps honestly instead of papering over them.
            4. In analysis, separate cited fact from inference visibly, in every finding.

            ## Rules
            - A record without a source is a rumor: source it or drop it.
            - If the data cannot answer a question, say so — do not reach.
            - Prefer primary sources; note explicitly when only secondary ones exist.
            """
        ),
        Skill(
            name: "red-teaming",
            description: "Stress-test a conclusion, claim set, or recommendation before it ships. Use whenever work would otherwise be judged only by the person who produced it.",
            body: """
            # Red-Teaming Conclusions

            ## Process
            1. State the conclusion under attack in one line.
            2. Hunt for: selection bias, cherry-picking, survivorship effects, data gaps, and alternative
               readings of the same evidence.
            3. Steelman the strongest OPPOSING conclusion from the same evidence.
            4. Try to falsify: what observation would prove this wrong, and did anyone look for it?
            5. Revise whatever fails; document every challenge run and its outcome.

            ## Rules
            - Attack the strongest form of your own case, never the weakest.
            - A conclusion that survived no real challenge has not been red-teamed.
            """
        ),
        Skill(
            name: "positioning-messaging",
            description: "Craft positioning, key messages, and launch content that is specific, defensible, and on-promise. Use for announcements, marketing copy, and product narratives.",
            body: """
            # Positioning & Messaging

            ## Process
            1. Audience first — specific enough that someone is excluded.
            2. State the problem in the audience's words, not the builder's.
            3. One promise, concrete and falsifiable; if a competitor could say it verbatim, sharpen it.
            4. Ladder 3–5 messages up to the promise: each stands alone, none overlap, each is defensible
               with evidence you can show.
            5. Write content to the messages: hook, problem, solution, one clear call to action.

            ## Rules
            - Features are not messages; what the audience can now DO is the message.
            - Every claim traces to evidence. Cut anything that does not earn its place.
            - Plainer beats cleverer.
            """
        ),
    ]

    /// Names of the shipped skills (for reference / resolution).
    static var starterNames: [String] { starters.map(\.name) }

    /// Write each starter skill to `<root>/<name>/SKILL.md`, overwriting so the
    /// shipped content stays current across app versions. Returns `root`.
    @discardableResult
    static func install(into root: URL) -> URL {
        let fm = FileManager.default
        for skill in starters {
            let dir = root.appendingPathComponent(skill.name, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("SKILL.md")
            let content = "---\nname: \(skill.name)\ndescription: \(skill.description)\n---\n\n\(skill.body)\n"
            try? content.write(to: file, atomically: true, encoding: .utf8)
        }
        return root
    }
}
