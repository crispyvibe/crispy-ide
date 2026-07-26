import SwiftUI

// F059 - Task detail. Left-right master–detail: the checkpoint lane (a vertical
// stepper) on the LEFT selects a step; the RIGHT pane shows that step's detail.
// The header carries status, the task-level worker/reviewer threads, and the
// primary action; the run log is a collapsed disclosure at the bottom.
// The split lives in VibeLaneTaskDetailView+Checkpoints.swift and the run-log
// rows in VibeLaneTaskDetailView+RunLog.swift (file size / cohesion).

/// Measures the detail content width so the split can choose side-by-side vs
/// stacked from the ACTUAL available width (ViewThatFits misjudges here because
/// long verification feedback inflates the ideal width).
private struct VibeLaneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
struct VibeLaneTaskDetailView: View {
    @Environment(\.appThemePalette) var palette
    @Environment(\.crispyvibesUIScale) var uiScale
    @ObservedObject var manager: VibeLaneTaskManager
    let taskID: UUID
    let onOpenACPSession: (VibeLaneACPChatTarget) -> Void
    let onStop: ((UUID) -> Void)?

    /// The checkpoint selected in the left rail (used by the +Checkpoints extension).
    /// nil follows the task's active/current checkpoint.
    @State var selectedKey: String?
    /// Measured content width; drives the side-by-side vs stacked split choice.
    @State var contentWidth: CGFloat = 0
    /// Supply/steer/review draft answers (rendered by the +RunLog extension's panels).
    @State var supplyValues: [String: String] = [:]
    @State var steeringGuidance: String = ""
    @State var reviewFeedback: String = ""
    /// User override for the activity disclosure; nil = follow the task state.
    @State var activityExpanded: Bool?
    /// User override for the step-definition disclosure; nil = auto (open until
    /// the step has attempt history). Reset when the selection changes.
    @State var definitionExpanded: Bool?
    /// Non-nil while the per-step rerun engine sheet is presented.
    @State var rerunCheckpoint: VibeLaneCheckpoint?

    init(
        manager: VibeLaneTaskManager,
        taskID: UUID,
        onOpenACPSession: @escaping (VibeLaneACPChatTarget) -> Void,
        onStop: ((UUID) -> Void)? = nil
    ) {
        self.manager = manager
        self.taskID = taskID
        self.onOpenACPSession = onOpenACPSession
        self.onStop = onStop
    }

    // Internal (not private): the +RunLog extension reads it (F060 link base).
    var task: VibeLaneTask? { manager.task(withID: taskID) }
    var lane: VibeLaneDefinition? { task.flatMap { manager.resolvedLane(for: $0) } }

    /// Whether the split renders side-by-side (enough width) or stacked.
    var isWideLayout: Bool { contentWidth >= 700 }

    var body: some View {
        Group {
            if let task {
                ScrollView {
                    VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
                        header(task)
                        if task.state == .running {
                            nowStrip(task)
                        }
                        inputRequestPanel(task)
                        if task.state == .stopped {
                            stoppedBanner(task)
                        }
                        outcome(task)
                        checkpointSplit(task)
                        activitySection(task)
                    }
                    .padding(uiScale.spacing(24))
                    .frame(maxWidth: 1120, alignment: .topLeading)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: VibeLaneWidthKey.self, value: geo.size.width)
                    })
                    .frame(maxWidth: .infinity, alignment: .top)
                    .onPreferenceChange(VibeLaneWidthKey.self) { contentWidth = $0 }
                }
                .background(palette.canvasBackgroundColor)
            } else {
                ContentUnavailableView(AppStrings.VibeLanes.taskNotFound, systemImage: "questionmark.circle")
            }
        }
        .sheet(item: $rerunCheckpoint) { checkpoint in
            VibeLaneRerunSheet(
                checkpointTitle: checkpoint.displayTitle,
                engine: checkpoint.engine,
                optionCatalog: manager.engineOptionCatalog,
                onRun: { engine in
                    Task {
                        await manager.rerunStep(
                            id: taskID,
                            checkpointKey: checkpoint.key,
                            engine: engine
                        )
                    }
                }
            )
        }
    }

    /// The checkpoint whose detail the right pane shows: the user's selection when
    /// still valid, otherwise the task's current/active checkpoint.
    func effectiveSelection(_ task: VibeLaneTask) -> String {
        if let key = selectedKey, lane?.checkpoint(forKey: key) != nil {
            return key
        }
        return task.currentCheckpointKey
    }

    // MARK: - Header

    private func header(_ task: VibeLaneTask) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: uiScale.spacing(18)) {
                headerIdentity(task)
                Spacer(minLength: uiScale.spacing(12))
                controlsRow(task)
            }

            VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                headerIdentity(task)
                controlsRow(task)
            }
        }
        .padding(uiScale.spacing(16))
        .vibeLaneCard()
    }

    private func headerIdentity(_ task: VibeLaneTask) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
            HStack(alignment: .firstTextBaseline, spacing: uiScale.spacing(10)) {
                statusPill(task)
                Text(task.title)
                    .font(.system(size: uiScale.textSize(20), weight: .semibold))
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(2)
            }
            FlowLayout(spacing: uiScale.spacing(12)) {
                if let lane {
                    metaLabel(lane.name, systemImage: "rectangle.stack")
                }
                metaLabel(URL(fileURLWithPath: task.projectPath).lastPathComponent, systemImage: "folder")
                if let agentID = task.agentID {
                    metaLabel(agentID, systemImage: "cpu")
                }
                if task.totalAttempts > 0 {
                    metaLabel(AppStrings.VibeLanes.attempts(task.totalAttempts), systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    private func metaLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: uiScale.textSize(12)))
            .foregroundStyle(palette.secondaryTextColor)
            .lineLimit(1)
    }

    @ViewBuilder
    private func controlsRow(_ task: VibeLaneTask) -> some View {
        FlowLayout(spacing: uiScale.spacing(8)) {
            threadButtons(task)
            switch task.state {
            case .running:
                Button(AppStrings.VibeLanes.stop, role: .destructive) { stop(task.id) }
                    .buttonStyle(.bordered)
            case .needsInput:
                Button(AppStrings.VibeLanes.stop, role: .destructive) { stop(task.id) }
                    .buttonStyle(.bordered)
            case .stopped:
                Button(AppStrings.VibeLanes.discard, role: .destructive) {
                    Task { await manager.delete(id: task.id) }
                }
                    .buttonStyle(.bordered)
            case .done:
                Button(AppStrings.VibeLanes.discard, role: .destructive) {
                    Task { await manager.delete(id: task.id) }
                }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func stop(_ id: UUID) {
        if let onStop {
            onStop(id)
        } else {
            Task { await manager.stop(id: id) }
        }
    }

    @ViewBuilder
    private func threadButtons(_ task: VibeLaneTask) -> some View {
        if let workerTarget = chatTarget(sessionRef: task.workerSessionRef, threadRef: task.workerThreadRef, task: task) {
            Button { onOpenACPSession(workerTarget) } label: {
                Label(AppStrings.VibeLanes.workerThread, systemImage: "message")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        if let reviewerTarget = chatTarget(sessionRef: task.reviewerSessionRef, threadRef: task.reviewerThreadRef, task: task) {
            Button { onOpenACPSession(reviewerTarget) } label: {
                Label(AppStrings.VibeLanes.reviewerThread, systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func statusPill(_ task: VibeLaneTask) -> some View {
        let text: String
        switch task.state {
        case .running:
            text = AppStrings.VibeLanes.running
        case .needsInput:
            text = AppStrings.VibeLanes.needsYou
        case .stopped:
            text = AppStrings.VibeLanes.stopped(reasonLabel(task.stopReason))
        case .done:
            text = AppStrings.VibeLanes.completed
        }
        return VibeLaneStatusChip(
            text: text,
            color: VibeLaneStateStyle.color(task.state),
            icon: VibeLaneStateStyle.icon(task.state),
            size: 12
        )
    }

    // MARK: - Now (live band for running tasks)

    /// The one place a running task explains itself: what step, which attempt,
    /// what the worker is doing right now, how far the lane has come, and a
    /// ticking clock — with a pulsing node so "running" visibly runs.
    private func nowStrip(_ task: VibeLaneTask) -> some View {
        let checkpoints = lane?.orderedCheckpoints ?? []
        let passed = checkpoints.filter { task.run(forKey: $0.key)?.status == .passed }.count
        let stepIndex = checkpoints.firstIndex { $0.key == task.currentCheckpointKey } ?? 0
        let current = lane?.checkpoint(forKey: task.currentCheckpointKey)
        let fraction = checkpoints.isEmpty ? 0 : (Double(passed) + 0.5) / Double(checkpoints.count)
        return VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            HStack(alignment: .center, spacing: uiScale.spacing(12)) {
                VibeLaneStatusNode(state: .active, diameter: uiScale.chromeSize(14), pulses: true)
                    .padding(uiScale.spacing(4))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: uiScale.spacing(8)) {
                        Text(current?.displayTitle ?? task.currentCheckpointKey)
                            .font(.system(size: uiScale.textSize(14), weight: .semibold))
                        if let cap = current?.bounds.maxAttempts {
                            Text(AppStrings.VibeLanes.attemptRunning(current: task.attemptsOnCurrentCheckpoint + 1, cap: cap))
                                .font(.system(size: uiScale.textSize(11), weight: .medium))
                                .foregroundStyle(palette.secondaryTextColor)
                        }
                    }
                    if let activity = nonEmpty(task.currentActivity) {
                        Text(activity)
                            .font(.system(size: uiScale.textSize(12)))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: activity)
                    }
                }
                Spacer(minLength: uiScale.spacing(12))
                if let workerTarget = chatTarget(
                    sessionRef: task.workerSessionRef,
                    threadRef: task.workerThreadRef,
                    task: task
                ) {
                    Button { onOpenACPSession(workerTarget) } label: {
                        Label(AppStrings.VibeLanes.workerThread, systemImage: "message")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                elapsedBadge(task)
            }
            VibeLaneProgressBar(fraction: fraction)
            Text(AppStrings.VibeLanes.stepOf(current: min(stepIndex + 1, max(1, checkpoints.count)), total: max(1, checkpoints.count)))
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.tertiaryTextColor)
        }
        .padding(uiScale.spacing(14))
        .frame(maxWidth: 820, alignment: .leading)
        .vibeLaneCard(tint: .accentColor)
    }

    /// Live elapsed time on the current checkpoint's active window; ticks every second.
    private func elapsedBadge(_ task: VibeLaneTask) -> some View {
        let started = task.run(forKey: task.currentCheckpointKey)?.activeWindowStartedAt
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            if let started {
                Label(Self.elapsedText(from: started, to: context.date), systemImage: "clock")
                    .font(.system(size: uiScale.textSize(11), weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
    }

    static func elapsedText(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    // MARK: - Stopped

    /// Compact why-it-stopped banner: the reason plus the reviewer's last words —
    /// full evidence stays with the attempt on the step, not up here.
    private func stoppedBanner(_ task: VibeLaneTask) -> some View {
        HStack(alignment: .top, spacing: uiScale.spacing(10)) {
            Image(systemName: "stop.circle.fill")
                .font(.system(size: uiScale.iconSize(14)))
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
                Text(AppStrings.VibeLanes.stopped(reasonLabel(task.stopReason)))
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    .foregroundStyle(.red)
                if let feedback = nonEmpty(task.lastVerification?.feedback) {
                    Text(feedback)
                        .font(.system(size: uiScale.textSize(12)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(uiScale.spacing(14))
        .frame(maxWidth: 820, alignment: .leading)
        .vibeLaneCard(tint: .red)
    }

    // MARK: - Outcome

    @ViewBuilder
    private func outcome(_ task: VibeLaneTask) -> some View {
        if task.state == .done, let text = outcomeText(task) {
            HStack(alignment: .top, spacing: uiScale.spacing(12)) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.green).frame(width: 3)
                VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                    Label(AppStrings.VibeLanes.outcome, systemImage: "flag.checkered")
                        .font(.system(size: uiScale.textSize(12), weight: .semibold))
                        .foregroundStyle(.green)
                    VibeLaneMarkdownText(markdown: text, linkBaseDirectory: URL(fileURLWithPath: task.projectPath))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(uiScale.spacing(16))
            .frame(maxWidth: 820, alignment: .leading)
            .vibeLaneCard(tint: .green)
        }
    }

    private func outcomeText(_ task: VibeLaneTask) -> String? {
        if let summary = nonEmpty(task.outcomeSummary) { return summary }
        // Back-compat: tasks finished before outcomeSummary existed stored the
        // wrap-up as the last checkpoint's summary.
        guard let lane else { return nil }
        for checkpoint in lane.orderedCheckpoints.reversed() {
            let s = task.run(forKey: checkpoint.key)?.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !s.isEmpty, !s.lowercased().hasPrefix("passed at attempt") {
                return s
            }
        }
        return nil
    }

    // MARK: - Shared helpers (used by the +Checkpoints extension too)

    func chatTarget(sessionRef: String?, threadRef: String?, task: VibeLaneTask) -> VibeLaneACPChatTarget? {
        let sessionID = sessionRef.flatMap(UUID.init(uuidString:))
        let threadID = nonEmpty(threadRef)
        guard sessionID != nil || threadID != nil else { return nil }
        return VibeLaneACPChatTarget(sessionID: sessionID, threadID: threadID, projectPath: task.projectPath)
    }

    func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func reasonLabel(_ reason: VibeLaneStopReason?) -> String {
        switch reason {
        case .verificationFailed:
            return AppStrings.VibeLanes.reasonVerificationFailed
        case .timeout:
            return AppStrings.VibeLanes.reasonTimedOut
        case .error:
            return AppStrings.VibeLanes.reasonError
        case .stoppedByUser:
            return AppStrings.VibeLanes.reasonStoppedByYou
        case .missingInput:
            return AppStrings.VibeLanes.reasonMissingInput
        case .misAuthoredLane:
            return AppStrings.VibeLanes.reasonMisAuthoredLane
        case .steerLimitReached:
            return AppStrings.VibeLanes.reasonSteerLimitReached
        case .done, .none:
            return AppStrings.VibeLanes.reasonStopped
        }
    }
}
