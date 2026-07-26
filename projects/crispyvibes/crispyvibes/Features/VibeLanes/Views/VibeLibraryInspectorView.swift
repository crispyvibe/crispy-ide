import SwiftUI

@MainActor
struct VibeLibraryInspectorView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let vibe: VibeDefinition
    let usageCount: Int
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiScale.spacing(18)) {
                header
                separator
                textSection(
                    AppStrings.VibeLanes.editorOutcome,
                    icon: "scope",
                    primary: vibe.work.goal,
                    secondary: nonEmpty(vibe.work.instructions)
                )
                separator
                verificationSection
                separator
                limitsSection
                separator
                executionSection
            }
            .padding(uiScale.spacing(22))
            .frame(maxWidth: uiScale.chromeSize(720), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(palette.canvasBackgroundColor)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(14)) {
            VibeLaneIconBadge(
                systemImage: "scope",
                color: palette.accentColor,
                side: 42,
                iconSize: 17
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
                Text(vibe.name)
                    .font(.system(size: uiScale.textSize(20), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(2)
                if let detail = nonEmpty(vibe.detail) {
                    Text(detail)
                        .font(.system(size: uiScale.textSize(12)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(3)
                }
                HStack(spacing: uiScale.spacing(8)) {
                    VibeCategoryLabel(category: vibe.category, isEmphasized: true)
                    readiness
                    metadata(AppStrings.VibeLanes.vibeVersion(vibe.version))
                    metadata(AppStrings.VibeLanes.vibeUsage(usageCount))
                }
            }
            Spacer(minLength: uiScale.spacing(10))
            Button(action: onEdit) {
                Label(AppStrings.VibeLanes.editVibe, systemImage: "pencil")
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(uiScale.controlSize)
        }
    }

    private var readiness: some View {
        Label(
            vibe.isReady ? AppStrings.VibeLanes.ready : AppStrings.VibeLanes.laneNeedsSetup,
            systemImage: vibe.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.system(size: uiScale.textSize(10), weight: .semibold))
        .foregroundStyle(vibe.isReady ? palette.successColor : palette.warningColor)
    }

    private func metadata(_ value: String) -> some View {
        Text(value)
            .font(.system(size: uiScale.textSize(10), weight: .semibold))
            .foregroundStyle(palette.tertiaryTextColor)
            .padding(.horizontal, uiScale.spacing(6))
            .padding(.vertical, uiScale.spacing(2))
            .background(
                Capsule()
                    .fill(palette.canvasSecondaryBackgroundColor)
            )
    }

    private func textSection(
        _ title: String,
        icon: String,
        primary: String,
        secondary: String?
    ) -> some View {
        section(title, icon: icon) {
            Text(primary)
                .font(.system(size: uiScale.textSize(13), weight: .medium))
                .foregroundStyle(palette.primaryTextColor)
                .lineSpacing(uiScale.spacing(2))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let secondary {
                Text(secondary)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineSpacing(uiScale.spacing(2))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var limitsSection: some View {
        section(AppStrings.VibeLanes.editorLimits, icon: "timer") {
            HStack(spacing: 0) {
                limitValue(
                    "\(vibe.bounds.maxAttempts)",
                    label: AppStrings.VibeLanes.maxAttempts
                )
                verticalSeparator
                limitValue(
                    AppStrings.VibeLanes.minutesShort(vibe.bounds.timeoutSeconds / 60),
                    label: AppStrings.VibeLanes.timeLimitMinutes
                )
                verticalSeparator
                limitValue(
                    exhaustedValue,
                    label: AppStrings.VibeLanes.whenExhausted
                )
            }
            .padding(.vertical, uiScale.spacing(4))
        }
    }

    private var verificationSection: some View {
        section(AppStrings.VibeLanes.editorDoneWhen, icon: "checkmark.seal") {
            Text(vibe.verify.definition)
                .font(.system(size: uiScale.textSize(13), weight: .medium))
                .foregroundStyle(palette.primaryTextColor)
                .lineSpacing(uiScale.spacing(2))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                verificationOwner,
                systemImage: vibe.verify.humanReview
                    ? "person.crop.circle.badge.checkmark"
                    : "checkmark.seal"
            )
            .font(.system(size: uiScale.textSize(11), weight: .semibold))
            .foregroundStyle(
                vibe.verify.humanReview ? palette.secondaryTextColor : palette.successColor
            )

            if !vibe.verify.reviewSkills.isEmpty {
                skillList(
                    AppStrings.VibeLanes.editorReviewSkills,
                    skills: vibe.verify.reviewSkills,
                    systemImage: "checkmark.seal",
                    color: palette.successColor
                )
                .opacity(vibe.verify.humanReview ? 0.55 : 1)
            }
        }
    }

    private var executionSection: some View {
        section(AppStrings.VibeLanes.editorExecution, icon: "cpu") {
            VibeLaneEngineSummaryView(configuration: vibe.engine)

            if !vibe.work.skills.isEmpty {
                skillList(
                    AppStrings.VibeLanes.editorWorkSkills,
                    skills: vibe.work.skills,
                    systemImage: "hammer",
                    color: palette.accentColor
                )
            }
        }
    }

    private func skillList(
        _ title: String,
        skills: [String],
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(6)) {
            Text(title)
                .font(.system(size: uiScale.textSize(10), weight: .bold))
                .foregroundStyle(palette.tertiaryTextColor)
                .textCase(.uppercase)
            ForEach(skills, id: \.self) { skill in
                Label(skill, systemImage: systemImage)
                    .font(.system(size: uiScale.textSize(11), design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            Label(title, systemImage: icon)
                .font(.system(size: uiScale.textSize(12), weight: .bold))
                .foregroundStyle(palette.secondaryTextColor)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func limitValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(3)) {
            Text(value)
                .font(.system(size: uiScale.textSize(15), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1)
            Text(label)
                .font(.system(size: uiScale.textSize(10), weight: .medium))
                .foregroundStyle(palette.tertiaryTextColor)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, uiScale.spacing(10))
    }

    private var verificationOwner: String {
        vibe.verify.humanReview
            ? AppStrings.VibeLanes.editorVerifiedByYou
            : AppStrings.VibeLanes.editorReviewerAgent
    }

    private var exhaustedValue: String {
        vibe.bounds.onExhausted == .stop
            ? AppStrings.VibeLanes.stopOnExhausted
            : AppStrings.VibeLanes.escalateOnExhausted
    }

    private var separator: some View {
        Rectangle()
            .fill(palette.borderColorValue.opacity(0.42))
            .frame(maxWidth: .infinity)
            .frame(height: uiScale.chromeSize(1))
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(palette.borderColorValue.opacity(0.42))
            .frame(width: uiScale.chromeSize(1), height: uiScale.chromeSize(42))
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
