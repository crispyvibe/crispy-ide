import SwiftUI

@MainActor
struct VibeLoopDetailView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var manager: VibeLoopManager
    let loopID: UUID
    let onEdit: () -> Void
    let onDeleted: () -> Void
    let onOpenTask: (UUID) -> Void

    @State private var confirmsDelete = false
    @State private var confirmsFullTrust = false
    @State private var pendingLaneUpdate: VibeLaneDefinition?
    @State private var actionError: String?

    var body: some View {
        Group {
            if let definition = manager.definition(withID: loopID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: uiScale.spacing(20)) {
                        header(definition)
                        summary(definition)
                        laneUpdate(definition)
                        runHistory(definition)
                    }
                    .padding(uiScale.spacing(24))
                    .frame(maxWidth: 1080, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .alert(AppStrings.Loops.deleteLoop, isPresented: $confirmsDelete) {
                    Button(AppStrings.Loops.cancel, role: .cancel) {}
                    if manager.activeTask(for: definition.id) != nil {
                        Button(AppStrings.Loops.stopAndDelete, role: .destructive) {
                            delete(definition, stopActiveRun: true)
                        }
                        Button(AppStrings.Loops.keepRunAndDelete, role: .destructive) {
                            delete(definition, stopActiveRun: false)
                        }
                    } else {
                        Button(AppStrings.Loops.deleteLoop, role: .destructive) {
                            delete(definition, stopActiveRun: false)
                        }
                    }
                } message: {
                    Text(
                        manager.activeTask(for: definition.id) == nil
                            ? AppStrings.Loops.deleteConfirmation(definition.name)
                            : AppStrings.Loops.deleteActiveRunMessage
                    )
                }
                .alert(AppStrings.Loops.fullTrustTitle, isPresented: $confirmsFullTrust) {
                    Button(AppStrings.Loops.cancel, role: .cancel) {}
                    Button(AppStrings.Loops.confirmEnable) {
                        Task {
                            await manager.setEnabled(
                                true,
                                id: definition.id,
                                confirmsFullTrust: true
                            )
                        }
                    }
                } message: {
                    Text(AppStrings.Loops.fullTrustMessage)
                }
                .confirmationDialog(
                    AppStrings.Loops.updateLaneTitle,
                    isPresented: Binding(
                        get: { pendingLaneUpdate != nil },
                        set: { if !$0 { pendingLaneUpdate = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button(AppStrings.Loops.updateLane) {
                        guard let latest = pendingLaneUpdate else { return }
                        Task {
                            var updated = definition
                            updated.updateLaneSnapshot(latest)
                            if !(await manager.save(updated)) {
                                actionError = manager.persistenceError ?? AppStrings.Loops.saveFailed
                            }
                            pendingLaneUpdate = nil
                        }
                    }
                    Button(AppStrings.Loops.cancel, role: .cancel) {
                        pendingLaneUpdate = nil
                    }
                } message: {
                    if let latest = pendingLaneUpdate {
                        Text(AppStrings.Loops.updateLaneMessage(
                            currentVersion: definition.laneVersion,
                            newVersion: latest.version,
                            route: latest.routeSummary
                        ))
                    }
                }
                .alert(
                    AppStrings.Loops.actionFailed,
                    isPresented: Binding(
                        get: { actionError != nil },
                        set: { if !$0 { actionError = nil } }
                    )
                ) {
                    Button("OK") { actionError = nil }
                } message: {
                    Text(actionError ?? AppStrings.Loops.actionFailed)
                }
            } else {
                ContentUnavailableView(AppStrings.Loops.notFound, systemImage: "questionmark.circle")
            }
        }
        .background(palette.canvasBackgroundColor)
    }

    private func header(_ definition: VibeLoopDefinition) -> some View {
        let state = manager.state(for: definition)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: uiScale.spacing(14)) {
                identity(definition, state: state)
                Spacer()
                actions(definition)
            }
            VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                identity(definition, state: state)
                actions(definition)
            }
        }
    }

    private func identity(_ definition: VibeLoopDefinition, state: VibeLoopStateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(state.status.color).frame(width: 9, height: 9)
                Text(state.status.title)
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                    .foregroundStyle(state.status.color)
                if state.execution != .idle {
                    Text(state.schedule.title)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.tertiaryTextColor)
                }
            }
            Text(definition.name)
                .font(.system(size: uiScale.textSize(22), weight: .bold))
            Text(definition.taskInstruction)
                .font(.system(size: uiScale.textSize(13)))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(3)
        }
    }

    private func actions(_ definition: VibeLoopDefinition) -> some View {
        HStack(spacing: 8) {
            Button {
                runNow(definition)
            } label: {
                Label(AppStrings.Loops.runNow, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                if definition.isEnabled {
                    Task {
                        if !(await manager.setEnabled(false, id: definition.id)) {
                            actionError = manager.persistenceError ?? AppStrings.Loops.actionFailed
                        }
                    }
                } else {
                    confirmsFullTrust = true
                }
            } label: {
                Label(
                    definition.isEnabled ? AppStrings.Loops.pause : AppStrings.Loops.resume,
                    systemImage: definition.isEnabled ? "pause.fill" : "play.circle"
                )
            }
            .buttonStyle(.bordered)

            Button(action: onEdit) {
                Label(AppStrings.Loops.editLoop, systemImage: "pencil")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help(AppStrings.Loops.deleteLoop)
        }
    }

    private func summary(_ definition: VibeLoopDefinition) -> some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
            summaryRow(AppStrings.Loops.project, value: definition.projectPath, icon: "folder")
            summaryRow(AppStrings.Loops.lane, value: "\(definition.laneSnapshot.name) · v\(definition.laneVersion)", icon: "rectangle.stack")
            summaryRow(AppStrings.Loops.schedule, value: definition.schedule.summary, icon: "calendar")
            summaryRow(AppStrings.Loops.nextRun, value: formatted(manager.nextRunDate(for: definition)), icon: "clock")
            summaryRow(
                AppStrings.Loops.lastRun,
                value: formatted(manager.runtimeStates[definition.id]?.lastTriggeredAt),
                icon: "clock.badge.checkmark"
            )
        }
        .padding(uiScale.spacing(16))
        .vibeLaneCard()
    }

    private func summaryRow(_ label: String, value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: uiScale.spacing(10)) {
            Image(systemName: icon)
                .foregroundStyle(palette.secondaryTextColor)
                .frame(width: uiScale.chromeSize(18))
            Text(label)
                .font(.system(size: uiScale.textSize(12), weight: .semibold))
                .frame(width: uiScale.chromeSize(90), alignment: .leading)
            Text(value)
                .font(.system(size: uiScale.textSize(12)))
                .foregroundStyle(palette.secondaryTextColor)
                .textSelection(.enabled)
            Spacer()
        }
    }

    @ViewBuilder
    private func laneUpdate(_ definition: VibeLoopDefinition) -> some View {
        if manager.hasLaneUpdate(for: definition),
           let latest = manager.latestLane(for: definition) {
            HStack(spacing: uiScale.spacing(10)) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.accentColor)
                Text(AppStrings.Loops.laneUpdateAvailable)
                    .font(.system(size: uiScale.textSize(12)))
                Spacer()
                Button(AppStrings.Loops.updateLane) {
                    pendingLaneUpdate = latest
                }
            }
            .padding(uiScale.spacing(12))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func runHistory(_ definition: VibeLoopDefinition) -> some View {
        let runs = manager.runs(for: definition.id)
        return VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
            Text(AppStrings.Loops.history)
                .font(.system(size: uiScale.textSize(15), weight: .semibold))
            if runs.isEmpty {
                Text(AppStrings.Loops.noHistory)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .padding(.vertical, uiScale.spacing(16))
            } else {
                VStack(spacing: 0) {
                    ForEach(runs) { run in
                        runRow(run)
                        if run.id != runs.last?.id { Divider() }
                    }
                }
                .vibeLaneCard()
            }
        }
    }

    private func runRow(_ run: VibeLoopRunRecord) -> some View {
        HStack(spacing: uiScale.spacing(12)) {
            Image(systemName: run.statusSymbol)
                .foregroundStyle(run.statusColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.statusTitle)
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                Text(run.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                if let detail = run.statusDetail {
                    Text(detail)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }
            Spacer()
            if let taskID = run.taskID, manager.laneManager.task(withID: taskID) != nil {
                Button {
                    onOpenTask(taskID)
                } label: {
                    Label(AppStrings.Loops.openTask, systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(10))
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? AppStrings.Loops.never
    }

    private func runNow(_ definition: VibeLoopDefinition) {
        Task { await runNowPersisted(definition) }
    }

    private func runNowPersisted(_ definition: VibeLoopDefinition) async {
        guard let run = await manager.runNow(id: definition.id) else {
            actionError = manager.persistenceError ?? AppStrings.Loops.taskCreationFailed
            return
        }
        if let taskID = run.taskID {
            onOpenTask(taskID)
        } else if let activeTaskID = manager.activeTask(for: definition.id)?.id {
            onOpenTask(activeTaskID)
        } else {
            actionError = run.statusDetail ?? AppStrings.Loops.actionFailed
        }
    }

    private func delete(_ definition: VibeLoopDefinition, stopActiveRun: Bool) {
        Task { await deletePersisted(definition, stopActiveRun: stopActiveRun) }
    }

    private func deletePersisted(
        _ definition: VibeLoopDefinition,
        stopActiveRun: Bool
    ) async {
        guard await manager.delete(id: definition.id, stopActiveRun: stopActiveRun) else {
            actionError = manager.persistenceError
                ?? (stopActiveRun ? AppStrings.Loops.stopFailed : AppStrings.Loops.actionFailed)
            return
        }
        onDeleted()
    }
}
