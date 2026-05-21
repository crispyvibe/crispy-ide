import SwiftUI
import UniformTypeIdentifiers

struct SplitPaneContentView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let paneID: UUID
    let isActive: Bool
    @ObservedObject var splitStore: SplitViewStore
    @ObservedObject var group: EditorGroupStore
    @ObservedObject var contentViewerStore: ContentViewerStore
    var projects: [AnyProjectSession] = []
    let viewerScope: ViewerScope
    let focusedProjectRootPath: String?
    var projectColorTagsByPath: [String: ProjectColorTag] = [:]
    @ObservedObject var activityTracker: ProjectActivityTracker
    var vibeCastView: (() -> AnyView)?
    var terminalSessionResolver: ((UUID, UUID) -> TerminalSession?)? = nil
    var dockedBrowserCoordinator: DockedBrowserCoordinator? = nil
    var onLinkTargetActivated: ((URL) -> Void)? = nil
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil
    let onActivate: () -> Void
    @State private var dropZone: EditorDropZone?
    @State private var isDropTargeted = false

    private var visibleTabs: [ContentViewerTab] {
        group.filteredTabs(scope: viewerScope, focusedProjectRootPath: focusedProjectRootPath)
    }

    private var visibleActiveTab: ContentViewerTab? {
        if let activeTab = group.activeTab,
           visibleTabs.contains(where: { $0.id == activeTab.id }) {
            return activeTab
        }
        return visibleTabs.first
    }

    private var paneDropTypes: [UTType] {
        ContentViewerTabDragSupport.contentAreaDropTypes(for: visibleActiveTab?.kind)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if splitStore.isSplit {
                    paneTabStrip
                    Divider()
                }
                ZStack {
                    paneBody.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if isDropTargeted { EditorDropZoneOverlay(hoveredZone: dropZone) }
                }
            }
            .background(palette.canvasBackgroundColor)
            .overlay(Rectangle().stroke(palette.borderColorValue.opacity(0.45), lineWidth: 1))
            .overlay(alignment: .top) {
                if isActive && splitStore.isSplit {
                    palette.accentColor.opacity(0.7).frame(height: 2)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { onActivate() })
            .onDrop(of: paneDropTypes,
                    delegate: PaneSplitDropDelegate(
                        size: proxy.size,
                        dropZone: $dropZone, isTargeted: $isDropTargeted,
                        group: group, splitStore: splitStore, onActivate: onActivate
                    ))
            .contextMenu { paneContextMenu }
            .onChange(of: group.tabs.count) { _, newCount in
                if newCount == 0 && splitStore.isSplit {
                    splitStore.closePane(paneID: paneID)
                }
            }
            .accessibilityIdentifier("content-viewer.pane")
        }
    }

    // MARK: - Tab strip

    private var paneTabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(visibleTabs) { tab in paneTabItem(tab) }
                if visibleTabs.isEmpty {
                    Text("Empty").font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor.opacity(0.5))
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .overlay(alignment: .trailing) {
            CrispyVibesIconButton(systemName: "xmark", size: 10, padding: 4,
                            color: palette.secondaryTextColor) { splitStore.closePane(paneID: paneID) }
            .padding(.trailing, 8)
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.7))
        .onDrop(of: ContentViewerTabDragSupport.dropTypes, isTargeted: nil) { providers in
            let didStartDrop = ContentViewerTabDragSupport.loadDropItem(from: providers) { item in
                guard let item else { return }
                DispatchQueue.main.async {
                    onActivate()
                    switch item {
                    case .tab(let tab):
                        splitStore.moveTab(tab, to: group)
                    case .file(let url):
                        splitStore.moveTab(.file(url: url), to: group)
                    }
                }
            }
            return didStartDrop
        }
    }

    private func paneTabItem(_ tab: ContentViewerTab) -> some View {
        let isTabActive = group.activeTabID == tab.id
        let projectColor = ContentViewerTab.projectColor(for: tab, projectColorTagsByPath: projectColorTagsByPath, fallback: palette.accentColor)
        return ContentViewerTabItemView(
            tab: tab,
            isActive: isTabActive,
            projectColor: projectColor,
            compact: true,
            browserViewModel: browserViewModel(for: tab),
            acpChatViewModel: paneACPChatViewModel(for: tab),
            onClose: {
                closeTab(tab)
                if group.tabs.isEmpty && splitStore.isSplit { splitStore.closePane(paneID: paneID) }
            },
            onSelect: { onActivate(); group.activateTab(tab.id) }
        )
    }

    private func closeTab(_ tab: ContentViewerTab) {
        splitStore.closeTab(tab, in: group)
    }

    private func browserViewModel(for tab: ContentViewerTab) -> BrowserPanelViewModel? {
        guard case .webPage(let reference) = tab.kind,
              let dockedBrowserCoordinator else { return nil }
        return dockedBrowserCoordinator.viewModel(for: reference)
    }

    private func paneACPChatViewModel(for tab: ContentViewerTab) -> ACPChatViewModel? {
        guard case .acpPane(let id) = tab.kind else { return nil }
        return contentViewerStore.acpStore(for: id)?.chatViewModel
    }

    // MARK: - Body

    @ViewBuilder
    private var paneBody: some View {
        if let activeTab = visibleActiveTab {
            switch activeTab.kind {
            case .file:
                MarkdownEditorView(
                    viewModel: group.markdownViewModel,
                    showsTopBar: false,
                    embeddedDropBridge: embeddedDropBridge
                )
            case .vibeCast:
                if let vibeCastView { vibeCastView() }
                else { vibeCastUnavailable }
            case .webPage(let reference):
                if let coordinator = dockedBrowserCoordinator {
                    let vm = coordinator.viewModel(for: reference)
                    BrowserContentView(viewModel: vm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    BrowserContentView(
                        viewModel: BrowserPanelViewModel(
                            initialURL: reference.seedURL
                        )
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .terminal(let projectID, let tabID):
                if let session = terminalSessionResolver?(projectID, tabID) {
                    TerminalSessionHostView(
                        session: session,
                        displayDensity: .regular,
                        isActive: true,
                        accessibilityIdentifier: "content-viewer.terminal.host",
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated
                    )
                } else {
                    ContentUnavailableView(
                        String(localized: "contentViewer.terminalUnavailable"),
                        systemImage: "terminal",
                        description: Text(String(localized: "contentViewer.terminalUnavailable.description"))
                    )
                }
            case .acpPane(let storeID):
                if let acpStore = contentViewerStore.acpStore(for: storeID) {
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
            ContentUnavailableView(
                AppStrings.ContentViewer.emptyPane,
                systemImage: "rectangle.dashed",
                description: Text(AppStrings.ContentViewer.emptyPaneDescription)
            )
        }
    }

    private var vibeCastUnavailable: some View {
        ContentUnavailableView(AppStrings.VibeCast.title,
                               systemImage: "antenna.radiowaves.left.and.right",
                               description: Text(AppStrings.VibeCast.noTerminalDescription))
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

    @ViewBuilder
    private var paneContextMenu: some View {
        if splitStore.canSplit {
            Button(AppStrings.ContentViewer.splitHorizontal) { splitStore.split(paneID: paneID, orientation: .horizontal) }
            Button(AppStrings.ContentViewer.splitVertical) { splitStore.split(paneID: paneID, orientation: .vertical) }
        }
        if splitStore.isSplit {
            Button(AppStrings.ContentViewer.toggleOrientation) { splitStore.toggleOrientation(paneID: paneID) }
            Divider()
            Button(AppStrings.ContentViewer.closePane) { splitStore.closePane(paneID: paneID) }
        }
    }

    private func handleEmbeddedDrop(item: ContentViewerDropItem, zone: EditorDropZone) {
        let tab: ContentViewerTab
        switch item {
        case .tab(let droppedTab):
            tab = droppedTab
        case .file(let url):
            tab = .file(url: url)
        }

        onActivate()
        if zone == .center || !splitStore.canSplit {
            splitStore.moveTab(tab, to: group)
        } else {
            let orientation: SplitOrientation = (zone == .left || zone == .right) ? .horizontal : .vertical
            splitStore.splitActiveWithTab(tab, orientation: orientation)
        }
    }
}

// MARK: - Drop Delegate

private struct PaneSplitDropDelegate: DropDelegate {
    let size: CGSize
    @Binding var dropZone: EditorDropZone?
    @Binding var isTargeted: Bool
    let group: EditorGroupStore
    let splitStore: SplitViewStore
    let onActivate: () -> Void

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

        onActivate()
        if zone == .center || !splitStore.canSplit {
            splitStore.moveTab(tab, to: group)
        } else {
            let orientation: SplitOrientation = (zone == .left || zone == .right) ? .horizontal : .vertical
            splitStore.splitActiveWithTab(tab, orientation: orientation)
        }
    }
}
