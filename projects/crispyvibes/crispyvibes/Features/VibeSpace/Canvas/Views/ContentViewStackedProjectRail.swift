import SwiftUI

typealias StackedRailCardRenderer = (
    StackedRailTerminalEntry,
    Bool,
    Int?,
    Bool
) -> AnyView

struct VibeSpaceStackedProjectRailView: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @ObservedObject var stackedRailStore: StackedRailTerminalStore
    @ObservedObject var stackedRailOverlayCoordinator: StackedRailExpansionOverlayCoordinator

    let vibespaceView: VibeSpaceViewContext
    let hiddenTerminalIDsByProjectPath: [String: Set<UUID>]
    let isHiddenRailSectionExpanded: Binding<Bool>
    let projectColorTagsByPath: [String: ProjectColorTag]
    let onAddProjectsRequested: () -> Void
    let onFocusTerminal: (AnyProjectSession, TerminalTab) -> Void
    let onCloseTerminal: (AnyProjectSession, TerminalTab) -> Void
    let onHideTerminal: (String, UUID, AnyProjectSession?) -> Void
    let onRestartTerminal: (String, TerminalTab, AnyProjectSession?) -> Void
    let onRenameTerminal: (AnyProjectSession, UUID, String) -> Void
    let onSpotlightTerminal: (AnyProjectSession, TerminalTab) -> Void
    let onUnhideTerminal: (String, UUID) -> Void

    private var presentation: StackedRailPresentation {
        StackedRailPresentation(
            projects: vibespaceView.stackedProjects,
        stackedRailStore: stackedRailStore,
        hiddenTerminalIDsByProjectPath: hiddenTerminalIDsByProjectPath
    )
}

    var body: some View {
        GeometryReader { proxy in
            let railPosition = vibespaceView.selectedRailPosition
            let isHorizontalRail = railPosition.isHorizontalRail
            let presentation = presentation
            let visibleGroups = presentation.visibleGroups
            let hiddenEntries = presentation.hiddenEntries
            let cardHeight = stackedCardHeight(
                for: visibleGroups.count,
                availableHeight: proxy.size.height,
                isHorizontal: isHorizontalRail
            )
            let cardWidth = stackedCardWidth(
                for: visibleGroups.count,
                availableWidth: proxy.size.width
            )
            let verticalRailCardWidth = max(proxy.size.width - 12, 220)

            VStack(spacing: 0) {
                if visibleGroups.isEmpty {
                    emptyRailState(hiddenEntries: hiddenEntries)
                } else if isHorizontalRail {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(visibleGroups) { group in
                                stackedRailProjectGroup(
                                    for: group,
                                    preferredHeight: cardHeight,
                                    preferredWidth: cardWidth
                                )
                            }
                        }
                        .padding([.horizontal, .bottom], 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .scrollClipDisabled()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(visibleGroups) { group in
                                stackedRailProjectGroup(
                                    for: group,
                                    preferredHeight: cardHeight,
                                    preferredWidth: verticalRailCardWidth
                                )
                            }
                        }
                        .padding([.horizontal, .bottom], 6)
                    }
                    .scrollClipDisabled()
                }

                if !hiddenEntries.isEmpty {
                    Divider()
                    hiddenRailTerminalsSection(
                        hiddenEntries,
                        isHorizontalRail: isHorizontalRail,
                        presentation: presentation
                    )
                }
            }
        }
    }

    private func emptyRailState(hiddenEntries: [StackedRailTerminalEntry]) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                vibespaceView.activeVibeSpaceProjects.isEmpty
                    ? "No Projects in VibeSpace"
                    : (hiddenEntries.isEmpty ? "No Rail Terminals" : "All Rail Terminals Hidden"),
                systemImage: "terminal",
                description: Text(
                    vibespaceView.activeVibeSpaceProjects.isEmpty
                        ? "Add project folders to start building this vibespace."
                        : (hiddenEntries.isEmpty
                            ? "No visible vibespace terminals are available right now."
                            : "Use the hidden terminals section below to restore terminals to the rail.")
                )
            )
            Button {
                onAddProjectsRequested()
            } label: {
                Label("Add Project(s)", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.crispyvibesPrimary)
            .accessibilityIdentifier("vibespace.rail.add-projects")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stackedRailProjectGroup(
        for group: StackedRailProjectGroup,
        preferredHeight: CGFloat,
        preferredWidth: CGFloat?
    ) -> some View {
        let accentColor = projectColorTagsByPath[group.projectPath]?.color
            ?? activeThemePalette.accentColor
        let shortcutIndex = vibespaceView.activeVibeSpace?.shortcutIndex(for: group.project)
        let cardRenderer = makeCardRenderer(
            for: group.project,
            projectTitle: group.project.title,
            accentColor: accentColor,
            preferredHeight: preferredHeight,
            preferredWidth: preferredWidth
        )
        let onFocusEntry: (StackedRailTerminalEntry) -> Void = { entry in
            onFocusTerminal(group.project, entry.terminalTab)
        }

        return StackedRailProjectStackView(
            group: group,
            stackedRailOverlayCoordinator: stackedRailOverlayCoordinator,
            railPosition: vibespaceView.selectedRailPosition,
            preferredHeight: preferredHeight,
            preferredWidth: preferredWidth,
            accentColor: accentColor,
            shortcutIndex: shortcutIndex,
            projectTitle: group.project.title,
            onCard: cardRenderer,
            onFocusEntry: onFocusEntry
        )
    }

    private func makeCardRenderer(
        for project: AnyProjectSession,
        projectTitle: String,
        accentColor: Color,
        preferredHeight: CGFloat,
        preferredWidth: CGFloat?
    ) -> StackedRailCardRenderer {
        { entry, showsProjectTitle, shortcutIndex, showsStackAffordance in
            AnyView(
                stackedRailCard(
                    entry,
                    project,
                    projectTitle,
                    showsProjectTitle,
                    accentColor,
                    shortcutIndex,
                    preferredHeight,
                    preferredWidth,
                    showsStackAffordance
                )
            )
        }
    }

    private func stackedRailCard(
        _ entry: StackedRailTerminalEntry,
        _ project: AnyProjectSession,
        _ projectTitle: String,
        _ showsProjectTitle: Bool,
        _ accentColor: Color,
        _ shortcutIndex: Int?,
        _ preferredHeight: CGFloat,
        _ preferredWidth: CGFloat?,
        _ showsStackAffordance: Bool
    ) -> some View {
        StackedTerminalCardView(
            title: entry.terminalTab.title,
            projectTitle: projectTitle,
            showsProjectTitle: showsProjectTitle,
            visibleTerminalCount: groupVisibleTerminalCount(
                projectPath: entry.projectPath,
                project: project
            ),
            showsStackAffordance: showsStackAffordance,
            tabActivityState: project.terminal.tabActivityStateOrInactive(for: entry.terminalTab.id),
            session: project.terminal.session(for: entry.terminalTab.id),
            preferredHeight: preferredHeight,
            preferredWidth: preferredWidth,
            accentColor: accentColor,
            shortcutIndex: shortcutIndex,
            onFocus: {
                onFocusTerminal(project, entry.terminalTab)
            },
            onClose: {
                onCloseTerminal(project, entry.terminalTab)
            },
            onHide: {
                onHideTerminal(entry.projectPath, entry.terminalTab.id, project)
            },
            onRestart: {
                onRestartTerminal(entry.projectPath, entry.terminalTab, project)
            },
            onRename: { renamedTitle in
                onRenameTerminal(project, entry.terminalTab.id, renamedTitle)
            },
            onSpotlight: {
                onSpotlightTerminal(project, entry.terminalTab)
            }
        )
    }

    private func groupVisibleTerminalCount(projectPath: String, project: AnyProjectSession) -> Int {
        let hiddenIDs = hiddenTerminalIDsByProjectPath[projectPath] ?? []
        return stackedRailStore.tabs(for: projectPath).filter { !hiddenIDs.contains($0.id) }.count
    }

    private func hiddenRailTerminalsSection(
        _ hiddenEntries: [StackedRailTerminalEntry],
        isHorizontalRail: Bool,
        presentation: StackedRailPresentation
    ) -> some View {
        VStack(spacing: 8) {
            DisclosureGroup(isExpanded: isHiddenRailSectionExpanded) {
                if isHorizontalRail {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(hiddenEntries) { entry in
                                hiddenRailTerminalChip(for: entry, presentation: presentation)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(hiddenEntries) { entry in
                            hiddenRailTerminalChip(for: entry, presentation: presentation)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Hidden Terminals")
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(activeThemePalette.primaryTextColor)

                    Text("\(hiddenEntries.count)")
                        .font(AppTypographyTokens.caption2Semibold)
                        .foregroundStyle(activeThemePalette.secondaryTextColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(activeThemePalette.canvasSecondaryBackgroundColor)
                        .clipShape(Capsule())

                    Spacer(minLength: 8)

                    Button("Show All") {
                        for entry in hiddenEntries {
                            onUnhideTerminal(entry.projectPath, entry.terminalTab.id)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(activeThemePalette.accentColor)
                }
            }
        }
        .padding(8)
        .background(activeThemePalette.canvasBackgroundColor.opacity(0.95))
    }

    private func hiddenRailTerminalChip(
        for entry: StackedRailTerminalEntry,
        presentation: StackedRailPresentation
    ) -> some View {
        let project = presentation.project(for: entry)
        let accentColor = project.flatMap { projectColorTagsByPath[$0.rootURL.standardizedFileURL.path]?.color }
            ?? activeThemePalette.accentColor
        let projectTitle = project?.title ?? entry.projectPath

        return Button {
            onUnhideTerminal(entry.projectPath, entry.terminalTab.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .foregroundStyle(accentColor)
                Text(entry.terminalTab.title)
                    .font(AppTypographyTokens.caption2Semibold)
                    .lineLimit(1)
                    .foregroundStyle(activeThemePalette.primaryTextColor)
                Text(projectTitle)
                    .font(AppTypographyTokens.caption2)
                    .lineLimit(1)
                    .foregroundStyle(activeThemePalette.secondaryTextColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(activeThemePalette.canvasSecondaryBackgroundColor.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accentColor.opacity(0.22), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show in Rail") {
                onUnhideTerminal(entry.projectPath, entry.terminalTab.id)
            }
            Button("Restart Terminal") {
                onRestartTerminal(entry.projectPath, entry.terminalTab, project)
            }
            Button("Close Terminal") {
                guard let project else { return }
                onCloseTerminal(project, entry.terminalTab)
            }
        }
    }
}

struct StackedRailProjectStackView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @FocusState private var isKeyboardFocused: Bool

    let group: StackedRailProjectGroup
    @ObservedObject var stackedRailOverlayCoordinator: StackedRailExpansionOverlayCoordinator
    let railPosition: ProjectRailPosition
    let preferredHeight: CGFloat
    let preferredWidth: CGFloat?
    let accentColor: Color
    let shortcutIndex: Int?
    let projectTitle: String
    let onCard: StackedRailCardRenderer
    let onFocusEntry: (StackedRailTerminalEntry) -> Void
    @State private var primaryCardFrame: CGRect = .zero

    private var isExpanded: Bool {
        isKeyboardFocused || stackedRailOverlayCoordinator.presentation?.group.projectPath == group.projectPath
    }

    private var isHorizontalRail: Bool {
        railPosition.isHorizontalRail
    }

    private var visibleTerminalCount: Int {
        group.orderedVisibleEntries.count
    }

    private var peekCount: Int {
        min(max(visibleTerminalCount - 1, 0), 2)
    }

    private func peekWidth(for index: Int) -> CGFloat? {
        guard let preferredWidth else { return nil }
        return max(preferredWidth - CGFloat(index + 1) * 8, 160)
    }

    private func peekHeight(for index: Int) -> CGFloat {
        max(preferredHeight - CGFloat(index + 1) * 8, 84)
    }

    private func peekOffset(for index: Int) -> CGSize {
        if isHorizontalRail {
            return CGSize(width: 0, height: CGFloat(index + 1) * -8)
        }
        if railPosition.expandsTowardLeadingInCanvas {
            return CGSize(width: CGFloat(index + 1) * -8, height: 0)
        }
        return CGSize(width: CGFloat(index + 1) * 8, height: 0)
    }

    private func peekFillOpacity(for index: Int) -> Double {
        0.88 - Double(index) * 0.12
    }

    var body: some View {
        stackContainer
            .focusable()
            .focused($isKeyboardFocused)
            .onHover(perform: handleHover)
            .onChange(of: isKeyboardFocused) { _, focused in
                if focused {
                    showOverlay()
                } else {
                    stackedRailOverlayCoordinator.scheduleDismiss(projectPath: group.projectPath)
                }
            }
            .onDisappear {
                stackedRailOverlayCoordinator.dismiss(projectPath: group.projectPath)
            }
            .zIndex(isExpanded ? 200 : 0)
            .animation(.easeOut(duration: 0.12), value: isExpanded)
    }

    private var showsStackShell: Bool {
        visibleTerminalCount > 1
    }

    private var stackContainer: some View {
        stackBody
    }

    private var stackBody: some View {
        primaryCard
    }

    private var primaryCard: some View {
        ZStack(alignment: .topLeading) {
            if showsStackShell {
                stackShell
            }
            collapsedPeekLayers
            cardView(
                for: group.primaryEntry,
                visibleTerminalCount: visibleTerminalCount,
                shortcutIndex: shortcutIndex,
                showsStackAffordance: visibleTerminalCount > 1,
                showsProjectTitle: true
            )
        }
        .background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        primaryCardFrame = frame
                        stackedRailOverlayCoordinator.updateAnchorFrame(frame, for: group.projectPath)
                    }
                    .onChange(of: frame) { _, newFrame in
                        primaryCardFrame = newFrame
                        stackedRailOverlayCoordinator.updateAnchorFrame(newFrame, for: group.projectPath)
                    }
            }
        )
        .zIndex(10)
    }

    private var stackShell: some View {
        RoundedRectangle(cornerRadius: crispyvibesTheme.radius(14), style: .continuous)
            .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(14), style: .continuous)
                    .stroke(accentColor.opacity(0.08), lineWidth: 0.8)
            )
            .frame(
                width: (preferredWidth ?? max(primaryCardFrame.width, 220)) + 10,
                height: preferredHeight + 8
            )
            .offset(stackShellOffset)
            .shadow(
                color: appThemePalette.canvasBackgroundColor.opacity(0.08),
                radius: 8,
                x: 0,
                y: 4
            )
    }

    private var stackShellOffset: CGSize {
        switch railPosition {
        case .left:
            return CGSize(width: 5, height: 0)
        case .right:
            return CGSize(width: -5, height: 0)
        case .top, .bottom:
            return CGSize(width: 0, height: -5)
        }
    }

    @ViewBuilder
    private var collapsedPeekLayers: some View {
        if !isExpanded {
            ForEach(0..<peekCount, id: \.self) { index in
                let cornerRadius = crispyvibesTheme.radius(10)
                let offset = peekOffset(for: index)
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                    .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(peekFillOpacity(for: index)))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(accentColor.opacity(0.18 - Double(index) * 0.04))
                            .frame(width: 2)
                            .padding(.vertical, 10)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(accentColor.opacity(0.12), lineWidth: 1)
                    )
                    .frame(
                        width: peekWidth(for: index),
                        height: peekHeight(for: index)
                    )
                    .offset(offset)
                    .shadow(
                        color: appThemePalette.canvasBackgroundColor.opacity(0.18 - Double(index) * 0.04),
                        radius: 10,
                        x: 0,
                        y: 5
                    )
            }
        }
    }

    @ViewBuilder
    private func cardView(
        for entry: StackedRailTerminalEntry?,
        visibleTerminalCount: Int,
        shortcutIndex: Int?,
        showsStackAffordance: Bool,
        showsProjectTitle: Bool
    ) -> some View {
        if let entry {
            onCard(
                entry,
                showsProjectTitle,
                shortcutIndex,
                showsStackAffordance
            )
        }
    }

    private func handleHover(_ isHovering: Bool) {
        if isHovering {
            showOverlay()
            return
        }
        stackedRailOverlayCoordinator.scheduleDismiss(
            projectPath: group.projectPath,
            isKeyboardFocused: isKeyboardFocused
        )
    }

    private func showOverlay() {
        guard let anchorFrame = currentAnchorFrame else { return }
        stackedRailOverlayCoordinator.show(
            StackedRailExpansionOverlayPresentation(
                group: group,
                railPosition: railPosition,
                anchorFrame: anchorFrame,
                preferredHeight: preferredHeight,
                preferredWidth: preferredWidth,
                accentColor: accentColor,
                shortcutIndex: shortcutIndex,
                projectTitle: projectTitle,
                onCard: onCard,
                onFocusEntry: onFocusEntry
            )
        )
    }

    private var currentAnchorFrame: CGRect? {
        primaryCardFrame.isEmpty ? nil : primaryCardFrame
    }
}

struct StackedRailExpansionCanvasOverlay: View {
    @ObservedObject var coordinator: StackedRailExpansionOverlayCoordinator

    var body: some View {
        GeometryReader { proxy in
            if let presentation = coordinator.presentation {
                let rootFrame = proxy.frame(in: .global)
                let metrics = StackedRailOverlayMetrics(
                    railPosition: presentation.railPosition,
                    anchorFrame: presentation.anchorFrame,
                    rootFrame: rootFrame,
                    preferredHeight: presentation.preferredHeight,
                    preferredWidth: presentation.preferredWidth,
                    additionalCardCount: presentation.group.additionalEntries.count
                )
                let animationKey = coordinator.presentation?.id ?? ""
                let projectPath = presentation.group.projectPath

                ZStack(alignment: .topLeading) {
                    ForEach(Array(presentation.group.additionalEntries.enumerated()), id: \.element.id) { index, entry in
                        StackedRailExpansionOverlayItemView(
                            coordinator: coordinator,
                            projectPath: projectPath,
                            entry: entry,
                            projectTitle: presentation.projectTitle,
                            accentColor: presentation.accentColor,
                            tabActivityState: presentation.group.project.terminal.tabActivityStateOrInactive(for: entry.terminalTab.id),
                            session: presentation.group.project.terminal.session(for: entry.terminalTab.id),
                            preferredHeight: presentation.preferredHeight,
                            preferredWidth: presentation.preferredWidth,
                            onFocusEntry: presentation.onFocusEntry
                        )
                        .position(metrics.center(for: index))
                        .transition(
                            .asymmetric(
                                insertion: .offset(metrics.transitionOffset(for: index, phase: .insertion))
                                    .combined(with: .opacity),
                                removal: .offset(metrics.transitionOffset(for: index, phase: .removal))
                                    .combined(with: .opacity)
                            )
                        )
                        .animation(
                            .interactiveSpring(response: 0.16, dampingFraction: 0.94).delay(Double(index) * 0.01),
                            value: animationKey
                        )
                        .zIndex(Double(max(0, presentation.group.additionalEntries.count - index)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(true)
                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.95), value: animationKey)
            }
        }
    }
}

private struct StackedRailExpansionOverlayItemView: View {
    @ObservedObject var coordinator: StackedRailExpansionOverlayCoordinator
    let projectPath: String
    let entry: StackedRailTerminalEntry
    let projectTitle: String
    let accentColor: Color
    @ObservedObject var tabActivityState: TerminalTabActivityState
    let session: TerminalSession?
    let preferredHeight: CGFloat
    let preferredWidth: CGFloat?
    let onFocusEntry: (StackedRailTerminalEntry) -> Void

    var body: some View {
        StackedRailOverlayPreviewCardView(
            entry: entry,
            projectTitle: projectTitle,
            accentColor: accentColor,
            tabActivityState: tabActivityState,
            session: session,
            preferredHeight: preferredHeight,
            preferredWidth: preferredWidth,
            onFocus: {
                onFocusEntry(entry)
                coordinator.dismiss(projectPath: projectPath)
            }
        )
        .onHover { isHovering in
            coordinator.setOverlayHover(
                projectPath: projectPath,
                isHovering: isHovering
            )
        }
    }
}

private struct StackedRailOverlayMetrics {
    enum TransitionPhase {
        case insertion
        case removal
    }

    let railPosition: ProjectRailPosition
    let anchorFrame: CGRect
    let rootFrame: CGRect
    let preferredHeight: CGFloat
    let preferredWidth: CGFloat?
    let additionalCardCount: Int

    private let stackSpacing: CGFloat = 6
    private let revealOverlap: CGFloat = 18

    private var cardWidth: CGFloat {
        preferredWidth ?? anchorFrame.width
    }

    func center(for index: Int) -> CGPoint {
        let anchorMinX = anchorFrame.minX - rootFrame.minX
        let anchorMinY = anchorFrame.minY - rootFrame.minY
        let anchorMaxX = anchorFrame.maxX - rootFrame.minX
        let anchorMidY = anchorMinY + preferredHeight / 2

        switch railPosition {
        case .left, .right:
            let firstCardLeadingEdge = anchorMaxX - revealOverlap
            return CGPoint(
                x: firstCardLeadingEdge + cardWidth / 2 + CGFloat(index) * (cardWidth + stackSpacing),
                y: anchorMidY
            )
        case .top, .bottom:
            let firstCardTopEdge = anchorMinY - preferredHeight + revealOverlap
            return CGPoint(
                x: anchorMinX + cardWidth / 2 + CGFloat(index) * (cardWidth + stackSpacing),
                y: firstCardTopEdge + preferredHeight / 2
            )
        }
    }

    func transitionOffset(for index: Int, phase: TransitionPhase) -> CGSize {
        let distance = 16 + CGFloat(index) * 4
        switch railPosition {
        case .left, .right:
            return CGSize(width: phase == .insertion ? -distance : -distance * 0.82, height: 0)
        case .top, .bottom:
            return CGSize(width: 0, height: phase == .insertion ? distance : distance * 0.82)
        }
    }

}

private struct StackedRailOverlayPreviewCardView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @ObservedObject var tabActivityState: TerminalTabActivityState

    let entry: StackedRailTerminalEntry
    let projectTitle: String
    let accentColor: Color
    let session: TerminalSession?
    let preferredHeight: CGFloat
    let preferredWidth: CGFloat?
    let onFocus: () -> Void

    init(
        entry: StackedRailTerminalEntry,
        projectTitle: String,
        accentColor: Color,
        tabActivityState: TerminalTabActivityState,
        session: TerminalSession?,
        preferredHeight: CGFloat,
        preferredWidth: CGFloat?,
        onFocus: @escaping () -> Void
    ) {
        self.entry = entry
        self.projectTitle = projectTitle
        self.accentColor = accentColor
        self._tabActivityState = ObservedObject(wrappedValue: tabActivityState)
        self.session = session
        self.preferredHeight = preferredHeight
        self.preferredWidth = preferredWidth
        self.onFocus = onFocus
    }

    var body: some View {
        VStack(spacing: 0) {
            CrispyVibesHeaderChrome(style: .card) {
                TerminalActivityBar(isActive: tabActivityState.isActive, color: accentColor)
                    .frame(width: 4, height: 28)

                Text(entry.terminalTab.title)
                    .font(CrispyVibesHeaderStyle.panel.titleFont(scale: 1))
                    .lineLimit(1)
                    .foregroundStyle(palette.primaryTextColor)

                Spacer(minLength: 8)
            }

            Rectangle()
                .fill(palette.primaryTextColor.opacity(0.08))
                .frame(height: 1)

            Group {
                if let session {
                    TerminalSessionHostView(
                        session: session,
                        displayDensity: .compact,
                        isActive: true,
                        accessibilityIdentifier: "project.stacked.overlay.terminal.host"
                    )
                    .id(session.viewIdentity)
                    .allowsHitTesting(false)
                } else {
                    ContentUnavailableView(
                        "Terminal Unavailable",
                        systemImage: "terminal",
                        description: Text("This terminal session is no longer available.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: preferredWidth, height: preferredHeight, alignment: .topLeading)
        .background(palette.canvasBackgroundColor.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(10), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(10), style: .continuous)
                .stroke(accentColor.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: palette.canvasBackgroundColor.opacity(0.18), radius: 10, x: 0, y: 5)
        .contentShape(Rectangle())
        .environment(\.terminalHostOwnershipPriorityBoost, 30)
        .onTapGesture(perform: onFocus)
    }
}
