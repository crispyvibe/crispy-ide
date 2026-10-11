import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentViewerView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    @ObservedObject var store: ContentViewerStore
    @ObservedObject var splitStore: SplitViewStore
    @ObservedObject var activityTracker: ProjectActivityTracker
    @ObservedObject var acpVibeSpaceSessionService: ACPVibeSpaceSessionService
    var vibespaceID: UUID? = nil
    var projects: [AnyProjectSession] = []
    var focusedProjectRootPath: String? = nil
    var projectColorTagsByPath: [String: ProjectColorTag] = [:]
    var showsTopBar: Bool = true
    var terminalSessionResolver: ((UUID, UUID) -> TerminalSession?)? = nil
    var dockedBrowserCoordinator: DockedBrowserCoordinator? = nil
    var onLinkTargetActivated: ((URL) -> Void)? = nil
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil
    /// F049: optional central comment store. When non-nil and the active tab
    /// is a file, the comments side-panel docks on the right.
    var commentStore: VibeSpaceCommentStore? = nil
    @Environment(\.vibespaceTodoStoreEnvironment) private var todoStore
    @Environment(\.todoLanePipelineBridgeEnvironment) private var todoPipelineBridge
    @Environment(\.vibeLaneSurfaceNavigationEnvironment) private var vibeLaneNavigation
    @State private var dropZone: EditorDropZone?
    @State private var isDropTargeted = false

    private func contentAreaDropTypes(for activeTab: ContentViewerTab?) -> [UTType] {
        ContentViewerTabDragSupport.contentAreaDropTypes(for: activeTab?.kind)
    }

    var body: some View {
        Group {
            if splitStore.isSplit {
                splitContentArea
            } else {
                SinglePaneContentViewerObserverScope(
                    group: splitStore.activeGroup,
                    viewerScope: store.viewerScope,
                    focusedProjectRootPath: focusedProjectRootPath
                ) { group, visibleTabs, visibleActiveTab in
                    singlePaneContent(
                        group: group,
                        visibleTabs: visibleTabs,
                        visibleActiveTab: visibleActiveTab
                    )
                }
            }
        }
        .background(appThemePalette.canvasBackgroundColor)
        .crispyvibesContainerBorder(opacity: 0.6)
        .overlay(alignment: .topLeading) { accessibilityStateMarker }
    }

    private func singlePaneContent(
        group: EditorGroupStore,
        visibleTabs: [ContentViewerTab],
        visibleActiveTab: ContentViewerTab?
    ) -> some View {
        VStack(spacing: 0) {
            if showsTopBar {
                tabStrip(group: group, visibleTabs: visibleTabs)
                Divider()
            }
            GeometryReader { proxy in
                singleContentArea(group: group, activeTab: visibleActiveTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("content-viewer.drop-surface")
                    .overlay {
                        if isDropTargeted {
                            EditorDropZoneOverlay(hoveredZone: dropZone)
                        }
                    }
                    .onDrop(
                        of: contentAreaDropTypes(for: visibleActiveTab),
                        delegate: EditorSplitDropDelegate(
                            size: proxy.size,
                            dropZone: $dropZone,
                            isTargeted: $isDropTargeted,
                            activeGroup: group,
                            splitStore: splitStore
                        )
                    )
            }
        }
    }

    // MARK: - Tab strip

    private func tabStrip(
        group: EditorGroupStore,
        visibleTabs: [ContentViewerTab]
    ) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(visibleTabs) { tab in
                        tabItem(tab, group: group)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            if projects.count > 1 {
                scopeToggle.padding(.trailing, 8)
            }
        }
        .frame(minHeight: CrispyVibesHeaderStyle.panel.minHeight(scale: AppPreferences.chromeScale(forCodeFontSize: codeFontSize)))
        .background(appThemePalette.canvasSecondaryBackgroundColor)
        .accessibilityIdentifier("content-viewer.tab.strip")
    }

    private var scopeToggle: some View {
        Picker("", selection: $store.viewerScope) {
            Image(systemName: "folder").tag(ViewerScope.focusedProject)
            Image(systemName: "square.grid.2x2").tag(ViewerScope.allProjects)
        }
        .pickerStyle(.segmented)
        .frame(width: 60)
        .help(store.viewerScope == .focusedProject
              ? String(localized: "contentViewer.scope.focusedProject")
              : String(localized: "contentViewer.scope.allProjects"))
        .accessibilityIdentifier("content-viewer.scope-toggle")
    }

    private func tabItem(_ tab: ContentViewerTab, group: EditorGroupStore) -> some View {
        let isActive = group.activeTabID == tab.id
        let projectColor = ContentViewerTab.projectColor(
            for: tab,
            projectColorTagsByPath: projectColorTagsByPath,
            fallback: appThemePalette.accentColor
        )
        return ContentViewerTabItemView(
            tab: tab,
            isActive: isActive,
            projectColor: projectColor,
            compact: false,
            browserViewModel: browserViewModel(for: tab),
            acpChatViewModel: acpChatViewModel(for: tab),
            onClose: { closeTab(tab) },
            onSelect: { group.activateTab(tab.id) }
        )
    }

    private func closeTab(_ tab: ContentViewerTab) {
        store.closeTab(tab)
    }

    private func browserViewModel(for tab: ContentViewerTab) -> BrowserPanelViewModel? {
        guard case .webPage(let reference) = tab.kind,
              let dockedBrowserCoordinator else { return nil }
        return dockedBrowserCoordinator.viewModel(for: reference)
    }

    private func acpChatViewModel(for tab: ContentViewerTab) -> ACPChatViewModel? {
        guard case .acpPane(let id) = tab.kind else { return nil }
        return store.acpStore(for: id)?.chatViewModel
    }

    // MARK: - Content area

    private var splitContentArea: some View {
        SplitContainerView(node: splitStore.root, store: splitStore) { paneID in
            AnyView(
                SplitPaneContentView(
                    paneID: paneID,
                    isActive: splitStore.activePaneID == paneID,
                    splitStore: splitStore,
                    group: splitStore.group(for: paneID),
                    contentViewerStore: store,
                    vibespaceID: vibespaceID,
                    projects: projects,
                    viewerScope: store.viewerScope,
                    focusedProjectRootPath: focusedProjectRootPath,
                    projectColorTagsByPath: projectColorTagsByPath,
                    activityTracker: activityTracker,
                    vibeCastView: vibeCastViewFactory(),
                    todosView: todosViewFactory(),
                    terminalSessionResolver: terminalSessionResolver,
                    dockedBrowserCoordinator: dockedBrowserCoordinator,
                    onLinkTargetActivated: onLinkTargetActivated,
                    onFileSystemTargetActivated: onFileSystemTargetActivated,
                    commentStore: commentStore,
                    onActivate: { splitStore.activePaneID = paneID }
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func singleContentArea(
        group: EditorGroupStore,
        activeTab: ContentViewerTab?
    ) -> some View {
        if let activeTab {
            ContentTabRoutedContentScope(tabID: activeTab.id, paneID: group.id) {
                singleRoutedContent(activeTab: activeTab, group: group)
            }
        } else {
            ContentUnavailableView(
                AppStrings.ContentViewer.noContent,
                systemImage: "doc.text",
                description: Text(AppStrings.ContentViewer.noContentDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func singleRoutedContent(
        activeTab: ContentViewerTab,
        group: EditorGroupStore
    ) -> some View {
        switch activeTab.kind {
        case .file(let reference):
            fileContentArea(
                group: group,
                filePath: reference.url.path
            )
        case .vibeCast:
            if !projects.isEmpty {
                vibeCastContent
            } else {
                ContentUnavailableView(
                    AppStrings.VibeCast.noTerminal,
                    systemImage: "terminal",
                    description: Text(AppStrings.VibeCast.noTerminalDescription)
                )
            }
        case .todos:
            todosContent
        case .vibeLanes:
            VibeLaneSurfaceView(
                focusedProjectPath: focusedProjectRootPath,
                onOpenACPSession: {
                    store.openVibeLaneACPPane(
                        target: $0,
                        projects: projects,
                        vibespaceID: vibespaceID
                    )
                },
                onOpenFileTarget: { target in
                    openTodoFileAction(target.url.path, target.line)
                }
            )
        case .webPage(let reference):
            WebPageTabView(
                reference: reference,
                coordinator: dockedBrowserCoordinator,
                onTitleChanged: { title in
                    group.updateTabTitle(activeTab.id, title: title)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .terminal(let projectID, let tabID):
            terminalTabContent(projectID: projectID, tabID: tabID)
        case .acpPane(let storeID):
            if let acpStore = store.acpStore(for: storeID) {
                ACPStandalonePaneContentView(
                    store: acpStore,
                    projects: projects,
                    onLinkTargetActivated: onLinkTargetActivated,
                    onFileSystemTargetActivated: onFileSystemTargetActivated
                )
            } else {
                ContentUnavailableView(
                    AppStrings.ACP.unavailableTitle,
                    systemImage: "sparkles",
                    description: Text(AppStrings.ACP.unavailableDescription)
                )
            }
        }
    }

    @ViewBuilder
    private func terminalTabContent(projectID: UUID, tabID: UUID) -> some View {
        if let session = terminalSessionResolver?(projectID, tabID) {
            TerminalSessionHostView(
                session: session,
                displayDensity: .regular,
                isActive: true,
                accessibilityIdentifier: "content-viewer.terminal.host",
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                String(localized: "contentViewer.terminalUnavailable"),
                systemImage: "terminal",
                description: Text(String(localized: "contentViewer.terminalUnavailable.description"))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// F049-R06: file content area, optionally docked with the comments side
    /// panel. The editor view itself owns the in-editor overlay + floating
    /// button. This wrapper just docks the panel.
    private func fileContentArea(
        group: EditorGroupStore,
        filePath: String
    ) -> some View {
        FileContentWithCommentsPanel(
            panel: group.commentsPanel,
            store: commentStore,
            filePath: filePath,
            editorContent: {
                MarkdownEditorView(
                    viewModel: group.markdownViewModel,
                    showsTopBar: false,
                    embeddedDropBridge: embeddedDropBridge(for: group)
                )
                .environment(\.vibespaceCommentStoreEnvironment, commentStore)
                .environment(\.commentsPanelEnvironment, group.commentsPanel)
                .environment(\.commentsFilePathEnvironment, filePath)
            }
        )
    }

    private var vibeCastContent: some View {
        VibeCastView(
            store: store.vibeCastStore,
            terminalSources: projects.map { project in
                let color = projectColorTagsByPath[project.rootURL.standardizedFileURL.path]?.color ?? appThemePalette.accentColor
                    return .init(
                        id: project.id.uuidString,
                        projectTitle: project.title,
                        projectRootURL: project.rootURL,
                        accentColor: color,
                        viewModel: project.terminalViewModel
                    )
                }
        ).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessibilityStateMarker: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(splitStore.isSplit ? "content-viewer.state.split" : "content-viewer.state.single")
    }

    @ViewBuilder
    private var todosContent: some View {
        if let todoStore {
            TodosSurfaceView(
                store: todoStore,
                focusedProjectPath: focusedProjectRootPath,
                onRefine: refineTodoAction,
                onOpenFile: openTodoFileAction,
                onOpenLaneTask: openLaneTaskAction
            )
        } else {
            ContentUnavailableView(AppStrings.Todos.title, systemImage: "checklist")
        }
    }

    private func todosViewFactory() -> (() -> AnyView)? {
        guard let todoStore else { return nil }
        let path = focusedProjectRootPath
        let refine = refineTodoAction
        let openFile = openTodoFileAction
        let openTask = openLaneTaskAction
        return { AnyView(TodosSurfaceView(store: todoStore, focusedProjectPath: path, onRefine: refine, onOpenFile: openFile, onOpenLaneTask: openTask)) }
    }

    /// F060 — the linked-task chip jumps straight to the task's detail: point
    /// the shared lanes navigation at the task, then open/activate the surface.
    private var openLaneTaskAction: ((UUID) -> Void)? {
        guard let vibeLaneNavigation else { return nil }
        return { taskID in
            vibeLaneNavigation.show(.detail(taskID))
            store.openVibeLanes()
        }
    }

    /// F060 — file links open like any file: absolute path, optional line
    /// anchor, project optional (standalone tabs for external paths).
    private var openTodoFileAction: (String, Int?) -> Void {
        { path, line in
            store.openFileInTab(
                at: URL(fileURLWithPath: path),
                line: line,
                projectIdentifier: projects.first {
                    path.hasPrefix($0.rootURL.standardizedFileURL.path + "/")
                }?.projectIdentifier
            )
        }
    }

    /// F060 — open (or reattach) the todo's refine chat as an ACP pane. New
    /// sessions are seeded by the bridge; reattach resolves the persisted
    /// session ID through the registry and falls back to a fresh session.
    private var refineTodoAction: ((Todo) -> Void)? {
        guard let bridge = todoPipelineBridge else { return nil }
        return { todo in
            let projectPath = todo.projectPath ?? focusedProjectRootPath
            let project = projects.first { $0.rootURL.standardizedFileURL.path == projectPath }
                ?? projects.first
            Task { @MainActor in
                await bridge.openRefineSession(
                    todoID: todo.id,
                    reattach: { sessionID in
                        guard let id = UUID(uuidString: sessionID),
                              store.sessionRegistry.store(forID: id) != nil else { return false }
                        store.ensureACPPaneTab(id: id)
                        return true
                    },
                    openNew: {
                        let pane = store.openACPPane(
                            focusedProject: project,
                            preferredAgentID: AppPreferences.acpDefaultAgentID(),
                            vibespaceID: vibespaceID
                        )
                        return (pane.id.uuidString, { prompt in
                            Task { @MainActor in
                                _ = await pane.chatViewModel.sendProgrammatic(prompt)
                            }
                        })
                    }
                )
            }
        }
    }

    private func vibeCastViewFactory() -> (() -> AnyView)? {
        guard !projects.isEmpty else { return nil }
        return { [store, projects, projectColorTagsByPath, appThemePalette] in
            AnyView(VibeCastView(
                store: store.vibeCastStore,
                terminalSources: projects.map { project in
                    let color = projectColorTagsByPath[project.rootURL.standardizedFileURL.path]?.color ?? appThemePalette.accentColor
                    return .init(
                        id: project.id.uuidString,
                        projectTitle: project.title,
                        projectRootURL: project.rootURL,
                        accentColor: color,
                        viewModel: project.terminalViewModel
                    )
                }
            ))
        }
    }

    private func embeddedDropBridge(for group: EditorGroupStore) -> ContentViewerEmbeddedDropBridge {
        ContentViewerEmbeddedDropBridge(
            updateTargeting: { location, size in
                isDropTargeted = true
                dropZone = EditorDropZoneOverlay.zone(at: location, in: size)
            },
            clearTargeting: {
                isDropTargeted = false
                dropZone = nil
            },
            performDrop: { item, location, size in
                let zone = EditorDropZoneOverlay.zone(at: location, in: size)
                isDropTargeted = false
                dropZone = nil
                handleEmbeddedDrop(item: item, zone: zone, group: group)
                return true
            }
        )
    }

    private func handleEmbeddedDrop(
        item: ContentViewerDropItem,
        zone: EditorDropZone,
        group: EditorGroupStore
    ) {
        let tab: ContentViewerTab
        switch item {
        case .tab(let droppedTab):
            tab = droppedTab
        case .file(let url):
            tab = .file(url: url)
        }

        if zone == .center {
            splitStore.moveTab(tab, to: group)
        } else {
            let orientation: SplitOrientation = (zone == .left || zone == .right) ? .horizontal : .vertical
            splitStore.splitActiveWithTab(tab, orientation: orientation)
        }
    }
}

@MainActor
struct SinglePaneContentViewerObserverScope<Content: View>: View {
    @ObservedObject var group: EditorGroupStore
    let viewerScope: ViewerScope
    let focusedProjectRootPath: String?
    let content: (
        EditorGroupStore,
        [ContentViewerTab],
        ContentViewerTab?
    ) -> Content

    init(
        group: EditorGroupStore,
        viewerScope: ViewerScope,
        focusedProjectRootPath: String?,
        @ViewBuilder content: @escaping (
            EditorGroupStore,
            [ContentViewerTab],
            ContentViewerTab?
        ) -> Content
    ) {
        self.group = group
        self.viewerScope = viewerScope
        self.focusedProjectRootPath = focusedProjectRootPath
        self.content = content
    }

    private var visibleTabs: [ContentViewerTab] {
        group.filteredTabs(
            scope: viewerScope,
            focusedProjectRootPath: focusedProjectRootPath
        )
    }

    private var visibleTabIDs: [String] {
        visibleTabs.map(\.id)
    }

    private var visibleActiveTab: ContentViewerTab? {
        guard let activeTabID = group.activeTabID,
              let activeTab = visibleTabs.first(where: { $0.id == activeTabID }),
              activeTab.id == group.activeTabID else { return nil }
        return activeTab
    }

    var body: some View {
        content(group, visibleTabs, visibleActiveTab)
            .onAppear(perform: reconcileActiveSelection)
            .onChange(of: visibleTabIDs) { _, _ in
                reconcileActiveSelection()
            }
            .onChange(of: group.activeTabID) { _, _ in
                reconcileActiveSelection()
            }
    }

    private func reconcileActiveSelection() {
        group.reconcileActiveSelection(visibleTabIDs: visibleTabIDs)
    }
}

@MainActor
struct ContentTabRoutedContentScope<Content: View>: View {
    let tabID: String
    let paneID: UUID?
    let content: () -> Content

    init(
        tabID: String,
        paneID: UUID?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tabID = tabID
        self.paneID = paneID
        self.content = content
    }

    var body: some View {
        content()
            .id(tabID)
            .onAppear {
                var metadata = ["tab": AppDiagnostics.pathToken(tabID)]
                if let paneID {
                    metadata["pane"] = AppDiagnostics.pathToken(paneID.uuidString)
                }
                AppDiagnostics.record(
                    category: .vibespaceLifecycle,
                    level: .info,
                    event: "content_tab_rendered",
                    metadata: metadata
                )
            }
    }
}

// MARK: - Single-pane Drop Delegate

private struct EditorSplitDropDelegate: DropDelegate {
    let size: CGSize
    @Binding var dropZone: EditorDropZone?
    @Binding var isTargeted: Bool
    let activeGroup: EditorGroupStore
    let splitStore: SplitViewStore

    func dropEntered(info: DropInfo) { isTargeted = true; dropZone = EditorDropZoneOverlay.zone(at: info.location, in: size) }
    func dropUpdated(info: DropInfo) -> DropProposal? { dropZone = EditorDropZoneOverlay.zone(at: info.location, in: size); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { isTargeted = false; dropZone = nil }

    func performDrop(info: DropInfo) -> Bool {
        let zone = dropZone ?? .center
        isTargeted = false; dropZone = nil

        return ContentViewerTabDragSupport.loadDropItem(from: info.itemProviders(for: ContentViewerTabDragSupport.dropTypes)) { item in
            guard let item else { return }
            DispatchQueue.main.async { handleDrop(item: item, zone: zone) }
        }
    }

    private func handleDrop(item: ContentViewerDropItem, zone: EditorDropZone) {
        let tab: ContentViewerTab
        switch item {
        case .tab(let droppedTab):
            tab = droppedTab
        case .file(let url):
            tab = .file(url: url)
        }

        if zone == .center {
            splitStore.moveTab(tab, to: activeGroup)
        } else {
            let orientation: SplitOrientation = (zone == .left || zone == .right) ? .horizontal : .vertical
            splitStore.splitActiveWithTab(tab, orientation: orientation)
        }
    }
}

private struct WebPageTabView: View {
    let reference: BrowserTabReference
    let coordinator: DockedBrowserCoordinator?
    var onTitleChanged: ((String) -> Void)? = nil

    init(reference: BrowserTabReference, coordinator: DockedBrowserCoordinator? = nil, onTitleChanged: ((String) -> Void)? = nil) {
        self.reference = reference
        self.coordinator = coordinator
        self.onTitleChanged = onTitleChanged
    }

    var body: some View {
        // The coordinator is optional only for testing/preview environments. In
        // production, `AppContainer` always provides one, and `ContentViewerStore.openWebPage`
        // eagerly populates `detailedViewGroups[browserID]` so the lookup here always
        // returns a stable instance. No fallback `@StateObject` is needed.
        if let coordinator {
            let viewModel = coordinator.viewModel(for: reference)
            BrowserContentView(viewModel: viewModel)
                .accessibilityIdentifier("content-viewer.webpage")
                .onAppear { syncTitle(viewModel: viewModel) }
                .onChange(of: viewModel.currentURL) { _, _ in syncTitle(viewModel: viewModel) }
        } else {
            Color.clear
                .accessibilityIdentifier("content-viewer.webpage.unavailable")
        }
    }

    private func syncTitle(viewModel: BrowserPanelViewModel) {
        guard let onTitleChanged else { return }
        if let url = viewModel.currentURL ?? reference.seedURL {
            onTitleChanged(ContentViewerTab.browserTitle(for: url))
        }
    }
}
