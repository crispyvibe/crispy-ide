import SwiftUI

@MainActor
struct VibeLaneCheckpointStepButton: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let index: Int
    let checkpoint: VibeLaneCheckpoint
    let isSelected: Bool
    let hasErrors: Bool
    /// Non-nil when this step belongs to an authored loop group.
    var loop: VibeLaneLoopGroup?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: uiScale.spacing(8)) {
                Text("\(index + 1)")
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                    .foregroundStyle(isSelected ? palette.accentColor : palette.secondaryTextColor)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: uiScale.spacing(5)) {
                        Text(checkpoint.displayTitle)
                            .font(.system(size: uiScale.textSize(12), weight: .semibold))
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if loop != nil {
                            Image(systemName: "repeat")
                                .font(.system(size: uiScale.iconSize(9), weight: .bold))
                                .foregroundStyle(palette.accentColor)
                        }
                    }
                    Label(
                        hasErrors ? AppStrings.VibeLanes.laneNeedsSetup : AppStrings.VibeLanes.ready,
                        systemImage: hasErrors ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                    )
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(hasErrors ? palette.warningColor : palette.successColor)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, uiScale.spacing(10))
            .padding(.vertical, uiScale.spacing(8))
            .frame(width: uiScale.chromeSize(170), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(9), style: .continuous)
                    .fill(
                        isSelected
                            ? palette.accentColor.opacity(0.10)
                            : (loop == nil
                                ? palette.canvasSecondaryBackgroundColor
                                : palette.accentColor.opacity(0.05))
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.0 : 0.05), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(9), style: .continuous)
                    .strokeBorder(
                        isSelected ? palette.accentColor : palette.borderColorValue.opacity(0.42),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(
            loop.map {
                "\(checkpoint.displayTitle) — \(AppStrings.VibeLanes.loopBadge(group: $0.key, iterations: $0.maxIterations))"
            } ?? checkpoint.displayTitle
        )
    }
}

@MainActor
struct VibeLaneCheckpointBehaviorSummary: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let checkpoint: VibeLaneCheckpoint

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: uiScale.spacing(12)) {
                summaryItem(
                    AppStrings.VibeLanes.editorOutcome,
                    value: summaryLine(checkpoint.work.goal) ?? AppStrings.VibeLanes.summaryMissingOutcome,
                    icon: "scope",
                    isComplete: !checkpoint.work.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                connector
                summaryItem(
                    AppStrings.VibeLanes.editorDoneWhen,
                    value: summaryLine(checkpoint.verify.definition) ?? AppStrings.VibeLanes.summaryMissingDoneWhen,
                    icon: checkpoint.verify.humanReview ? "person.crop.circle.badge.checkmark" : "checkmark.seal",
                    isComplete: !checkpoint.verify.isEmpty
                )
                connector
                summaryItem(
                    AppStrings.VibeLanes.editorLimits,
                    value: AppStrings.VibeLanes.boundsSummary(
                        attempts: checkpoint.bounds.maxAttempts,
                        minutes: max(1, checkpoint.bounds.timeoutSeconds / 60),
                        behavior: checkpoint.bounds.onExhausted == .escalate
                            ? AppStrings.VibeLanes.escalateOnExhausted
                            : AppStrings.VibeLanes.stopOnExhausted
                    ),
                    icon: "timer",
                    isComplete: checkpoint.bounds.maxAttempts > 0 && checkpoint.bounds.timeoutSeconds > 0
                )
            }

            VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
                compactRow(
                    AppStrings.VibeLanes.editorOutcome,
                    value: summaryLine(checkpoint.work.goal) ?? AppStrings.VibeLanes.summaryMissingOutcome,
                    icon: "scope"
                )
                compactRow(
                    AppStrings.VibeLanes.editorDoneWhen,
                    value: summaryLine(checkpoint.verify.definition) ?? AppStrings.VibeLanes.summaryMissingDoneWhen,
                    icon: "checkmark.seal"
                )
                compactRow(
                    AppStrings.VibeLanes.editorLimits,
                    value: AppStrings.VibeLanes.boundsSummary(
                        attempts: checkpoint.bounds.maxAttempts,
                        minutes: max(1, checkpoint.bounds.timeoutSeconds / 60),
                        behavior: checkpoint.bounds.onExhausted == .escalate
                            ? AppStrings.VibeLanes.escalateOnExhausted
                            : AppStrings.VibeLanes.stopOnExhausted
                    ),
                    icon: "timer"
                )
            }
        }
        .padding(.vertical, uiScale.spacing(2))
    }

    private var connector: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: uiScale.iconSize(9), weight: .semibold))
            .foregroundStyle(palette.tertiaryTextColor)
            .padding(.top, uiScale.spacing(11))
    }

    private func summaryItem(
        _ title: String,
        value: String,
        icon: String,
        isComplete: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
            Label(title, systemImage: icon)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(isComplete ? Color.accentColor : Color.orange)
            Text(value)
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactRow(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: uiScale.spacing(8)) {
            Label(title, systemImage: icon)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: uiScale.chromeSize(100), alignment: .leading)
            Text(value)
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(2)
        }
    }

    private func summaryLine(_ value: String) -> String? {
        value
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

@MainActor
enum VibeLaneEditorValidation {
    static func errors(for lane: VibeLaneDefinition) -> [String] {
        uniqueMessages(
            lane.validationIssues
                .filter { !$0.isRepairedOnEditorSave }
                .map { message(for: $0, in: lane) }
        )
    }

    static func warnings(for lane: VibeLaneDefinition) -> [String] {
        var warnings: [String] = []
        let rawKeys = lane.checkpoints.map(\.key)
        let normalized = rawKeys.map(VibeLaneTaskManager.normalizedKey)
        if normalized.contains("") || Set(normalized).count != normalized.count || rawKeys != normalized {
            warnings.append(AppStrings.VibeLanes.keyNormalizationWarning)
        }
        return warnings
    }

    private static func message(
        for issue: VibeLaneDefinitionIssue,
        in lane: VibeLaneDefinition
    ) -> String {
        let checkpoint = issue.checkpointIndex
            .flatMap { lane.checkpoints.indices.contains($0) ? lane.checkpoints[$0] : nil }
        let title = checkpoint?.displayTitle ?? AppStrings.VibeLanes.editorCheckpoint
        switch issue {
        case .missingLaneName:
            return AppStrings.VibeLanes.laneNeedsName
        case .missingCheckpoints:
            return AppStrings.VibeLanes.laneNeedsCheckpoint
        case .invalidSteerLimit:
            return AppStrings.VibeLanes.laneNeedsValidSteerLimit
        case .missingGoal:
            return AppStrings.VibeLanes.stepNeedsGoal(title)
        case .missingVerification:
            return AppStrings.VibeLanes.stepNeedsVerification(title)
        case .invalidBounds:
            return AppStrings.VibeLanes.stepNeedsValidBounds(title)
        case .emptyInputKey, .duplicateInputKey:
            return AppStrings.VibeLanes.stepNeedsValidInput(title)
        case .emptyOutputKey, .duplicateOutputKey:
            return AppStrings.VibeLanes.stepNeedsValidOutput(title)
        case .unsatisfiedInput(_, let key):
            return AppStrings.VibeLanes.misAuthoredContractWarning(checkpoint: title, keys: key)
        case .emptyLoopGroupKey:
            return AppStrings.VibeLanes.loopGroupNeedsKey
        case .duplicateLoopGroupKey(let key):
            return AppStrings.VibeLanes.loopGroupDuplicateKey(key)
        case .invalidLoopGroupBounds(let key):
            return AppStrings.VibeLanes.loopGroupInvalidBounds(key)
        case .invalidLoopGroupMembers(let key), .noncontiguousLoopGroup(let key):
            return AppStrings.VibeLanes.loopGroupInvalidMembers(key)
        case .missingLoopGroupMember(let groupKey, let memberKey):
            return AppStrings.VibeLanes.loopGroupMissingMember(group: groupKey, member: memberKey)
        case .overlappingLoopGroupMember(let memberKey):
            return AppStrings.VibeLanes.loopGroupOverlappingMember(memberKey)
        case .unavailableLoopConditionVariable(let groupKey, let variable):
            return AppStrings.VibeLanes.loopGroupMissingVariable(group: groupKey, variable: variable)
        case .emptyCheckpointKey, .duplicateCheckpointKey:
            return AppStrings.VibeLanes.keyNormalizationWarning
        case .unresolvedVibeReference:
            return AppStrings.VibeLanes.stepVibeMissing(title)
        }
    }

    private static func uniqueMessages(_ messages: [String]) -> [String] {
        var seen = Set<String>()
        return messages.filter { seen.insert($0).inserted }
    }
}

@MainActor
struct VibeLaneWarningPanel: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    let warnings: [String]

    var body: some View {
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

@MainActor
struct VibeLaneErrorPanel: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    let errors: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
            ForEach(errors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(.red)
            }
        }
        .padding(uiScale.spacing(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .vibeLaneCard(cornerRadius: 10, tint: .red)
    }
}

/// Minimal flow layout for chips (wraps to available width).
@MainActor
struct FlowLayout: @preconcurrency Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
