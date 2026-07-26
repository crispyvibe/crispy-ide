import SwiftUI

@MainActor
struct VibeLaneEditorView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let lane: VibeLaneDefinition
    let vibes: [VibeDefinition]
    var onSave: (VibeLaneDefinition) async -> VibeLaneDefinition? = { $0 }
    var onDelete: (() -> Void)?
    var onEditVibe: (UUID) -> Void = { _ in }
    var onNewVibe: () -> Void = {}

    @State var draft: VibeLaneDefinition
    @State var selectedIndex = 0
    @State private var searchText = ""
    @State private var selectedCategory: VibeCategory?
    @State private var savedFlash = false
    @State private var isSaving = false

    init(
        lane: VibeLaneDefinition,
        vibes: [VibeDefinition],
        onSave: @escaping (VibeLaneDefinition) async -> VibeLaneDefinition? = { $0 },
        onDelete: (() -> Void)? = nil,
        onEditVibe: @escaping (UUID) -> Void = { _ in },
        onNewVibe: @escaping () -> Void = {}
    ) {
        self.lane = lane
        self.vibes = vibes
        self.onSave = onSave
        self.onDelete = onDelete
        self.onEditVibe = onEditVibe
        self.onNewVibe = onNewVibe
        _draft = State(initialValue: lane)
    }

    private var categories: [VibeCategory] {
        VibeCategory.available(in: vibes)
    }

    private var filteredVibes: [VibeDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return vibes.filter {
            selectedCategory == nil || $0.category == selectedCategory
        }
        .filter {
            query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || ($0.detail?.localizedCaseInsensitiveContains(query) == true)
                || $0.work.goal.localizedCaseInsensitiveContains(query)
                || AppStrings.VibeLanes.vibeCategoryName($0.category)
                    .localizedCaseInsensitiveContains(query)
        }
        .sorted {
            if $0.category != $1.category {
                return VibeCategory.sort($0.category, $1.category)
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    catalogPanel
                        .frame(minWidth: 250, idealWidth: 290, maxWidth: 320)
                    Divider()
                    recipePanel
                        .frame(minWidth: 520, maxWidth: .infinity)
                }
                VStack(spacing: 0) {
                    catalogPanel.frame(height: uiScale.chromeSize(310))
                    Divider()
                    recipePanel
                }
            }
        }
        .background(palette.canvasBackgroundColor)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(16)) {
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
                DisclosureGroup {
                    Stepper(value: $draft.steerLimit, in: 0...10) {
                        Text(AppStrings.VibeLanes.steerLimit(draft.steerLimit))
                            .font(.system(size: uiScale.textSize(12)))
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .padding(.top, uiScale.spacing(6))
                } label: {
                    Label(AppStrings.VibeLanes.editorLaneSettings, systemImage: "slider.horizontal.3")
                        .font(.system(size: uiScale.textSize(12), weight: .medium))
                        .foregroundStyle(palette.secondaryTextColor)
                }
                .frame(width: 240, alignment: .leading)
            }
            Spacer()
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(AppStrings.VibeLanes.deleteLane, systemImage: "trash")
                }
            }
            Button(action: save) {
                Label(
                    savedFlash ? AppStrings.VibeLanes.saved : AppStrings.VibeLanes.saveLane,
                    systemImage: savedFlash ? "checkmark" : "square.and.arrow.down"
                )
                .font(.system(size: uiScale.textSize(13), weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(!blockingErrors.isEmpty || isSaving)
            .help(blockingErrors.isEmpty ? AppStrings.VibeLanes.saveLane : AppStrings.VibeLanes.fixLaneErrors)
        }
        .padding(.horizontal, uiScale.spacing(24))
        .padding(.vertical, uiScale.spacing(16))
    }

    private var catalogPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(AppStrings.VibeLanes.vibeLibrary, systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                Spacer()
                Button(action: onNewVibe) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(AppStrings.VibeLanes.newVibe)
            }
            .padding(.horizontal, uiScale.spacing(14))
            .padding(.top, uiScale.spacing(14))

            HStack(spacing: uiScale.spacing(8)) {
                Picker(AppStrings.VibeLanes.vibeCategories, selection: $selectedCategory) {
                    Text(AppStrings.VibeLanes.vibeCategoryAll).tag(nil as VibeCategory?)
                    ForEach(categories) { category in
                        Label(
                            AppStrings.VibeLanes.vibeCategoryName(category),
                            systemImage: category.systemImage
                        )
                        .tag(category as VibeCategory?)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(uiScale.controlSize)
                Spacer()
                Text("\(filteredVibes.count)")
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .monospacedDigit()
            }
            .padding(.horizontal, uiScale.spacing(14))
            .padding(.top, uiScale.spacing(10))

            TextField(AppStrings.VibeLanes.searchVibes, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, uiScale.spacing(14))
                .padding(.vertical, uiScale.spacing(10))

            ScrollView {
                LazyVStack(spacing: uiScale.spacing(4)) {
                    ForEach(filteredVibes) { vibe in
                        catalogRow(vibe)
                    }
                }
                .padding(.horizontal, uiScale.spacing(8))
                .padding(.bottom, uiScale.spacing(12))
            }
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.45))
    }

    private func catalogRow(_ vibe: VibeDefinition) -> some View {
        HStack(spacing: uiScale.spacing(9)) {
            Image(systemName: vibe.isReady ? "checkmark.seal" : "exclamationmark.circle")
                .foregroundStyle(vibe.isReady ? palette.successColor : palette.warningColor)
                .frame(width: uiScale.chromeSize(20))
            VStack(alignment: .leading, spacing: uiScale.spacing(3)) {
                Text(vibe.name)
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)
                VibeCategoryLabel(category: vibe.category)
                Text(vibe.isReady ? vibe.work.goal : AppStrings.VibeLanes.laneNeedsSetup)
                    .font(.system(size: uiScale.textSize(10)))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { addVibe(vibe) } label: {
                Image(systemName: "plus")
                    .frame(width: uiScale.chromeSize(24), height: uiScale.chromeSize(24))
            }
            .buttonStyle(.bordered)
            .disabled(!vibe.isReady)
            .help(AppStrings.VibeLanes.addVibeToLane)
        }
        .padding(.horizontal, uiScale.spacing(8))
        .padding(.vertical, uiScale.spacing(7))
        .contentShape(Rectangle())
        .vibeLaneHoverable(cornerRadius: 6)
    }

    private var recipePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            recipeHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
                    let errors = VibeLaneEditorValidation.errors(for: draft)
                    let warnings = VibeLaneEditorValidation.warnings(for: draft)
                    if !errors.isEmpty {
                        VibeLaneErrorPanel(errors: errors)
                    }
                    if !warnings.isEmpty {
                        VibeLaneWarningPanel(warnings: warnings)
                    }
                    if let checkpoint = selectedCheckpointBinding {
                        inspector(checkpoint)
                    } else {
                        ContentUnavailableView(
                            AppStrings.VibeLanes.noLaneSteps,
                            systemImage: "square.stack.3d.up.slash"
                        )
                        .frame(maxWidth: .infinity, minHeight: uiScale.chromeSize(280))
                    }
                }
                .padding(uiScale.spacing(18))
            }
        }
    }

    private var recipeHeader: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            Label(AppStrings.VibeLanes.laneRecipe, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(size: uiScale.textSize(13), weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: uiScale.spacing(6)) {
                    ForEach(Array(draft.checkpoints.enumerated()), id: \.element.key) { index, checkpoint in
                        VibeLaneCheckpointStepButton(
                            index: index,
                            checkpoint: checkpoint,
                            isSelected: index == selectedIndex,
                            hasErrors: checkpointHasErrors(at: index),
                            onSelect: { selectedIndex = index }
                        )
                        if index < draft.checkpoints.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: uiScale.iconSize(9), weight: .semibold))
                                .foregroundStyle(palette.tertiaryTextColor)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, uiScale.spacing(18))
        .padding(.vertical, uiScale.spacing(12))
    }

    private func inspector(_ checkpoint: Binding<VibeLaneCheckpoint>) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: uiScale.spacing(12)) {
                    vibeIdentity(checkpoint)
                    Spacer()
                    stepActions(checkpoint)
                }
                VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
                    vibeIdentity(checkpoint)
                    stepActions(checkpoint)
                }
            }

            VibeLaneCheckpointBehaviorSummary(checkpoint: checkpoint.wrappedValue)

            if let latest = latestVibe(for: checkpoint.wrappedValue),
               latest.version != checkpoint.wrappedValue.vibeVersion {
                HStack(spacing: uiScale.spacing(10)) {
                    Label(AppStrings.VibeLanes.updateAvailable, systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: uiScale.textSize(12), weight: .semibold))
                        .foregroundStyle(palette.warningColor)
                    Text(AppStrings.VibeLanes.vibeVersion(latest.version))
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.secondaryTextColor)
                    Spacer()
                    Button(AppStrings.VibeLanes.useLatestVersion) {
                        useLatestVibe(latest)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(uiScale.spacing(10))
                .background(
                    palette.warningColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: uiScale.chromeSize(6))
                )
            }

            Divider()
            VibeLaneContractEditor(checkpoint: checkpoint, showsTitle: true)
            Divider()
            DisclosureGroup {
                TextField(AppStrings.VibeLanes.stepKeyPlaceholder, text: checkpoint.key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .padding(.top, uiScale.spacing(10))
            } label: {
                Label(AppStrings.VibeLanes.editorStableID, systemImage: "number")
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
            }
        }
        .padding(uiScale.spacing(18))
        .vibeLaneCard()
    }

    private func vibeIdentity(_ checkpoint: Binding<VibeLaneCheckpoint>) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
            Text(AppStrings.VibeLanes.stepOf(current: selectedIndex + 1, total: draft.checkpoints.count))
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            HStack(spacing: uiScale.spacing(8)) {
                Text(checkpoint.wrappedValue.displayTitle)
                    .font(.system(size: uiScale.textSize(18), weight: .semibold))
                if let version = checkpoint.wrappedValue.vibeVersion {
                    Text(AppStrings.VibeLanes.vibeVersion(version))
                        .font(.system(size: uiScale.textSize(10), weight: .semibold))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
            }
            if let vibeID = checkpoint.wrappedValue.vibeID,
               let category = vibes.first(where: { $0.id == vibeID })?.category {
                VibeCategoryLabel(category: category, isEmphasized: true)
            }
        }
    }

    private func stepActions(_ checkpoint: Binding<VibeLaneCheckpoint>) -> some View {
        HStack(spacing: uiScale.spacing(8)) {
            if let vibeID = checkpoint.wrappedValue.vibeID {
                Button { onEditVibe(vibeID) } label: {
                    Label(AppStrings.VibeLanes.editVibe, systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }
            Button { moveCheckpoint(offset: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(selectedIndex == 0)
            .buttonStyle(.bordered)
            .help(AppStrings.VibeLanes.moveCheckpointLeft)
            Button { moveCheckpoint(offset: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(selectedIndex >= draft.checkpoints.count - 1)
            .buttonStyle(.bordered)
            .help(AppStrings.VibeLanes.moveCheckpointRight)
            Button(role: .destructive, action: removeCheckpoint) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help(AppStrings.VibeLanes.removeVibeFromLane)
        }
    }

    private var blockingErrors: [String] {
        VibeLaneEditorValidation.errors(for: draft)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            guard let saved = await onSave(draft) else { return }
            draft = saved
            selectedIndex = min(selectedIndex, max(0, draft.checkpoints.count - 1))
            savedFlash = true
            try? await Task.sleep(for: .seconds(1.2))
            savedFlash = false
        }
    }
}
