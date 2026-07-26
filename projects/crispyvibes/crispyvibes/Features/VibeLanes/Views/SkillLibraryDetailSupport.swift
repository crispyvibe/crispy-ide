import AppKit
import SwiftUI

@MainActor
struct SkillLibraryDetailSummary: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let skill: VibeLaneSkillDefinition?
    let usageCount: Int

    var body: some View {
        HStack(spacing: uiScale.spacing(18)) {
            metric(
                validationIcon,
                AppStrings.Skills.validationName(skill?.validationState ?? .ready),
                AppStrings.Skills.validation,
                validationColor
            )
            metric(
                "folder",
                AppStrings.Skills.resourceCount(skill?.resources.count ?? 0),
                AppStrings.Skills.package,
                palette.accentColor
            )
            metric(
                "point.3.connected.trianglepath.dotted",
                AppStrings.Skills.vibeUsage(usageCount),
                AppStrings.VibeLanes.vibes,
                palette.successColor
            )
            Spacer(minLength: 0)
        }
        .padding(.vertical, uiScale.spacing(12))
        .overlay(alignment: .top) {
            Divider().overlay(palette.borderColorValue.opacity(0.5))
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(palette.borderColorValue.opacity(0.5))
        }
    }

    private func metric(
        _ icon: String,
        _ value: String,
        _ label: String,
        _ color: Color
    ) -> some View {
        HStack(spacing: uiScale.spacing(7)) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: uiScale.textSize(11), weight: .semibold))
                    .foregroundStyle(palette.primaryTextColor)
                Text(label)
                    .font(.system(size: uiScale.textSize(9)))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
        }
    }

    private var validationColor: Color {
        switch skill?.validationState ?? .ready {
        case .ready: palette.successColor
        case .attention: palette.warningColor
        case .unavailable: palette.errorColor
        }
    }

    private var validationIcon: String {
        switch skill?.validationState ?? .ready {
        case .ready: "checkmark.seal.fill"
        case .attention: "exclamationmark.circle.fill"
        case .unavailable: "xmark.octagon.fill"
        }
    }
}

@MainActor
struct SkillLibraryResourcesSection: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let skill: VibeLaneSkillDefinition?

    @ViewBuilder
    var body: some View {
        if let skill, !skill.resources.isEmpty {
            VStack(spacing: 0) {
                ForEach(skill.resources) { resource in
                    resourceRow(resource)
                    Divider().overlay(palette.borderColorValue.opacity(0.35))
                }
            }
        } else {
            ContentUnavailableView(AppStrings.Skills.noResources, systemImage: "folder")
                .frame(maxWidth: .infinity)
                .padding(.top, uiScale.spacing(34))
        }
    }

    private func resourceRow(_ resource: VibeLaneSkillResource) -> some View {
        HStack(spacing: uiScale.spacing(10)) {
            Image(systemName: resourceIcon(resource.kind))
                .foregroundStyle(palette.accentColor)
                .frame(width: uiScale.chromeSize(18))
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.relativePath)
                    .font(.system(size: uiScale.textSize(11), design: .monospaced))
                    .foregroundStyle(palette.primaryTextColor)
                Text(AppStrings.Skills.resourceKindName(resource.kind))
                    .font(.system(size: uiScale.textSize(9)))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([resource.fileURL])
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
            .help(AppStrings.Skills.reveal)
        }
        .padding(.vertical, uiScale.spacing(9))
    }

    private func resourceIcon(_ kind: VibeLaneSkillResourceKind) -> String {
        switch kind {
        case .reference: "doc.text"
        case .script: "terminal"
        case .asset: "shippingbox"
        case .agentMetadata: "person.text.rectangle"
        case .other: "doc"
        }
    }
}

@MainActor
struct SkillLibraryRequirementsSection: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let skill: VibeLaneSkillDefinition?
    let canEdit: Bool
    @Binding var commands: String

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
            labeled(AppStrings.Skills.requiredCommands) {
                if canEdit {
                    TextField(AppStrings.Skills.requiredCommandsPlaceholder, text: $commands)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(commandSummary)
                        .font(.system(size: uiScale.textSize(11), design: .monospaced))
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }
            labeled(AppStrings.Skills.validation) {
                if let skill, !skill.issues.isEmpty {
                    VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                        ForEach(Array(skill.issues.enumerated()), id: \.offset) { _, issue in
                            Label(
                                AppStrings.Skills.issueText(issue),
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(palette.warningColor)
                        }
                    }
                    .font(.system(size: uiScale.textSize(11)))
                } else {
                    Label(AppStrings.Skills.compatible, systemImage: "checkmark.seal.fill")
                        .font(.system(size: uiScale.textSize(11), weight: .semibold))
                        .foregroundStyle(palette.successColor)
                }
            }
        }
    }

    private var commandSummary: String {
        guard let commands = skill?.requiredCommands, !commands.isEmpty else {
            return AppStrings.Skills.noRequirements
        }
        return commands.joined(separator: ", ")
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

@MainActor
struct SkillLibraryPackageLocation: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let skill: VibeLaneSkillDefinition
    let usageCount: Int
    let onRemove: (VibeLaneSkillDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            Text(AppStrings.Skills.location)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.secondaryTextColor)
            Text(skill.rootURL.path)
                .font(.system(size: uiScale.textSize(10), design: .monospaced))
                .foregroundStyle(palette.tertiaryTextColor)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack(spacing: uiScale.spacing(8)) {
                revealButton
                removeButton
            }
            .controlSize(uiScale.controlSize)
        }
    }

    private var revealButton: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([skill.rootURL])
        } label: {
            Label(AppStrings.Skills.reveal, systemImage: "folder")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var removeButton: some View {
        if skill.source != .bundled {
            Button(role: .destructive) {
                onRemove(skill)
            } label: {
                Label(
                    skill.source == .linked ? AppStrings.Skills.unlink : AppStrings.Skills.delete,
                    systemImage: skill.source == .linked ? "link.badge.minus" : "trash"
                )
            }
            .buttonStyle(.bordered)
            .disabled(usageCount > 0)
            .help(
                usageCount > 0
                    ? AppStrings.Skills.inUse
                    : AppStrings.Skills.vibeUsage(usageCount)
            )
        }
    }
}
