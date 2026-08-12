import SwiftUI

@MainActor
struct SkillLibraryDetailView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview, instructions, resources, requirements
        var id: String { rawValue }
    }

    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let skill: VibeLaneSkillDefinition?
    let usageCount: Int
    let onCreate: (VibeLaneSkillDraft) -> Void
    let onUpdate: (VibeLaneSkillDefinition, VibeLaneSkillDraft) -> Void
    let onDuplicate: (VibeLaneSkillDefinition) -> Void
    let onRemove: (VibeLaneSkillDefinition) -> Void
    let onCancel: () -> Void

    @State private var section: Section = .overview
    @State private var name: String
    @State private var detail: String
    @State private var bodyText: String
    @State private var category: String
    @State private var roles: Set<VibeLaneSkillRole>
    @State private var interaction: VibeLaneSkillInteraction
    @State private var commands: String

    init(
        skill: VibeLaneSkillDefinition?,
        usageCount: Int,
        onCreate: @escaping (VibeLaneSkillDraft) -> Void,
        onUpdate: @escaping (VibeLaneSkillDefinition, VibeLaneSkillDraft) -> Void,
        onDuplicate: @escaping (VibeLaneSkillDefinition) -> Void,
        onRemove: @escaping (VibeLaneSkillDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.skill = skill
        self.usageCount = usageCount
        self.onCreate = onCreate
        self.onUpdate = onUpdate
        self.onDuplicate = onDuplicate
        self.onRemove = onRemove
        self.onCancel = onCancel
        _name = State(initialValue: skill?.name ?? "")
        _detail = State(initialValue: skill?.detail ?? "")
        _bodyText = State(initialValue: skill?.body ?? Self.newSkillTemplate)
        _category = State(initialValue: skill?.category ?? "General")
        _roles = State(initialValue: Set(skill?.roles ?? VibeLaneSkillRole.allCases))
        _interaction = State(initialValue: skill?.interaction ?? .unattended)
        _commands = State(initialValue: skill?.requiredCommands.joined(separator: ", ") ?? "")
    }

    private var isCreating: Bool { skill == nil }
    private var canEdit: Bool { isCreating || skill?.isEditable == true }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !roles.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiScale.spacing(18)) {
                header
                summary
                sectionPicker
                sectionContent
                if let skill {
                    Divider().overlay(palette.borderColorValue.opacity(0.5))
                    SkillLibraryPackageLocation(
                        skill: skill,
                        usageCount: usageCount,
                        onRemove: onRemove
                    )
                }
            }
            .padding(uiScale.spacing(22))
            .frame(maxWidth: uiScale.chromeSize(820), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(palette.canvasBackgroundColor)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: uiScale.spacing(14)) {
                identity
                Spacer(minLength: uiScale.spacing(12))
                actions
            }
            VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                identity
                actions
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(12)) {
            VibeLaneIconBadge(
                systemImage: skill?.source.systemImage ?? "plus",
                color: identityColor,
                side: 42,
                iconSize: 17
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
                Text(isCreating ? AppStrings.Skills.newSkill : name)
                    .font(.system(size: uiScale.textSize(20), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(2)
                Text(detail.isEmpty ? AppStrings.Skills.descriptionPlaceholder : detail)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(2)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: uiScale.spacing(8)) {
            if isCreating {
                Button(AppStrings.Skills.cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Button(action: save) {
                    Label(AppStrings.Skills.create, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            } else if let skill {
                Button {
                    onDuplicate(skill)
                } label: {
                    Label(AppStrings.Skills.duplicate, systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                if skill.isEditable {
                    Button(action: save) {
                        Label(AppStrings.Skills.save, systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
            }
        }
        .controlSize(uiScale.controlSize)
    }

    private var summary: some View {
        SkillLibraryDetailSummary(skill: skill, usageCount: usageCount)
    }

    private var sectionPicker: some View {
        Picker("", selection: $section) {
            Text(AppStrings.Skills.overview).tag(Section.overview)
            Text(AppStrings.Skills.instructions).tag(Section.instructions)
            Text(AppStrings.Skills.resources).tag(Section.resources)
            Text(AppStrings.Skills.requirements).tag(Section.requirements)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(uiScale.controlSize)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .overview: overviewFields
        case .instructions: instructionsView
        case .resources: resourcesView
        case .requirements: requirementsView
        }
    }

    private var overviewFields: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
            labeled(AppStrings.Skills.name) {
                TextField(AppStrings.Skills.namePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!canEdit)
            }
            labeled(AppStrings.Skills.description) {
                TextField(AppStrings.Skills.descriptionPlaceholder, text: $detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .disabled(!canEdit)
            }
            labeled(AppStrings.Skills.category) {
                TextField(AppStrings.Skills.category, text: $category)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!canEdit)
            }
            labeled(AppStrings.Skills.roles) {
                HStack(spacing: uiScale.spacing(18)) {
                    ForEach(VibeLaneSkillRole.allCases) { role in
                        Toggle(AppStrings.Skills.roleName(role), isOn: roleBinding(role))
                            .toggleStyle(.checkbox)
                            .disabled(!canEdit)
                    }
                }
            }
            labeled(AppStrings.Skills.interaction) {
                Picker("", selection: $interaction) {
                    ForEach(VibeLaneSkillInteraction.allCases) { value in
                        Text(AppStrings.Skills.interactionName(value)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!canEdit)
            }
        }
    }

    @ViewBuilder
    private var instructionsView: some View {
        if canEdit {
            TextEditor(text: $bodyText)
                .font(.system(size: uiScale.textSize(12), design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(uiScale.spacing(9))
                .frame(minHeight: uiScale.chromeSize(360))
                .background(palette.canvasSecondaryBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: uiScale.chromeSize(6)))
                .overlay(
                    RoundedRectangle(cornerRadius: uiScale.chromeSize(6))
                        .strokeBorder(palette.borderColorValue.opacity(0.6))
                )
        } else {
            VibeLaneMarkdownText(markdown: bodyText, linkBaseDirectory: skill?.rootURL)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var resourcesView: some View {
        SkillLibraryResourcesSection(skill: skill)
    }

    private var requirementsView: some View {
        SkillLibraryRequirementsSection(
            skill: skill,
            canEdit: canEdit,
            commands: $commands
        )
    }

    private var identityColor: Color {
        switch skill?.source ?? .personal {
        case .bundled: palette.accentColor
        case .personal: palette.successColor
        case .linked: palette.secondaryTextColor
        }
    }

    private func roleBinding(_ role: VibeLaneSkillRole) -> Binding<Bool> {
        Binding(
            get: { roles.contains(role) },
            set: { isOn in
                if isOn { roles.insert(role) } else { roles.remove(role) }
            }
        )
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

    private func save() {
        let parsedCommands = commands
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let draft = VibeLaneSkillDraft(
            name: name,
            detail: detail,
            body: bodyText,
            metadata: VibeLaneSkillMetadata(
                category: category.trimmingCharacters(in: .whitespacesAndNewlines),
                roles: VibeLaneSkillRole.allCases.filter(roles.contains),
                interaction: interaction,
                requiredCommands: parsedCommands
            )
        )
        if let skill { onUpdate(skill, draft) } else { onCreate(draft) }
    }

    private static let newSkillTemplate = """
    # New Skill

    ## Process
    1. Inspect the task and the project context.
    2. Perform the work using the project's existing conventions.
    3. Record concrete evidence of the result.

    ## Completion criteria
    - The requested outcome exists in the project.
    - Relevant checks have been run and their results are recorded.
    """
}
