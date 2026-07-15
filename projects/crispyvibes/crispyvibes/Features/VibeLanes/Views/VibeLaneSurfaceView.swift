import SwiftUI

// F059 — the Vibe Lanes surface entry point and its screen router. The
// individual screens live in their own files (VibeLaneDashboardView,
// VibeLaneNewTaskView, VibeLaneLanesView, VibeLaneTaskDetailView,
// VibeLaneEditorView) per one-primary-type-per-file (coding-guidelines).

/// What the surface asks the host to open when the user taps a task's chat.
struct VibeLaneACPChatTarget: Equatable {
    var sessionID: UUID?
    var threadID: String?
    var projectPath: String
}

@MainActor
struct VibeLaneSurfaceView: View {
    @Environment(\.vibeLaneTaskManagerEnvironment) private var manager
    @Environment(\.vibeLaneSurfaceNavigationEnvironment) private var injectedNavigation
    @Environment(\.appThemePalette) private var palette
    let focusedProjectPath: String?
    let onOpenACPSession: (VibeLaneACPChatTarget) -> Void
    /// F060: opens detected file-path links (outcome, handoffs, activity log)
    /// in the content viewer. nil = links fall back to the system handler.
    let onOpenFileTarget: ((TerminalFileSystemTarget) -> Void)?

    @StateObject private var fallbackNavigation = VibeLaneSurfaceNavigationViewModel()

    private var navigation: VibeLaneSurfaceNavigationViewModel {
        injectedNavigation ?? fallbackNavigation
    }

    init(
        focusedProjectPath: String? = nil,
        onOpenACPSession: @escaping (VibeLaneACPChatTarget) -> Void = { _ in },
        onOpenFileTarget: ((TerminalFileSystemTarget) -> Void)? = nil
    ) {
        self.focusedProjectPath = focusedProjectPath
        self.onOpenACPSession = onOpenACPSession
        self.onOpenFileTarget = onOpenFileTarget
    }

    var body: some View {
        Group {
            if let manager {
                VibeLaneSurfaceContentView(
                    manager: manager,
                    navigation: navigation,
                    focusedProjectPath: focusedProjectPath,
                    onOpenACPSession: onOpenACPSession
                )
            } else {
                ContentUnavailableView(AppStrings.VibeLanes.unavailable, systemImage: "rectangle.stack.badge.play")
                    .background(palette.canvasBackgroundColor)
            }
        }
        // F060 — path links detected in lane text open like terminal-board
        // paths; plain web links keep their default behavior.
        .environment(\.openURL, OpenURLAction { url in
            guard let onOpenFileTarget else { return .systemAction(url) }
            return ACPTextLinking.handle(
                url: url,
                onLinkTargetActivated: nil,
                onFileSystemTargetActivated: onOpenFileTarget
            )
        })
    }
}

@MainActor
private struct VibeLaneSurfaceContentView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var manager: VibeLaneTaskManager
    @ObservedObject var navigation: VibeLaneSurfaceNavigationViewModel
    let focusedProjectPath: String?
    let onOpenACPSession: (VibeLaneACPChatTarget) -> Void

    @ViewBuilder
    var body: some View {
        content
            .onAppear(perform: validateNavigationSelection)
            .onChange(of: manager.tasks.map(\.id)) { _, _ in validateNavigationSelection() }
            .onChange(of: manager.lanes.map(\.id)) { _, _ in validateNavigationSelection() }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.screen {
        case .dashboard:
            VibeLaneDashboardView(
                manager: manager,
                onNewTask: { navigation.showNewTask() },
                onOpenTask: { navigation.showTask($0) },
                onShowLanes: { navigation.showLanes() }
            )
        case .newTask:
            screenScaffold(title: AppStrings.VibeLanes.newTask, back: .dashboard) {
                VibeLaneNewTaskView(
                    manager: manager,
                    focusedProjectPath: focusedProjectPath,
                    onStarted: { navigation.showTask($0) },
                    onCancel: { navigation.showDashboard() }
                )
            }
        case .detail(let id):
            screenScaffold(title: AppStrings.VibeLanes.task, back: .dashboard) {
                VibeLaneTaskDetailView(
                    manager: manager,
                    taskID: id,
                    onOpenACPSession: onOpenACPSession
                )
                .id(id)
            }
        case .lanes:
            screenScaffold(title: AppStrings.VibeLanes.lanes, back: .dashboard) {
                VibeLaneLanesView(
                    manager: manager,
                    onEdit: { navigation.showLaneEditor(id: $0) },
                    onNew: {
                        let lane = manager.createLane()
                        navigation.showLaneEditor(id: lane.id)
                    }
                )
            }
        case .laneEditor(let id):
            screenScaffold(title: AppStrings.VibeLanes.editLane, back: .lanes) {
                if let lane = manager.lane(withID: id) {
                    VibeLaneEditorView(
                        lane: lane,
                        onSave: { manager.updateLane($0) },
                        onDelete: {
                            manager.deleteLane(id: id)
                            navigation.showLanes()
                        }
                    )
                } else {
                    ContentUnavailableView(AppStrings.VibeLanes.laneNotFound, systemImage: "questionmark.circle")
                }
            }
        }
    }

    private func validateNavigationSelection() {
        navigation.validateSelection(
            taskExists: { manager.task(withID: $0) != nil },
            laneExists: { manager.lane(withID: $0) != nil }
        )
    }

    @ViewBuilder
    private func screenScaffold<Content: View>(
        title: String,
        back: VibeLaneSurfaceNavigationViewModel.Screen,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: uiScale.spacing(6)) {
                Button { navigation.show(back) } label: {
                    HStack(spacing: uiScale.spacing(4)) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: uiScale.iconSize(10), weight: .semibold))
                        Text(backTitle(for: back))
                            .font(.system(size: uiScale.textSize(13), weight: .medium))
                    }
                    .padding(.horizontal, uiScale.spacing(8))
                    .padding(.vertical, uiScale.spacing(4))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .vibeLaneHoverable(cornerRadius: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: uiScale.iconSize(8), weight: .semibold))
                    .foregroundStyle(palette.tertiaryTextColor)

                Text(title)
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    .foregroundStyle(palette.primaryTextColor)
                Spacer()
            }
            .padding(.horizontal, uiScale.spacing(16))
            .padding(.vertical, uiScale.spacing(9))
            .background(.bar)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.tertiaryTextColor.opacity(0.14)).frame(height: 1)
            }

            content()
        }
        .background(palette.canvasBackgroundColor)
    }

    private func backTitle(for screen: VibeLaneSurfaceNavigationViewModel.Screen) -> String {
        switch screen {
        case .dashboard:
            AppStrings.VibeLanes.dashboard
        case .lanes:
            AppStrings.VibeLanes.lanes
        case .newTask:
            AppStrings.VibeLanes.newTask
        case .detail:
            AppStrings.VibeLanes.task
        case .laneEditor:
            AppStrings.VibeLanes.editLane
        }
    }
}
