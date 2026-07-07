import SwiftUI

// F059 — Task detail: the activity timeline and the Needs-you answer panels
// (Supply / Steer). Split from VibeLaneTaskDetailView.swift for file size
// (coding-guidelines).

extension VibeLaneTaskDetailView {

    // MARK: - Needs you (Supply / Steer)

    @ViewBuilder
    func inputRequestPanel(_ task: VibeLaneTask) -> some View {
        if task.state == .needsInput, let request = task.openInputRequest {
            VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                Label(requestTitle(request.kind), systemImage: requestIcon(request.kind))
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    .foregroundStyle(.orange)
                Text(request.prompt)
                    .font(.system(size: uiScale.textSize(13)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                switch request.kind {
                case .supply:
                    supplyFields(task: task, request: request)
                case .steer:
                    steerFields(task: task, request: request)
                case .review:
                    reviewFields(task: task, request: request)
                }
            }
            .padding(uiScale.spacing(16))
            .frame(maxWidth: 820, alignment: .leading)
            .vibeLaneCard(tint: .orange)
        }
    }

    private func requestTitle(_ kind: VibeLaneInputRequestKind) -> String {
        switch kind {
        case .supply: return AppStrings.VibeLanes.supplyInput
        case .steer: return AppStrings.VibeLanes.steerTask
        case .review: return AppStrings.VibeLanes.reviewStep
        }
    }

    private func requestIcon(_ kind: VibeLaneInputRequestKind) -> String {
        switch kind {
        case .supply: return "square.and.pencil"
        case .steer: return "arrow.triangle.turn.up.right.diamond"
        case .review: return "checkmark.seal"
        }
    }

    /// The user takes the reviewer's seat: inspect the outcome, then approve or
    /// send it back with feedback (which loops to the worker like a reviewer FAIL).
    private func reviewFields(task: VibeLaneTask, request: VibeLaneInputRequest) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            Text(AppStrings.VibeLanes.reviewHint)
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.tertiaryTextColor)
            TextField(AppStrings.VibeLanes.reviewFeedbackPlaceholder, text: $reviewFeedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
            HStack(spacing: uiScale.spacing(10)) {
                Button {
                    manager.answerInput(id: task.id, requestID: request.id, approved: true)
                    reviewFeedback = ""
                } label: {
                    Label(AppStrings.VibeLanes.approve, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    manager.answerInput(id: task.id, requestID: request.id, approved: false, feedback: reviewFeedback)
                    reviewFeedback = ""
                } label: {
                    Label(AppStrings.VibeLanes.requestChanges, systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(reviewFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func supplyFields(task: VibeLaneTask, request: VibeLaneInputRequest) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            ForEach(request.missingKeys, id: \.self) { key in
                VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
                    Text(key)
                        .font(.system(size: uiScale.textSize(11), weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.tertiaryTextColor)
                    TextField(AppStrings.VibeLanes.requiredInput, text: supplyBinding(for: key), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                }
            }
            Button {
                manager.answerInput(id: task.id, requestID: request.id, values: supplyValues)
                supplyValues = [:]
            } label: {
                Label(AppStrings.VibeLanes.continueTask, systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasAllSupplyValues(request))
        }
    }

    private func steerFields(task: VibeLaneTask, request: VibeLaneInputRequest) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            if let feedback = nonEmpty(request.lastFeedback) {
                inputDetailLine(title: AppStrings.VibeLanes.lastFeedback, text: feedback)
            }
            if let reason = request.reason {
                inputDetailLine(title: AppStrings.VibeLanes.exhaustedReason, text: reasonLabel(reason))
            }
            if let lane {
                inputDetailLine(
                    title: AppStrings.VibeLanes.remainingSteers,
                    text: "\(max(0, lane.steerLimit - task.steerCount))"
                )
            }
            TextField(AppStrings.VibeLanes.steeringGuidance, text: $steeringGuidance, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
            Button {
                manager.answerInput(id: task.id, requestID: request.id, guidance: steeringGuidance)
                steeringGuidance = ""
            } label: {
                Label(AppStrings.VibeLanes.continueTask, systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(steeringGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func supplyBinding(for key: String) -> Binding<String> {
        Binding(
            get: { supplyValues[key] ?? "" },
            set: { supplyValues[key] = $0 }
        )
    }

    private func hasAllSupplyValues(_ request: VibeLaneInputRequest) -> Bool {
        request.missingKeys.allSatisfy {
            supplyValues[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func inputDetailLine(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
            Text(text)
                .font(.system(size: uiScale.textSize(12), design: .monospaced))
                .foregroundStyle(palette.secondaryTextColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Activity timeline

    /// Compact chronological feed, newest last. Expanded while the task is live
    /// (so it visibly streams), collapsed once terminal; the user can override.
    @ViewBuilder
    func activitySection(_ task: VibeLaneTask) -> some View {
        let entries = task.visibleActivityLog
        if !entries.isEmpty {
            let expanded = Binding<Bool>(
                get: { activityExpanded ?? (task.state == .running || task.state == .needsInput) },
                set: { activityExpanded = $0 }
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                DisclosureGroup(isExpanded: expanded) {
                    timeline(entries, live: task.state == .running)
                        .padding(.top, uiScale.spacing(8))
                } label: {
                    HStack(spacing: uiScale.spacing(8)) {
                        Text(AppStrings.VibeLanes.activity)
                            .font(.system(size: uiScale.textSize(13), weight: .semibold))
                            .foregroundStyle(palette.primaryTextColor)
                        Text("\(entries.count)")
                            .font(.system(size: uiScale.textSize(10), weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(palette.secondaryTextColor)
                            .padding(.horizontal, uiScale.spacing(6))
                            .padding(.vertical, uiScale.spacing(1))
                            .background(Capsule().fill(palette.tertiaryTextColor.opacity(0.14)))
                    }
                }
                .disclosureGroupStyle(.automatic)
            }
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func timeline(_ entries: [VibeLaneActivityLogEntry], live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                timelineRow(
                    entry,
                    isFirst: index == 0,
                    isLast: index == entries.count - 1,
                    isLatestLive: live && index == entries.count - 1
                )
            }
        }
        .padding(.vertical, uiScale.spacing(6))
        .padding(.horizontal, uiScale.spacing(10))
        .vibeLaneCard(cornerRadius: 10)
    }

    private func timelineRow(_ entry: VibeLaneActivityLogEntry, isFirst: Bool, isLast: Bool, isLatestLive: Bool) -> some View {
        HStack(alignment: .top, spacing: uiScale.spacing(10)) {
            // Time gutter keeps the eye on one column.
            Text(entry.at, style: .time)
                .font(.system(size: uiScale.textSize(10), design: .monospaced))
                .foregroundStyle(palette.tertiaryTextColor)
                .frame(width: uiScale.chromeSize(58), alignment: .trailing)
                .padding(.top, uiScale.spacing(2))

            // Dot + connector.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : palette.tertiaryTextColor.opacity(0.22))
                    .frame(width: 1.5, height: uiScale.spacing(4))
                if isLatestLive {
                    VibeLaneStatusNode(state: .active, diameter: uiScale.chromeSize(8), pulses: true)
                } else {
                    Circle()
                        .fill(timelineColor(for: entry.kind))
                        .frame(width: uiScale.chromeSize(7), height: uiScale.chromeSize(7))
                }
                Rectangle()
                    .fill(isLast ? Color.clear : palette.tertiaryTextColor.opacity(0.22))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: uiScale.chromeSize(12))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: uiScale.textSize(12), weight: isLatestLive ? .semibold : .regular))
                    .foregroundStyle(isLatestLive ? palette.primaryTextColor : palette.secondaryTextColor)
                    .lineLimit(2)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: uiScale.textSize(10), design: .monospaced))
                        .foregroundStyle(palette.tertiaryTextColor)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, uiScale.spacing(7))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timelineColor(for kind: VibeLaneActivityKind) -> Color {
        switch kind {
        case .system:
            return palette.tertiaryTextColor
        case .worker:
            return .accentColor
        case .verify:
            return .green
        case .input:
            return .orange
        case .error:
            return .red
        }
    }
}
