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
    @State private var dropZone: EditorDropZone?
    @State private var isDropTargeted = false

    private var activeGroup: EditorGroupStore { splitStore.activeGroup }

    private var visibleTabs: [ContentViewerTab] {
        activeGroup.filteredTabs(scope: store.viewerScope, focusedProjectRootPath: focusedProjectRootPath)
    }

    private var visibleActiveTab: ContentViewerTab? {
        if let activeTab = activeGroup.activeTab,
           visibleTabs.contains(where: { $0.id == activeTab.id }) {
            return activeTab
        }
        return visibleTabs.first
    }

    private var contentAreaDropTypes: [UTType] {
        ContentViewerTabDragSupport.contentAreaDropTypes(for: visibleActiveTab?.kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsTopBar && !splitStore.isSplit { tabStrip; Divider() }
            contentArea
        }
        .background(appThemePalette.canvasBackgroundColor)
        .crispyvibesContainerBorder(opacity: 0.6)
        .overlay(alignment: .topLeading) { accessibilityStateMarker }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleTabs) { tab in tabItem(tab) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            if projects.count > 1 { scopeToggle.padding(.trailing, 8) }
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

    private func tabItem(_ tab: ContentViewerTab) -> some View {
        let isActive = activeGroup.activeTabID == tab.id
        let projectColor = ContentViewerTab.projectColor(for: tab, projectColorTagsByPath: projectColorTagsByPath, fallback: appThemePalette.accentColor)
        return ContentViewerTabItemView(
            tab: tab,
            isActive: isActive,
            projectColor: projectColor,
            compact: false,
            browserViewModel: browserViewModel(for: tab),
            acpChatViewModel: acpChatViewModel(for: tab),
            onClose: { closeTab(tab) },
            onSelect: { activeGroup.activateTab(tab.id) }
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

    @ViewBuilder
    private var contentArea: some View {
        if splitStore.isSplit {
            SplitContainerView(node: splitStore.root, store: splitStore) { paneID in
                AnyView(
                    SplitPaneContentView(
                        paneID: paneID,
                        isActive: splitStore.activePaneID == paneID,
                        splitStore: splitStore,
                        group: splitStore.group(for: paneID),
                        contentViewerStore: store,
                        projects: projects,
                        viewerScope: store.viewerScope,
                        focusedProjectRootPath: focusedProjectRootPath,
                        projectColorTagsByPath: projectColorTagsByPath,
                        activityTracker: activityTracker,
                        vibeCastView: vibeCastViewFactory(),
                        terminalSessionResolver: terminalSessionResolver,
                        dockedBrowserCoordinator: dockedBrowserCoordinator,
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated,
                        onActivate: { splitStore.activePaneID = paneID }
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                singleContentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("content-viewer.drop-surface")
                    .overlay { if isDropTargeted { EditorDropZoneOverlay(hoveredZone: dropZone) } }
                    .onDrop(of: contentAreaDropTypes,
                            delegate: EditorSplitDropDelegate(
                                size: proxy.size, dropZone: $dropZone, isTargeted: $isDropTargeted,
                                activeGroup: activeGroup, splitStore: splitStore
                            ))
            }
        }
    }

    @ViewBuilder
    private var singleContentArea: some View {
        if let activeTab = visibleActiveTab {
            switch activeTab.kind {
            case .file:
                MarkdownEditorView(
                    viewModel: activeGroup.markdownViewModel,
                    showsTopBar: false,
                    embeddedDropBridge: embeddedDropBridge
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .vibeCast:
                if !projects.isEmpty { vibeCastContent }
                else {
                    ContentUnavailableView(AppStrings.VibeCast.noTerminal, systemImage: "terminal",
                                           description: Text(AppStrings.VibeCast.noTerminalDescription))
                }
            case .webPage(let reference):
                WebPageTabView(reference: reference, coordinator: dockedBrowserCoordinator, onTitleChanged: { title in
                    activeGroup.updateTabTitle(activeTab.id, title: title)
                })
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
        } else {
            ContentUnavailableView(AppStrings.ContentViewer.noContent, systemImage: "doc.text",
                                   description: Text(AppStrings.ContentViewer.noContentDescription))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var embeddedDropBridge: ContentViewerEmbeddedDropBridge {
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
                handleEmbeddedDrop(item: item, zone: zone)
                return true
            }
        )
    }

    private func handleEmbeddedDrop(item: ContentViewerDropItem, zone: EditorDropZone) {
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
