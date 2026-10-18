import SwiftUI

struct SpotlightCardPresentation {
    let focused: TerminalSpotlightState
    let members: [TerminalSpotlightState]
    let positionID: UUID?
    let orientation: SpotlightComboOrientation

    var companion: TerminalSpotlightState? {
        members.first { $0.navigationIdentity != focused.navigationIdentity }
    }
}

struct TerminalSpotlightOverlayHostView<CardContent: View>: View {
    @ObservedObject var coordinator: TerminalSpotlightCoordinator

    let items: [SpotlightItem]
    let layoutSnapshot: SpotlightLayoutSnapshot
    let hostID: String
    let layoutGeneration: UInt64
    let projectColorTag: (AnyProjectSession) -> ProjectColorTag?
    let metadataResolver: SpotlightMetadataResolver
    let onDismiss: () -> Void
    let onInstallScrollMonitor: () -> Void
    let onRemoveScrollMonitor: () -> Void
    let onSwitchSpotlight: (Int) -> Void
    let onSelectSpotlight: (SpotlightNavigationIdentity) -> Void
    let onCommitLayout: (SpotlightLayoutSnapshot) -> Void
    let resolveCurrentLayout: () -> SpotlightLayoutSnapshot
    let onReconcile: () -> Void
    let onFileOwnershipChanged: (Set<UUID>) -> Void
    let stateForItem: (SpotlightItem) -> TerminalSpotlightState?
    let positionCardContent: (SpotlightCardPresentation) -> CardContent

    init(
        coordinator: TerminalSpotlightCoordinator,
        items: [SpotlightItem],
        layoutSnapshot: SpotlightLayoutSnapshot,
        hostID: String,
        layoutGeneration: UInt64,
        projectColorTag: @escaping (AnyProjectSession) -> ProjectColorTag?,
        metadataResolver: SpotlightMetadataResolver? = nil,
        onDismiss: @escaping () -> Void,
        onInstallScrollMonitor: @escaping () -> Void,
        onRemoveScrollMonitor: @escaping () -> Void,
        onSwitchSpotlight: @escaping (Int) -> Void,
        onSelectSpotlight: @escaping (SpotlightNavigationIdentity) -> Void,
        onCommitLayout: @escaping (SpotlightLayoutSnapshot) -> Void,
        resolveCurrentLayout: @escaping () -> SpotlightLayoutSnapshot,
        onReconcile: @escaping () -> Void,
        onFileOwnershipChanged: @escaping (Set<UUID>) -> Void = { _ in },
        stateForItem: @escaping (SpotlightItem) -> TerminalSpotlightState?,
        @ViewBuilder positionCardContent: @escaping (SpotlightCardPresentation) -> CardContent
    ) {
        self.coordinator = coordinator
        self.items = items
        self.layoutSnapshot = layoutSnapshot
        self.hostID = hostID
        self.layoutGeneration = layoutGeneration
        self.projectColorTag = projectColorTag
        self.metadataResolver = metadataResolver ?? SpotlightMetadataResolver(projectColorTag: projectColorTag)
        self.onDismiss = onDismiss
        self.onInstallScrollMonitor = onInstallScrollMonitor
        self.onRemoveScrollMonitor = onRemoveScrollMonitor
        self.onSwitchSpotlight = onSwitchSpotlight
        self.onSelectSpotlight = onSelectSpotlight
        self.onCommitLayout = onCommitLayout
        self.resolveCurrentLayout = resolveCurrentLayout
        self.onReconcile = onReconcile
        self.onFileOwnershipChanged = onFileOwnershipChanged
        self.stateForItem = stateForItem
        self.positionCardContent = positionCardContent
    }

    /// Compatibility initializer for single-card hosts and existing mounted tests.
    init(
        coordinator: TerminalSpotlightCoordinator,
        items: [SpotlightItem],
        projectColorTag: @escaping (AnyProjectSession) -> ProjectColorTag?,
        metadataResolver: SpotlightMetadataResolver? = nil,
        onDismiss: @escaping () -> Void,
        onInstallScrollMonitor: @escaping () -> Void,
        onRemoveScrollMonitor: @escaping () -> Void,
        onSwitchSpotlight: @escaping (Int) -> Void,
        onSelectSpotlight: @escaping (SpotlightNavigationIdentity) -> Void,
        onReorderTerminalTab: @escaping (SpotlightItem, SpotlightItem, TerminalTabMovePlacement) -> Bool,
        @ViewBuilder cardContent: @escaping (TerminalSpotlightState) -> CardContent
    ) {
        self.init(
            coordinator: coordinator,
            items: items,
            layoutSnapshot: SpotlightLayoutSnapshot(
                positions: items.map { SpotlightPositionSnapshot(members: [$0.persistentID]) }
            ),
            hostID: "compatibility",
            layoutGeneration: 0,
            projectColorTag: projectColorTag,
            onDismiss: onDismiss,
            onInstallScrollMonitor: onInstallScrollMonitor,
            onRemoveScrollMonitor: onRemoveScrollMonitor,
            onSwitchSpotlight: onSwitchSpotlight,
            onSelectSpotlight: onSelectSpotlight,
            onCommitLayout: { _ in },
            resolveCurrentLayout: {
                SpotlightLayoutSnapshot(positions: items.map { SpotlightPositionSnapshot(members: [$0.persistentID]) })
            },
            onReconcile: {},
            stateForItem: { _ in nil },
            positionCardContent: { presentation in cardContent(presentation.focused) }
        )
    }

    var body: some View {
        Group {
            if let spotlight = coordinator.spotlight {
                TerminalSpotlightOverlayView(
                    coordinator: coordinator,
                    spotlight: spotlight,
                    swipeDirection: coordinator.swipeDirection,
                    swipeOffset: coordinator.swipeOffset,
                    items: items,
                    layoutSnapshot: layoutSnapshot,
                    hostID: hostID,
                    layoutGeneration: layoutGeneration,
                    projectColorTag: projectColorTag,
                    metadataResolver: metadataResolver,
                    onDismiss: onDismiss,
                    onInstallScrollMonitor: onInstallScrollMonitor,
                    onRemoveScrollMonitor: onRemoveScrollMonitor,
                    onSwitchSpotlight: onSwitchSpotlight,
                    onSelectSpotlight: onSelectSpotlight,
                    onCommitLayout: onCommitLayout,
                    resolveCurrentLayout: resolveCurrentLayout,
                    onReconcile: onReconcile,
                    onFileOwnershipChanged: onFileOwnershipChanged,
                    stateForItem: stateForItem,
                    positionCardContent: positionCardContent
                )
            }
        }
    }
}

struct TerminalSpotlightOverlayView<CardContent: View>: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var coordinator: TerminalSpotlightCoordinator
    @StateObject private var metadataMonitor = SpotlightMetadataMonitor()

    let spotlight: TerminalSpotlightState
    let swipeDirection: SpotlightSwipeDirection
    let swipeOffset: CGFloat
    let items: [SpotlightItem]
    let layoutSnapshot: SpotlightLayoutSnapshot
    let hostID: String
    let layoutGeneration: UInt64
    let projectColorTag: (AnyProjectSession) -> ProjectColorTag?
    let metadataResolver: SpotlightMetadataResolver
    let onDismiss: () -> Void
    let onInstallScrollMonitor: () -> Void
    let onRemoveScrollMonitor: () -> Void
    let onSwitchSpotlight: (Int) -> Void
    let onSelectSpotlight: (SpotlightNavigationIdentity) -> Void
    let onCommitLayout: (SpotlightLayoutSnapshot) -> Void
    let resolveCurrentLayout: () -> SpotlightLayoutSnapshot
    let onReconcile: () -> Void
    let onFileOwnershipChanged: (Set<UUID>) -> Void
    let stateForItem: (SpotlightItem) -> TerminalSpotlightState?
    let positionCardContent: (SpotlightCardPresentation) -> CardContent

    private var metadataCatalog: SpotlightMetadataCatalog {
        SpotlightMetadataCatalog(items.map { SpotlightItemMetadata.make(item: $0, resolver: metadataResolver) })
    }

    private var currentItem: SpotlightItem? {
        guard let identity = spotlight.navigationIdentity else { return nil }
        return items.first { $0.navigationIdentity == identity }
    }

    private var currentID: SpotlightPersistentItemID? { currentItem?.persistentID }

    private var currentPosition: SpotlightPositionSnapshot? {
        currentID.flatMap(layoutSnapshot.position(containing:))
    }

    private var shelfVisible: Bool {
        spotlight.supportsCarouselNavigation && currentItem != nil && !items.isEmpty
    }

    private var carouselEnabled: Bool {
        shelfVisible && layoutSnapshot.positions.count > 1 && !coordinator.isOverviewPresented
    }

    private var liveIdentityTokens: [String] {
        items.map { $0.persistentID.safeToken }
    }

    private var cardPresentation: SpotlightCardPresentation {
        let states = currentPosition?.members.compactMap { memberID -> TerminalSpotlightState? in
            guard let item = items.first(where: { $0.persistentID == memberID }) else { return nil }
            if item.navigationIdentity == spotlight.navigationIdentity { return spotlight }
            return stateForItem(item)
        } ?? [spotlight]
        return SpotlightCardPresentation(
            focused: spotlight,
            members: states.isEmpty ? [spotlight] : states,
            positionID: currentPosition?.id,
            orientation: currentPosition?.orientation ?? .sideBySide
        )
    }

    private var spotlightFileTileIDs: Set<UUID> {
        Set((currentPosition?.members ?? []).compactMap { id in
            guard case let .file(tileID) = id else { return nil }
            return tileID
        })
    }

    var body: some View {
        let _ = metadataMonitor.configure(items: items, resolver: metadataResolver)
        let catalog = metadataCatalog
        ZStack {
            backdrop
            spotlightContainer
                .padding(24)
                .allowsHitTesting(!coordinator.isOverviewPresented)
                .transition(.opacity.combined(with: .scale(scale: 0.975)))

            if coordinator.isOverviewPresented {
                backdrop.opacity(0.45)
                SpotlightAllTabsOverview(
                    catalog: catalog,
                    snapshot: layoutSnapshot,
                    currentID: currentID,
                    focusedID: currentID,
                    onSelect: { identity in
                        coordinator.dismissOverview()
                        onSelectSpotlight(identity)
                    },
                    onDismiss: coordinator.dismissOverview
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(2)
            }
        }
        .transition(.opacity)
        .zIndex(220)
        .onExitCommand {
            if coordinator.isOverviewPresented { coordinator.dismissOverview() } else { onDismiss() }
        }
        .onAppear {
            onFileOwnershipChanged(spotlightFileTileIDs)
            metadataMonitor.configure(items: items, resolver: metadataResolver)
            DispatchQueue.main.async {
                metadataMonitor.configure(items: items, resolver: metadataResolver)
                metadataMonitor.objectWillChange.send()
            }
            synchronizeMonitor()
            onReconcile()
        }
        .onChange(of: spotlightFileTileIDs) { _, tileIDs in
            onFileOwnershipChanged(tileIDs)
        }
        .onChange(of: liveIdentityTokens) { _, _ in onReconcile() }
        .onChange(of: carouselEnabled) { _, _ in synchronizeMonitor() }
        .onChange(of: shelfVisible) { _, _ in synchronizeMonitor() }
        .onChange(of: coordinator.isOverviewPresented) { _, _ in synchronizeMonitor() }
        .onDisappear {
            onFileOwnershipChanged([])
            coordinator.registerShelfScrollView(nil)
            coordinator.registerShelfHitRegion(nil)
            coordinator.registerShelfExcludedRegion(nil)
            onRemoveScrollMonitor()
        }
    }

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(0.72)
            Rectangle().fill(palette.windowBackgroundColor.opacity(0.42))
            Rectangle().fill(Color.black.opacity(0.14))
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            if coordinator.isOverviewPresented { coordinator.dismissOverview() } else { onDismiss() }
        }
        .transition(.opacity)
    }

    private var spotlightContainer: some View {
        HStack(spacing: 0) {
            if carouselEnabled { navigationButton(offset: -1) }

            VStack(spacing: 0) {
                if shelfVisible {
                    SpotlightTabShelf(
                        coordinator: coordinator,
                        catalog: metadataCatalog,
                        snapshot: layoutSnapshot,
                        hostID: hostID,
                        generation: layoutGeneration,
                        currentID: currentID,
                        focusedID: currentID,
                        onSelect: onSelectSpotlight,
                        onCommit: onCommitLayout,
                        resolveCurrentLayout: resolveCurrentLayout,
                        onShowAll: coordinator.presentOverview
                    )
                }
                positionCardContent(cardPresentation)
                    .offset(x: swipeOffset)
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: swipeDirection == .none
                                ? .opacity
                                : .move(edge: swipeDirection == .trailing ? .leading : .trailing)
                                    .combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if carouselEnabled { navigationButton(offset: 1) }
        }
    }

    private func navigationButton(offset: Int) -> some View {
        Button { onSwitchSpotlight(offset) } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                .font(AppTypographyTokens.scaledIcon(16, weight: .semibold))
                .foregroundStyle(palette.secondaryTextColor)
                .frame(width: uiScale.chromeSize(40), height: uiScale.chromeSize(48))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offset < 0 ? AppStrings.Spotlight.previous : AppStrings.Spotlight.next)
        .accessibilityIdentifier(offset < 0 ? "spotlight.navigation.previous" : "spotlight.navigation.next")
    }

    private func synchronizeMonitor() {
        coordinator.setCarouselAvailable(carouselEnabled)
        if shelfVisible && !coordinator.isOverviewPresented {
            onInstallScrollMonitor()
        } else {
            onRemoveScrollMonitor()
        }
    }
}

extension ContentView {
    @discardableResult
    func commitMainSpotlightLayout(
        _ snapshot: SpotlightLayoutSnapshot,
        liveIDs: [SpotlightPersistentItemID]
    ) -> Bool {
        guard let boardStore = vibespaceHydrationCoordinator.boardStore,
              boardStore.vibespaceID == activeVibeSpaceID else {
            return false
        }
        return boardStore.commitMainSpotlightLayout(snapshot, liveIDs: liveIDs)
    }

    var terminalSpotlightOverlay: some View {
        let items = flatSpotlightItems
        let liveIDs = items.map(\.persistentID)
        let snapshot = layoutPersistence.spotlightLayout(liveIDs: liveIDs, for: activeVibeSpaceID)
        return TerminalSpotlightOverlayHostView(
            coordinator: terminalSpotlightCoordinator,
            items: items,
            layoutSnapshot: snapshot,
            hostID: "main:\(activeVibeSpaceID?.uuidString ?? "none")",
            layoutGeneration: terminalSpotlightCoordinator.layoutGeneration,
            projectColorTag: vibespaceCanvasActionsCoordinator.colorTag(for:),
            metadataResolver: SpotlightMetadataResolver(
                projectColorTag: vibespaceCanvasActionsCoordinator.colorTag(for:),
                fileGroup: dockedFileViewerCoordinator.assignedEditorGroup(for:),
                browserViewModel: dockedBrowserCoordinator.existingViewModel(for:)
            ),
            onDismiss: closeTerminalSpotlight,
            onInstallScrollMonitor: installSpotlightScrollMonitor,
            onRemoveScrollMonitor: removeSpotlightScrollMonitor,
            onSwitchSpotlight: switchSpotlight(by:),
            onSelectSpotlight: selectSpotlightItem(_:),
            onCommitLayout: { updated in
                if commitMainSpotlightLayout(updated, liveIDs: liveIDs) {
                    terminalSpotlightCoordinator.noteLayoutCommitted()
                }
            },
            resolveCurrentLayout: {
                layoutPersistence.spotlightLayout(liveIDs: flatSpotlightItems.map(\.persistentID), for: activeVibeSpaceID)
            },
            onReconcile: {
                guard let currentID = terminalSpotlightCoordinator.spotlight?.persistentItemID else { return }
                let result = layoutPersistence.spotlightReconciliation(
                    liveIDs: liveIDs,
                    currentID: currentID,
                    for: activeVibeSpaceID
                )
                let didReconcileLayout = commitMainSpotlightLayout(
                    result.snapshot,
                    liveIDs: liveIDs
                )
                if didReconcileLayout {
                    terminalSpotlightCoordinator.noteLayoutCommitted()
                }
                guard result.replacementForCurrent != currentID else { return }
                guard let replacement = result.replacementForCurrent,
                      let item = items.first(where: { $0.persistentID == replacement }),
                      let state = spotlightState(for: item) else {
                    closeTerminalSpotlight()
                    return
                }
                setTerminalSpotlight(state, animated: false)
            },
            onFileOwnershipChanged: { tileIDs in
                dockedFileViewerCoordinator.setSpotlightOwnedTileIDs(
                    tileIDs,
                    ownerID: "main:\(activeVibeSpaceID?.uuidString ?? "none")"
                )
            },
            stateForItem: spotlightState(for:),
            positionCardContent: { presentation in
                terminalSpotlightCard(for: presentation)
            }
        )
    }
}
