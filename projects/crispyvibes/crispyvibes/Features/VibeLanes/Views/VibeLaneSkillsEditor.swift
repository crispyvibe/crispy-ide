import SwiftUI

extension VibeLaneSkillRole {
    var systemImage: String {
        switch self {
        case .work: "hammer"
        case .review: "checkmark.seal"
        }
    }

    var placeholder: String {
        switch self {
        case .work: AppStrings.VibeLanes.addWorkSkillPlaceholder
        case .review: AppStrings.VibeLanes.addReviewSkillPlaceholder
        }
    }
}

@MainActor
struct VibeLaneSkillsEditor: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.vibeLaneSkillStoreEnvironment) private var skillStore

    @Binding var skills: [String]
    let role: VibeLaneSkillRole
    @State private var newSkill = ""
    @State private var refusedSkill: String?

    init(skills: Binding<[String]>, role: VibeLaneSkillRole = .work) {
        _skills = skills
        self.role = role
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            if !skills.isEmpty {
                FlowLayout(spacing: uiScale.spacing(8)) {
                    ForEach(Array(skills.enumerated()), id: \.offset) { index, skill in
                        skillChip(skill, at: index)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: uiScale.spacing(8)) {
                    installedSkillMenu
                    customSkillField
                }
                VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                    installedSkillMenu
                    customSkillField
                }
            }

            if let refusedSkill {
                Label(refusedSkill, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.warningColor)
                    .accessibilityLabel(refusedSkill)
            }
        }
    }

    private func skillChip(_ skill: String, at index: Int) -> some View {
        let definition = skillStore?.skills.first { $0.reference == skill }
        return HStack(spacing: uiScale.spacing(5)) {
            Image(
                systemName: definition?.validationState == .unavailable
                    ? "exclamationmark.triangle.fill"
                    : role.systemImage
            )
                .font(.system(size: uiScale.iconSize(10), weight: .semibold))
            Text(definition?.name ?? skill)
                .font(.system(size: uiScale.textSize(12)))
                .lineLimit(1)
            Button { skills.remove(at: index) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: uiScale.iconSize(9), weight: .semibold))
                    .frame(width: uiScale.chromeSize(16), height: uiScale.chromeSize(16))
            }
            .buttonStyle(.plain)
            .help(AppStrings.VibeLanes.removeSkill)
            .accessibilityLabel(AppStrings.VibeLanes.removeSkill)
        }
        .padding(.leading, uiScale.spacing(8))
        .padding(.trailing, uiScale.spacing(4))
        .padding(.vertical, uiScale.spacing(5))
        .background(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(5), style: .continuous)
                .fill(roleColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(5), style: .continuous)
                .strokeBorder(roleColor.opacity(0.18), lineWidth: uiScale.chromeSize(1))
        )
        .foregroundStyle(roleColor)
        .help(definition?.detail ?? skill)
    }

    private var installedSkillMenu: some View {
        Menu {
            if let skillStore {
                ForEach(skillStore.skills.filter { $0.supports(role) }) { skill in
                    Button {
                        addSkill(skill.reference)
                    } label: {
                        Label(
                            skill.name,
                            systemImage: skill.validationState == .unavailable
                                ? "exclamationmark.triangle"
                                : contains(skill.reference)
                                ? "checkmark"
                                : skill.source.systemImage
                        )
                    }
                    .disabled(contains(skill.reference) || !skill.isAssignable(to: role))
                }
            } else {
                ForEach(VibeLaneSkillLibrary.starterNames, id: \.self) { skill in
                    Button {
                        addSkill(skill)
                    } label: {
                        Label(
                            skill,
                            systemImage: contains(skill) ? "checkmark" : role.systemImage
                        )
                    }
                    .disabled(contains(skill))
                }
            }
        } label: {
            Label(AppStrings.VibeLanes.installedSkills, systemImage: "books.vertical")
        }
        .buttonStyle(.bordered)
        .controlSize(uiScale.controlSize)
    }

    private var customSkillField: some View {
        HStack(spacing: uiScale.spacing(6)) {
            TextField(role.placeholder, text: $newSkill)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onSubmit(addCustomSkill)
            Button(action: addCustomSkill) {
                Image(systemName: "plus")
                    .frame(
                        width: uiScale.chromeSize(16),
                        height: uiScale.chromeSize(16)
                    )
            }
            .buttonStyle(.bordered)
            .controlSize(uiScale.controlSize)
            .disabled(newSkill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(AppStrings.VibeLanes.addCustomSkill)
            .accessibilityLabel(AppStrings.VibeLanes.addCustomSkill)
        }
    }

    private var roleColor: Color {
        switch role {
        case .work: palette.accentColor
        case .review: palette.successColor
        }
    }

    private func contains(_ skill: String) -> Bool {
        skills.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(skill) == .orderedSame
        }
    }

    private func addCustomSkill() {
        addSkill(newSkill)
        newSkill = ""
    }

    /// The only place an assignment is made. A hand-typed reference to an
    /// installed skill is held to the same eligibility rule as the menu — the
    /// menu's `.disabled` is presentation, not enforcement. References that are
    /// not installed stay allowed (custom paths); the engine reports those.
    private func addSkill(_ skill: String) {
        let trimmed = skill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !contains(trimmed) else { return }
        if let installed = skillStore?.skills.first(where: { $0.reference == trimmed }),
           let refusal = installed.assignmentRefusal(for: role) {
            refusedSkill = AppStrings.VibeLanes.skillNotAssignable(
                skill: installed.name,
                reason: refusal.reason
            )
            return
        }
        refusedSkill = nil
        skills.append(trimmed)
    }
}

extension VibeLaneSkillAssignmentRefusal {
    var reason: String {
        switch self {
        case .roleNotSupported: AppStrings.VibeLanes.skillRoleNotSupported
        case .unavailable: AppStrings.VibeLanes.skillUnavailable
        case .interactiveReview: AppStrings.VibeLanes.skillInteractiveReview
        }
    }
}
