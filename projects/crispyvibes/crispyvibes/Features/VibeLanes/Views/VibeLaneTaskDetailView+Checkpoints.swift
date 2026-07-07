import SwiftUI

// F059 — Task detail: the checkpoint LANE as a left-right master–detail. The left
// rail is a vertical stepper (status nodes on a continuous connector) that selects
// a step; the right pane shows the selected step's definition of done, per-attempt
// verification results, and the carry-forward it produced.
//
// Worker/reviewer ACP sessions are shared across a task's checkpoints (one
// continuous thread each), so thread access lives once in the header — never here.

extension VibeLaneTaskDetailView {

    @ViewBuilder
    func checkpointSplit(_ task: VibeLaneTask) -> some View {
        let checkpoints = lane?.orderedCheckpoints ?? []
        if checkpoints.isEmpty {
            ContentUnavailableView(AppStrings.VibeLanes.laneNotFound, systemImage: "rectangle.stack.badge.questionmark")
                .frame(maxWidth: .infinity)
                .padding(uiScale.spacing(24))
        } else if checkpoints.count == 1 {
            // A single-step lane has nothing to select — no rail, full-width detail.
            checkpointDetailPane(task)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if isWideLayout {
            HStack(alignment: .top, spacing: uiScale.spacing(20)) {
                checkpointRail(task)
                    .frame(width: uiScale.chromeSize(240), alignment: .topLeading)
                checkpointDetailPane(task)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
                checkpointRail(task)
                    .frame(maxWidth: .infinity, alignment: .leading)
                checkpointDetailPane(task)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Left rail (the lane)

    private func checkpointRail(_ task: VibeLaneTask) -> some View {
        let checkpoints = lane?.orderedCheckpoints ?? []
        let states = checkpoints.map { VibeLaneNodeState.resolve(for: $0, task: task) }
        let selected = effectiveSelection(task)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checkpoints.enumerated()), id: \.element.key) { index, checkpoint in
                railRow(
                    checkpoint,
                    task: task,
                    state: states[index],
                    topColor: index == 0 ? nil : connectorColor(states[index]),
                    bottomColor: index == checkpoints.count - 1 ? nil : connectorColor(states[index + 1]),
                    isSelected: checkpoint.key == selected
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func railRow(
        _ checkpoint: VibeLaneCheckpoint,
        task: VibeLaneTask,
        state: VibeLaneNodeState,
        topColor: Color?,
        bottomColor: Color?,
        isSelected: Bool
    ) -> some View {
        Button {
            selectedKey = checkpoint.key
            definitionExpanded = nil
        } label: {
            HStack(alignment: .top, spacing: uiScale.spacing(10)) {
                // Reserve the gutter; the connector is drawn in an overlay so it
                // spans exactly the row's natural height (no greedy stretching).
                Color.clear.frame(width: uiScale.chromeSize(30), height: 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(checkpoint.displayTitle)
                        .font(.system(size: uiScale.textSize(13), weight: (state == .active || state == .needsInput) ? .semibold : .regular))
                        .foregroundStyle(palette.primaryTextColor)
                    stepStatusLine(checkpoint, task: task, state: state)
                }
                .padding(.vertical, uiScale.spacing(4))
                Spacer(minLength: 0)
            }
            .padding(.vertical, uiScale.spacing(5))
            .padding(.horizontal, uiScale.spacing(8))
            .overlay(alignment: .topLeading) {
                connectorGutter(state: state, topColor: topColor, bottomColor: bottomColor)
                    .padding(.leading, uiScale.spacing(8))
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vibeLaneHoverable()
    }

    /// Fixed-width leading gutter drawn as a row overlay: top segment, node, then
    /// a bottom segment that fills the row's remaining natural height, keeping
    /// the connector continuous without inflating the row.
    private func connectorGutter(state: VibeLaneNodeState, topColor: Color?, bottomColor: Color?) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(topColor ?? .clear).frame(width: 2, height: uiScale.spacing(7))
            VibeLaneStatusNode(state: state, diameter: uiScale.chromeSize(16), pulses: state == .active)
            Rectangle().fill(bottomColor ?? .clear).frame(width: 2).frame(maxHeight: .infinity)
        }
        .frame(width: uiScale.chromeSize(30))
        .frame(maxHeight: .infinity)
    }

    // MARK: - Right detail pane

    @ViewBuilder
    func checkpointDetailPane(_ task: VibeLaneTask) -> some View {
        if let checkpoint = lane?.checkpoint(forKey: effectiveSelection(task)) {
            let run = task.run(forKey: checkpoint.key)
            let state = VibeLaneNodeState.resolve(for: checkpoint, task: task)
            VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                HStack(spacing: uiScale.spacing(10)) {
                    VibeLaneStatusNode(state: state, diameter: uiScale.chromeSize(18), pulses: state == .active)
                    Text(checkpoint.displayTitle)
                        .font(.system(size: uiScale.textSize(17), weight: .semibold))
                        .foregroundStyle(palette.primaryTextColor)
                    Spacer(minLength: 0)
                }
                stepStatusLine(checkpoint, task: task, state: state)

                // What happened here (the payoff) comes first…
                if let run, !run.attempts.isEmpty {
                    VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                        Text(AppStrings.VibeLanes.attempts(run.attempts.count))
                            .font(.system(size: uiScale.textSize(11), weight: .semibold))
                            .foregroundStyle(palette.tertiaryTextColor)
                        ForEach(run.attempts) { attemptRow($0) }
                    }
                }
                if let summary = nonEmpty(run?.summary), !summary.lowercased().hasPrefix("passed at attempt") {
                    carryForward(summary)
                }

                // …and the authored definition is reference material, collapsed
                // once the step has history.
                definitionDisclosure(checkpoint, task: task, hasHistory: !(run?.attempts.isEmpty ?? true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(uiScale.spacing(16))
            .vibeLaneCard()
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func definitionDisclosure(_ checkpoint: VibeLaneCheckpoint, task: VibeLaneTask, hasHistory: Bool) -> some View {
        let expanded = Binding<Bool>(
            get: { definitionExpanded ?? !hasHistory },
            set: { definitionExpanded = $0 }
        )
        DisclosureGroup(isExpanded: expanded) {
            VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
                if let goal = nonEmpty(checkpoint.goal) {
                    detailBlock(title: AppStrings.VibeLanes.checkpointGoal, text: goal)
                }
                if let instructions = nonEmpty(checkpoint.instructions) {
                    detailBlock(title: AppStrings.VibeLanes.checkpointInstructions, text: instructions)
                }
                skillsBlock(checkpoint.skills)
                if !checkpoint.inputRequirements.isEmpty || !checkpoint.outputDeclarations.isEmpty {
                    contractBlock(checkpoint, task: task)
                }
                if let doneWhen = nonEmpty(checkpoint.verify.definition) {
                    detailBlock(title: AppStrings.VibeLanes.checkpointDoneWhen, text: doneWhen)
                }
                boundsBlock(checkpoint)
            }
            .padding(.top, uiScale.spacing(8))
        } label: {
            Text(AppStrings.VibeLanes.stepDefinition)
                .font(.system(size: uiScale.textSize(12), weight: .semibold))
                .foregroundStyle(palette.secondaryTextColor)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func stepStatusLine(_ checkpoint: VibeLaneCheckpoint, task: VibeLaneTask, state: VibeLaneNodeState) -> some View {
        let run = task.run(forKey: checkpoint.key)
        switch state {
        case .done:
            HStack(spacing: uiScale.spacing(6)) {
                passChip(true)
                if let n = run?.attempts.count, n > 0 {
                    Text(AppStrings.VibeLanes.attempts(n))
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
                if let started = run?.startedAt, let ended = run?.endedAt {
                    Text(VibeLaneTaskDetailView.elapsedText(from: started, to: ended))
                        .font(.system(size: uiScale.textSize(11), design: .monospaced))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
            }
        case .active:
            Text(nonEmpty(task.currentActivity)
                 ?? AppStrings.VibeLanes.attemptRunning(current: task.attemptsOnCurrentCheckpoint + 1, cap: checkpoint.bounds.maxAttempts))
                .font(.system(size: uiScale.textSize(11), weight: .medium))
                .foregroundStyle(Color.accentColor)
                .lineLimit(2)
        case .needsInput:
            Text(task.openInputRequest?.prompt ?? AppStrings.VibeLanes.needsYou)
                .font(.system(size: uiScale.textSize(11), weight: .medium))
                .foregroundStyle(Color.orange)
                .lineLimit(2)
        case .stopped:
            HStack(spacing: uiScale.spacing(6)) {
                passChip(false)
                Text(reasonLabel(task.stopReason))
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(.orange)
            }
        case .pending:
            Text(AppStrings.VibeLanes.checkpointNotStarted)
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.tertiaryTextColor)
        }
    }

    private func passChip(_ passed: Bool) -> some View {
        Text(passed ? AppStrings.VibeLanes.pass : AppStrings.VibeLanes.fail)
            .font(.system(size: uiScale.textSize(10), weight: .bold))
            .foregroundStyle(passed ? .green : .orange)
            .padding(.horizontal, uiScale.spacing(5))
            .padding(.vertical, uiScale.spacing(1))
            .background(Capsule().fill((passed ? Color.green : Color.orange).opacity(0.14)))
    }

    private func attemptRow(_ attempt: VibeLaneAttempt) -> some View {
        let passed = attempt.result?.passed ?? false
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: uiScale.spacing(6)) {
                Text(AppStrings.VibeLanes.attemptLabel(attempt.index + 1))
                    .font(.system(size: uiScale.textSize(11), weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                if attempt.result != nil {
                    passChip(passed)
                }
            }
            if let feedback = nonEmpty(attempt.result?.feedback) {
                detailText(feedback)
            }
            if let detail = nonEmpty(attempt.result?.detail) {
                detailText(detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: uiScale.textSize(11), design: .monospaced))
            .foregroundStyle(palette.secondaryTextColor)
            .textSelection(.enabled)
            .lineLimit(8)
    }

    private func detailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            Text(text)
                .font(.system(size: uiScale.textSize(12)))
                .foregroundStyle(palette.secondaryTextColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boundsBlock(_ checkpoint: VibeLaneCheckpoint) -> some View {
        let text = AppStrings.VibeLanes.boundsSummary(
            attempts: checkpoint.bounds.maxAttempts,
            minutes: max(1, checkpoint.bounds.timeoutSeconds / 60),
            behavior: checkpoint.bounds.onExhausted == .escalate
                ? AppStrings.VibeLanes.escalateOnExhausted
                : AppStrings.VibeLanes.stopOnExhausted
        )
        return detailBlock(title: AppStrings.VibeLanes.editorBounds, text: text)
    }

    private func skillsBlock(_ skills: [String]) -> some View {
        let cleaned = skills
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let text = cleaned.isEmpty
            ? AppStrings.VibeLanes.checkpointNoSkills
            : cleaned.map { "- \($0)" }.joined(separator: "\n")
        return detailBlock(title: AppStrings.VibeLanes.checkpointSkills, text: text)
    }

    /// The step's declared inputs (with resolved carry-forward values) and outputs.
    @ViewBuilder
    private func contractBlock(_ checkpoint: VibeLaneCheckpoint, task: VibeLaneTask) -> some View {
        let carried = task.carryForward ?? [:]
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            if !checkpoint.inputRequirements.isEmpty {
                inputContractList(AppStrings.VibeLanes.checkpointInputs, inputs: checkpoint.inputRequirements, carried: carried)
            }
            if !checkpoint.outputDeclarations.isEmpty {
                outputContractList(AppStrings.VibeLanes.checkpointProduces, outputs: checkpoint.outputDeclarations, carried: carried)
            }
        }
    }

    private func inputContractList(_ title: String, inputs: [VibeLaneInputRequirement], carried: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            ForEach(inputs, id: \.key) { input in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: uiScale.spacing(6)) {
                        Text(input.askUser ? AppStrings.VibeLanes.askUserInput(input.key) : input.key)
                            .font(.system(size: uiScale.textSize(11), weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.primaryTextColor)
                        Text(nonEmpty(carried[input.key]) ?? "—")
                            .font(.system(size: uiScale.textSize(11)))
                            .foregroundStyle(palette.secondaryTextColor)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let prompt = nonEmpty(input.prompt) {
                        Text(prompt)
                            .font(.system(size: uiScale.textSize(10)))
                            .foregroundStyle(palette.tertiaryTextColor)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func outputContractList(_ title: String, outputs: [VibeLaneOutputDeclaration], carried: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            ForEach(outputs, id: \.key) { output in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: uiScale.spacing(6)) {
                        Text(output.key)
                            .font(.system(size: uiScale.textSize(11), weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.primaryTextColor)
                        Text(nonEmpty(carried[output.key]) ?? "—")
                            .font(.system(size: uiScale.textSize(11)))
                            .foregroundStyle(palette.secondaryTextColor)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let detail = nonEmpty(output.detail) {
                        Text(AppStrings.VibeLanes.outputDescription(detail))
                            .font(.system(size: uiScale.textSize(10)))
                            .foregroundStyle(palette.tertiaryTextColor)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func carryForward(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(AppStrings.VibeLanes.checkpointHandoff, systemImage: "arrow.turn.down.right")
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            VibeLaneMarkdownText(markdown: text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(uiScale.spacing(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.canvasSecondaryBackgroundColor.opacity(0.9)))
    }

    private func connectorColor(_ state: VibeLaneNodeState) -> Color {
        VibeLaneRoute.connectorColor(for: state, tertiary: palette.tertiaryTextColor)
    }
}
