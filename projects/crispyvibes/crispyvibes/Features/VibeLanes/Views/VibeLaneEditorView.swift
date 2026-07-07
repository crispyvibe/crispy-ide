import SwiftUI

// F059 — lane authoring. Edits a draft copy of the lane and commits via `onSave`.
// A checkpoint is exactly: Work Definition (goal/instructions/skills),
// Verification Definition (an independent reviewer of the outcome), and Bounds (max attempts + time).

@MainActor
struct VibeLaneEditorView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let lane: VibeLaneDefinition
    var onSave: (VibeLaneDefinition) -> VibeLaneDefinition = { $0 }
    var onDelete: (() -> Void)? = nil

    @State private var draft: VibeLaneDefinition
    @State private var selectedIndex: Int = 0
    @State private var newSkill: String = ""
    @State private var savedFlash = false

    init(lane: VibeLaneDefinition,
         onSave: @escaping (VibeLaneDefinition) -> VibeLaneDefinition = { $0 },
         onDelete: (() -> Void)? = nil) {
        self.lane = lane
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: lane)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiScale.spacing(18)) {
                header
                if !laneWarnings.isEmpty {
                    warningPanel(laneWarnings)
                }
                stepper
                if let cp = selectedCheckpointBinding {
                    checkpointPanel(cp)
                }
            }
            .padding(uiScale.spacing(26))
        }
        .background(palette.canvasBackgroundColor)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: uiScale.spacing(6)) {
                TextField(AppStrings.VibeLanes.laneNamePlaceholder, text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: uiScale.textSize(21), weight: .semibold))
                    .frame(maxWidth: 420)
                TextField(AppStrings.VibeLanes.laneDescriptionPlaceholder, text: detailBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: uiScale.textSize(13)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(maxWidth: 520)
                Stepper(value: $draft.steerLimit, in: 0...10) {
                    Text(AppStrings.VibeLanes.steerLimit(draft.steerLimit))
                        .font(.system(size: uiScale.textSize(12)))
                        .foregroundStyle(palette.secondaryTextColor)
                }
                .frame(width: 180, alignment: .leading)
            }
            Spacer()
            HStack(spacing: uiScale.spacing(10)) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) { Text(AppStrings.VibeLanes.deleteLane) }
                }
                Button {
                    draft = onSave(draft)
                    savedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedFlash = false }
                } label: {
                    Label(savedFlash ? AppStrings.VibeLanes.saved : AppStrings.VibeLanes.saveLane, systemImage: savedFlash ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: uiScale.textSize(13), weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Stepper

    private var stepper: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: uiScale.spacing(6)) {
                ForEach(Array(draft.checkpoints.enumerated()), id: \.offset) { index, checkpoint in
                    checkpointStep(index: index, checkpoint: checkpoint)
                    if index < draft.checkpoints.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: uiScale.iconSize(10), weight: .semibold))
                            .foregroundStyle(palette.tertiaryTextColor)
                    }
                }
                Button(action: addCheckpoint) {
                    Image(systemName: "plus")
                        .font(.system(size: uiScale.iconSize(13), weight: .semibold))
                        .frame(width: uiScale.chromeSize(34), height: uiScale.chromeSize(34))
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(dash: [4])))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(AppStrings.VibeLanes.editorCheckpoint)
            }
            .padding(.vertical, 1)
        }
    }

    private func checkpointStep(index: Int, checkpoint: VibeLaneCheckpoint) -> some View {
        let isSelected = index == selectedIndex
        return Button { selectedIndex = index } label: {
            HStack(spacing: uiScale.spacing(8)) {
                Text("\(index + 1)")
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : palette.secondaryTextColor)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(checkpoint.displayTitle)
                        .font(.system(size: uiScale.textSize(12), weight: .semibold))
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(checkpoint.key)
                        .font(.system(size: uiScale.textSize(10), design: .monospaced))
                        .foregroundStyle(palette.tertiaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, uiScale.spacing(10))
            .padding(.vertical, uiScale.spacing(8))
            .frame(width: uiScale.chromeSize(170), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(isSelected ? 0.0 : 0.05), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : palette.tertiaryTextColor.opacity(0.14),
                                  lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(checkpoint.displayTitle)
    }

    // MARK: - Checkpoint panel

    private func checkpointPanel(_ cp: Binding<VibeLaneCheckpoint>) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    checkpointPanelTitle
                    Spacer()
                    checkpointActions
                }
                VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
                    checkpointPanelTitle
                    checkpointActions
                }
            }

            // Work Definition
            sectionLabel(AppStrings.VibeLanes.editorWork)
            labeled(AppStrings.VibeLanes.editorStepKey) {
                TextField(AppStrings.VibeLanes.stepKeyPlaceholder, text: cp.key).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
            }
            labeled(AppStrings.VibeLanes.editorGoal) {
                TextField(AppStrings.VibeLanes.goalPlaceholder, text: cp.work.goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
            }
            labeled(AppStrings.VibeLanes.editorSkillPaths) {
                editableSkills(cp.work.skills)
            }
            labeled(AppStrings.VibeLanes.editorInstructions) {
                TextField(AppStrings.VibeLanes.instructionsPlaceholder, text: cp.work.instructions, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
            }

            Divider()

            // Verification Definition — judged by the reviewer agent, or by the
            // user when the author picks human verification.
            labeled(AppStrings.VibeLanes.editorVerification) {
                TextField("", text: verifyBinding(cp), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...8)
            }
            labeled(AppStrings.VibeLanes.editorVerifiedBy) {
                Picker("", selection: humanReviewBinding(cp)) {
                    Text(AppStrings.VibeLanes.editorReviewerAgent).tag(false)
                    Text(AppStrings.VibeLanes.editorVerifiedByYou).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            Divider()

            // Contract — declared inputs/outputs the engine validates + carries forward.
            VibeLaneContractEditor(checkpoint: cp)

            Divider()

            // Bounds
            sectionLabel(AppStrings.VibeLanes.editorBounds)
            ViewThatFits(in: .horizontal) {
                boundsRow(cp)
                VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                    boundsAttemptControl(cp)
                    boundsTimeControl(cp)
                    boundsExhaustedControl(cp)
                }
            }
        }
        .padding(uiScale.spacing(18))
        .vibeLaneCard()
    }

    private var checkpointPanelTitle: some View {
        Text(AppStrings.VibeLanes.editorCheckpoint)
            .font(.system(size: uiScale.textSize(16), weight: .semibold))
    }

    private var checkpointActions: some View {
        HStack(spacing: uiScale.spacing(8)) {
            if draft.checkpoints.count > 1 {
                Button { moveCheckpoint(offset: -1) } label: {
                    Label(AppStrings.VibeLanes.moveCheckpointLeft, systemImage: "chevron.left")
                }
                .disabled(selectedIndex == 0)
                .buttonStyle(.bordered)

                Button { moveCheckpoint(offset: 1) } label: {
                    Label(AppStrings.VibeLanes.moveCheckpointRight, systemImage: "chevron.right")
                }
                .disabled(selectedIndex >= draft.checkpoints.count - 1)
                .buttonStyle(.bordered)

                Button(role: .destructive) { removeCheckpoint() } label: {
                    Image(systemName: "trash")
                        .frame(width: uiScale.chromeSize(28), height: uiScale.chromeSize(24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help(AppStrings.VibeLanes.discard)
                .accessibilityLabel(AppStrings.VibeLanes.discard)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: uiScale.textSize(12), weight: .semibold))
            .foregroundStyle(palette.secondaryTextColor)
    }

    private func boundsRow(_ cp: Binding<VibeLaneCheckpoint>) -> some View {
        HStack(spacing: uiScale.spacing(24)) {
            boundsAttemptControl(cp)
            boundsTimeControl(cp)
            boundsExhaustedControl(cp)
        }
    }

    private func boundsAttemptControl(_ cp: Binding<VibeLaneCheckpoint>) -> some View {
        labeled(AppStrings.VibeLanes.maxAttempts) {
            Stepper(value: cp.bounds.maxAttempts, in: 1...100) {
                Text("\(cp.wrappedValue.bounds.maxAttempts)")
                    .font(.system(size: uiScale.textSize(14), weight: .semibold))
                    .monospacedDigit()
            }
            .frame(width: 160)
        }
    }

    private func boundsTimeControl(_ cp: Binding<VibeLaneCheckpoint>) -> some View {
        labeled(AppStrings.VibeLanes.timeLimitMinutes) {
            Stepper(value: timeoutMinutesBinding(cp), in: 1...240) {
                Text(AppStrings.VibeLanes.minutesShort(cp.wrappedValue.bounds.timeoutSeconds / 60))
                    .font(.system(size: uiScale.textSize(14), weight: .semibold))
            }
            .frame(width: 160)
        }
    }

    private func boundsExhaustedControl(_ cp: Binding<VibeLaneCheckpoint>) -> some View {
        labeled(AppStrings.VibeLanes.whenExhausted) {
            Picker("", selection: exhaustedBehaviorBinding(cp)) {
                Text(AppStrings.VibeLanes.stopOnExhausted).tag(VibeLaneBoundBehavior.stop)
                Text(AppStrings.VibeLanes.escalateOnExhausted).tag(VibeLaneBoundBehavior.escalate)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }

    private func editableSkills(_ skills: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            FlowLayout(spacing: uiScale.spacing(8)) {
                ForEach(Array(skills.wrappedValue.enumerated()), id: \.offset) { idx, skill in
                    HStack(spacing: 5) {
                        Text(skill).font(.system(size: uiScale.textSize(12)))
                        Button { skills.wrappedValue.remove(at: idx) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .frame(width: uiScale.chromeSize(16), height: uiScale.chromeSize(16))
                        }
                            .buttonStyle(.plain)
                            .help(AppStrings.VibeLanes.deleteTask)
                            .accessibilityLabel(AppStrings.VibeLanes.deleteTask)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.10)))
                    .foregroundStyle(Color.accentColor)
                }
            }
            HStack {
                TextField(AppStrings.VibeLanes.addSkillPlaceholder, text: $newSkill)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    .onSubmit { addSkill(skills) }
                Button(AppStrings.VibeLanes.add) { addSkill(skills) }.disabled(newSkill.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Bindings & mutations

    private var selectedCheckpointBinding: Binding<VibeLaneCheckpoint>? {
        guard draft.checkpoints.indices.contains(selectedIndex) else { return nil }
        return Binding(
            get: { draft.checkpoints[selectedIndex] },
            set: { draft.checkpoints[selectedIndex] = $0 }
        )
    }

    private var detailBinding: Binding<String> {
        Binding(get: { draft.detail ?? "" }, set: { draft.detail = $0.isEmpty ? nil : $0 })
    }

    private func verifyBinding(_ cp: Binding<VibeLaneCheckpoint>) -> Binding<String> {
        Binding(
            get: { cp.wrappedValue.verify.definition },
            set: { cp.wrappedValue.verify.definition = $0 }
        )
    }

    private func humanReviewBinding(_ cp: Binding<VibeLaneCheckpoint>) -> Binding<Bool> {
        Binding(
            get: { cp.wrappedValue.verify.humanReview },
            set: { cp.wrappedValue.verify.humanReview = $0 }
        )
    }

    private func timeoutMinutesBinding(_ cp: Binding<VibeLaneCheckpoint>) -> Binding<Int> {
        Binding(
            get: { max(1, cp.wrappedValue.bounds.timeoutSeconds / 60) },
            set: { cp.wrappedValue.bounds.timeoutSeconds = $0 * 60 }
        )
    }

    private func exhaustedBehaviorBinding(_ cp: Binding<VibeLaneCheckpoint>) -> Binding<VibeLaneBoundBehavior> {
        Binding(
            get: { cp.wrappedValue.bounds.onExhausted },
            set: { cp.wrappedValue.bounds.onExhausted = $0 }
        )
    }

    private func addCheckpoint() {
        let existing = Set(draft.checkpoints.map { $0.key })
        var key = VibeLaneTaskManager.normalizedKey("step-\(draft.checkpoints.count + 1)")
        while key.isEmpty || existing.contains(key) {
            key = "step-\(draft.checkpoints.count + 1)-\(UUID().uuidString.prefix(4))"
        }
        draft.checkpoints.append(
            VibeLaneCheckpoint(key: key, order: draft.checkpoints.count,
                               goal: "", verify: VibeLaneVerificationDefinition(""))
        )
        selectedIndex = draft.checkpoints.count - 1
    }

    private func removeCheckpoint() {
        guard draft.checkpoints.indices.contains(selectedIndex), draft.checkpoints.count > 1 else { return }
        draft.checkpoints.remove(at: selectedIndex)
        refreshCheckpointOrder()
        selectedIndex = min(selectedIndex, draft.checkpoints.count - 1)
    }

    private func moveCheckpoint(offset: Int) {
        let newIndex = selectedIndex + offset
        guard draft.checkpoints.indices.contains(selectedIndex),
              draft.checkpoints.indices.contains(newIndex) else { return }
        draft.checkpoints.swapAt(selectedIndex, newIndex)
        selectedIndex = newIndex
        refreshCheckpointOrder()
    }

    private func refreshCheckpointOrder() {
        for i in draft.checkpoints.indices { draft.checkpoints[i].order = i }
    }

    private func addSkill(_ skills: Binding<[String]>) {
        let trimmed = newSkill.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        skills.wrappedValue.append(trimmed)
        newSkill = ""
    }

    @ViewBuilder
    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(7)) {
            Text(label).font(.system(size: uiScale.textSize(13), weight: .semibold))
            content()
        }
    }

    private var laneWarnings: [String] {
        var warnings: [String] = []
        let rawKeys = draft.checkpoints.map(\.key)
        let normalized = rawKeys.map(VibeLaneTaskManager.normalizedKey)
        if normalized.contains("") || Set(normalized).count != normalized.count || rawKeys != normalized {
            warnings.append(AppStrings.VibeLanes.keyNormalizationWarning)
        }
        let producedByPrior = draft.checkpoints.sorted { $0.order < $1.order }.reduce(into: (seen: Set<String>(), warnings: [String]())) { partial, checkpoint in
            let missing = checkpoint.inputRequirements
                .filter { !$0.askUser && !partial.seen.contains($0.key) }
                .map(\.key)
            if !missing.isEmpty {
                partial.warnings.append(AppStrings.VibeLanes.misAuthoredContractWarning(checkpoint: checkpoint.displayTitle, keys: missing.joined(separator: ", ")))
            }
            partial.seen.formUnion(checkpoint.producedOutputs)
        }.warnings
        warnings.append(contentsOf: producedByPrior)
        return warnings
    }

    private func warningPanel(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(.orange)
            }
        }
        .padding(uiScale.spacing(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .vibeLaneCard(cornerRadius: 10, tint: .orange)
    }
}

/// Minimal flow layout for chips (wraps to available width).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
