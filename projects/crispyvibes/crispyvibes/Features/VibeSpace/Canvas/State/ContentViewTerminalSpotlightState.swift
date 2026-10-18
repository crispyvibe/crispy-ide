import AppKit
import SwiftUI

enum SpotlightSwipeDirection {
    case none, leading, trailing
}

struct SpotlightScrollGestureSample {
    let phase: NSEvent.Phase
    let momentumPhase: NSEvent.Phase
    let deltaX: CGFloat
    let deltaY: CGFloat
    let isPrecise: Bool
    var beginsOverShelf = false
    var beginsOverExcludedShelfControl = false
}

enum SpotlightScrollGestureAction: Equatable {
    case passThrough(resetOffset: Bool)
    case routeToShelf
    case consume
    case consumeAndResetOffset
    case updateOffset(CGFloat)
    case finishSwitch(Int?)
}

struct SpotlightScrollGestureTracker {
    private enum Owner {
        case undecided, shelfPending, shelf, carousel, vertical
    }

    private(set) var cumulativeDeltaX: CGFloat = 0
    private(set) var cumulativeDeltaY: CGFloat = 0
    private(set) var isTracking = false
    private(set) var isHorizontalGesture = false
    private(set) var isVerticalGesture = false
    private var owner: Owner = .undecided

    mutating func handle(
        _ sample: SpotlightScrollGestureSample,
        carouselEnabled: Bool,
        terminalReservesScroll: Bool
    ) -> SpotlightScrollGestureAction {
        guard sample.isPrecise else {
            reset()
            return .passThrough(resetOffset: true)
        }

        if sample.phase == .began {
            reset()
            isTracking = true
            if sample.beginsOverExcludedShelfControl {
                owner = .vertical
                return .passThrough(resetOffset: true)
            }
            if sample.beginsOverShelf {
                owner = .shelfPending
                return .passThrough(resetOffset: true)
            }
            guard carouselEnabled, !terminalReservesScroll else {
                return .passThrough(resetOffset: true)
            }
            return .passThrough(resetOffset: true)
        }

        if owner == .shelf {
            if sample.momentumPhase == .ended || sample.momentumPhase == .cancelled {
                reset()
            }
            return .routeToShelf
        }

        if owner == .shelfPending {
            if sample.momentumPhase != [] {
                if sample.momentumPhase == .ended || sample.momentumPhase == .cancelled { reset() }
                return .passThrough(resetOffset: true)
            }
            if sample.phase == .changed {
                cumulativeDeltaX += sample.deltaX
                cumulativeDeltaY += sample.deltaY
                guard max(abs(cumulativeDeltaX), abs(cumulativeDeltaY)) > 4 else {
                    return .passThrough(resetOffset: true)
                }
                if abs(cumulativeDeltaX) > abs(cumulativeDeltaY) {
                    owner = .shelf
                    isHorizontalGesture = true
                    return .routeToShelf
                }
                owner = .vertical
                isVerticalGesture = true
                return .passThrough(resetOffset: true)
            }
            if sample.phase == .ended || sample.phase == .cancelled { reset() }
            return .passThrough(resetOffset: true)
        }

        guard carouselEnabled, !terminalReservesScroll else {
            reset()
            return .passThrough(resetOffset: true)
        }

        if sample.momentumPhase != [] {
            let shouldConsume = owner == .carousel || isHorizontalGesture
            if sample.momentumPhase == .ended || sample.momentumPhase == .cancelled {
                reset()
                return shouldConsume ? .consumeAndResetOffset : .passThrough(resetOffset: true)
            }
            return shouldConsume ? .consume : .passThrough(resetOffset: false)
        }

        switch sample.phase {
        case .changed where isTracking:
            cumulativeDeltaX += sample.deltaX
            cumulativeDeltaY += sample.deltaY
            if owner != .carousel {
                if owner == .vertical {
                    return .passThrough(resetOffset: false)
                }
                if abs(cumulativeDeltaY) > 12,
                   abs(cumulativeDeltaY) > abs(cumulativeDeltaX) {
                    owner = .vertical
                    isVerticalGesture = true
                    return .passThrough(resetOffset: false)
                }
                guard abs(cumulativeDeltaX) > 20,
                      abs(cumulativeDeltaX) > abs(cumulativeDeltaY) * 2 else {
                    return .passThrough(resetOffset: false)
                }
                owner = .carousel
                isHorizontalGesture = true
            }
            return .updateOffset(cumulativeDeltaX * 0.35)
        case .ended, .cancelled:
            guard isTracking else {
                reset()
                return .passThrough(resetOffset: false)
            }
            let wasHorizontal = owner == .carousel
            let finalDeltaX = cumulativeDeltaX
            isTracking = false
            cumulativeDeltaX = 0
            cumulativeDeltaY = 0
            guard wasHorizontal else {
                reset()
                return .passThrough(resetOffset: false)
            }
            let switchOffset = abs(finalDeltaX) > 50 ? (finalDeltaX < 0 ? 1 : -1) : nil
            return .finishSwitch(switchOffset)
        default:
            return .passThrough(resetOffset: false)
        }
    }

    mutating func reset() {
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
        isTracking = false
        isHorizontalGesture = false
        isVerticalGesture = false
        owner = .undecided
    }
}

enum SpotlightItem {
    case terminal(project: AnyProjectSession, tab: TerminalTab)
    case standaloneTerminal(
        surfaceID: UUID,
        tileID: UUID,
        terminalViewModel: TerminalViewModel,
        tab: TerminalTab
    )
    case vibeCast
    case vibeLanes
    case acp(tileID: UUID, storeID: UUID, title: String, accentColor: Color?)
    case file(tileID: UUID, fileURL: URL)
    case browser(tileID: UUID, url: URL)

    @MainActor
    var navigationIdentity: SpotlightNavigationIdentity {
        switch self {
        case let .terminal(project, tab):
            return .terminal(
                projectScope: .projectPath(project.rootURL.standardizedFileURL.path),
                tabID: tab.id
            )
        case let .standaloneTerminal(_, tileID, _, tab):
            return .terminal(projectScope: .unscoped(tileID), tabID: tab.id)
        case .vibeCast:
            return .vibeCast
        case .vibeLanes:
            return .vibeLanes
        case let .acp(tileID, storeID, _, _):
            return .acp(tileID: tileID, storeID: storeID)
        case let .file(tileID, _):
            return .file(tileID: tileID)
        case let .browser(tileID, _):
            return .browser(tileID: tileID)
        }
    }
}

enum SpotlightTerminalProjectScope: Hashable {
    case projectPath(String)
    case unscoped(UUID)

    static func projectRoot(_ rootURL: URL) -> Self {
        .projectPath(rootURL.standardizedFileURL.path)
    }

    var diagnosticToken: String {
        switch self {
        case let .projectPath(path):
            return AppDiagnostics.pathToken(path)
        case let .unscoped(identity):
            return "unscoped#\(identity.uuidString)"
        }
    }
}

enum SpotlightNavigationIdentity: Hashable {
    case terminal(projectScope: SpotlightTerminalProjectScope, tabID: UUID)
    case vibeCast
    case vibeLanes
    case acp(tileID: UUID, storeID: UUID)
    case file(tileID: UUID)
    case browser(tileID: UUID)

    var diagnosticToken: String {
        switch self {
        case let .terminal(projectScope, tabID):
            return "terminal:\(projectScope.diagnosticToken):\(tabID.uuidString)"
        case .vibeCast:
            return "vibeCast"
        case .vibeLanes:
            return "vibeLanes"
        case let .acp(tileID, storeID):
            return "acp:\(tileID.uuidString):\(storeID.uuidString)"
        case let .file(tileID):
            return "file:\(tileID.uuidString)"
        case let .browser(tileID):
            return "browser:\(tileID.uuidString)"
        }
    }
}

struct SpotlightNavigationSelection {
    let item: SpotlightItem
    let sourceIdentity: SpotlightNavigationIdentity
    let targetIdentity: SpotlightNavigationIdentity
    let direction: Int
}

@MainActor
enum SpotlightNavigationResolver {
    static func hasNavigableCurrentItem(
        currentIdentity: SpotlightNavigationIdentity?,
        items: [SpotlightItem]
    ) -> Bool {
        guard let currentIdentity else { return false }
        return items.contains { $0.navigationIdentity == currentIdentity }
    }

    static func carouselNavigationEnabled(
        for spotlight: TerminalSpotlightState,
        items: [SpotlightItem]
    ) -> Bool {
        spotlight.supportsCarouselNavigation
            && items.count > 1
            && hasNavigableCurrentItem(
                currentIdentity: spotlight.navigationIdentity,
                items: items
            )
    }

    static func relativeSelection(
        offset: Int,
        currentIdentity: SpotlightNavigationIdentity,
        items: [SpotlightItem]
    ) -> SpotlightNavigationSelection? {
        guard !items.isEmpty,
              let currentIndex = items.firstIndex(where: { $0.navigationIdentity == currentIdentity }) else {
            return nil
        }
        let targetIndex = (currentIndex + offset + items.count) % items.count
        let targetItem = items[targetIndex]
        guard targetItem.navigationIdentity != currentIdentity else { return nil }
        return SpotlightNavigationSelection(
            item: targetItem,
            sourceIdentity: currentIdentity,
            targetIdentity: targetItem.navigationIdentity,
            direction: offset > 0 ? 1 : -1
        )
    }

    static func selection(
        targetIdentity: SpotlightNavigationIdentity,
        currentIdentity: SpotlightNavigationIdentity,
        items: [SpotlightItem]
    ) -> SpotlightNavigationSelection? {
        guard targetIdentity != currentIdentity,
              let currentIndex = items.firstIndex(where: { $0.navigationIdentity == currentIdentity }),
              let targetIndex = items.firstIndex(where: { $0.navigationIdentity == targetIdentity }) else {
            return nil
        }
        return SpotlightNavigationSelection(
            item: items[targetIndex],
            sourceIdentity: currentIdentity,
            targetIdentity: targetIdentity,
            direction: targetIndex > currentIndex ? 1 : -1
        )
    }
}

struct SpotlightSwitchTransaction {
    let generation: UInt64
    let sourceIdentity: SpotlightNavigationIdentity
    let targetIdentity: SpotlightNavigationIdentity
}

struct TerminalSpotlightState: Identifiable {
    enum Source {
        case persistent(terminalViewModel: TerminalViewModel, tabID: UUID)
        case transient(session: TerminalSession)
        case vibeCast
        case vibeLanes
        case todos
        case acp(tileID: UUID, storeID: UUID)
        case filePreview(target: TerminalFileSystemTarget, group: EditorGroupStore)
        case file(tileID: UUID, fileURL: URL, group: EditorGroupStore)
        case browserPreview(snapshot: BrowserSessionSnapshot)
        case browser(tileID: UUID, url: URL)
    }

    let id: UUID
    let source: Source
    let title: String
    let accentColor: Color?
    let workingDirectoryURL: URL
    let onSplitTerminalRequested: (() -> Void)?
    let onTemporaryTerminalRequested: (() -> Void)?
    let shortcutDefinitions: [TerminalShortcutDefinition]
    let onShortcutSelected: ((TerminalShortcutDefinition) -> Void)?
    let onManageShortcutsRequested: (() -> Void)?
    let agentPresets: [TerminalPresetDefinition]
    let onAgentPresetSelected: ((TerminalPresetDefinition, TerminalPresetLaunchMode) -> Void)?
    let isTemporary: Bool
    let owningProjectRootURL: URL?
    let surfaceID: UUID?
    let navigationIdentityOverride: SpotlightNavigationIdentity?

    init(
        id: UUID,
        source: Source,
        title: String,
        accentColor: Color?,
        workingDirectoryURL: URL,
        onSplitTerminalRequested: (() -> Void)?,
        onTemporaryTerminalRequested: (() -> Void)?,
        shortcutDefinitions: [TerminalShortcutDefinition] = [],
        onShortcutSelected: ((TerminalShortcutDefinition) -> Void)? = nil,
        onManageShortcutsRequested: (() -> Void)? = nil,
        agentPresets: [TerminalPresetDefinition] = [],
        onAgentPresetSelected: ((TerminalPresetDefinition, TerminalPresetLaunchMode) -> Void)? = nil,
        isTemporary: Bool,
        owningProjectRootURL: URL?,
        surfaceID: UUID? = nil,
        navigationIdentityOverride: SpotlightNavigationIdentity? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.accentColor = accentColor
        self.workingDirectoryURL = workingDirectoryURL
        self.onSplitTerminalRequested = onSplitTerminalRequested
        self.onTemporaryTerminalRequested = onTemporaryTerminalRequested
        self.shortcutDefinitions = shortcutDefinitions
        self.onShortcutSelected = onShortcutSelected
        self.onManageShortcutsRequested = onManageShortcutsRequested
        self.agentPresets = agentPresets
        self.onAgentPresetSelected = onAgentPresetSelected
        self.isTemporary = isTemporary
        self.owningProjectRootURL = owningProjectRootURL
        self.surfaceID = surfaceID
        self.navigationIdentityOverride = navigationIdentityOverride
    }
}

/// Exact live Spotlight state retained while a temporary presentation is active.
/// Keeping the state value preserves its stable ID, live owner, callbacks, surface
/// affinity, and standalone navigation identity across nested restore chains.
struct SpotlightRestoreDescriptor {
    let spotlight: TerminalSpotlightState
}

extension TerminalSpotlightState.Source {
    var supportsCarouselNavigation: Bool {
        switch self {
        case .persistent, .vibeCast, .vibeLanes, .acp, .file, .browser:
            return true
        case .transient, .todos, .filePreview, .browserPreview:
            return false
        }
    }

    @MainActor
    var reservesScrollForTerminalViewport: Bool {
        switch self {
        case let .persistent(terminalViewModel, tabID):
            return (terminalViewModel.session(for: tabID)?.displayMagnification ?? 1) > 1
        case let .transient(session):
            return session.displayMagnification > 1
        case .vibeCast, .vibeLanes, .todos, .acp, .filePreview, .file, .browserPreview, .browser:
            return false
        }
    }

    var showsTemporaryBadge: Bool {
        switch self {
        case .transient, .filePreview, .browserPreview:
            return true
        case .persistent, .vibeCast, .vibeLanes, .todos, .acp, .file, .browser:
            return false
        }
    }

    var headerIconName: String {
        switch self {
        case .persistent:
            return "terminal"
        case .transient:
            return "scope"
        case .vibeCast:
            return "antenna.radiowaves.left.and.right"
        case .vibeLanes:
            return VibeLaneVisualIdentity.symbolName
        case .todos:
            return "checklist"
        case .acp:
            return "sparkles"
        case .filePreview, .file:
            return "doc.text"
        case .browserPreview, .browser:
            return "globe"
        }
    }

    var showsComposeInputBar: Bool {
        switch self {
        case .persistent, .transient:
            return true
        case .vibeCast, .vibeLanes, .todos, .acp, .filePreview, .file, .browserPreview, .browser:
            return false
        }
    }

    var supportsBoardPin: Bool {
        switch self {
        case .vibeLanes, .filePreview, .browserPreview:
            return true
        case .persistent, .transient, .vibeCast, .todos, .acp, .file, .browser:
            return false
        }
    }

    var canBeRestored: Bool {
        switch self {
        case .persistent, .transient, .vibeCast, .vibeLanes, .acp, .filePreview, .file, .browserPreview, .browser:
            return true
        case .todos:
            return false
        }
    }
}

extension TerminalSpotlightState {
    func replacingSource(_ source: Source) -> TerminalSpotlightState {
        TerminalSpotlightState(
            id: id,
            source: source,
            title: title,
            accentColor: accentColor,
            workingDirectoryURL: workingDirectoryURL,
            onSplitTerminalRequested: onSplitTerminalRequested,
            onTemporaryTerminalRequested: onTemporaryTerminalRequested,
            shortcutDefinitions: shortcutDefinitions,
            onShortcutSelected: onShortcutSelected,
            onManageShortcutsRequested: onManageShortcutsRequested,
            agentPresets: agentPresets,
            onAgentPresetSelected: onAgentPresetSelected,
            isTemporary: isTemporary,
            owningProjectRootURL: owningProjectRootURL,
            surfaceID: surfaceID,
            navigationIdentityOverride: navigationIdentityOverride
        )
    }

    var supportsCarouselNavigation: Bool { source.supportsCarouselNavigation }
    var showsTemporaryBadge: Bool { source.showsTemporaryBadge || isTemporary }
    var headerIconName: String { source.headerIconName }

    var navigationIdentity: SpotlightNavigationIdentity? {
        if let navigationIdentityOverride { return navigationIdentityOverride }
        switch source {
        case let .persistent(_, tabID):
            let projectScope = owningProjectRootURL.map(SpotlightTerminalProjectScope.projectRoot)
                ?? .unscoped(id)
            return .terminal(projectScope: projectScope, tabID: tabID)
        case .vibeCast:
            return .vibeCast
        case .vibeLanes:
            return .vibeLanes
        case let .acp(tileID, storeID):
            return .acp(tileID: tileID, storeID: storeID)
        case let .file(tileID, _, _):
            return .file(tileID: tileID)
        case let .browser(tileID, _):
            return .browser(tileID: tileID)
        case .transient, .todos, .filePreview, .browserPreview:
            return nil
        }
    }
}

@MainActor
final class TerminalSpotlightCoordinator: ObservableObject {
    private let diagnosticsSnapshot: TerminalDiagnosticsSnapshot
    @Published var spotlight: TerminalSpotlightState?
    @Published var swipeDirection: SpotlightSwipeDirection = .none
    @Published var swipeOffset: CGFloat = 0
    @Published var tabPageOffset: Int = 0
    @Published private(set) var activeSwitchGeneration: UInt64?
    @Published private(set) var isOverviewPresented = false
    @Published private(set) var layoutGeneration: UInt64 = 0
    private var isCarouselAvailable = false

    private var scrollMonitor: Any?
    private weak var shelfScrollView: NSScrollView?
    private weak var shelfHitRegion: NSView?
    private weak var shelfExcludedRegion: NSView?
    private(set) var scrollOwnershipGeneration: UInt64 = 0
    private var nextSwitchGeneration: UInt64 = 0
    private var pendingSwitchTransaction: SpotlightSwitchTransaction?
    private var switchStartWorkItem: DispatchWorkItem?
    private var switchCompletionWorkItem: DispatchWorkItem?
    private var focusWorkItem: DispatchWorkItem?
    private(set) var restoreStack: [SpotlightRestoreDescriptor] = []
    private let maxRestoreStackDepth = 8

    init(diagnosticsSnapshot: TerminalDiagnosticsSnapshot) {
        self.diagnosticsSnapshot = diagnosticsSnapshot
    }

    func setCarouselAvailable(_ isAvailable: Bool) {
        isCarouselAvailable = isAvailable
        if !isAvailable { swipeOffset = 0 }
    }

    func noteLayoutCommitted() {
        layoutGeneration &+= 1
        clearScrollSequenceOwnership()
    }

    deinit {
        MainActor.assumeIsolated {
            switchStartWorkItem?.cancel()
            switchCompletionWorkItem?.cancel()
            focusWorkItem?.cancel()
            removeScrollMonitor()
            let stackedSpotlights = restoreStack.map(\.spotlight)
            restoreStack.removeAll()
            for stackedSpotlight in stackedSpotlights {
                releaseTerminalSpotlightIfNeeded(stackedSpotlight, replacingWith: nil)
            }
            releaseTerminalSpotlightIfNeeded(spotlight, replacingWith: nil)
        }
    }

    func registerShelfScrollView(_ scrollView: NSScrollView?) {
        guard shelfScrollView !== scrollView else { return }
        shelfScrollView = scrollView
        clearScrollSequenceOwnership()
    }

    func registerShelfHitRegion(_ view: NSView?) {
        guard shelfHitRegion !== view else { return }
        shelfHitRegion = view
        clearScrollSequenceOwnership()
    }

    func registerShelfExcludedRegion(_ view: NSView?) {
        guard shelfExcludedRegion !== view else { return }
        shelfExcludedRegion = view
        clearScrollSequenceOwnership()
    }

    func presentOverview() {
        guard spotlight != nil, !isOverviewPresented else { return }
        isOverviewPresented = true
        clearScrollSequenceOwnership()
    }

    func dismissOverview() {
        guard isOverviewPresented else { return }
        isOverviewPresented = false
        clearScrollSequenceOwnership()
    }

    func clearScrollSequenceOwnership() {
        scrollOwnershipGeneration &+= 1
        swipeOffset = 0
    }

    func installScrollMonitor(onSwitchSpotlight: @escaping (Int) -> Void) {
        guard scrollMonitor == nil else { return }
        var gestureTracker = SpotlightScrollGestureTracker()
        var observedOwnershipGeneration = scrollOwnershipGeneration

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            if observedOwnershipGeneration != self.scrollOwnershipGeneration {
                gestureTracker.reset()
                observedOwnershipGeneration = self.scrollOwnershipGeneration
            }
            let beginsOverExcludedShelfControl = event.phase == .began && self.eventIsInsideShelfExcludedRegion(event)
            let beginsOverShelf = event.phase == .began && self.eventIsInsideShelf(event)
            let action = gestureTracker.handle(
                SpotlightScrollGestureSample(
                    phase: event.phase,
                    momentumPhase: event.momentumPhase,
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY,
                    isPrecise: event.hasPreciseScrollingDeltas,
                    beginsOverShelf: beginsOverShelf,
                    beginsOverExcludedShelfControl: beginsOverExcludedShelfControl
                ),
                carouselEnabled: self.spotlight?.supportsCarouselNavigation == true
                    && self.isCarouselAvailable
                    && !self.isOverviewPresented,
                terminalReservesScroll: self.spotlight?.source.reservesScrollForTerminalViewport == true
            )

            switch action {
            case let .passThrough(resetOffset):
                if resetOffset { self.swipeOffset = 0 }
                return event
            case .routeToShelf:
                self.routeScrollEventToShelf(event)
                return nil
            case .consume:
                return nil
            case .consumeAndResetOffset:
                self.swipeOffset = 0
                return nil
            case let .updateOffset(offset):
                withAnimation(.interactiveSpring(response: 0.08, dampingFraction: 0.9)) {
                    self.swipeOffset = offset
                }
                return nil
            case let .finishSwitch(offset):
                if let offset {
                    onSwitchSpotlight(offset)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        self.swipeOffset = 0
                    }
                }
                return nil
            }
        }
    }

    private func eventIsInsideShelfExcludedRegion(_ event: NSEvent) -> Bool {
        guard let excluded = shelfExcludedRegion,
              excluded.window === event.window,
              excluded.window != nil else { return false }
        return excluded.bounds.contains(excluded.convert(event.locationInWindow, from: nil))
    }

    private func eventIsInsideShelf(_ event: NSEvent) -> Bool {
        guard let hitRegion = shelfHitRegion,
              hitRegion.window === event.window,
              hitRegion.window != nil,
              hitRegion.bounds.contains(hitRegion.convert(event.locationInWindow, from: nil)) else { return false }
        if let excluded = shelfExcludedRegion,
           excluded.window === event.window,
           excluded.bounds.contains(excluded.convert(event.locationInWindow, from: nil)) {
            return false
        }
        return true
    }

    private func routeScrollEventToShelf(_ event: NSEvent) {
        guard let scrollView = shelfScrollView, scrollView.window != nil else {
            clearScrollSequenceOwnership()
            return
        }
        let clipView = scrollView.contentView
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let maximumX = max(documentWidth - clipView.bounds.width, 0)
        var origin = clipView.bounds.origin
        origin.x = max(0, min(origin.x - event.scrollingDeltaX, maximumX))
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    func removeScrollMonitor() {
        clearScrollSequenceOwnership()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    func beginCarouselSwitch(_ selection: SpotlightNavigationSelection) -> SpotlightSwitchTransaction {
        cancelSpotlightFocusRequestIfNeeded(spotlight)
        focusWorkItem?.cancel()
        focusWorkItem = nil
        switchStartWorkItem?.cancel()
        switchCompletionWorkItem?.cancel()
        nextSwitchGeneration &+= 1
        let transaction = SpotlightSwitchTransaction(
            generation: nextSwitchGeneration,
            sourceIdentity: selection.sourceIdentity,
            targetIdentity: selection.targetIdentity
        )
        activeSwitchGeneration = transaction.generation
        pendingSwitchTransaction = transaction
        swipeDirection = selection.direction > 0 ? .trailing : .leading
        swipeOffset = selection.direction > 0 ? 200 : -200
        return transaction
    }

    func cancelCarouselSwitch(_ transaction: SpotlightSwitchTransaction? = nil) {
        if let transaction, activeSwitchGeneration != transaction.generation {
            return
        }
        switchStartWorkItem?.cancel()
        switchStartWorkItem = nil
        switchCompletionWorkItem?.cancel()
        switchCompletionWorkItem = nil
        focusWorkItem?.cancel()
        focusWorkItem = nil
        pendingSwitchTransaction = nil
        activeSwitchGeneration = nil
        swipeDirection = .none
        swipeOffset = 0
    }

    func isCurrentSelection(
        _ identity: SpotlightNavigationIdentity,
        generation: UInt64?
    ) -> Bool {
        spotlight?.navigationIdentity == identity && activeSwitchGeneration == generation
    }

    func animateSwipeOffset(_ offset: CGFloat, animation: Animation? = nil) {
        if let animation {
            withAnimation(animation) {
                swipeOffset = offset
            }
        } else {
            swipeOffset = offset
        }
    }

    func dismiss(animated: Bool = true) {
        cancelCarouselSwitch()
        tabPageOffset = 0
        isOverviewPresented = false
        removeScrollMonitor()
        let stackedSpotlights = restoreStack.map(\.spotlight)
        restoreStack.removeAll()
        for stackedSpotlight in stackedSpotlights {
            releaseTerminalSpotlightIfNeeded(stackedSpotlight, replacingWith: nil)
        }
        releaseTerminalSpotlightIfNeeded(spotlight, replacingWith: nil)
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                spotlight = nil
            }
        } else {
            spotlight = nil
        }
    }

    /// Build an exact restore descriptor from the current Spotlight state.
    func descriptorForCurrentSpotlight(
        browserPreviewSnapshotProvider: (() -> BrowserSessionSnapshot?)? = nil
    ) -> SpotlightRestoreDescriptor? {
        guard let spotlight, spotlight.source.canBeRestored else { return nil }
        if case let .browserPreview(snapshot) = spotlight.source {
            return SpotlightRestoreDescriptor(
                spotlight: spotlight.replacingSource(
                    .browserPreview(snapshot: browserPreviewSnapshotProvider?() ?? snapshot)
                )
            )
        }
        return SpotlightRestoreDescriptor(spotlight: spotlight)
    }

    /// Push the current spotlight onto the restore stack before replacing it.
    func pushCurrentSpotlightForRestore(
        browserPreviewSnapshotProvider: (() -> BrowserSessionSnapshot?)? = nil
    ) {
        guard let descriptor = descriptorForCurrentSpotlight(
            browserPreviewSnapshotProvider: browserPreviewSnapshotProvider
        ) else { return }
        guard restoreStack.last?.spotlight.id != descriptor.spotlight.id else { return }
        if restoreStack.count >= maxRestoreStackDepth {
            releaseTerminalSpotlightIfNeeded(restoreStack.removeFirst().spotlight, replacingWith: spotlight)
        }
        restoreStack.append(descriptor)
    }

    /// Pop and return the next valid restore descriptor, or nil if exhausted.
    func popRestoreDescriptor() -> SpotlightRestoreDescriptor? {
        restoreStack.popLast()
    }

    @discardableResult
    func restorePreviousSpotlight(
        animated: Bool = false,
        resolve: (SpotlightRestoreDescriptor) -> TerminalSpotlightState?,
        onFocusSpotlight: ((TerminalSpotlightState) -> Void)? = nil
    ) -> Bool {
        while let descriptor = popRestoreDescriptor() {
            guard let resolved = resolve(descriptor) else { continue }
            return setSpotlight(
                resolved,
                animated: animated,
                preservingCurrentForRestore: false,
                onFocusSpotlight: onFocusSpotlight
            )
        }
        return false
    }

    func temporaryProcessDidTerminate(
        spotlightID: UUID,
        onRestoreRequested: () -> Void
    ) {
        guard spotlight?.id == spotlightID else { return }
        onRestoreRequested()
    }

    @discardableResult
    func setSpotlight(
        _ nextSpotlight: TerminalSpotlightState?,
        animated: Bool = true,
        switchTransaction: SpotlightSwitchTransaction? = nil,
        preservingCurrentForRestore: Bool = true,
        onFocusSpotlight: ((TerminalSpotlightState) -> Void)? = nil
    ) -> Bool {
        if preservingCurrentForRestore,
           nextSpotlight?.showsTemporaryBadge == true,
           let current = spotlight,
           current.id != nextSpotlight?.id {
            pushCurrentSpotlightForRestore()
        }
        clearScrollSequenceOwnership()
        isOverviewPresented = false
        let effectiveSwitchTransaction = switchTransaction
            ?? pendingSwitchTransaction.flatMap { transaction in
                nextSpotlight?.navigationIdentity == transaction.targetIdentity ? transaction : nil
            }
        if let effectiveSwitchTransaction {
            guard activeSwitchGeneration == effectiveSwitchTransaction.generation,
                  nextSpotlight?.navigationIdentity == effectiveSwitchTransaction.targetIdentity else {
                recordFocusSuppression(
                    spotlight: nextSpotlight,
                    generation: effectiveSwitchTransaction.generation,
                    sourceIdentity: effectiveSwitchTransaction.sourceIdentity
                )
                return false
            }
        } else {
            cancelCarouselSwitch()
        }

        releaseTerminalSpotlightIfNeeded(spotlight, replacingWith: nextSpotlight)
        diagnosticsSnapshot.spotlightActive = nextSpotlight != nil

        if let effectiveSwitchTransaction, let nextSpotlight {
            pendingSwitchTransaction = nil
            spotlight = nextSpotlight
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .info,
                event: "spotlight_switch_selection_commit",
                metadata: [
                    "generation": String(effectiveSwitchTransaction.generation),
                    "source": effectiveSwitchTransaction.sourceIdentity.diagnosticToken,
                    "target": effectiveSwitchTransaction.targetIdentity.diagnosticToken
                ]
            )
            scheduleCarouselCommit(
                spotlight: nextSpotlight,
                transaction: effectiveSwitchTransaction,
                onFocusSpotlight: onFocusSpotlight
            )
        } else {
            if animated {
                withAnimation(.easeInOut(duration: 0.22)) {
                    spotlight = nextSpotlight
                }
            } else {
                spotlight = nextSpotlight
            }
            if let nextSpotlight {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self,
                          self.spotlight?.id == nextSpotlight.id,
                          self.activeSwitchGeneration == nil else {
                        self?.recordFocusSuppression(
                            spotlight: nextSpotlight,
                            generation: nil,
                            sourceIdentity: nextSpotlight.navigationIdentity
                        )
                        return
                    }
                    self.focusWorkItem = nil
                    onFocusSpotlight?(nextSpotlight)
                }
                focusWorkItem = workItem
                DispatchQueue.main.async(execute: workItem)
            }
        }
        return true
    }

    private func scheduleCarouselCommit(
        spotlight nextSpotlight: TerminalSpotlightState,
        transaction: SpotlightSwitchTransaction,
        onFocusSpotlight: ((TerminalSpotlightState) -> Void)?
    ) {
        switchStartWorkItem?.cancel()
        let startWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.activeSwitchGeneration == transaction.generation,
                  self.spotlight?.id == nextSpotlight.id,
                  self.spotlight?.navigationIdentity == transaction.targetIdentity else {
                self.recordAnimationSuppression(transaction)
                self.recordFocusSuppression(
                    spotlight: nextSpotlight,
                    generation: transaction.generation,
                    sourceIdentity: transaction.sourceIdentity
                )
                return
            }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                self.swipeOffset = 0
            }
            onFocusSpotlight?(nextSpotlight)
            self.scheduleCarouselCompletion(
                spotlightID: nextSpotlight.id,
                transaction: transaction
            )
        }
        switchStartWorkItem = startWorkItem
        DispatchQueue.main.async(execute: startWorkItem)
    }

    private func scheduleCarouselCompletion(
        spotlightID: UUID,
        transaction: SpotlightSwitchTransaction
    ) {
        switchCompletionWorkItem?.cancel()
        let completionWorkItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeSwitchGeneration == transaction.generation,
                  self.spotlight?.id == spotlightID,
                  self.spotlight?.navigationIdentity == transaction.targetIdentity else {
                return
            }
            self.swipeDirection = .none
            self.swipeOffset = 0
            self.activeSwitchGeneration = nil
            self.switchCompletionWorkItem = nil
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .info,
                event: "spotlight_switch_animation_completed",
                metadata: [
                    "generation": String(transaction.generation),
                    "source": transaction.sourceIdentity.diagnosticToken,
                    "target": transaction.targetIdentity.diagnosticToken
                ]
            )
        }
        switchCompletionWorkItem = completionWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: completionWorkItem)
    }

    private func recordAnimationSuppression(_ transaction: SpotlightSwitchTransaction) {
        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .info,
            event: "spotlight_switch_animation_suppressed",
            metadata: [
                "generation": String(transaction.generation),
                "source": transaction.sourceIdentity.diagnosticToken,
                "target": transaction.targetIdentity.diagnosticToken
            ]
        )
    }

    private func recordFocusSuppression(
        spotlight: TerminalSpotlightState?,
        generation: UInt64?,
        sourceIdentity: SpotlightNavigationIdentity?
    ) {
        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .info,
            event: "spotlight_focus_suppressed",
            metadata: [
                "generation": generation.map(String.init) ?? "direct",
                "source": sourceIdentity?.diagnosticToken ?? "non-carousel",
                "target": spotlight?.navigationIdentity?.diagnosticToken ?? "non-carousel"
            ]
        )
    }

    private func releaseTerminalSpotlightIfNeeded(
        _ spotlight: TerminalSpotlightState?,
        replacingWith nextSpotlight: TerminalSpotlightState?
    ) {
        guard let spotlight else { return }
        guard spotlight.id != nextSpotlight?.id else { return }
        cancelSpotlightFocusRequestIfNeeded(spotlight)
        guard case let .transient(session) = spotlight.source else { return }
        guard !restoreStack.contains(where: { $0.spotlight.id == spotlight.id }) else { return }
        session.onProcessTerminated = nil
        session.terminate()
    }

    private func cancelSpotlightFocusRequestIfNeeded(_ spotlight: TerminalSpotlightState?) {
        switch spotlight?.source {
        case let .persistent(terminalViewModel, tabID):
            terminalViewModel.session(for: tabID)?.cancelKeyboardFocusRequest()
        case let .transient(session):
            session.cancelKeyboardFocusRequest()
        case .vibeCast, .vibeLanes, .todos, .acp, .filePreview, .file, .browserPreview, .browser, .none:
            break
        }
    }
}

extension ContentView {
    func spotlightShortcutDefinitions(
        for owningProjectRootURL: URL?,
        fallback fallbackShortcuts: [TerminalShortcutDefinition] = []
    ) -> [TerminalShortcutDefinition] {
        guard let vibespaceID = activeVibeSpaceSession.vibespaceID ?? activeVibeSpaceID else {
            return fallbackShortcuts
        }
        let vibespaceShortcuts = vibespaceManagement.vibespaceShortcuts(vibespaceID: vibespaceID)
        let projectShortcuts: [TerminalShortcutDefinition]
        if let owningProjectRootURL {
            projectShortcuts = vibespaceManagement.projectShortcuts(
                vibespaceID: vibespaceID,
                projectPath: owningProjectRootURL.standardizedFileURL.path
            )
        } else {
            projectShortcuts = []
        }

        let resolvedShortcuts = vibespaceShortcuts + projectShortcuts
        guard !resolvedShortcuts.isEmpty else { return fallbackShortcuts }
        return resolvedShortcuts
    }

    func spotlightManageShortcuts() {
        vibespaceShell.presentVibeSpaceSettings(.shortcuts)
    }

    private func spotlightProject(rootURL: URL?) -> AnyProjectSession? {
        guard let rootURL else { return nil }
        let normalizedRoot = rootURL.standardizedFileURL
        return vibespaceView.activeVibeSpaceProjects.first(where: {
            $0.rootURL.standardizedFileURL == normalizedRoot
        })
    }

    func pushCurrentSpotlightForRestore() {
        terminalSpotlightCoordinator.pushCurrentSpotlightForRestore(
            browserPreviewSnapshotProvider: { [weak dockedBrowserCoordinator] in
                dockedBrowserCoordinator?.previewSnapshot()
            }
        )
    }

    func presentTerminalSpotlight(
        terminalViewModel: TerminalViewModel,
        tabID: UUID,
        title: String,
        accentColor: Color?,
        owningProjectRootURL: URL? = nil,
        surfaceID: UUID? = nil,
        navigationIdentityOverride: SpotlightNavigationIdentity? = nil,
        animated: Bool = true
    ) {
        if case let .persistent(existingViewModel, existingTabID) = terminalSpotlightCoordinator.spotlight?.source,
           existingViewModel === terminalViewModel,
           existingTabID == tabID,
           terminalSpotlightCoordinator.spotlight?.surfaceID == surfaceID,
           terminalSpotlightCoordinator.spotlight?.navigationIdentityOverride == navigationIdentityOverride,
           terminalSpotlightCoordinator.spotlight?.owningProjectRootURL?.standardizedFileURL
                == owningProjectRootURL?.standardizedFileURL {
            return
        }
        guard let resolvedTab = terminalViewModel.tabs.first(where: { $0.id == tabID }) else { return }
        let workingDirectoryURL = resolvedTab.workingDirectory.standardizedFileURL
        let shortcutDefinitions = spotlightShortcutDefinitions(
            for: owningProjectRootURL,
            fallback: terminalViewModel.shortcutCommands
        )
        let spotlight = TerminalSpotlightState(
            id: UUID(),
            source: .persistent(terminalViewModel: terminalViewModel, tabID: tabID),
            title: title,
            accentColor: accentColor,
            workingDirectoryURL: workingDirectoryURL,
            onSplitTerminalRequested: { [weak terminalViewModel] in
                guard let terminalViewModel else { return }
                createSplitTerminal(
                    in: terminalViewModel,
                    directoryURL: workingDirectoryURL,
                    surfaceID: surfaceID,
                    owningProjectRootURL: owningProjectRootURL
                )
            },
            onTemporaryTerminalRequested: { [weak terminalViewModel] in
                guard let terminalViewModel else { return }
                presentTemporaryTerminalSpotlight(
                    title: title,
                    accentColor: accentColor,
                    directoryURL: workingDirectoryURL,
                    shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                    onSplitTerminalRequested: {
                        createSplitTerminal(
                            in: terminalViewModel,
                            directoryURL: workingDirectoryURL,
                            surfaceID: surfaceID,
                            owningProjectRootURL: owningProjectRootURL
                        )
                    },
                    owningProjectRootURL: owningProjectRootURL,
                    surfaceID: surfaceID
                )
            },
            shortcutDefinitions: shortcutDefinitions,
            onShortcutSelected: { shortcut in
                if shortcut.launchBehavior == .newPermanentTerminal,
                   let surfaceID,
                   let boardStore = vibespaceHydrationCoordinator.boardStore,
                   DetachedPermanentShortcutTileLauncher.launch(
                        shortcut,
                        directoryURL: workingDirectoryURL,
                        owningProjectRootURL: owningProjectRootURL,
                        surfaceID: surfaceID,
                        boardStore: boardStore
                   ) {
                    return
                }
                executeTerminalShortcut(
                    shortcut,
                    viewModel: terminalViewModel,
                    defaultDirectory: workingDirectoryURL,
                    onTemporaryShortcutRequested: { shortcut, directoryURL in
                        presentTemporaryTerminalSpotlight(
                            title: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? title
                                : shortcut.name,
                            accentColor: accentColor,
                            directoryURL: directoryURL,
                            shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                            onSplitTerminalRequested: {
                                createSplitTerminal(
                                    in: terminalViewModel,
                                    directoryURL: directoryURL,
                                    surfaceID: surfaceID,
                                    owningProjectRootURL: owningProjectRootURL
                                )
                            },
                            owningProjectRootURL: owningProjectRootURL,
                            surfaceID: surfaceID,
                            initialCommand: shortcut.command
                        )
                    }
                )
            },
            onManageShortcutsRequested: spotlightManageShortcuts,
            agentPresets: terminalViewModel.availablePresets,
            onAgentPresetSelected: { [weak terminalViewModel] preset, mode in
                guard let session = terminalViewModel?.session(for: tabID) else { return }
                session.requestKeyboardFocus()
                session.sendUICommand(preset.command(for: mode))
            },
            isTemporary: false,
            owningProjectRootURL: owningProjectRootURL,
            surfaceID: surfaceID,
            navigationIdentityOverride: navigationIdentityOverride
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentTemporaryTerminalSpotlight(
        title: String,
        accentColor: Color?,
        directoryURL: URL,
        shellResolutionProvider: @escaping @Sendable () -> TerminalShellResolution,
        sessionConfigurator: ((TerminalSession) -> Void)? = nil,
        onSplitTerminalRequested: (() -> Void)? = nil,
        owningProjectRootURL: URL? = nil,
        surfaceID: UUID? = nil,
        initialCommand: String? = nil,
        pushCurrentToRestore: Bool = true
    ) {
        let originatingSurfaceID = surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        if pushCurrentToRestore {
            pushCurrentSpotlightForRestore()
        }
        let normalizedDirectoryURL = directoryURL.standardizedFileURL
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: normalizedDirectoryURL,
            terminalServices: appContainer.terminalServices,
            shellResolutionProvider: shellResolutionProvider
        )
        sessionConfigurator?(session)
        let spotlightID = UUID()
        let coordinator = terminalSpotlightCoordinator
        session.onProcessTerminated = { [spotlightID, weak coordinator] _ in
            coordinator?.temporaryProcessDidTerminate(spotlightID: spotlightID) {
                restoreOrDismissSpotlight()
            }
        }
        let fallbackShortcuts = spotlightProject(rootURL: owningProjectRootURL)?.terminalViewModel.shortcutCommands ?? []
        let shortcutDefinitions = spotlightShortcutDefinitions(
            for: owningProjectRootURL,
            fallback: fallbackShortcuts
        )
        let spotlight = TerminalSpotlightState(
            id: spotlightID,
            source: .transient(session: session),
            title: title,
            accentColor: accentColor,
            workingDirectoryURL: normalizedDirectoryURL,
            onSplitTerminalRequested: onSplitTerminalRequested,
            onTemporaryTerminalRequested: {
                presentTemporaryTerminalSpotlight(
                    title: title,
                    accentColor: accentColor,
                    directoryURL: normalizedDirectoryURL,
                    shellResolutionProvider: shellResolutionProvider,
                    sessionConfigurator: sessionConfigurator,
                    onSplitTerminalRequested: onSplitTerminalRequested,
                    owningProjectRootURL: owningProjectRootURL,
                    surfaceID: originatingSurfaceID,
                    initialCommand: initialCommand
                )
            },
            shortcutDefinitions: shortcutDefinitions,
            onShortcutSelected: { shortcut in
                let command = shortcut.command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else { return }
                switch shortcut.launchBehavior {
                case .currentTerminal:
                    session.startIfNeeded()
                    session.sendStartupCommand(command)
                case .newTemporaryTerminal:
                    presentTemporaryTerminalSpotlight(
                        title: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? title
                            : shortcut.name,
                        accentColor: accentColor,
                        directoryURL: normalizedDirectoryURL,
                        shellResolutionProvider: shellResolutionProvider,
                        sessionConfigurator: sessionConfigurator,
                        onSplitTerminalRequested: onSplitTerminalRequested,
                        owningProjectRootURL: owningProjectRootURL,
                        surfaceID: originatingSurfaceID,
                        initialCommand: command
                    )
                case .newPermanentTerminal:
                    if let originatingSurfaceID,
                       let boardStore = vibespaceHydrationCoordinator.boardStore,
                       DetachedPermanentShortcutTileLauncher.launch(
                            shortcut,
                            directoryURL: normalizedDirectoryURL,
                            owningProjectRootURL: owningProjectRootURL,
                            surfaceID: originatingSurfaceID,
                            boardStore: boardStore
                       ) {
                        return
                    } else if let project = spotlightProject(rootURL: owningProjectRootURL) {
                        project.terminalViewModel.runShortcut(shortcut, defaultDirectory: normalizedDirectoryURL)
                        requestTerminalFocusWithStabilization(for: project.terminal)
                    } else {
                        session.startIfNeeded()
                        session.sendStartupCommand(command)
                    }
                }
            },
            onManageShortcutsRequested: spotlightManageShortcuts,
            agentPresets: TerminalViewModel.availableBuiltInPresets(
                using: appContainer.terminalViewModelDependencies
            ),
            onAgentPresetSelected: { preset, mode in
                session.requestKeyboardFocus()
                session.sendUICommand(preset.command(for: mode))
            },
            isTemporary: true,
            owningProjectRootURL: owningProjectRootURL,
            surfaceID: originatingSurfaceID
        )
        setTerminalSpotlight(spotlight)
        let command = initialCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !command.isEmpty {
            session.sendStartupCommand(command)
        }
    }

    func createSplitTerminal(
        in terminalViewModel: TerminalViewModel,
        directoryURL: URL,
        surfaceID: UUID? = nil,
        owningProjectRootURL: URL? = nil
    ) {
        let normalizedDirectoryURL = directoryURL.standardizedFileURL
        if let surfaceID,
           let boardStore = vibespaceHydrationCoordinator.boardStore {
            let projectPath = owningProjectRootURL?.standardizedFileURL.path
                ?? vibespaceView.activeVibeSpaceProjects.first {
                    $0.terminalViewModel === terminalViewModel
                }?.rootURL.standardizedFileURL.path
            if boardStore.addTile(
                projectPath: projectPath,
                directoryURL: normalizedDirectoryURL,
                preferStandalone: projectPath == nil,
                surfaceID: surfaceID
            ) {
                return
            }
        }
        terminalViewModel.createTab(directoryURL: normalizedDirectoryURL, startImmediately: true)
        requestTerminalFocusWithStabilization(for: AnyTerminalProvider(terminalViewModel))
    }

    func openTerminalInEditorPane(tabID: UUID, projectRootURL: URL?) {
        guard let rootURL = projectRootURL?.standardizedFileURL,
              let project = vibespaceView.activeVibeSpaceProjects.first(where: { $0.rootURL.standardizedFileURL == rootURL }) else { return }
        contentViewerStore.activeGroup.openTab(.terminal(projectID: project.id, tabID: tabID))
    }

    func focusSpotlightTerminal(_ spotlight: TerminalSpotlightState) {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            guard let tab = terminalViewModel.tabs.first(where: { $0.id == tabID }),
                  let session = terminalViewModel.session(for: tabID) else { return }
            terminalViewModel.selectTab(tab)
            session.requestKeyboardFocus()
        case let .transient(session):
            session.startIfNeeded()
        case .vibeCast:
            break
        case .vibeLanes:
            break
        case .todos:
            break
        case .acp:
            break
        case .filePreview:
            break
        case .file:
            break
        case .browserPreview:
            dockedBrowserCoordinator.previewViewModel?.focus()
        case let .browser(tileID, url):
            dockedBrowserCoordinator.viewModel(for: tileID, url: url).focus()
        }
    }

    func dismissTerminalSpotlight() {
        dockedBrowserCoordinator.dismissPreview()
        terminalSpotlightCoordinator.dismiss()
    }

    func handleTerminalSpotlightSessionDoubleClick(_ tabID: UUID) {
        _ = tabID
        closeTerminalSpotlight()
    }

    func closeTerminalSpotlight() {
        if terminalSpotlightCoordinator.restoreStack.isEmpty {
            dismissTerminalSpotlight()
        } else {
            restoreOrDismissSpotlight()
        }
    }

    func restoreOrDismissSpotlight() {
        dockedBrowserCoordinator.dismissPreview()
        while let descriptor = terminalSpotlightCoordinator.popRestoreDescriptor() {
            if restoreSpotlightFromDescriptor(descriptor) { return }
        }
        terminalSpotlightCoordinator.dismiss()
    }

    private func restoreSpotlightFromDescriptor(_ descriptor: SpotlightRestoreDescriptor) -> Bool {
        let restoredSpotlight = descriptor.spotlight
        if let persistentID = restoredSpotlight.persistentItemID,
           !flatSpotlightItems.contains(where: { $0.persistentID == persistentID }) {
            return false
        }
        switch restoredSpotlight.source {
        case let .persistent(terminalViewModel, tabID):
            guard terminalViewModel.tabs.contains(where: { $0.id == tabID }) else { return false }
        case .transient:
            break
        case .vibeCast, .vibeLanes:
            break
        case .todos:
            return false
        case let .acp(_, storeID):
            guard contentViewerStore.acpStore(for: storeID) != nil else { return false }
        case let .filePreview(_, group):
            guard group.activeFileDocumentReference != nil else { return false }
        case let .file(_, _, group):
            guard group.activeFileDocumentReference != nil else { return false }
        case let .browserPreview(snapshot):
            guard snapshot.urlString.flatMap(URL.init(string:)) != nil else { return false }
            dockedBrowserCoordinator.restorePreview(
                from: snapshot,
                projectPath: restoredSpotlight.owningProjectRootURL?.standardizedFileURL.path
            )
        case let .browser(tileID, _):
            guard let boardStore = vibespaceHydrationCoordinator.boardStore,
                  boardStore.tile(
                    for: tileID,
                    includeMinimized: true,
                    surfaceID: restoredSpotlight.surfaceID ?? boardStore.primarySurfaceID
                  ) != nil else { return false }
        }
        setTerminalSpotlight(
            restoredSpotlight,
            animated: false,
            preservingCurrentForRestore: false
        )
        return true
    }

    func setTerminalSpotlight(
        _ nextSpotlight: TerminalSpotlightState?,
        animated: Bool = true,
        preservingCurrentForRestore: Bool = true
    ) {
        let ownershipID = "main:\(activeVibeSpaceID?.uuidString ?? "none")"
        let ownedFileTiles: Set<UUID>
        if let persistentID = nextSpotlight?.persistentItemID {
            let items = flatSpotlightItems
            let snapshot = layoutPersistence.spotlightLayout(
                liveIDs: items.map(\.persistentID),
                for: activeVibeSpaceID
            )
            ownedFileTiles = Set((snapshot.position(containing: persistentID)?.members ?? [persistentID]).compactMap {
                guard case let .file(tileID) = $0 else { return nil }
                return tileID
            })
        } else {
            ownedFileTiles = []
        }
        dockedFileViewerCoordinator.setSpotlightOwnedTileIDs(ownedFileTiles, ownerID: ownershipID)
        terminalSpotlightCoordinator.setSpotlight(
            nextSpotlight,
            animated: animated,
            preservingCurrentForRestore: preservingCurrentForRestore,
            onFocusSpotlight: focusSpotlightTerminal
        )
    }

    func presentACPSpotlight(
        tileID: UUID,
        storeID: UUID,
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        guard let store = contentViewerStore.acpStore(for: storeID) else { return }
        let selectedProject = store.selectedProject(from: vibespaceView.activeVibeSpaceProjects)
        let owningProjectRootURL = selectedProject?.rootURL.standardizedFileURL
        let workingDirectoryURL = owningProjectRootURL ?? URL(fileURLWithPath: NSHomeDirectory())
        let accentColor = selectedProject.flatMap { vibespaceCanvasActionsCoordinator.colorTag(for: $0)?.color }

        let spotlight = TerminalSpotlightState(
            id: UUID(),
            source: .acp(tileID: tileID, storeID: storeID),
            title: store.tabTitle,
            accentColor: accentColor,
            workingDirectoryURL: workingDirectoryURL,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: owningProjectRootURL,
            surfaceID: surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }
}
