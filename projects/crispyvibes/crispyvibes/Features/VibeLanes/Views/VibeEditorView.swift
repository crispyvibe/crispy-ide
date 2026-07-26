import SwiftUI

@MainActor
struct VibeEditorView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let vibe: VibeDefinition
    let usageCount: Int
    let categories: [VibeCategory]
    let engineOptionCatalog: ACPAgentEngineOptionCatalog
    let onSave: (VibeDefinition) async -> VibeDefinition?
    let onDelete: (() -> Void)?

    @State private var draft: VibeDefinition
    @State private var savedFlash = false
    @State private var isSaving = false
    init(
        vibe: VibeDefinition,
        usageCount: Int,
        categories: [VibeCategory],
        engineOptionCatalog: ACPAgentEngineOptionCatalog,
        onSave: @escaping (VibeDefinition) async -> VibeDefinition?,
        onDelete: (() -> Void)?
    ) {
        self.vibe = vibe
        self.usageCount = usageCount
        self.categories = categories
        self.engineOptionCatalog = engineOptionCatalog
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: vibe)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiScale.spacing(20)) {
                header
                behaviorSummary
                editor
            }
            .padding(.horizontal, uiScale.spacing(30))
            .padding(.vertical, uiScale.spacing(24))
            .frame(maxWidth: uiScale.chromeSize(1_180), alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(palette.canvasBackgroundColor)
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: uiScale.spacing(20)) {
                identity
                Spacer(minLength: uiScale.spacing(20))
                actions
            }
            VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
                identity
                actions
            }
        }
    }
    private var identity: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(12)) {
            VibeLaneIconBadge(
                systemImage: "scope",
                color: palette.accentColor,
                side: 40,
                iconSize: 16
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
                TextField(AppStrings.VibeLanes.vibeNamePlaceholder, text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: uiScale.textSize(22), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                    .frame(maxWidth: uiScale.chromeSize(540))

                TextField(AppStrings.VibeLanes.vibeDescriptionPlaceholder, text: detailBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(maxWidth: uiScale.chromeSize(600))

                metadata
            }
        }
    }
    private var metadata: some View {
        HStack(spacing: uiScale.spacing(10)) {
            VibeCategoryPicker(
                selection: $draft.category,
                categories: categories
            )

            VibeLaneStatusChip(
                text: draft.isReady ? AppStrings.VibeLanes.ready : AppStrings.VibeLanes.laneNeedsSetup,
                color: draft.isReady ? palette.successColor : palette.warningColor,
                icon: draft.isReady ? "checkmark" : "exclamationmark",
                size: 9
            )

            Label(
                AppStrings.VibeLanes.vibeVersion(draft.version),
                systemImage: "clock.arrow.circlepath"
            )
            Label(
                AppStrings.VibeLanes.vibeUsage(usageCount),
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        }
        .font(.system(size: uiScale.textSize(10), weight: .medium))
        .foregroundStyle(palette.tertiaryTextColor)
    }
    private var actions: some View {
        HStack(spacing: uiScale.spacing(8)) {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(AppStrings.VibeLanes.deleteVibe, systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(usageCount > 0)
                .help(AppStrings.VibeLanes.vibeUsage(usageCount))
            }

            Button(action: save) {
                Label(
                    savedFlash ? AppStrings.VibeLanes.saved : AppStrings.VibeLanes.saveVibe,
                    systemImage: savedFlash ? "checkmark" : "square.and.arrow.down"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isSaving
            )
        }
        .controlSize(uiScale.controlSize)
    }
    private var behaviorSummary: some View {
        VibeLaneCheckpointBehaviorSummary(
            checkpoint: draft.checkpoint(key: "preview", order: 0)
        )
        .padding(uiScale.spacing(14))
        .background(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                .fill(palette.canvasSecondaryBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(8), style: .continuous)
                .strokeBorder(palette.borderColorValue.opacity(0.48), lineWidth: uiScale.chromeSize(1))
        )
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(20)) {
            contractEditor
            sectionDivider
            operationalSettings
        }
    }
    private var contractEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: uiScale.spacing(24)) {
                workColumn
                    .frame(width: uiScale.chromeSize(520), alignment: .topLeading)

                Divider()
                    .padding(.vertical, uiScale.spacing(4))

                reviewColumn
                    .frame(width: uiScale.chromeSize(520), alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: uiScale.spacing(20)) {
                workColumn
                sectionDivider
                reviewColumn
            }
        }
    }

    private var workColumn: some View {
        section(AppStrings.VibeLanes.editorWork, icon: "hammer") {
            labeled(AppStrings.VibeLanes.editorGoal) {
                TextField(AppStrings.VibeLanes.goalPlaceholder, text: $draft.work.goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
            }
            labeled(AppStrings.VibeLanes.editorInstructions) {
                TextField(
                    AppStrings.VibeLanes.instructionsPlaceholder,
                    text: $draft.work.instructions,
                    axis: .vertical
                )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
            }
            labeled(AppStrings.VibeLanes.editorWorkSkills) {
                VibeLaneSkillsEditor(
                    skills: $draft.work.skills,
                    role: .work
                )
            }
        }
    }

    private var reviewColumn: some View {
        section(
            AppStrings.VibeLanes.editorReview,
            icon: "checkmark.seal",
            color: palette.successColor
        ) {
            labeled(AppStrings.VibeLanes.editorVerification) {
                TextField(
                    AppStrings.VibeLanes.doneWhenPlaceholder,
                    text: $draft.verify.definition,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
            }
            labeled(AppStrings.VibeLanes.editorReviewSkills) {
                VibeLaneSkillsEditor(
                    skills: $draft.verify.reviewSkills,
                    role: .review
                )
                .disabled(draft.verify.humanReview)
                .opacity(draft.verify.humanReview ? 0.55 : 1)
                .help(
                    draft.verify.humanReview
                        ? AppStrings.VibeLanes.reviewSkillsHumanHint
                        : AppStrings.VibeLanes.reviewSkillsHint
                )
            }
            labeled(AppStrings.VibeLanes.editorVerifiedBy) {
                Picker("", selection: $draft.verify.humanReview) {
                    Text(AppStrings.VibeLanes.editorReviewerAgent).tag(false)
                    Text(AppStrings.VibeLanes.editorVerifiedByYou).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: uiScale.chromeSize(280))
            }
        }
    }

    private var operationalSettings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: uiScale.spacing(24)) {
                limitsSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()
                    .padding(.vertical, uiScale.spacing(4))

                executionSection
                    .frame(width: uiScale.chromeSize(360), alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: uiScale.spacing(20)) {
                limitsSection
                sectionDivider
                executionSection
            }
        }
    }

    private var limitsSection: some View {
        section(AppStrings.VibeLanes.editorLimits, icon: "timer") {
            ViewThatFits(in: .horizontal) {
                limitsRow
                VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                    attemptsControl
                    timeoutControl
                    exhaustionControl
                }
            }
        }
    }

    private var executionSection: some View {
        section(AppStrings.VibeLanes.editorExecution, icon: "cpu") {
            labeled(AppStrings.VibeLanes.engine) {
                VibeLaneEngineEditor(
                    configuration: $draft.engine,
                    optionCatalog: engineOptionCatalog
                )
            }
        }
    }

    private var limitsRow: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(20)) {
            attemptsControl
            timeoutControl
            exhaustionControl
        }
    }

    private var attemptsControl: some View {
        labeled(AppStrings.VibeLanes.maxAttempts) {
            Stepper(value: $draft.bounds.maxAttempts, in: 1...100) {
                Text("\(draft.bounds.maxAttempts)")
                    .monospacedDigit()
            }
            .frame(width: uiScale.chromeSize(145))
        }
    }

    private var timeoutControl: some View {
        labeled(AppStrings.VibeLanes.timeLimitMinutes) {
            Stepper(value: timeoutMinutesBinding, in: 1...240) {
                Text(AppStrings.VibeLanes.minutesShort(draft.bounds.timeoutSeconds / 60))
                    .monospacedDigit()
            }
            .frame(width: uiScale.chromeSize(155))
        }
    }

    private var exhaustionControl: some View {
        labeled(AppStrings.VibeLanes.whenExhausted) {
            Picker("", selection: $draft.bounds.onExhausted) {
                Text(AppStrings.VibeLanes.stopOnExhausted).tag(VibeLaneBoundBehavior.stop)
                Text(AppStrings.VibeLanes.escalateOnExhausted).tag(VibeLaneBoundBehavior.escalate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: uiScale.chromeSize(210))
        }
    }

    private var detailBinding: Binding<String> {
        Binding(
            get: { draft.detail ?? "" },
            set: { draft.detail = $0.isEmpty ? nil : $0 }
        )
    }

    private var timeoutMinutesBinding: Binding<Int> {
        Binding(
            get: { max(1, draft.bounds.timeoutSeconds / 60) },
            set: { draft.bounds.timeoutSeconds = $0 * 60 }
        )
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(palette.borderColorValue.opacity(0.42))
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            guard let saved = await onSave(draft) else { return }
            draft = saved
            savedFlash = true
            try? await Task.sleep(for: .seconds(1.2))
            savedFlash = false
        }
    }

    private func section<Content: View>(
        _ title: String,
        icon: String,
        color: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
            sectionTitle(title, icon: icon, color: color)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String, icon: String, color: Color? = nil) -> some View {
        HStack(spacing: uiScale.spacing(8)) {
            VibeLaneIconBadge(
                systemImage: icon,
                color: color ?? palette.accentColor,
                side: 28,
                iconSize: 12
            )
            Text(title)
                .font(.system(size: uiScale.textSize(13), weight: .bold))
                .foregroundStyle(palette.primaryTextColor)
        }
    }

    private func labeled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(7)) {
            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.secondaryTextColor)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
