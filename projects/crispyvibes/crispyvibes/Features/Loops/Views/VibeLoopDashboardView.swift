import SwiftUI

@MainActor
struct VibeLoopDashboardView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var manager: VibeLoopManager
    let onNew: () -> Void
    let onOpen: (UUID) -> Void
    let onEdit: (UUID) -> Void

    @State private var filter: VibeLoopFilter = .all
    @State private var pendingDeletion: VibeLoopDefinition?
    @State private var pendingFullTrustEnableID: UUID?
    @State private var actionError: String?

    private var visibleDefinitions: [VibeLoopDefinition] {
        manager.definitions.filter { filter.includes(manager.state(for: $0)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let persistenceError = manager.persistenceError {
                errorBanner(persistenceError)
            }
            if manager.definitions.isEmpty {
                emptyState
            } else {
                filterBar
                if visibleDefinitions.isEmpty {
                    ContentUnavailableView.search(text: filter.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    loopTable
                }
            }
        }
        .background(palette.canvasBackgroundColor)
        .alert(
            AppStrings.Loops.deleteLoop,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { definition in
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
        } message: { definition in
            Text(
                manager.activeTask(for: definition.id) == nil
                    ? AppStrings.Loops.deleteConfirmation(definition.name)
                    : AppStrings.Loops.deleteActiveRunMessage
            )
        }
        .confirmationDialog(
            AppStrings.Loops.fullTrustTitle,
            isPresented: Binding(
                get: { pendingFullTrustEnableID != nil },
                set: { if !$0 { pendingFullTrustEnableID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.Loops.confirmEnable) {
                if let pendingFullTrustEnableID {
                    Task {
                        await manager.setEnabled(
                            true,
                            id: pendingFullTrustEnableID,
                            confirmsFullTrust: true
                        )
                    }
                }
                pendingFullTrustEnableID = nil
            }
            Button(AppStrings.Loops.cancel, role: .cancel) {
                pendingFullTrustEnableID = nil
            }
        } message: {
            Text(AppStrings.Loops.fullTrustMessage)
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
    }

    private var header: some View {
        HStack(spacing: uiScale.spacing(12)) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: uiScale.iconSize(18), weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: uiScale.chromeSize(36), height: uiScale.chromeSize(36))
                .background(palette.canvasSecondaryBackgroundColor, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.Loops.title)
                    .font(.system(size: uiScale.textSize(22), weight: .bold))
                Text(AppStrings.Loops.subtitle)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.secondaryTextColor)
            }
            Spacer()
            if manager.attentionCount > 0 {
                Label("\(manager.attentionCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
                    .foregroundStyle(.orange)
            }
            if !manager.definitions.isEmpty {
                Button(action: onNew) {
                    Label(AppStrings.Loops.newLoop, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("loops.new")
            }
        }
        .padding(.horizontal, uiScale.spacing(22))
        .padding(.vertical, uiScale.spacing(16))
    }

    private var filterBar: some View {
        HStack {
            Picker(AppStrings.Loops.filter, selection: $filter) {
                ForEach(VibeLoopFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: uiScale.chromeSize(430))
            Spacer()
            Text(AppStrings.Loops.loopCount(manager.definitions.count))
                .font(.system(size: uiScale.textSize(11)))
                .foregroundStyle(palette.secondaryTextColor)
        }
        .padding(.horizontal, uiScale.spacing(22))
        .padding(.bottom, uiScale.spacing(14))
    }

    private var loopTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleDefinitions) { definition in
                        loopRow(definition)
                        Divider().padding(.leading, uiScale.spacing(18))
                    }
                }
            }
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.35))
        .overlay(alignment: .top) {
            Rectangle().fill(palette.borderColorValue.opacity(0.4)).frame(height: 1)
        }
    }

    private var tableHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: uiScale.spacing(10)) {
                Text(AppStrings.Loops.name).frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                Text(AppStrings.Loops.project).frame(width: 120, alignment: .leading)
                Text(AppStrings.Loops.schedule).frame(width: 190, alignment: .leading)
                Text(AppStrings.Loops.nextRun).frame(width: 100, alignment: .leading)
                Text(AppStrings.Loops.status).frame(width: 80, alignment: .leading)
                Color.clear.frame(width: 100, height: 1)
            }
            HStack {
                Text(AppStrings.Loops.name)
                Spacer()
                Text(AppStrings.Loops.status)
                    .frame(width: 90, alignment: .leading)
                Color.clear.frame(width: 112, height: 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: uiScale.textSize(10), weight: .semibold))
        .foregroundStyle(palette.tertiaryTextColor)
        .textCase(.uppercase)
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(8))
    }

    private func loopRow(_ definition: VibeLoopDefinition) -> some View {
        let state = manager.state(for: definition)
        return ViewThatFits(in: .horizontal) {
            wideLoopRow(definition, state: state)
            compactLoopRow(definition, state: state)
        }
        .font(.system(size: uiScale.textSize(12)))
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(11))
        .contentShape(Rectangle())
        .onTapGesture { onOpen(definition.id) }
        .accessibilityIdentifier("loops.row.\(definition.id.uuidString)")
    }

    private func wideLoopRow(
        _ definition: VibeLoopDefinition,
        state: VibeLoopStateSnapshot
    ) -> some View {
        HStack(spacing: uiScale.spacing(10)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name)
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    .lineLimit(1)
                Text(definition.laneSnapshot.name)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
            }
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            Text(URL(fileURLWithPath: definition.projectPath).lastPathComponent)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            Text(definition.schedule.summary)
                .frame(width: 190, alignment: .leading)
                .lineLimit(1)
            Text(nextRunText(definition))
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)
            statusLabel(state).frame(width: 80, alignment: .leading)
            rowActions(definition)
                .frame(width: 100, alignment: .trailing)
        }
    }

    private func compactLoopRow(
        _ definition: VibeLoopDefinition,
        state: VibeLoopStateSnapshot
    ) -> some View {
        HStack(spacing: uiScale.spacing(10)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    .lineLimit(1)
                Text("\(URL(fileURLWithPath: definition.projectPath).lastPathComponent) · \(definition.laneSnapshot.name)")
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                Text(definition.schedule.summary)
                    .font(.system(size: uiScale.textSize(11)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                statusLabel(state)
                Text(nextRunText(definition))
                    .font(.system(size: uiScale.textSize(10)))
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
            }
            .frame(width: 90, alignment: .leading)
            rowActions(definition)
                .frame(width: 112, alignment: .trailing)
        }
    }

    private func statusLabel(_ state: VibeLoopStateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(state.status.color).frame(width: 7, height: 7)
                Text(state.status.title).lineLimit(1)
            }
            if state.execution != .idle {
                Text(state.schedule.title)
                    .font(.system(size: uiScale.textSize(9)))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .lineLimit(1)
            }
        }
    }

    private func rowActions(_ definition: VibeLoopDefinition) -> some View {
        HStack(spacing: 4) {
            iconButton("play.fill", help: AppStrings.Loops.runNow) {
                runNow(definition)
            }
            iconButton(definition.isEnabled ? "pause.fill" : "play.circle", help: definition.isEnabled ? AppStrings.Loops.pause : AppStrings.Loops.resume) {
                if definition.isEnabled {
                    Task { await manager.setEnabled(false, id: definition.id) }
                } else {
                    pendingFullTrustEnableID = definition.id
                }
            }
            iconButton("pencil", help: AppStrings.Loops.editLoop) { onEdit(definition.id) }
            iconButton("trash", help: AppStrings.Loops.deleteLoop, role: .destructive) {
                pendingDeletion = definition
            }
        }
        .buttonStyle(.borderless)
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .frame(width: uiScale.chromeSize(22), height: uiScale.chromeSize(22))
        }
        .help(help)
    }

    private func nextRunText(_ definition: VibeLoopDefinition) -> String {
        manager.nextRunDate(for: definition)?
            .formatted(.relative(presentation: .named)) ?? AppStrings.Loops.never
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(AppStrings.Loops.noLoops, systemImage: "clock.arrow.circlepath")
        } description: {
            Text(AppStrings.Loops.noLoopsDetail)
        } actions: {
            Button(action: onNew) {
                Label(AppStrings.Loops.newLoop, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runNow(_ definition: VibeLoopDefinition) {
        Task { await runNowPersisted(definition) }
    }

    private func runNowPersisted(_ definition: VibeLoopDefinition) async {
        guard let run = await manager.runNow(id: definition.id) else {
            actionError = manager.persistenceError ?? AppStrings.Loops.taskCreationFailed
            return
        }
        switch run.disposition {
        case .started, .skippedActiveRun:
            onOpen(definition.id)
        case .blocked, .creationFailed:
            actionError = run.statusDetail ?? AppStrings.Loops.actionFailed
        case .pending, .skippedMissed:
            onOpen(definition.id)
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
        pendingDeletion = nil
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "externaldrive.badge.exclamationmark")
            .font(.system(size: uiScale.textSize(12), weight: .medium))
            .foregroundStyle(.red)
            .padding(.horizontal, uiScale.spacing(22))
            .padding(.vertical, uiScale.spacing(8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
    }
}
