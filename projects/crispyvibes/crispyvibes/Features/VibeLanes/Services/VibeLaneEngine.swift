import Foundation

// F059 — the execution engine. Drives ONE task through its lane's checkpoints.
// Per checkpoint it loops: run the worker on the Work Definition, then run the
// Verification Definition (an independent reviewer of the outcome). On pass the
// worker writes a short HANDOFF that is persisted to a handoff FILE on disk and
// becomes durable context for every later checkpoint (injected by path, like
// skills, so a fresh ACP session can recover the full journey after a restart);
// on fail it feeds the result back and retries; on a bound it stops.
// The engine orchestrates context — it points at handoff files and carries only
// small declared key/value outputs — rather than acting as the payload carrier.
// The engine never reads the worker's free-form text to decide completion.

@MainActor
final class VibeLaneEngine {
    private let lane: VibeLaneDefinition
    private let worker: VibeLaneWorkRunning
    private let reviewer: VibeLaneReviewing
    private let skillsRoot: URL?
    /// Root directory for persisted handoff files (`<root>/<taskID>/<checkpointKey>.md`).
    /// nil (tests/previews) falls back to inline-only handoff context.
    private let handoffRoot: URL?
    private let clock: VibeLaneClock
    /// Called after every state transition so the caller can persist + publish.
    private let onTransition: @MainActor (VibeLaneTask) -> Void

    init(
        lane: VibeLaneDefinition,
        worker: VibeLaneWorkRunning,
        reviewer: VibeLaneReviewing? = nil,
        skillsRoot: URL? = nil,
        handoffRoot: URL? = nil,
        clock: VibeLaneClock = VibeLaneSystemClock(),
        onTransition: @escaping @MainActor (VibeLaneTask) -> Void = { _ in }
    ) {
        self.lane = lane
        self.worker = worker
        self.reviewer = reviewer ?? VibeLaneUnavailableReviewer()
        self.skillsRoot = skillsRoot
        self.handoffRoot = handoffRoot
        self.clock = clock
        self.onTransition = onTransition
    }

    /// Drive the task until it is done, stopped, or waiting for user input.
    /// Honors cancellation of the surrounding Swift task.
    func run(_ input: VibeLaneTask) async -> VibeLaneTask {
        var task = input
        if task.state == .needsInput {
            return task
        }
        task.state = .running
        task.stopReason = nil
        setActivity(&task, AppStrings.VibeLanes.activityStarting, kind: .system)

        while true {
            if Swift.Task.isCancelled {
                return stopTask(&task, reason: .stoppedByUser)
            }
            guard let checkpoint = lane.checkpoint(forKey: task.currentCheckpointKey) else {
                return stopTask(&task, reason: .error)
            }

            ensureRunStarted(&task, checkpointKey: checkpoint.key)
            var runRecord = task.run(forKey: checkpoint.key)!
            let attemptsUsed = attemptsUsed(in: runRecord)

            // A human Review verdict answered while paused settles the pending
            // attempt first — the work already happened; never re-run the worker.
            if checkpoint.verify.humanReview, let verdict = task.pendingHumanVerdict {
                task.pendingHumanVerdict = nil
                touch(&task)
                let kind: VibeLanePromptKind = attemptsUsed == 0 ? .goal : .feedback
                if let finished = await settleAttempt(verdict, promptKind: kind, checkpoint: checkpoint, workText: "", task: &task) {
                    return finished
                }
                continue
            }

            // Contract: required carry-forward inputs must exist before entering.
            // Fatal resolutions come first so the user is never asked to Supply a
            // value for a task that must stop anyway.
            if attemptsUsed == 0 {
                let missing = missingRequiredInputs(checkpoint, task: task)
                if !missing.fatal.isEmpty {
                    appendLog(
                        &task,
                        AppStrings.VibeLanes.activityMissingInput,
                        kind: .error,
                        detail: missing.fatal.map(\.key).joined(separator: ", ")
                    )
                    // A key an earlier checkpoint declared it would produce is a
                    // runtime emission failure (missingInput); a key nothing could
                    // ever supply is an authoring error (misAuthoredLane).
                    let reason: VibeLaneStopReason = missing.fatal
                        .allSatisfy { isDeclaredProducedEarlier(key: $0.key, before: checkpoint) }
                        ? .missingInput
                        : .misAuthoredLane
                    return stopAtCheckpoint(&task, checkpoint: checkpoint, reason: reason)
                }
                if !missing.askUser.isEmpty {
                    return needsSupply(&task, checkpoint: checkpoint, missing: missing.askUser)
                }
            }

            // Bound: attempt cap.
            if attemptsUsed >= checkpoint.bounds.maxAttempts {
                return handleExhaustedBound(&task, checkpoint: checkpoint, reason: .verificationFailed)
            }
            // Bound: time limit (since the checkpoint started).
            if let startedAt = runRecord.activeWindowStartedAt ?? runRecord.startedAt,
               clock.now.timeIntervalSince(startedAt) > Double(checkpoint.bounds.timeoutSeconds) {
                return handleExhaustedBound(&task, checkpoint: checkpoint, reason: .timeout)
            }

            let steerGuidance = task.pendingSteerGuidance?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasSteerGuidance = steerGuidance?.isEmpty == false
            let promptKind: VibeLanePromptKind = hasSteerGuidance ? .steer : (attemptsUsed == 0 ? .goal : .feedback)
            // Rebuild the checkpoint context on every attempt. A retry may occur
            // after app restart or ACP reconnect, so correctness cannot depend on
            // volatile chat memory from the first prompt.
            let skillsText = skillsReference(checkpoint.work.skills)
            let inherited = inheritedHandoff(forCheckpointKey: checkpoint.key, task: task)
            let inputsText = carryForwardInputs(for: checkpoint, task: task)
            let handoffPathsText = priorHandoffPaths(forCheckpointKey: checkpoint.key, task: task)
            let prompt = Self.buildPrompt(
                taskTitle: task.title,
                checkpoint: checkpoint,
                kind: promptKind,
                lastFeedback: hasSteerGuidance ? steerGuidance : runRecord.attempts.last?.result?.feedback,
                skillsText: skillsText,
                inheritedHandoff: inherited,
                inputsText: inputsText,
                handoffPathsText: handoffPathsText
            )
            if hasSteerGuidance {
                task.pendingSteerGuidance = nil
                touch(&task)
            }

            if task.workerSessionRef == nil {
                task.workerSessionRef = UUID().uuidString
                appendLog(&task, AppStrings.VibeLanes.activityWorkerChatReady, kind: .worker)
                touch(&task)
            }
            setActivity(
                &task,
                AppStrings.VibeLanes.activityWorking(
                    checkpoint: checkpoint.displayTitle,
                    current: attemptsUsed + 1,
                    cap: checkpoint.bounds.maxAttempts
                ),
                kind: .worker
            )

            // 1) Worker does the work.
            let turn = await worker.work(prompt: prompt, projectPath: task.projectPath, sessionRef: task.workerSessionRef, agentID: task.agentID)
            let workText = turn.responseText ?? ""
            if let ref = turn.sessionRef { task.workerSessionRef = ref }
            if let ref = turn.threadRef { task.workerThreadRef = ref }
            if Swift.Task.isCancelled {
                return stopTask(&task, reason: .stoppedByUser)
            }
            if timedOut(runRecord, checkpoint: checkpoint) {
                return handleExhaustedBound(&task, checkpoint: checkpoint, reason: .timeout)
            }
            guard turn.ok else {
                let note = turn.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                appendLog(
                    &task,
                    AppStrings.VibeLanes.activityWorkerError,
                    kind: .error,
                    detail: (note?.isEmpty == false) ? note : nil
                )
                return stopAtCheckpoint(&task, checkpoint: checkpoint, reason: .error)
            }

            // 2) Verification decides "done". A human-review checkpoint pauses
            // here for the user's verdict; otherwise the reviewer agent judges.
            if checkpoint.verify.humanReview {
                return needsHumanReview(&task, checkpoint: checkpoint)
            }
            let result = await verify(checkpoint, task: &task)
            if let finished = await settleAttempt(result, promptKind: promptKind, checkpoint: checkpoint, workText: workText, task: &task) {
                return finished
            }
            // Failed verification (or an advance) → loop again; bounds are
            // re-checked at the top before any retry.
        }
    }

    /// Records the attempt and, on PASS, runs the shared pass path: handoff,
    /// declared outputs, and advancing the lane. Returns the finished task when
    /// the lane is done; nil when the loop should continue (advance or retry).
    /// A completed PASS stands even if the time bound elapsed while verifying —
    /// the bound did not run out "first".
    private func settleAttempt(
        _ result: VibeLaneVerificationResult,
        promptKind: VibeLanePromptKind,
        checkpoint: VibeLaneCheckpoint,
        workText: String,
        task: inout VibeLaneTask
    ) async -> VibeLaneTask? {
        guard var runRecord = task.run(forKey: checkpoint.key) else {
            return stopTask(&task, reason: .error)
        }
        let attempt = VibeLaneAttempt(
            index: runRecord.attempts.count,
            promptKind: promptKind,
            result: result,
            at: clock.now,
            budgetEpoch: runRecord.budgetEpoch
        )
        runRecord.attempts.append(attempt)
        upsert(run: runRecord, in: &task)
        task.lastVerification = result
        touch(&task)

        guard result.passed else { return nil }

        runRecord.status = .passed
        runRecord.endedAt = clock.now
        // Every step ends with a handoff summary.
        let handoff = await produceHandoff(checkpoint: checkpoint, attemptsUsed: max(0, runRecord.attempts.count - 1), task: &task)
        runRecord.summary = handoff
        upsert(run: runRecord, in: &task)
        // Persist the handoff durably so later checkpoints (and fresh ACP
        // sessions after a restart) can read the full journey from disk.
        writeHandoffFile(handoff, task: task, checkpointKey: checkpoint.key)
        // Store the step's declared outputs into carry-forward. The work turn
        // text is a fallback source so a thin handoff cannot lose outputs the
        // (verified) work turn already emitted.
        recordProducedOutputs(checkpoint, handoff: handoff, workText: workText, task: &task)

        if let next = lane.checkpoint(after: checkpoint.key) {
            task.currentCheckpointKey = next.key
            setActivity(&task, AppStrings.VibeLanes.activityMovingTo(next.displayTitle), kind: .system)
            return nil
        }
        // Final checkpoint: ask the worker for a task-level wrap-up
        // (kept separate from the per-step handoff).
        let outcome = await produceFinalOutcome(checkpoint: checkpoint, task: &task)
        task.outcomeSummary = outcome
        task.state = .done
        task.stopReason = .done
        setActivity(&task, AppStrings.VibeLanes.activityDone, kind: .system)
        return task
    }

    // MARK: - Verification

    /// An independent reviewer checks the checkpoint's OUTCOME against its
    /// authored verification definition and returns PASS/FAIL with feedback.
    /// Authored in the lane — nothing hardcoded.
    private func verify(_ checkpoint: VibeLaneCheckpoint, task: inout VibeLaneTask) async -> VibeLaneVerificationResult {
        if task.reviewerSessionRef == nil {
            task.reviewerSessionRef = UUID().uuidString
            appendLog(&task, AppStrings.VibeLanes.activityReviewerChatReady, kind: .verify)
            touch(&task)
        }
        setActivity(&task, AppStrings.VibeLanes.activityReviewerReviewing, kind: .verify)
        let currentRun = task.run(forKey: checkpoint.key)
        let attemptIndex = currentRun.map { run in
            run.attempts.filter { $0.budgetEpoch == run.budgetEpoch }.count
        } ?? 0
        let outcome = await reviewer.review(
            VibeLaneReviewRequest(
                taskTitle: task.title,
                projectPath: task.projectPath,
                checkpoint: checkpoint,
                attemptIndex: attemptIndex,
                repoBaselineRef: task.repoBaselineRef,
                agentID: task.agentID
            ),
            sessionRef: task.reviewerSessionRef
        )
        if let ref = outcome.sessionRef { task.reviewerSessionRef = ref }
        if let ref = outcome.threadRef { task.reviewerThreadRef = ref }
        let detail = [outcome.summary, Self.outputSnippet(outcome.evidence ?? "")]
            .compactMap { $0 }
            .joined(separator: "\n")
        if outcome.passed {
            setActivity(&task, AppStrings.VibeLanes.activityReviewerAccepted, kind: .verify)
        } else {
            setActivity(&task, AppStrings.VibeLanes.activityReviewerRejected, kind: .verify)
        }
        return VibeLaneVerificationResult(
            passed: outcome.passed,
            detail: detail.isEmpty ? nil : detail,
            feedback: outcome.passed ? nil : (outcome.feedback ?? "The reviewer did not return a clear PASS.")
        )
    }

    // MARK: - Skills (referenced by path; the worker reads them on demand)

    /// List the checkpoint's skill paths for the prompt. A bare name (e.g. "tdd")
    /// resolves to the installed skill library; an explicit path (contains "/",
    /// "~", or absolute) is used as-is (project-relative or absolute). The worker
    /// reads each skill's SKILL.md itself as needed — we never inline contents.
    private func skillsReference(_ paths: [String]) -> String? {
        let cleaned = paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.map { entry -> String in
            let resolved: String
            if entry.hasPrefix("/") || entry.hasPrefix("~") || entry.contains("/") {
                resolved = entry
            } else if let root = skillsRoot {
                resolved = root.appendingPathComponent(entry).path
            } else {
                resolved = entry
            }
            return "- \(resolved)"
        }.joined(separator: "\n")
    }

    // MARK: - Handoff baton

    /// Ask the worker (same session) to write a short handoff for the next step.
    /// An empty response is retried once — the handoff is the one artifact later
    /// steps depend on. A persistent failure never fails the task (it already
    /// passed verification); we fall back to a derived summary.
    private func produceHandoff(checkpoint: VibeLaneCheckpoint, attemptsUsed: Int, task: inout VibeLaneTask) async -> String {
        setActivity(&task, AppStrings.VibeLanes.activityWritingHandoff, kind: .worker)
        for _ in 0..<2 {
            let turn = await worker.work(
                prompt: Self.handoffPrompt(checkpoint: checkpoint),
                projectPath: task.projectPath,
                sessionRef: task.workerSessionRef,
                agentID: task.agentID
            )
            if let ref = turn.sessionRef { task.workerSessionRef = ref }
            if let ref = turn.threadRef { task.workerThreadRef = ref }
            let text = (turn.responseText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return "Checkpoint \(checkpoint.displayTitle) completed and verified (attempt \(attemptsUsed + 1))."
    }

    /// The handoff doc the previous checkpoint produced, to inject inline.
    private func inheritedHandoff(forCheckpointKey key: String, task: VibeLaneTask) -> String? {
        let ordered = lane.orderedCheckpoints
        guard let idx = ordered.firstIndex(where: { $0.key == key }), idx > 0 else { return nil }
        let summary = task.run(forKey: ordered[idx - 1].key)?.summary
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Handoff files (durable carry-forward substrate)

    /// Where one checkpoint's handoff lives on disk: `<handoffRoot>/<taskID>/<key>.md`.
    private func handoffFileURL(taskID: UUID, checkpointKey: String) -> URL? {
        handoffRoot?
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
            .appendingPathComponent("\(checkpointKey).md")
    }

    /// Persist a passed checkpoint's handoff to disk. Failures are logged-only —
    /// the handoff also survives on the checkpoint run record.
    private func writeHandoffFile(_ text: String, task: VibeLaneTask, checkpointKey: String) {
        guard let url = handoffFileURL(taskID: task.id, checkpointKey: checkpointKey) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Non-fatal: inline summary + carry-forward still exist.
        }
    }

    /// Paths of every earlier passed checkpoint's handoff file, in lane order,
    /// for injection into the worker prompt (read on demand — never inlined).
    /// This survives app restarts and fresh ACP sessions, unlike chat memory.
    private func priorHandoffPaths(forCheckpointKey key: String, task: VibeLaneTask) -> String? {
        guard handoffRoot != nil else { return nil }
        let ordered = lane.orderedCheckpoints
        guard let idx = ordered.firstIndex(where: { $0.key == key }), idx > 0 else { return nil }
        let lines = ordered[..<idx].compactMap { earlier -> String? in
            guard task.run(forKey: earlier.key)?.status == .passed,
                  let url = handoffFileURL(taskID: task.id, checkpointKey: earlier.key),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return "- \(earlier.displayTitle): \(url.path)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Every passed checkpoint's handoff path, in lane order — the full journey,
    /// fed to the final outcome prompt so the report is grounded in what each
    /// step actually recorded rather than end-of-session memory (F060 feedback).
    private func allHandoffPaths(task: VibeLaneTask) -> [String] {
        guard handoffRoot != nil else { return [] }
        return lane.orderedCheckpoints.compactMap { checkpoint -> String? in
            guard task.run(forKey: checkpoint.key)?.status == .passed,
                  let url = handoffFileURL(taskID: task.id, checkpointKey: checkpoint.key),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url.path
        }
    }

    // MARK: - Carry-forward contract (declared inputs/outputs)

    private func missingRequiredInputs(
        _ checkpoint: VibeLaneCheckpoint,
        task: VibeLaneTask
    ) -> (askUser: [VibeLaneInputRequirement], fatal: [VibeLaneInputRequirement]) {
        let carried = task.carryForward ?? [:]
        var askUser: [VibeLaneInputRequirement] = []
        var fatal: [VibeLaneInputRequirement] = []
        for input in checkpoint.inputRequirements {
            let value = carried[input.key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard value.isEmpty else { continue }
            if input.askUser {
                askUser.append(input)
            } else {
                fatal.append(input)
            }
        }
        return (askUser, fatal)
    }

    /// Whether any checkpoint ordered before `checkpoint` declares `key` in its
    /// `produces`. Distinguishes a worker emission failure (missingInput) from a
    /// lane that could never satisfy the requirement (misAuthoredLane).
    private func isDeclaredProducedEarlier(key: String, before checkpoint: VibeLaneCheckpoint) -> Bool {
        let ordered = lane.orderedCheckpoints
        guard let idx = ordered.firstIndex(where: { $0.key == checkpoint.key }) else { return false }
        return ordered[..<idx].contains { $0.producedOutputs.contains(key) }
    }

    /// The `key: value` lines for this step's required inputs, to inject into its prompt.
    private func carryForwardInputs(for checkpoint: VibeLaneCheckpoint, task: VibeLaneTask) -> String? {
        let carried = task.carryForward ?? [:]
        let lines = checkpoint.requiredInputs.compactMap { key -> String? in
            guard let value = carried[key], !value.isEmpty else { return nil }
            return "- \(key): \(value)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Parse `OUTPUT <key>: <value>` lines from the handoff (falling back to the
    /// verified work turn's text) and store the step's declared outputs into
    /// carry-forward. Missing declared outputs are logged, not hard-failed, and
    /// NEVER delete a value already carried forward (e.g. a user-supplied one);
    /// a later checkpoint that requires a truly absent key resolves it through
    /// the missing-input rules.
    private func recordProducedOutputs(
        _ checkpoint: VibeLaneCheckpoint,
        handoff: String,
        workText: String = "",
        task: inout VibeLaneTask
    ) {
        let declared = checkpoint.producedOutputs
        guard !declared.isEmpty else { return }
        let fromHandoff = Self.parseOutputs(handoff)
        let fromWork = Self.parseOutputs(workText)
        var carried = task.carryForward ?? [:]
        var missing: [String] = []
        for key in declared {
            if let value = fromHandoff[key] ?? fromWork[key], !value.isEmpty {
                carried[key] = value
            } else {
                missing.append(key)
            }
        }
        task.carryForward = carried
        if !missing.isEmpty {
            appendLog(&task, AppStrings.VibeLanes.activityMissingOutput, kind: .system, detail: missing.joined(separator: ", "))
        }
    }

    /// Extract `OUTPUT <key>: <value>` lines from worker text.
    static func parseOutputs(_ text: String) -> [String: String] {
        var outputs: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix("OUTPUT ") else { continue }
            let rest = line.dropFirst("OUTPUT ".count)
            guard let colon = rest.firstIndex(of: ":") else { continue }
            let key = rest[..<colon].trimmingCharacters(in: .whitespaces)
            let value = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty { outputs[key] = value }
        }
        return outputs
    }

    /// On the final checkpoint, ask the worker for a wrap-up of the whole task so
    /// the Done state has a clear outcome. Failures fall back to a derived line.
    private func produceFinalOutcome(checkpoint: VibeLaneCheckpoint, task: inout VibeLaneTask) async -> String {
        setActivity(&task, AppStrings.VibeLanes.activityWritingOutcome, kind: .worker)
        let turn = await worker.work(
            prompt: Self.finalOutcomePrompt(
                taskTitle: task.title,
                handoffPaths: allHandoffPaths(task: task)
            ),
            projectPath: task.projectPath,
            sessionRef: task.workerSessionRef,
            agentID: task.agentID
        )
        if let ref = turn.sessionRef { task.workerSessionRef = ref }
        if let ref = turn.threadRef { task.workerThreadRef = ref }
        let text = (turn.responseText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Task completed: \(task.title)." : text
    }

    static func finalOutcomePrompt(taskTitle: String, handoffPaths: [String] = []) -> String {
        var prompt = """
        All checkpoints for this task are complete and verified. Write the FINAL OUTCOME report the user \
        will read on the task's Done screen — it is the single artifact they judge this task by, so make \
        every line earn its place. Ground every claim in the actual repository state: re-check files and \
        results before citing them; never repeat a claim from memory you can verify on disk.

        ## Task
        \(taskTitle)

        Rules:
        - Concrete over general: exact file paths (path:line where useful), commands run, test names and \
        counts, commit refs, URLs. A reader should be able to click/verify every reference.
        - No process narration ("first I explored…"), no praise, no restating the task.
        - If something is partially done or was descoped, say so plainly under Follow-ups.

        Use exactly this structure:

        ## Outcome
        2–4 sentences: what now exists that didn't before, and whether it fully satisfies the task.

        ## What changed
        Bullet list of the files/artifacts that changed, each with its path and a clause on what changed \
        in it. Include new tests here.

        ## How it's verified
        The exact checks that prove it works: commands + their results, test suites + pass counts, or \
        manual verification steps taken. Quote real numbers.

        ## Where it lives
        Branch, commits, PRs, or URLs — exact references.

        ## Follow-ups
        Deferred work, known risks, and the recommended next action. Write "None" if truly empty.
        """
        if !handoffPaths.isEmpty {
            prompt += """
            \n
            The step-by-step journey is in these handoff files — read them to recall earlier steps' \
            outcomes before writing (do not copy them verbatim):
            \(handoffPaths.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
        return prompt
    }

    static func handoffPrompt(checkpoint: VibeLaneCheckpoint) -> String {
        var prompt = """
        The checkpoint "\(checkpoint.displayTitle)" is complete and its verification passed. Write the handoff \
        the NEXT step will rely on — it may run in a fresh session with no memory of this conversation, so \
        include everything it needs and nothing it doesn't.

        Use exactly this structure, concrete and under ~15 lines total:

        ## What changed
        Files touched and the essence of the change.

        ## What's verified
        What was checked and how (commands, results).

        ## Open risks
        Anything unresolved the next step should know. Write "None" if empty.

        ## What the next step needs
        The specific context, paths, or decisions to carry forward.
        """
        let outputs = checkpoint.outputDeclarations
        if !outputs.isEmpty {
            prompt += "\n\nThis step declares outputs. After the sections above, end with exactly one line per output, in this exact machine-readable form:\n"
            prompt += outputs.map { declaration in
                let hint = declaration.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = (hint?.isEmpty == false) ? " <\(hint!)>" : " <file path or one-line reference>"
                return "OUTPUT \(declaration.key):\(suffix)"
            }.joined(separator: "\n")
        }
        return prompt
    }

    // MARK: - Prompt

    static func buildPrompt(
        taskTitle: String,
        checkpoint: VibeLaneCheckpoint,
        kind: VibeLanePromptKind,
        lastFeedback: String?,
        skillsText: String? = nil,
        inheritedHandoff: String? = nil,
        inputsText: String? = nil,
        handoffPathsText: String? = nil
    ) -> String {
        let task = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = checkpoint.work.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = checkpoint.work.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = checkpoint.verify.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedback = lastFeedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = []

        // Opening frame differs per prompt kind; the context sections are shared.
        switch kind {
        case .goal:
            parts.append("""
            You are an autonomous engineer working ONE step of a larger task. Do this step fully and \
            correctly. When you finish, an independent reviewer will verify your actual outcome against \
            the Definition of done below before the work may advance — so produce real changes, not a plan.
            """)
        case .feedback:
            parts.append("""
            You are continuing the SAME step after an independent reviewer rejected the previous attempt. \
            Do not restart from scratch — build on the current state and fix what the reviewer raised.
            """)
        case .steer:
            parts.append("""
            You are continuing the SAME step after it exhausted its bounds and the user provided steering guidance. \
            Treat the guidance as feedback for this checkpoint only; it does not change the Definition of done.
            """)
        }

        if !task.isEmpty {
            parts.append("## Overall task\n\(task)")
        }
        parts.append("## This step — \(checkpoint.displayTitle)\n\(goal.isEmpty ? "(see overall task)" : goal)")
        if let inheritedHandoff, !inheritedHandoff.isEmpty {
            parts.append("""
            ## Inherited handoff (advisory context from the previous step)
            This is background only — it does not change this step's goal, instructions, or definition of done.
            \(inheritedHandoff)
            """)
        }
        if let handoffPathsText, !handoffPathsText.isEmpty {
            parts.append("""
            ## Earlier step handoffs (read on demand)
            Each earlier step wrote a handoff file. Read the ones you need for context — they record \
            what changed, what was verified, and open risks:
            \(handoffPathsText)
            """)
        }
        if let inputsText, !inputsText.isEmpty {
            parts.append("""
            ## Inputs (produced by earlier steps — use these)
            \(inputsText)
            """)
        }
        if !instructions.isEmpty {
            parts.append("## How to do it\n\(instructions)")
        }
        if let skillsText, !skillsText.isEmpty {
            parts.append("""
            ## Skills available
            Read each skill's SKILL.md (and any files it references) as needed before you work:
            \(skillsText)
            """)
        }

        switch kind {
        case .goal:
            if !definition.isEmpty {
                parts.append("## Definition of done (the reviewer will check the outcome against this)\n\(definition)")
            }
            parts.append("""
            ## What good looks like
            - You actually achieved the goal and meet every part of the Definition of done — verifiable from the repository, not from your description.
            - The change is the smallest one that does the job: no unrelated edits, no dead code, no debug leftovers.
            - You followed the step's instructions and the skills you were given.
            - The work is left in a clean, checkable state (build/tests green where applicable).
            - When done, briefly state what you changed and how it satisfies the Definition of done.
            """)
        case .feedback:
            if !feedback.isEmpty {
                parts.append("## Reviewer feedback to address\n\(feedback)")
            }
            if !definition.isEmpty {
                parts.append("## Definition of done\n\(definition)")
            }
            parts.append("Address the feedback specifically and bring the outcome up to the Definition of done.")
        case .steer:
            if !feedback.isEmpty {
                parts.append("## User steering guidance\n\(feedback)")
            }
            if !definition.isEmpty {
                parts.append("## Definition of done\n\(definition)")
            }
            parts.append("Use the steering guidance to make a focused next attempt that satisfies the Definition of done.")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func outputSnippet(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(12).joined(separator: "\n")
    }

    // MARK: - Mutation helpers

    private func ensureRunStarted(_ task: inout VibeLaneTask, checkpointKey: String) {
        if var existing = task.run(forKey: checkpointKey) {
            if existing.status == .pending || existing.status == .needsInput || existing.status == .stopped {
                existing.status = .running
                existing.startedAt = existing.startedAt ?? clock.now
                existing.activeWindowStartedAt = existing.activeWindowStartedAt ?? clock.now
                existing.stopReason = nil
                existing.endedAt = nil
                upsert(run: existing, in: &task)
            }
            return
        }
        let runRecord = VibeLaneCheckpointRun(
            checkpointKey: checkpointKey,
            status: .running,
            startedAt: clock.now,
            activeWindowStartedAt: clock.now
        )
        task.checkpointRuns.append(runRecord)
    }

    private func attemptsUsed(in runRecord: VibeLaneCheckpointRun) -> Int {
        runRecord.attempts.filter { $0.budgetEpoch == runRecord.budgetEpoch }.count
    }

    private func timedOut(_ runRecord: VibeLaneCheckpointRun, checkpoint: VibeLaneCheckpoint) -> Bool {
        guard let startedAt = runRecord.activeWindowStartedAt ?? runRecord.startedAt else { return false }
        return clock.now.timeIntervalSince(startedAt) > Double(checkpoint.bounds.timeoutSeconds)
    }

    private func needsSupply(
        _ task: inout VibeLaneTask,
        checkpoint: VibeLaneCheckpoint,
        missing: [VibeLaneInputRequirement]
    ) -> VibeLaneTask {
        let keys = missing.map(\.key)
        let prompt = missing.compactMap { input -> String? in
            let trimmed = input.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : "\(input.key): \(trimmed)"
        }.joined(separator: "\n")
        let fallback = AppStrings.VibeLanes.supplyRequestPrompt(keys: keys.joined(separator: ", "))
        return needsInput(
            &task,
            checkpoint: checkpoint,
            request: VibeLaneInputRequest(
                kind: .supply,
                checkpointKey: checkpoint.key,
                createdAt: clock.now,
                prompt: prompt.isEmpty ? fallback : prompt,
                missingKeys: keys
            ),
            reason: nil
        )
    }

    /// Pause for the user's verdict on a human-review checkpoint. The work is
    /// done; the user inspects the outcome and approves or requests changes.
    private func needsHumanReview(
        _ task: inout VibeLaneTask,
        checkpoint: VibeLaneCheckpoint
    ) -> VibeLaneTask {
        let definition = checkpoint.verify.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = definition.isEmpty
            ? AppStrings.VibeLanes.reviewRequestPrompt(checkpoint: checkpoint.displayTitle)
            : definition
        return needsInput(
            &task,
            checkpoint: checkpoint,
            request: VibeLaneInputRequest(
                kind: .review,
                checkpointKey: checkpoint.key,
                createdAt: clock.now,
                prompt: prompt
            ),
            reason: nil
        )
    }

    private func handleExhaustedBound(
        _ task: inout VibeLaneTask,
        checkpoint: VibeLaneCheckpoint,
        reason: VibeLaneStopReason
    ) -> VibeLaneTask {
        guard checkpoint.bounds.onExhausted == .escalate else {
            return stopAtCheckpoint(&task, checkpoint: checkpoint, reason: reason)
        }
        guard task.steerCount < lane.steerLimit else {
            appendLog(&task, AppStrings.VibeLanes.reasonSteerLimitReached, kind: .system, detail: "limit \(lane.steerLimit)")
            return stopAtCheckpoint(&task, checkpoint: checkpoint, reason: .steerLimitReached)
        }
        let feedback = task.run(forKey: checkpoint.key)?.attempts.last?.result?.feedback
        let prompt = AppStrings.VibeLanes.steerRequestPrompt(
            checkpoint: checkpoint.displayTitle,
            reason: reasonLabel(reason)
        )
        return needsInput(
            &task,
            checkpoint: checkpoint,
            request: VibeLaneInputRequest(
                kind: .steer,
                checkpointKey: checkpoint.key,
                createdAt: clock.now,
                prompt: prompt,
                lastFeedback: feedback,
                reason: reason
            ),
            reason: reason
        )
    }

    private func needsInput(
        _ task: inout VibeLaneTask,
        checkpoint: VibeLaneCheckpoint,
        request: VibeLaneInputRequest,
        reason: VibeLaneStopReason?
    ) -> VibeLaneTask {
        if var runRecord = task.run(forKey: checkpoint.key) {
            runRecord.status = .needsInput
            runRecord.stopReason = reason
            runRecord.endedAt = clock.now
            upsert(run: runRecord, in: &task)
        }
        task.state = .needsInput
        task.stopReason = nil
        task.openInputRequest = request
        setActivity(&task, AppStrings.VibeLanes.needsYou, kind: .input)
        return task
    }

    private func upsert(run: VibeLaneCheckpointRun, in task: inout VibeLaneTask) {
        if let idx = task.checkpointRuns.firstIndex(where: { $0.checkpointKey == run.checkpointKey }) {
            task.checkpointRuns[idx] = run
        } else {
            task.checkpointRuns.append(run)
        }
    }

    private func stopAtCheckpoint(
        _ task: inout VibeLaneTask,
        checkpoint: VibeLaneCheckpoint,
        reason: VibeLaneStopReason
    ) -> VibeLaneTask {
        if var runRecord = task.run(forKey: checkpoint.key) {
            runRecord.status = .stopped
            runRecord.stopReason = reason
            runRecord.endedAt = clock.now
            upsert(run: runRecord, in: &task)
        }
        return stopTask(&task, reason: reason)
    }

    private func stopTask(_ task: inout VibeLaneTask, reason: VibeLaneStopReason) -> VibeLaneTask {
        task.state = .stopped
        task.stopReason = reason
        task.openInputRequest = nil
        setActivity(&task, AppStrings.VibeLanes.activityStopped(reasonLabel(reason)), kind: reason == .error ? .error : .system)
        return task
    }

    private func setActivity(_ task: inout VibeLaneTask, _ activity: String, kind: VibeLaneActivityKind) {
        let now = clock.now
        task.currentActivity = activity
        appendLog(&task, activity, kind: kind, at: now)
        task.updatedAt = now
        onTransition(task)
    }

    private func appendLog(
        _ task: inout VibeLaneTask,
        _ message: String,
        kind: VibeLaneActivityKind,
        detail: String? = nil,
        at: Date? = nil
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = at ?? clock.now
        var log = task.activityLog ?? []
        if let last = log.last, last.message == trimmed, last.kind == kind {
            return
        }
        log.append(VibeLaneActivityLogEntry(at: now, kind: kind, message: trimmed, detail: detail))
        if log.count > 120 {
            log.removeFirst(log.count - 120)
        }
        task.activityLog = log
    }

    private func touch(_ task: inout VibeLaneTask) {
        task.updatedAt = clock.now
        onTransition(task)
    }

    private func reasonLabel(_ reason: VibeLaneStopReason) -> String {
        switch reason {
        case .verificationFailed:
            return AppStrings.VibeLanes.reasonVerificationFailed
        case .timeout:
            return AppStrings.VibeLanes.reasonTimedOut
        case .error:
            return AppStrings.VibeLanes.reasonError
        case .stoppedByUser:
            return AppStrings.VibeLanes.reasonStoppedByYou
        case .missingInput:
            return AppStrings.VibeLanes.reasonMissingInput
        case .misAuthoredLane:
            return AppStrings.VibeLanes.reasonMisAuthoredLane
        case .steerLimitReached:
            return AppStrings.VibeLanes.reasonSteerLimitReached
        case .done:
            return AppStrings.VibeLanes.completed
        }
    }
}
