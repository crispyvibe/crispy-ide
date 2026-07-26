import SwiftUI

// F059 - Vibe Lanes dashboard. Task-first landing: create work, scan status,
// and recover running/stopped tasks.

@MainActor
struct VibeLaneDashboardView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var manager: VibeLaneTaskManager

    var onNewTask: () -> Void = {}
    var onOpenTask: (VibeLaneTask) -> Void = { _ in }
    var onShowLanes: () -> Void = {}
    var onShowVibes: () -> Void = {}

    private var sortedTasks: [VibeLaneTask] {
        manager.tasks.sorted {
            if stateRank($0.state) != stateRank($1.state) {
                return stateRank($0.state) < stateRank($1.state)
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiScale.spacing(18)) {
                header
                stats
                taskList
            }
            .padding(uiScale.spacing(24))
        }
        .background(palette.canvasBackgroundColor)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: uiScale.spacing(14)) {
            VibeLaneIconBadge(systemImage: VibeLaneVisualIdentity.symbolName, side: 42, iconSize: 18)
            VStack(alignment: .leading, spacing: uiScale.spacing(2)) {
                Text(AppStrings.VibeLanes.title)
                    .font(.system(size: uiScale.textSize(23), weight: .bold))
                Text(AppStrings.VibeLanes.subtitle)
                    .font(.system(size: uiScale.textSize(13)))
                    .foregroundStyle(palette.secondaryTextColor)
            }
            Spacer()
            Button(action: onShowVibes) {
                Label(AppStrings.VibeLanes.vibes, systemImage: "sparkles.rectangle.stack")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button(action: onShowLanes) {
                Label(AppStrings.VibeLanes.manageLanes, systemImage: "rectangle.stack")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button(action: onNewTask) {
                Label(AppStrings.VibeLanes.newTask, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var stats: some View {
        HStack(spacing: uiScale.spacing(12)) {
            statCard(count: manager.runningCount, label: AppStrings.VibeLanes.running, color: .accentColor, icon: "play.fill")
            statCard(count: manager.needsInputCount, label: AppStrings.VibeLanes.needsYou, color: .orange, icon: "person.crop.circle.badge.exclamationmark")
            statCard(count: manager.stoppedCount, label: AppStrings.VibeLanes.stopped, color: .red, icon: "stop.fill")
            statCard(count: manager.doneCount, label: AppStrings.VibeLanes.completed, color: .green, icon: "checkmark")
        }
    }

    private func statCard(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: uiScale.spacing(11)) {
            VibeLaneIconBadge(systemImage: icon, color: count > 0 ? color : .gray, side: 32, iconSize: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: uiScale.textSize(19), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(count > 0 ? palette.primaryTextColor : palette.tertiaryTextColor)
                Text(label)
                    .font(.system(size: uiScale.textSize(11), weight: .medium))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, uiScale.spacing(13))
        .padding(.vertical, uiScale.spacing(11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .vibeLaneCard()
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
            HStack(spacing: uiScale.spacing(8)) {
                Text(AppStrings.VibeLanes.allTasks)
                    .font(.system(size: uiScale.textSize(15), weight: .semibold))
                if !sortedTasks.isEmpty {
                    Text("\(sortedTasks.count)")
                        .font(.system(size: uiScale.textSize(11), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryTextColor)
                        .padding(.horizontal, uiScale.spacing(7))
                        .padding(.vertical, uiScale.spacing(2))
                        .background(Capsule().fill(palette.tertiaryTextColor.opacity(0.14)))
                }
                Spacer()
            }
            if sortedTasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    taskTableHeader
                    Divider()
                    ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task)
                        if index < sortedTasks.count - 1 {
                            Divider().padding(.leading, uiScale.chromeSize(34))
                        }
                    }
                }
                .padding(uiScale.spacing(4))
                .vibeLaneCard()
            }
        }
    }

    private var taskTableHeader: some View {
        HStack(spacing: uiScale.spacing(16)) {
            Text(AppStrings.VibeLanes.task)
                .frame(width: uiScale.chromeSize(290), alignment: .leading)
            Text(AppStrings.VibeLanes.route)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(AppStrings.VibeLanes.currentStep)
                .frame(width: uiScale.chromeSize(180), alignment: .leading)
            Spacer().frame(width: uiScale.chromeSize(118))
        }
        .font(.system(size: uiScale.textSize(10), weight: .semibold))
        .foregroundStyle(palette.tertiaryTextColor)
        .textCase(.uppercase)
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(8))
    }

    private var emptyState: some View {
        VStack(spacing: uiScale.spacing(14)) {
            VibeLaneIconBadge(systemImage: VibeLaneVisualIdentity.symbolName, side: 56, iconSize: 24)
            VStack(spacing: 4) {
                Text(AppStrings.VibeLanes.noTasksTitle)
                    .font(.system(size: uiScale.textSize(15), weight: .semibold))
                Text(AppStrings.VibeLanes.noTasksBody)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            Button(action: onNewTask) {
                Label(AppStrings.VibeLanes.startFirstTask, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(uiScale.spacing(44))
        .vibeLaneCard()
    }

    private func taskRow(_ task: VibeLaneTask) -> some View {
        let lane = manager.resolvedLane(for: task)
        return ViewThatFits(in: .horizontal) {
            wideTaskRow(task, lane: lane)
            compactTaskRow(task, lane: lane)
        }
        .vibeLaneHoverable()
        .contentShape(Rectangle())
        .onTapGesture { onOpenTask(task) }
    }

    private func wideTaskRow(_ task: VibeLaneTask, lane: VibeLaneDefinition?) -> some View {
        return HStack(spacing: uiScale.spacing(16)) {
            statusDot(for: task.state)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: uiScale.textSize(14), weight: .semibold))
                    .lineLimit(1)
                Text(taskSubtitle(task, lane: lane))
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                if let activity = task.currentActivity, !activity.isEmpty {
                    Text(activity)
                        .font(.system(size: uiScale.textSize(11), weight: .medium))
                        .foregroundStyle(task.state == .running ? Color.accentColor : palette.tertiaryTextColor)
                        .lineLimit(1)
                }
            }
            .frame(width: uiScale.chromeSize(256), alignment: .leading)

            progressSummary(for: task, lane: lane)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: uiScale.spacing(7)) {
                statusText(for: task)
            }
            .frame(width: uiScale.chromeSize(180), alignment: .leading)

            rowAction(for: task)
                .frame(width: uiScale.chromeSize(118), alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: uiScale.iconSize(10), weight: .semibold))
                .foregroundStyle(palette.tertiaryTextColor)
        }
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(12))
    }

    private func compactTaskRow(_ task: VibeLaneTask, lane: VibeLaneDefinition?) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(9)) {
            HStack(alignment: .top, spacing: uiScale.spacing(10)) {
                statusDot(for: task.state)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: uiScale.textSize(14), weight: .semibold))
                        .lineLimit(2)
                    Text(taskSubtitle(task, lane: lane))
                        .font(.system(size: uiScale.textSize(12)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                    statusText(for: task)
                }
                Spacer(minLength: 0)
                rowAction(for: task)
            }
            progressSummary(for: task, lane: lane)
                .padding(.leading, uiScale.chromeSize(28))
        }
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(12))
    }

    private func statusDot(for state: VibeLaneTaskState) -> some View {
        Circle()
            .fill(stateColor(state))
            .frame(width: uiScale.chromeSize(10), height: uiScale.chromeSize(10))
            .frame(width: uiScale.chromeSize(18), alignment: .leading)
    }

    private func rowAction(for task: VibeLaneTask) -> some View {
        Group {
            switch task.state {
            case .running:
                Button(AppStrings.VibeLanes.stop, role: .destructive) {
                    Task { await manager.stop(id: task.id) }
                }
            case .needsInput:
                Button(AppStrings.VibeLanes.answer) {
                    onOpenTask(task)
                }
            case .stopped:
                HStack(spacing: uiScale.spacing(8)) {
                    Button(AppStrings.VibeLanes.open) { onOpenTask(task) }
                    Button(AppStrings.VibeLanes.deleteTask, role: .destructive) {
                        Task { await manager.delete(id: task.id) }
                    }
                }
            case .done:
                HStack(spacing: uiScale.spacing(8)) {
                    Button(AppStrings.VibeLanes.open) { onOpenTask(task) }
                    Button(AppStrings.VibeLanes.deleteTask, role: .destructive) {
                        Task { await manager.delete(id: task.id) }
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: uiScale.textSize(12), weight: .semibold))
    }

    private func progressSummary(for task: VibeLaneTask, lane: VibeLaneDefinition?) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(6)) {
            rail(for: task, lane: lane)
            Text(currentCheckpointTitle(task, lane: lane))
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
        }
    }

    private func rail(for task: VibeLaneTask, lane: VibeLaneDefinition?) -> some View {
        let checkpoints = lane?.orderedCheckpoints ?? []
        return HStack(spacing: 0) {
            ForEach(Array(checkpoints.enumerated()), id: \.element.key) { index, checkpoint in
                let state = nodeState(for: checkpoint, task: task)
                if index > 0 {
                    Rectangle()
                        .fill(connectorColor(for: state))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
                node(state)
                    .frame(width: uiScale.chromeSize(18), height: uiScale.chromeSize(18))
            }
        }
    }

    @ViewBuilder
    private func node(_ state: VibeLaneNodeState) -> some View {
        VibeLaneStatusNode(state: state)
    }

    private func connectorColor(for state: VibeLaneNodeState) -> Color {
        VibeLaneRoute.connectorColor(for: state, tertiary: palette.tertiaryTextColor)
    }

    private func nodeState(for checkpoint: VibeLaneCheckpoint, task: VibeLaneTask) -> VibeLaneNodeState {
        VibeLaneNodeState.resolve(for: checkpoint, task: task)
    }

    private func statusText(for task: VibeLaneTask) -> some View {
        HStack(spacing: uiScale.spacing(7)) {
            Image(systemName: VibeLaneStateStyle.icon(task.state))
                .font(.system(size: uiScale.iconSize(11), weight: .semibold))
                .foregroundStyle(stateColor(task.state))
            Text(statusLabel(for: task))
                .font(.system(size: uiScale.textSize(12)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
        }
    }

    private func currentCheckpointTitle(_ task: VibeLaneTask, lane: VibeLaneDefinition?) -> String {
        lane?.checkpoint(forKey: task.currentCheckpointKey)?.displayTitle ?? AppStrings.VibeLanes.laneNotFound
    }

    private func statusLabel(for task: VibeLaneTask) -> String {
        switch task.state {
        case .running:
            if let activity = task.currentActivity, !activity.isEmpty {
                return activity
            }
            let lane = manager.resolvedLane(for: task)
            let cap = lane?.checkpoint(forKey: task.currentCheckpointKey)?.bounds.maxAttempts ?? 0
            return AppStrings.VibeLanes.attemptRunning(current: task.attemptsOnCurrentCheckpoint + 1, cap: cap)
        case .needsInput:
            return task.openInputRequest?.prompt ?? AppStrings.VibeLanes.needsYou
        case .stopped:
            return AppStrings.VibeLanes.stopped(reasonLabel(task.stopReason))
        case .done:
            return AppStrings.VibeLanes.doneAttempts(task.totalAttempts)
        }
    }

    private func taskSubtitle(_ task: VibeLaneTask, lane: VibeLaneDefinition?) -> String {
        let projectName = URL(fileURLWithPath: task.projectPath).lastPathComponent
        guard let lane else { return projectName }
        return AppStrings.VibeLanes.dashboardSubtitle(lane: lane.name, project: projectName)
    }

    private func reasonLabel(_ reason: VibeLaneStopReason?) -> String {
        switch reason {
        case .verificationFailed:
            return AppStrings.VibeLanes.reasonVerificationFailed
        case .timeout:
            return AppStrings.VibeLanes.reasonTimedOut
        case .error:
            return AppStrings.VibeLanes.reasonError
        case .stoppedByUser:
            return AppStrings.VibeLanes.reasonStopped
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

    private func stateColor(_ state: VibeLaneTaskState) -> Color {
        VibeLaneStateStyle.color(state)
    }

    private func stateRank(_ state: VibeLaneTaskState) -> Int {
        switch state {
        case .needsInput:
            return 0
        case .running:
            return 1
        case .stopped:
            return 2
        case .done:
            return 3
        }
    }
}
