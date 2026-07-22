import SwiftUI
import UniformTypeIdentifiers

struct TerminalSpotlightOverlayHostView<CardContent: View>: View {
    @ObservedObject var coordinator: TerminalSpotlightCoordinator

    let items: [SpotlightItem]
    let projectColorTag: (AnyProjectSession) -> ProjectColorTag?
    let onDismiss: () -> Void
    let onFocusSpotlight: (TerminalSpotlightState) -> Void
    let onInstallScrollMonitor: () -> Void
    let onRemoveScrollMonitor: () -> Void
    let onSwitchSpotlight: (Int) -> Void
    let onReorderTerminalTab: (SpotlightItem, SpotlightItem, TerminalTabMovePlacement) -> Bool
    let cardContent: (TerminalSpotlightState) -> CardContent

    var body: some View {
        Group {
            if let spotlight = coordinator.spotlight {
                TerminalSpotlightOverlayView(
                    spotlight: spotlight,
                    swipeDirection: coordinator.swipeDirection,
                    swipeOffset: coordinator.swipeOffset,
                    tabPageOffset: Binding(
                        get: { coordinator.tabPageOffset },
                        set: { coordinator.tabPageOffset = $0 }
                    ),
                    items: items,
                    projectColorTag: projectColorTag,
                    onDismiss: onDismiss,
                    onFocus: { onFocusSpotlight(spotlight) },
                    onInstallScrollMonitor: onInstallScrollMonitor,
                    onRemoveScrollMonitor: onRemoveScrollMonitor,
                    onSwitchSpotlight: onSwitchSpotlight,
                    onReorderTerminalTab: onReorderTerminalTab,
                    cardContent: { cardContent(spotlight) }
                )
            }
        }
    }
}

struct TerminalSpotlightOverlayView<CardContent: View>: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @State private var draggedTerminalIdentity: String?
    @State private var dropTarget: SpotlightTabDropTarget?
    @State private var lastAppliedDropTarget: SpotlightTabDropTarget?

    let spotlight: TerminalSpotlightState
    let swipeDirection: SpotlightSwipeDirection
    let swipeOffset: CGFloat
    let tabPageOffset: Binding<Int>
    let items: [SpotlightItem]
    let projectColorTag: (AnyProjectSession) -> ProjectColorTag?
    let onDismiss: () -> Void
    let onFocus: () -> Void
    let onInstallScrollMonitor: () -> Void
    let onRemoveScrollMonitor: () -> Void
    let onSwitchSpotlight: (Int) -> Void
    let onReorderTerminalTab: (SpotlightItem, SpotlightItem, TerminalTabMovePlacement) -> Bool
    let cardContent: () -> CardContent

    var body: some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .opacity(0.72)

                Rectangle()
                    .fill(activeThemePalette.windowBackgroundColor.opacity(0.42))
                    .ignoresSafeArea()

                Rectangle()
                    .fill(Color.black.opacity(0.14))
                    .ignoresSafeArea()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .transition(.opacity)

            spotlightContainer
                .padding(24)
                .transition(
                    .asymmetric(
                        insertion: swipeDirection == .none
                            ? .opacity.combined(with: .scale(scale: 0.975))
                            : .move(edge: swipeDirection == .trailing ? .trailing : .leading).combined(with: .opacity),
                        removal: swipeDirection == .none
                            ? .opacity.combined(with: .scale(scale: 0.985))
                            : .move(edge: swipeDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
                    )
                )

        }
        .transition(.opacity)
        .zIndex(220)
        .onExitCommand(perform: onDismiss)
        .onAppear {
            if !spotlight.source.showsComposeInputBar {
                onFocus()
            }
            onInstallScrollMonitor()
        }
        .onDisappear(perform: onRemoveScrollMonitor)
    }

    @ViewBuilder
    private var spotlightContainer: some View {
        let showNav = spotlight.supportsCarouselNavigation && flatSpotlightItems.count > 1
        HStack(spacing: 0) {
            if showNav {
                Button { onSwitchSpotlight(-1) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(AppTypographyTokens.scaledIcon(16, weight: .semibold))
                        if let shortcut = AppShortcutRegistry.binding(for: .boardNavigateLeft) {
                            Text(shortcut.displayString)
                                .font(AppTypographyTokens.scaledSystem(9, weight: .medium))
                        }
                    }
                    .foregroundStyle(activeThemePalette.secondaryTextColor)
                    .frame(width: uiScale.chromeSize(40), height: uiScale.chromeSize(48))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }

            VStack(spacing: 8) {
                if showNav {
                    spotlightTabStrip
                }
                cardContent()
                    .offset(x: swipeOffset)
            }

            if showNav {
                Button { onSwitchSpotlight(1) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "chevron.right")
                            .font(AppTypographyTokens.scaledIcon(16, weight: .semibold))
                        if let shortcut = AppShortcutRegistry.binding(for: .boardNavigateRight) {
                            Text(shortcut.displayString)
                                .font(AppTypographyTokens.scaledSystem(9, weight: .medium))
                        }
                    }
                    .foregroundStyle(activeThemePalette.secondaryTextColor)
                    .frame(width: uiScale.chromeSize(40), height: uiScale.chromeSize(48))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
        }
    }

    @ViewBuilder
    private var spotlightTabStrip: some View {
        let items = flatSpotlightItems
        let currentIdx = spotlightItemIndex ?? 0
        // File-tab styling: the current tab is a solid canvas-colored card with
        // a border (matching the editor's file tabs), so it clearly pops off
        // the translucent capsule; inactive tabs stay flat and quiet.
        let style = TerminalTabChipStyle(
            activeBackground: activeThemePalette.canvasBackgroundColor,
            inactiveBackground: .clear,
            activeBorderColor: activeThemePalette.borderColorValue.opacity(0.75),
            inactiveBorderColor: .clear,
            selectedTextColor: activeThemePalette.primaryTextColor,
            inactiveTextColor: activeThemePalette.secondaryTextColor
        )
        if items.count > 1 {
            HStack(spacing: 8) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(tabStripEntries(items: items)) { entry in
                                spotlightTabChip(
                                    entry: entry,
                                    currentIdx: currentIdx,
                                    style: style
                                )
                                .id(entry.index)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                    }
                    .frame(maxWidth: uiScale.chromeSize(560))
                    .fixedSize(horizontal: true, vertical: false)
                    .mask(scrollEdgeFade)
                    .onAppear {
                        scrollProxy.scrollTo(currentIdx, anchor: .center)
                    }
                    .onChange(of: currentIdx) { _, newIdx in
                        withAnimation(.easeOut(duration: 0.18)) {
                            scrollProxy.scrollTo(newIdx, anchor: .center)
                        }
                    }
                }

                if items.count > 5 {
                    Text("\(currentIdx + 1)/\(items.count)")
                        .font(AppTypographyTokens.caption2)
                        .monospacedDigit()
                        .foregroundStyle(activeThemePalette.secondaryTextColor)
                        .padding(.trailing, 12)
                }
            }
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(activeThemePalette.canvasSecondaryBackgroundColor.opacity(0.55))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(activeThemePalette.borderColorValue.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
            }
        }
    }

    /// Fades the strip's clipped edges so overflow reads as "scroll for more"
    /// rather than tabs being abruptly cut off.
    private var scrollEdgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 16)
            Rectangle().fill(Color.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 16)
        }
    }

    @ViewBuilder
    private func spotlightTabChip(
        entry: SpotlightTabStripEntry,
        currentIdx: Int,
        style: TerminalTabChipStyle
    ) -> some View {
        let index = entry.index
        let item = entry.item
        let isCurrent = index == currentIdx
        let accent: TerminalTabChipAccent? = {
            switch item {
            case let .terminal(project, tab):
                guard let color = projectColorTag(project)?.color else { return nil }
                let isTabActive = project.terminal.tabActivityStateOrInactive(for: tab.id).isActive
                return TerminalTabChipAccent(isActive: isTabActive, color: color, width: 2.5)
            case let .acp(_, _, _, accentColor):
                guard let accentColor else { return nil }
                return TerminalTabChipAccent(isActive: false, color: accentColor, width: 2.5)
            default:
                return nil
            }
        }()
        Button {
            guard !isCurrent else { return }
            onSwitchSpotlight(index - currentIdx)
        } label: {
            TerminalTabChipChrome(
                isSelected: isCurrent,
                style: style,
                accent: accent,
                showsActivityUnderline: true,
                cornerRadiusToken: 9
            ) {
                let titleFont: Font = isCurrent ? AppTypographyTokens.captionSemibold : AppTypographyTokens.caption
                HStack(spacing: 6) {
                    switch item {
                    case .terminal:
                        Text(entry.displayTitle)
                            .font(titleFont)
                            .lineLimit(1)
                    case .vibeCast:
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                        Text(entry.displayTitle)
                            .font(titleFont)
                            .lineLimit(1)
                    case .vibeLanes:
                        Image(systemName: "rectangle.stack.badge.play")
                            .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                        Text(entry.displayTitle)
                            .font(titleFont)
                            .lineLimit(1)
                    case .acp:
                        Image(systemName: "sparkles")
                            .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                        Text(entry.displayTitle)
                            .font(titleFont)
                            .lineLimit(1)
                    case .file:
                        Image(systemName: "doc.text")
                            .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                        Text(entry.displayTitle)
                            .font(titleFont)
                            .lineLimit(1)
                    case .browser:
                        Image(systemName: "globe")
                            .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                        Text(entry.displayTitle)
                            .font(titleFont)
                            .lineLimit(1)
                    }
                    if let ordinal = entry.ordinal {
                        Text("\(ordinal)")
                            .font(AppTypographyTokens.scaledSystem(9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                isCurrent ? style.selectedTextColor.opacity(0.72) : style.inactiveTextColor.opacity(0.72)
                            )
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(activeThemePalette.primaryTextColor.opacity(0.08))
                            )
                    }
                }
                .foregroundStyle(isCurrent ? style.selectedTextColor : style.inactiveTextColor)
            }
        }
        .buttonStyle(.plain)
        .opacity(isDraggedTab(item) && dropTarget != nil ? 0.62 : 1)
        .scaleEffect(isDraggedTab(item) && dropTarget != nil ? 0.98 : 1)
        .shadow(
            color: {
                if isDraggedTab(item) && dropTarget != nil { return Color.black.opacity(0.22) }
                if isCurrent { return Color.black.opacity(0.28) }
                return .clear
            }(),
            radius: isCurrent && !(isDraggedTab(item) && dropTarget != nil) ? 4 : 5,
            x: 0,
            y: 2
        )
        .overlay {
            dropIndicator(for: item)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onDrop(
                    of: [UTType.plainText, UTType.text],
                    delegate: SpotlightTabDropDelegate(
                        item: item,
                        targetSize: proxy.size,
                        setDropTarget: { dropTarget = $0 },
                        clearDropTarget: { dropTarget = nil },
                        previewDrop: { placement in
                            handleSpotlightTabHover(on: item, placement: placement)
                        },
                        performDrop: { providers, placement in
                            handleSpotlightTabDrop(providers, on: item, placement: placement)
                        }
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.12), value: draggedTerminalIdentity)
        .animation(.easeInOut(duration: 0.12), value: dropTarget)
        .onDrag {
            makeSpotlightTabDragProvider(for: item)
        }
    }

    private var flatSpotlightItems: [SpotlightItem] {
        items
    }

    /// Builds one entry per item, numbering duplicates ("cmux 1", "cmux 2")
    /// so identically-titled tabs stay distinguishable in the strip.
    private func tabStripEntries(items: [SpotlightItem]) -> [SpotlightTabStripEntry] {
        let titles = items.map { Self.baseTitle(for: $0) }
        var totals: [String: Int] = [:]
        for title in titles {
            totals[title, default: 0] += 1
        }
        var seen: [String: Int] = [:]
        return items.enumerated().map { index, item in
            let title = titles[index]
            seen[title, default: 0] += 1
            let ordinal = (totals[title] ?? 0) > 1 ? seen[title] : nil
            return SpotlightTabStripEntry(
                index: index,
                item: item,
                displayTitle: title,
                ordinal: ordinal
            )
        }
    }

    private static func baseTitle(for item: SpotlightItem) -> String {
        switch item {
        case let .terminal(project, tab):
            return tab.title.isEmpty ? project.title : tab.title
        case .vibeCast:
            return AppStrings.VibeCast.title
        case .vibeLanes:
            return AppStrings.VibeLanes.title
        case let .acp(_, _, title, _):
            return title
        case let .file(_, fileURL):
            return fileURL.lastPathComponent
        case let .browser(_, url):
            return url.host ?? url.absoluteString
        }
    }

    private func terminalDragIdentity(for item: SpotlightItem) -> String? {
        guard case .terminal = item else { return nil }
        return item.tabStripIdentity
    }

    private func isDraggedTab(_ item: SpotlightItem) -> Bool {
        guard let draggedTerminalIdentity,
              terminalDragIdentity(for: item) == draggedTerminalIdentity else {
            return false
        }
        return true
    }

    @ViewBuilder
    private func dropIndicator(for item: SpotlightItem) -> some View {
        if let identity = terminalDragIdentity(for: item),
           let dropTarget,
           dropTarget.identity == identity,
           draggedTerminalIdentity != identity {
            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(activeThemePalette.accentColor)
                    .frame(width: 2, height: max(proxy.size.height - 5, 10))
                    .shadow(color: activeThemePalette.accentColor.opacity(0.38), radius: 3, x: 0, y: 0)
                    .position(
                        x: dropTarget.placement == .before ? 0 : proxy.size.width,
                        y: proxy.size.height / 2
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func makeSpotlightTabDragProvider(for item: SpotlightItem) -> NSItemProvider {
        guard case .terminal = item else {
            return NSItemProvider()
        }

        let identity = item.tabStripIdentity
        draggedTerminalIdentity = identity
        lastAppliedDropTarget = nil
        let provider = NSItemProvider()
        let payload = Data(identity.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }

    private func handleSpotlightTabDrop(
        _ providers: [NSItemProvider],
        on targetItem: SpotlightItem,
        placement: TerminalTabMovePlacement
    ) -> Bool {
        guard case .terminal = targetItem else {
            self.draggedTerminalIdentity = nil
            lastAppliedDropTarget = nil
            return false
        }

        if let draggedTerminalIdentity,
           let draggedItem = items.first(where: { $0.tabStripIdentity == draggedTerminalIdentity }) {
            let didReorder = reorderSpotlightTab(
                draggedItem,
                relativeTo: targetItem,
                placement: placement
            )
            self.draggedTerminalIdentity = nil
            lastAppliedDropTarget = nil
            dropTarget = nil
            return didReorder
        }

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            self.draggedTerminalIdentity = nil
            lastAppliedDropTarget = nil
            dropTarget = nil
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            guard let data,
                  let payload = String(data: data, encoding: .utf8),
                  let draggedItem = items.first(where: { $0.tabStripIdentity == payload }) else {
                return
            }
            Task { @MainActor in
                _ = reorderSpotlightTab(
                    draggedItem,
                    relativeTo: targetItem,
                    placement: placement
                )
                lastAppliedDropTarget = nil
                dropTarget = nil
            }
        }
        return true
    }

    @MainActor
    private func handleSpotlightTabHover(
        on targetItem: SpotlightItem,
        placement: TerminalTabMovePlacement
    ) {
        guard let draggedTerminalIdentity,
              case .terminal = targetItem,
              draggedTerminalIdentity != targetItem.tabStripIdentity,
              let draggedItem = items.first(where: { $0.tabStripIdentity == draggedTerminalIdentity }) else {
            return
        }

        let candidate = SpotlightTabDropTarget(identity: targetItem.tabStripIdentity, placement: placement)
        guard lastAppliedDropTarget != candidate else { return }

        let didReorder = reorderSpotlightTab(
            draggedItem,
            relativeTo: targetItem,
            placement: placement
        )
        if didReorder {
            lastAppliedDropTarget = candidate
        }
    }

    @MainActor
    @discardableResult
    private func reorderSpotlightTab(
        _ draggedItem: SpotlightItem,
        relativeTo targetItem: SpotlightItem,
        placement: TerminalTabMovePlacement
    ) -> Bool {
        guard case .terminal = draggedItem,
              case .terminal = targetItem,
              draggedItem.tabStripIdentity != targetItem.tabStripIdentity else {
            return false
        }

        var didReorder = false
        withAnimation(.easeInOut(duration: 0.14)) {
            didReorder = onReorderTerminalTab(
                draggedItem,
                targetItem,
                placement
            )
        }
        return didReorder
    }

    private var spotlightItemIndex: Int? {
        switch spotlight.source {
        case let .persistent(_, tabID):
            return items.firstIndex(where: {
                if case let .terminal(_, tab) = $0 { return tab.id == tabID }
                return false
            })
        case .vibeCast:
            return items.firstIndex(where: {
                if case .vibeCast = $0 { return true }
                return false
            })
        case .vibeLanes:
            return items.firstIndex(where: {
                if case .vibeLanes = $0 { return true }
                return false
            })
        case let .acp(tileID, _):
            return items.firstIndex(where: {
                if case let .acp(id, _, _, _) = $0 { return id == tileID }
                return false
            })
        case .transient:
            return nil
        case .todos:
            return nil
        case .filePreview:
            return nil
        case .file:
            return items.firstIndex(where: {
                if case let .file(_, url) = $0, case let .file(_, spotlightURL) = spotlight.source {
                    return url == spotlightURL
                }
                return false
            })
        case .browserPreview:
            return nil
        case .browser(let tileID, _):
            return items.firstIndex(where: {
                if case let .browser(id, _) = $0 { return id == tileID }
                return false
            })
        }
    }
}

private struct SpotlightTabStripEntry: Identifiable {
    let index: Int
    let item: SpotlightItem
    let displayTitle: String
    /// 1-based position among identically-titled items; nil when the title is unique.
    let ordinal: Int?

    var id: String {
        item.tabStripIdentity
    }
}

private extension SpotlightItem {
    var tabStripIdentity: String {
        switch self {
        case let .terminal(project, tab):
            return "terminal:\(project.id.uuidString):\(tab.id.uuidString)"
        case .vibeCast:
            return "vibeCast"
        case .vibeLanes:
            return "vibeLanes"
        case let .acp(tileID, storeID, _, _):
            return "acp:\(tileID.uuidString):\(storeID.uuidString)"
        case let .file(tileID, fileURL):
            return "file:\(tileID.uuidString):\(fileURL.standardizedFileURL.path)"
        case let .browser(tileID, url):
            return "browser:\(tileID.uuidString):\(url.absoluteString)"
        }
    }
}

private struct SpotlightTabDropTarget: Equatable {
    let identity: String
    let placement: TerminalTabMovePlacement
}

private struct SpotlightTabDropDelegate: DropDelegate {
    let item: SpotlightItem
    let targetSize: CGSize
    let setDropTarget: (SpotlightTabDropTarget?) -> Void
    let clearDropTarget: () -> Void
    let previewDrop: (TerminalTabMovePlacement) -> Void
    let performDrop: ([NSItemProvider], TerminalTabMovePlacement) -> Bool

    func dropEntered(info: DropInfo) {
        updateDropTarget(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearDropTarget()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard case .terminal = item else {
            clearDropTarget()
            return false
        }

        let accepted = performDrop(
            info.itemProviders(for: [UTType.plainText, UTType.text]),
            placement(for: info)
        )
        clearDropTarget()
        return accepted
    }

    private func updateDropTarget(_ info: DropInfo) {
        guard case let .terminal(_, tab) = item else {
            clearDropTarget()
            return
        }

        setDropTarget(
            SpotlightTabDropTarget(
                identity: item.tabStripIdentity,
                placement: placement(for: info)
            )
        )
        previewDrop(placement(for: info))
    }

    private func placement(for info: DropInfo) -> TerminalTabMovePlacement {
        info.location.x < targetSize.width / 2 ? .before : .after
    }
}

extension ContentView {
    var terminalSpotlightOverlay: some View {
        TerminalSpotlightOverlayHostView(
            coordinator: terminalSpotlightCoordinator,
            items: flatSpotlightItems,
            projectColorTag: vibespaceCanvasActionsCoordinator.colorTag(for:),
            onDismiss: closeTerminalSpotlight,
            onFocusSpotlight: focusSpotlightTerminal,
            onInstallScrollMonitor: installSpotlightScrollMonitor,
            onRemoveScrollMonitor: removeSpotlightScrollMonitor,
            onSwitchSpotlight: switchSpotlight(by:),
            onReorderTerminalTab: { draggedItem, targetItem, placement in
                guard case let .terminal(draggedProject, draggedTab) = draggedItem,
                      case let .terminal(targetProject, targetTab) = targetItem else {
                    return false
                }
                return layoutPersistence.moveVibeSpaceSpotlightTerminal(
                    vibespaceSpotlightTerminalIdentity(for: draggedProject, tab: draggedTab),
                    relativeTo: vibespaceSpotlightTerminalIdentity(for: targetProject, tab: targetTab),
                    placement: placement,
                    liveIdentities: vibespaceSpotlightTerminalIdentities(),
                    for: activeVibeSpaceID
                )
            },
            cardContent: terminalSpotlightCard(for:)
        )
    }
}
