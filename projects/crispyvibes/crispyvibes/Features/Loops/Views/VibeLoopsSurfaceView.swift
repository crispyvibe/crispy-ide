import SwiftUI

@MainActor
struct VibeLoopsSurfaceView: View {
    private struct PendingStop {
        var loopID: UUID
        var taskID: UUID
    }

    private enum Screen {
        case dashboard
        case editor(UUID?)
        case detail(UUID)
        case task(UUID, UUID)
        case acp(UUID, UUID, ACPStandaloneSessionStore)
    }

    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var manager: VibeLoopManager
    let projectOptions: [VibeLoopProjectOption]
    let acpProjects: [AnyProjectSession]
    let resolveACPSession: (VibeLaneACPChatTarget) -> ACPStandaloneSessionStore?
    let onOpenLane: (UUID?) -> Void
    let onOpenVibes: () -> Void

    @State private var screen: Screen = .dashboard
    @State private var pendingStop: PendingStop?
    @State private var actionError: String?

    var body: some View {
        Group {
            switch screen {
            case .dashboard:
                VibeLoopDashboardView(
                    manager: manager,
                    onNew: { screen = .editor(nil) },
                    onOpen: { screen = .detail($0) },
                    onEdit: { screen = .editor($0) }
                )
            case .editor(let id):
                scaffold(title: id == nil ? AppStrings.Loops.newLoop : AppStrings.Loops.editLoop) {
                    VibeLoopEditorView(
                        manager: manager,
                        definition: id.flatMap(manager.definition(withID:)),
                        projectOptions: projectOptions,
                        onSave: { savedID in screen = .detail(savedID) },
                        onCancel: { screen = id.map(Screen.detail) ?? .dashboard },
                        onOpenLane: onOpenLane,
                        onOpenVibes: onOpenVibes
                    )
                    .id(id)
                }
            case .detail(let id):
                scaffold(title: manager.definition(withID: id)?.name ?? AppStrings.Loops.title) {
                    VibeLoopDetailView(
                        manager: manager,
                        loopID: id,
                        onEdit: { screen = .editor(id) },
                        onDeleted: { screen = .dashboard },
                        onOpenTask: { screen = .task(id, $0) }
                    )
                }
            case .task(let loopID, let taskID):
                scaffold(title: AppStrings.VibeLanes.task, back: .detail(loopID)) {
                    VibeLaneTaskDetailView(
                        manager: manager.laneManager,
                        taskID: taskID,
                        onOpenACPSession: { target in
                            guard let store = resolveACPSession(target) else { return }
                            screen = .acp(loopID, taskID, store)
                        },
                        onStop: { pendingStop = PendingStop(loopID: loopID, taskID: $0) }
                    )
                    .id(taskID)
                }
            case .acp(let loopID, let taskID, let store):
                scaffold(title: store.tabTitle, back: .task(loopID, taskID)) {
                    ACPStandalonePaneContentView(
                        store: store,
                        projects: acpProjects,
                        onLinkTargetActivated: nil,
                        onFileSystemTargetActivated: nil
                    )
                }
            }
        }
        .background(palette.canvasBackgroundColor)
        .onChange(of: manager.definitions.map(\.id)) { _, ids in
            switch screen {
            case .detail(let id), .editor(.some(let id)), .task(let id, _), .acp(let id, _, _):
                if !ids.contains(id) { screen = .dashboard }
            case .dashboard, .editor(nil):
                break
            }
        }
        .confirmationDialog(
            AppStrings.Loops.stopRunTitle,
            isPresented: Binding(
                get: { pendingStop != nil },
                set: { if !$0 { pendingStop = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingStop,
               manager.definition(withID: pendingStop.loopID)?.isEnabled == true {
                Button(AppStrings.Loops.stopAndPause, role: .destructive) {
                    Task {
                        if !(await manager.stopRun(
                            loopID: pendingStop.loopID,
                            taskID: pendingStop.taskID,
                            pauseLoop: true
                        )) {
                            actionError = manager.persistenceError ?? AppStrings.Loops.stopFailed
                        }
                        self.pendingStop = nil
                    }
                }
            }
            Button(AppStrings.Loops.stopCurrentRun, role: .destructive) {
                if let pendingStop {
                    Task {
                        if !(await manager.stopRun(
                            loopID: pendingStop.loopID,
                            taskID: pendingStop.taskID,
                            pauseLoop: false
                        )) {
                            actionError = manager.persistenceError ?? AppStrings.Loops.stopFailed
                        }
                        self.pendingStop = nil
                    }
                }
            }
            Button(AppStrings.Loops.cancel, role: .cancel) {
                pendingStop = nil
            }
        } message: {
            Text(AppStrings.Loops.stopRunMessage)
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
            Text(actionError ?? AppStrings.Loops.stopFailed)
        }
    }

    @ViewBuilder
    private func scaffold<Content: View>(
        title: String,
        back: Screen = .dashboard,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: uiScale.spacing(8)) {
                Button { screen = back } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: uiScale.iconSize(12), weight: .semibold))
                        .frame(width: uiScale.chromeSize(28), height: uiScale.chromeSize(28))
                }
                .buttonStyle(.plain)
                .help(AppStrings.Loops.title)
                Text(title)
                    .font(.system(size: uiScale.textSize(14), weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, uiScale.spacing(16))
            .padding(.vertical, uiScale.spacing(8))
            .background(palette.canvasBackgroundColor)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.borderColorValue.opacity(0.5))
                    .frame(height: uiScale.chromeSize(1))
            }

            content()
        }
    }
}
