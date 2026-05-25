import AppKit
import SwiftUI

enum AppSideMenuItem: String, Identifiable {
    case home
    case files
    case git
    case sessions
    case conversations
    case vibespaceSettings
    case crispyvibesSettings
    case help
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .files:
            return "Files"
        case .git:
            return "Git"
        case .sessions:
            return AppStrings.Sidebar.sessionsTab
        case .conversations:
            return "Conversations"
        case .vibespaceSettings:
            return "VibeSpace Settings"
        case .crispyvibesSettings:
            return "Crispy Settings"
        case .help:
            return "Help"
        case .account:
            return "Account"
        }
    }

    var symbolName: String {
        switch self {
        case .home:
            return "house.fill"
        case .files:
            return "folder"
        case .git:
            return "arrow.triangle.branch"
        case .sessions:
            return "square.stack.3d.up"
        case .conversations:
            return "bubble.left.and.bubble.right"
        case .vibespaceSettings:
            return "slider.horizontal.3"
        case .crispyvibesSettings:
            return "gearshape"
        case .help:
            return "questionmark.circle"
        case .account:
            return "person.crop.circle"
        }
    }
}

struct HomeVibeSpaceViewModeToggleButton: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    let canvasMode: VibeSpaceCanvasMode
    let action: () -> Void

    private var targetMode: VibeSpaceCanvasMode {
        canvasMode == .detailed ? .terminalOnly : .detailed
    }

    var body: some View {
        Button(action: action) {
            HomeToolbarIconLabel(systemName: targetMode.symbolName)
        }
        .help(targetMode == .detailed ? AppStrings.Toolbar.switchToDetailed : AppStrings.Toolbar.switchToTerminalBoard)
        .accessibilityLabel(targetMode == .detailed ? AppStrings.Toolbar.switchToDetailed : AppStrings.Toolbar.switchToTerminalBoard)
        .accessibilityIdentifier("toolbar.vibespace-view")
    }
}

struct HomeVibeSpaceRailPositionMenu: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    let selectedProjectRailPosition: ProjectRailPosition
    let action: (ProjectRailPosition) -> Void

    var body: some View {
        Menu {
            ForEach(ProjectRailPosition.allCases) { position in
                Button {
                    action(position)
                } label: {
                    HomeToolbarSelectionLabel(
                        title: position.title,
                        symbolName: position.symbolName,
                        isSelected: position == selectedProjectRailPosition
                    )
                }
            }
        } label: {
            HomeToolbarIconLabel(systemName: selectedProjectRailPosition.symbolName)
        }
        .menuIndicator(.hidden)
        .help("Project Rail Position")
        .accessibilityIdentifier("toolbar.rail-position")
    }
}

struct HomeToolbarIconLabel: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(AppTypographyTokens.scaledIcon(14, weight: .semibold))
            .frame(width: uiScale.iconSize(28), height: uiScale.iconSize(28))
            .contentShape(Rectangle())
    }
}

struct HomeToolbarSelectionLabel: View {
    let title: String
    let symbolName: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
            Text(title)
            if isSelected {
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
            }
        }
    }
}


struct HomeAppSideMenuRailView: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @State private var hoveringItem: AppSideMenuItem?

    let activeItem: AppSideMenuItem?
    let canOpenProjectFiles: Bool
    let canOpenVibeSpaceSettings: Bool
    let onHome: () -> Void
    let onFiles: () -> Void
    let onGit: () -> Void
    let onSessions: () -> Void
    let onConversations: () -> Void
    let onVibeSpaceSettings: () -> Void
    let onAppSettings: (AppSettingsCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                menuButton(item: .home, isActive: activeItem == .home, action: onHome)
            }

            Spacer(minLength: 18)

            VStack(spacing: 10) {
                menuButton(
                    item: .files,
                    isActive: activeItem == .files,
                    isDisabled: !canOpenProjectFiles,
                    action: onFiles
                )

                menuButton(
                    item: .git,
                    isActive: activeItem == .git,
                    isDisabled: !canOpenProjectFiles,
                    action: onGit
                )

                menuButton(
                    item: .sessions,
                    isActive: activeItem == .sessions,
                    isDisabled: !canOpenProjectFiles,
                    action: onSessions
                )

                menuButton(
                    item: .conversations,
                    isActive: activeItem == .conversations,
                    isDisabled: !canOpenProjectFiles,
                    action: onConversations
                )

                menuButton(
                    item: .vibespaceSettings,
                    isActive: activeItem == .vibespaceSettings,
                    isDisabled: !canOpenVibeSpaceSettings,
                    action: onVibeSpaceSettings
                )
            }

            Spacer(minLength: 18)

            VStack(spacing: 10) {
                menuButton(
                    item: .crispyvibesSettings,
                    isActive: activeItem == .crispyvibesSettings,
                    action: { onAppSettings(.general) }
                )

                menuButton(
                    item: .account,
                    isActive: activeItem == .account,
                    action: { onAppSettings(.account) }
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(activeThemePalette.canvasSecondaryBackgroundColor.opacity(0.94))
    }

    private func menuButton(
        item: AppSideMenuItem,
        isActive: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radius(11), style: .continuous)
                    .fill(activeThemePalette.windowBackgroundColor.opacity(hoveringItem == item ? 0.55 : 0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.radius(14), style: .continuous)
                            .stroke(
                                isActive
                                    ? activeThemePalette.accentColor.opacity(0.75)
                                    : activeThemePalette.borderColorValue.opacity(hoveringItem == item ? 0.7 : 0.45),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )

                Image(systemName: item.symbolName)
                    .font(AppTypographyTokens.scaledIcon(item == .home ? 16 : 14, weight: .semibold))
                    .foregroundStyle(activeThemePalette.secondaryTextColor)
            }
            .frame(width: uiScale.chromeSize(34), height: uiScale.chromeSize(34))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveringItem = hovering ? item : nil
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.40 : 1)
        .help(item.title)
        .accessibilityIdentifier("app.side-menu.\(item.rawValue)")
    }
}

extension ContentView {
    private var activeVibeSpaceHasRemoteProjects: Bool {
        activeVibeSpaceSession.projects.contains { $0.metadata.hostLabel != nil }
    }

    private var shouldShowVibeSpaceToolbarControls: Bool {
        activeVibeSpaceID != nil &&
        !isPresentingSurface &&
        !isShowingHome
    }

    private func vibespaceToolbarControl<Control: View>(_ control: Control) -> some View {
        control
            .disabled(!shouldShowVibeSpaceToolbarControls)
            .opacity(shouldShowVibeSpaceToolbarControls ? 1 : 0)
            .accessibilityHidden(!shouldShowVibeSpaceToolbarControls)
    }
}

extension ContentView {
    @ToolbarContentBuilder
    var vibespaceActionsToolbarContent: some ToolbarContent {
        if let activeVibeSpaceID {
            // Group 1: content creation (vibecast / agent / browser) — one pill
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    vibespaceToolbarControl(NewTerminalToolbarButton(
                        projects: activeVibeSpaceSession.projects,
                        focusedProject: activeVibeSpaceSession.focusedProject,
                        colorForProject: { project in
                            vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color
                        },
                        onCreate: { directoryURL, projectPath, preferTemporary in
                            // Post notification — `ContentView` listens and
                            // dispatches based on canvas mode (board tile in
                            // terminal-only mode, temporary spotlight in
                            // detailed mode), honoring `preferTemporary` to
                            // force a spotlight regardless of mode.
                            var userInfo: [String: Any] = [
                                AppCommandUserInfoKey.currentDirectoryURL: directoryURL
                            ]
                            if let projectPath {
                                userInfo[AppCommandUserInfoKey.projectPath] = projectPath
                            }
                            if preferTemporary {
                                userInfo[AppCommandUserInfoKey.preferTemporary] = true
                            }
                            NotificationCenter.default.post(
                                name: .createTerminalRequested,
                                object: nil,
                                userInfo: userInfo
                            )
                        }
                    ))

                    vibespaceToolbarControl(Button {
                        openACPConversationFromToolbar()
                    } label: {
                        HomeToolbarIconLabel(systemName: "sparkles")
                    })
                        .help(AppStrings.ACP.openAgent)
                        .accessibilityIdentifier("toolbar.agent")

                    vibespaceToolbarControl(Button {
                        if selectedVibeSpaceCanvasMode == .detailed {
                            contentViewerStore.openWebPage(
                                url: URL(string: "about:blank")!,
                                projectPath: activeVibeSpaceSession.focusedProject?.rootURL.standardizedFileURL.path
                            )
                        } else {
                            presentBrowserSpotlight(url: nil, projectPath: activeVibeSpaceSession.focusedProject?.rootURL.standardizedFileURL.path)
                        }
                    } label: {
                        HomeToolbarIconLabel(systemName: "globe")
                    })
                        .help("Open Browser")
                        .accessibilityIdentifier("toolbar.open-browser")

                    vibespaceToolbarControl(Button {
                        NotificationCenter.default.post(name: .toggleVibeCast, object: nil)
                    } label: {
                        HomeToolbarIconLabel(systemName: "antenna.radiowaves.left.and.right")
                    })
                        .help(AppStrings.VibeCast.title)
                        .accessibilityIdentifier("toolbar.vibecast")
                }
            }

            // Group 2: vibespace view + management — one pill
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    vibespaceToolbarControl(vibespaceViewToolbarMenu(for: activeVibeSpaceID))

                    if selectedVibeSpaceCanvasMode == .detailed {
                        vibespaceToolbarControl(vibespaceAlignmentToolbarMenu(for: activeVibeSpaceID))
                    }

                    if activeVibeSpaceHasRemoteProjects {
                        vibespaceToolbarControl(RemoteConnectionStatusButton(
                            connectionManager: appContainer.sshConnectionManager,
                            projects: activeVibeSpaceSession.projects
                        ))
                    }

                    vibespaceToolbarControl(Menu {
                        Button {
                            homeCatalogCoordinator.addProjectsToActiveVibeSpaceFromFolderPicker(
                                focusProject: { project, forceTerminalFocus in
                                    vibespaceCanvasActionsCoordinator.focusProject(
                                        project,
                                        forceTerminalFocus: forceTerminalFocus
                                    )
                                },
                                openTerminalOnlyVibeSpaceView: {
                                    vibespaceCanvasActionsCoordinator.openTerminalOnlyVibeSpaceView()
                                }
                            )
                        } label: {
                            Label("Add Local Folder", systemImage: "folder.badge.plus")
                        }
                        Button {
                            addRemoteProjectToVibeSpace(activeVibeSpaceID)
                        } label: {
                            Label("Add Remote Folder", systemImage: "network")
                        }
                    } label: {
                        HomeToolbarIconLabel(systemName: "folder.badge.plus")
                    })
                        .menuStyle(.borderlessButton)
                        .help(AppStrings.Toolbar.addProject)
                        .accessibilityIdentifier("toolbar.add-project")

                    vibespaceToolbarControl(Button(role: .destructive) {
                        homeCatalogCoordinator.closeActiveVibeSpaceSession()
                    } label: {
                        HomeToolbarIconLabel(systemName: "xmark.circle")
                    })
                        .help(AppStrings.VibeSpace.closeVibeSpace)
                        .accessibilityIdentifier("toolbar.close-vibespace")
                }
            }
        }
    }

    func vibespaceViewToolbarMenu(for vibespaceID: UUID) -> some View {
        HomeVibeSpaceViewModeToggleButton(canvasMode: selectedVibeSpaceCanvasMode) {
            layoutPersistence.setCanvasMode(
                selectedVibeSpaceCanvasMode == .detailed ? .terminalOnly : .detailed,
                for: vibespaceID
            )
        }
    }

    @ViewBuilder
    func vibespaceAlignmentToolbarMenu(for vibespaceID: UUID) -> some View {
        if selectedVibeSpaceCanvasMode == .detailed {
            HomeVibeSpaceRailPositionMenu(
                selectedProjectRailPosition: selectedProjectRailPosition
            ) { position in
                defaultRailPositionRaw = position.rawValue
            }
        }
    }

    private var activeAppSideMenuItem: AppSideMenuItem? {
        homeShell.activeAppSideMenuItem(
            hasAnyVibeSpace: hasAnyVibeSpace,
            showsVibeSpaceSidebar: showsVibeSpaceSidebar,
            walkthroughPresented: walkthroughController.isPresented
        )
    }

    private var vibespaceSidebarPrimarySizeBinding: Binding<CGFloat> {
        Binding(
            get: { showsVibeSpaceSidebar ? layoutPersistence.vibespaceSidebarWidth : 0 },
            set: { newValue in
                guard showsVibeSpaceSidebar else { return }
                layoutPersistence.setVibeSpaceSidebarWidth(newValue)
            }
        )
    }

    private var vibespaceSidebarMinPrimary: CGFloat {
        showsVibeSpaceSidebar ? 180 : 0
    }

    private var vibespaceSidebarMaxPrimary: CGFloat {
        showsVibeSpaceSidebar ? .greatestFiniteMagnitude : 0
    }

    private var sidebarPrimaryPane: some View {
        Group {
            if showsVibeSpaceSidebar {
                vibespaceSidebarPanel
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    var shellContent: some View {
        HStack(spacing: 0) {
            if resolvedAppSideMenuDockPosition == .left {
                appSideMenuRail
            }

            let sidebarOnLeft = resolvedAppSideMenuDockPosition == .left
            NativeSplitView(
                isVerticalSplit: true,
                primaryAtEnd: !sidebarOnLeft,
                primarySize: vibespaceSidebarPrimarySizeBinding,
                minPrimary: vibespaceSidebarMinPrimary,
                maxPrimary: vibespaceSidebarMaxPrimary,
                minSecondary: 400
            ) {
                sidebarPrimaryPane
            } secondary: {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if resolvedAppSideMenuDockPosition == .right {
                appSideMenuRail
            }
        }
    }

    var appSideMenuRail: some View {
        HomeAppSideMenuRailView(
            activeItem: activeAppSideMenuItem,
            canOpenProjectFiles: canOpenProjectFilesFromAppMenu,
            canOpenVibeSpaceSettings: canOpenVibeSpaceSettingsFromAppMenu,
            onHome: showHomeCanvas,
            onFiles: { showProjectSidebar(.files) },
            onGit: { showProjectSidebar(.git) },
            onSessions: { showProjectSidebar(.sessions) },
            onConversations: { showProjectSidebar(.conversations) },
            onVibeSpaceSettings: showVibeSpaceSettingsFromAppMenu,
            onAppSettings: { category in showAppSettingsFromAppMenu(category: category) }
        )
    }
}
