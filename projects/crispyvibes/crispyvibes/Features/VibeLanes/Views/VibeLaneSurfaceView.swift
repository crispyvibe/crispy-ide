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
    var managedSessionEnded = false
}

@MainActor
struct VibeLaneSurfaceView: View {
    @Environment(\.vibeLaneTaskManagerEnvironment) private var manager
    @Environment(\.vibeLaneSurfaceNavigationEnvironment) private var injectedNavigation
    @Environment(\.appThemePalette) private var palette
    let rootScreen: VibeLaneSurfaceNavigationViewModel.Screen
    let focusedProjectPath: String?
    let onOpenACPSession: (VibeLaneACPChatTarget) -> Void
    /// Set by hosts that show a task's worker/reviewer chat inside this surface
    /// (Automation) instead of handing it to a vibespace pane.
    let resolveACPSession: ((VibeLaneACPChatTarget) -> ACPStandaloneSessionStore?)?
    let acpProjects: [AnyProjectSession]
    /// F060: opens detected file-path links (outcome, handoffs, activity log)
    /// in the content viewer. nil = links fall back to the system handler.
    let onOpenFileTarget: ((TerminalFileSystemTarget) -> Void)?

    @StateObject private var fallbackNavigation = VibeLaneSurfaceNavigationViewModel()

    private var navigation: VibeLaneSurfaceNavigationViewModel {
        injectedNavigation ?? fallbackNavigation
    }

    init(
        rootScreen: VibeLaneSurfaceNavigationViewModel.Screen = .dashboard,
        focusedProjectPath: String? = nil,
        onOpenACPSession: @escaping (VibeLaneACPChatTarget) -> Void = { _ in },
        resolveACPSession: ((VibeLaneACPChatTarget) -> ACPStandaloneSessionStore?)? = nil,
        acpProjects: [AnyProjectSession] = [],
        onOpenFileTarget: ((TerminalFileSystemTarget) -> Void)? = nil
    ) {
        self.rootScreen = rootScreen
        self.focusedProjectPath = focusedProjectPath
        self.onOpenACPSession = onOpenACPSession
        self.resolveACPSession = resolveACPSession
        self.acpProjects = acpProjects
        self.onOpenFileTarget = onOpenFileTarget
    }

    var body: some View {
        Group {
            if let manager {
                VibeLaneSurfaceContentView(
                    manager: manager,
                    navigation: navigation,
                    rootScreen: rootScreen,
                    focusedProjectPath: focusedProjectPath,
                    onOpenACPSession: onOpenACPSession,
                    resolveACPSession: resolveACPSession,
                    acpProjects: acpProjects
                )
            } else {
                ContentUnavailableView(
                    AppStrings.VibeLanes.unavailable,
                    systemImage: VibeLaneVisualIdentity.symbolName
                )
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
    let rootScreen: VibeLaneSurfaceNavigationViewModel.Screen
    let focusedProjectPath: String?
    let onOpenACPSession: (VibeLaneACPChatTarget) -> Void
    let resolveACPSession: ((VibeLaneACPChatTarget) -> ACPStandaloneSessionStore?)?
    let acpProjects: [AnyProjectSession]

    @ViewBuilder
    var body: some View {
        content
            .onAppear(perform: validateNavigationSelection)
            .onChange(of: manager.tasks.map(\.id)) { _, _ in validateNavigationSelection() }
            .onChange(of: manager.lanes.map(\.id)) { _, _ in validateNavigationSelection() }
            .onChange(of: manager.vibes.map(\.id)) { _, _ in validateNavigationSelection() }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.screen {
        case .dashboard:
            VibeLaneDashboardView(
                manager: manager,
                onNewTask: { navigation.showNewTask() },
                onOpenTask: { navigation.showTask($0) },
                onShowLanes: { navigation.showLanes() },
                onShowVibes: { navigation.showVibes() }
            )
        case .newTask(let laneID):
            screenScaffold(title: AppStrings.VibeLanes.newTask, back: rootScreen) {
                VibeLaneNewTaskView(
                    manager: manager,
                    focusedProjectPath: focusedProjectPath,
                    preselectedLaneID: laneID,
                    onStarted: { navigation.showTask($0) },
                    onCancel: { navigation.show(rootScreen) }
                )
            }
        case .detail(let id):
            screenScaffold(title: AppStrings.VibeLanes.task, back: rootScreen) {
                VibeLaneTaskDetailView(
                    manager: manager,
                    taskID: id,
                    onOpenACPSession: { target in
                        // Hosts that can render the chat in place do so; the rest
                        // hand it to their own pane (vibespace tabs, board tiles).
                        if resolveACPSession != nil {
                            navigation.showACPSession(target: target, taskID: id)
                        } else {
                            onOpenACPSession(target)
                        }
                    }
                )
                .id(id)
            }
        case .acp(let target, let taskID):
            screenScaffold(
                title: AppStrings.VibeLanes.task,
                back: .detail(taskID)
            ) {
                if let store = resolveACPSession?(target) {
                    ACPStandalonePaneContentView(
                        store: store,
                        projects: acpProjects,
                        onLinkTargetActivated: nil,
                        onFileSystemTargetActivated: nil
                    )
                } else {
                    ContentUnavailableView(
                        AppStrings.ACP.managedSessionEndedTitle,
                        systemImage: "message",
                        description: Text(AppStrings.ACP.managedSessionEndedDescription)
                    )
                }
            }
        case .lanes:
            if rootScreen == .lanes {
                lanesView
            } else {
                screenScaffold(title: AppStrings.VibeLanes.lanes, back: .dashboard) {
                    lanesView
                }
            }
        case .laneEditor(let id):
            screenScaffold(title: AppStrings.VibeLanes.editLane, back: .lanes) {
                if let lane = manager.lane(withID: id) {
                    VibeLaneEditorView(
                        lane: lane,
                        vibes: manager.vibes,
                        onSave: { lane in
                            await manager.updateLane(lane)
                        },
                        onDelete: {
                            Task {
                                await manager.deleteLane(id: id)
                                navigation.showLanes()
                            }
                        },
                        onEditVibe: {
                            navigation.showVibeEditor(id: $0, fromLaneID: id)
                        },
                        onNewVibe: {
                            Task {
                                guard let vibe = await manager.createVibe() else { return }
                                navigation.showVibeEditor(id: vibe.id, fromLaneID: id)
                            }
                        }
                    )
                } else {
                    ContentUnavailableView(AppStrings.VibeLanes.laneNotFound, systemImage: "questionmark.circle")
                }
            }
        case .vibes:
            if rootScreen == .vibes {
                vibesView
            } else {
                screenScaffold(title: AppStrings.VibeLanes.vibes, back: .dashboard) {
                    vibesView
                }
            }
        case .vibeEditor(let id, let laneID):
            screenScaffold(
                title: AppStrings.VibeLanes.editVibe,
                back: laneID.map(VibeLaneSurfaceNavigationViewModel.Screen.laneEditor) ?? .vibes
            ) {
                if let vibe = manager.vibe(withID: id) {
                    VibeEditorView(
                        vibe: vibe,
                        usageCount: manager.vibeUsageCount(id: id),
                        categories: VibeCategory.available(
                            in: manager.vibes,
                            including: vibe.category
                        ),
                        engineOptionCatalog: manager.engineOptionCatalog,
                        onSave: { vibe in
                            await manager.updateVibe(vibe)
                        },
                        onDelete: {
                            Task {
                                guard await manager.deleteVibe(id: id) else { return }
                                if let laneID {
                                    navigation.showLaneEditor(id: laneID)
                                } else {
                                    navigation.showVibes()
                                }
                            }
                        }
                    )
                } else {
                    ContentUnavailableView(AppStrings.VibeLanes.vibeNotFound, systemImage: "questionmark.circle")
                }
            }
        }
    }

    private var lanesView: some View {
        VibeLaneLanesView(
            manager: manager,
            onEdit: { navigation.showLaneEditor(id: $0) },
            onNew: {
                Task {
                    guard let lane = await manager.createLane() else { return }
                    navigation.showLaneEditor(id: lane.id)
                }
            },
            onStartTask: { navigation.showNewTask(laneID: $0) }
        )
    }

    private var vibesView: some View {
        VibeLibraryView(
            manager: manager,
            onEdit: { navigation.showVibeEditor(id: $0) },
            onNew: {
                Task {
                    guard let vibe = await manager.createVibe() else { return }
                    navigation.showVibeEditor(id: vibe.id)
                }
            }
        )
    }

    private func validateNavigationSelection() {
        navigation.validateSelection(
            taskExists: { manager.task(withID: $0) != nil },
            laneExists: { manager.lane(withID: $0) != nil },
            vibeExists: { manager.vibe(withID: $0) != nil }
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
                .foregroundStyle(palette.accentColor)
                .vibeLaneHoverable(cornerRadius: uiScale.chromeSize(6))

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
            .background(palette.canvasBackgroundColor)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.borderColorValue.opacity(0.42))
                    .frame(height: uiScale.chromeSize(1))
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
        case .vibes:
            AppStrings.VibeLanes.vibes
        case .vibeEditor:
            AppStrings.VibeLanes.editVibe
        case .acp:
            AppStrings.VibeLanes.task
        }
    }
}
