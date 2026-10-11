@preconcurrency import AppKit
import CoreGraphics
import SwiftUI
import os

@MainActor
final class SplitHostedContentHolder: ObservableObject {
    @Published private(set) var content = AnyView(EmptyView())
    private(set) var updateCount = 0

    func update(_ content: AnyView) {
        self.content = content
        updateCount += 1
    }
}

@MainActor
struct SplitHostedContentRoot: View {
    @ObservedObject var holder: SplitHostedContentHolder

    var body: some View {
        holder.content
    }
}

@MainActor
final class OverflowHostingView<Content: View>: NSHostingView<Content> {
    override var wantsDefaultClipping: Bool {
        false
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        wantsLayer = true
        layer?.masksToBounds = false
    }
}

@MainActor
enum DividerDragFinishReason: String, Sendable {
    case mouseUp
    case replacement
    case appResignedActive
    case windowResignedKey
    case windowMiniaturized
    case windowClosed
    case windowOrderedOut
    case viewRemoved
    case globalMouseUp
    case initiatingButtonReleased
    case maximumDuration
    case configurationChanged
    case dismantled
    case deinitialized

    var isNormalEnd: Bool {
        self == .mouseUp || self == .globalMouseUp
    }

    var isErrorDiagnostic: Bool {
        self == .initiatingButtonReleased || self == .maximumDuration
    }
}

@MainActor
final class TrackingSplitView: NSSplitView {
    var onDividerMouseDown: ((NSEvent) -> Void)?
    var onDividerMouseDragged: ((NSEvent) -> Void)?
    var onDividerMouseUp: ((NSEvent) -> Void)?
    var onViewRemoved: (() -> Void)?
    var onGeometryChanged: (() -> Void)?
    var isCustomDividerDragActive: (() -> Bool)?

    private(set) var customDividerColor: NSColor = .clear
    private(set) var dividerAppearanceUpdateCount = 0
    private(set) var dividerMouseDownCount = 0
    private(set) var nonDividerMouseDownForwardCount = 0

    override var wantsDefaultClipping: Bool {
        false
    }

    override var dividerThickness: CGFloat {
        2
    }

    override func drawDivider(in rect: NSRect) {
        // Intentionally empty — no visible border between panes.
    }

    override func mouseDown(with event: NSEvent) {
        let pointInSplitView = eventPointInSplitView(event)
        guard isPointNearDivider(pointInSplitView) else {
            nonDividerMouseDownForwardCount += 1
            super.mouseDown(with: event)
            return
        }

        dividerMouseDownCount += 1
        onDividerMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isCustomDividerDragActive?() == true else {
            super.mouseDragged(with: event)
            return
        }
        onDividerMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isCustomDividerDragActive?() == true else {
            super.mouseUp(with: event)
            return
        }
        onDividerMouseUp?(event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let dividerHitRect else { return }
        addCursorRect(dividerHitRect, cursor: isVertical ? .resizeLeftRight : .resizeUpDown)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousSize = frame.size
        super.setFrameSize(newSize)
        guard frame.size != previousSize else { return }
        onGeometryChanged?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            onViewRemoved?()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            onViewRemoved?()
        }
    }

    @discardableResult
    func updateDividerColorIfNeeded(_ color: NSColor) -> Bool {
        guard !customDividerColor.isEqual(color) else { return false }
        customDividerColor = color
        dividerAppearanceUpdateCount += 1
        needsDisplay = true
        return true
    }

    func detachInteractionHandlers() {
        onDividerMouseDown = nil
        onDividerMouseDragged = nil
        onDividerMouseUp = nil
        onViewRemoved = nil
        onGeometryChanged = nil
        isCustomDividerDragActive = nil
    }

    func isPointNearDivider(_ point: NSPoint) -> Bool {
        guard subviews.count >= 2 else { return false }
        return dividerHitRect?.contains(point) == true
    }

    func eventPointInSplitView(_ event: NSEvent) -> NSPoint {
        if event.window != nil {
            return convert(event.locationInWindow, from: nil)
        }
        guard let window else { return event.locationInWindow }
        let pointInWindow = window.convertPoint(fromScreen: event.locationInWindow)
        return convert(pointInWindow, from: nil)
    }

    private var dividerHitRect: NSRect? {
        guard subviews.count >= 2 else { return nil }
        let firstFrame = subviews[0].frame
        let tolerance = dividerThickness + 2
        if isVertical {
            return NSRect(
                x: firstFrame.maxX - tolerance,
                y: bounds.minY,
                width: tolerance * 2,
                height: bounds.height
            )
        }
        return NSRect(
            x: bounds.minX,
            y: firstFrame.maxY - tolerance,
            width: bounds.width,
            height: tolerance * 2
        )
    }
}

@MainActor
struct NativeSplitView<Primary: View, Secondary: View>: NSViewRepresentable {
    let isVerticalSplit: Bool
    let primaryAtEnd: Bool
    @Binding var primarySize: CGFloat
    let minPrimary: CGFloat
    let maxPrimary: CGFloat
    let minSecondary: CGFloat
    let accessibilityIdentifier: String?
    let primary: () -> Primary
    let secondary: () -> Secondary

    init(
        isVerticalSplit: Bool,
        primaryAtEnd: Bool,
        primarySize: Binding<CGFloat>,
        minPrimary: CGFloat,
        maxPrimary: CGFloat,
        minSecondary: CGFloat = 0,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.isVerticalSplit = isVerticalSplit
        self.primaryAtEnd = primaryAtEnd
        self._primarySize = primarySize
        self.minPrimary = minPrimary
        self.maxPrimary = maxPrimary
        self.minSecondary = minSecondary
        self.accessibilityIdentifier = accessibilityIdentifier
        self.primary = primary
        self.secondary = secondary
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = TrackingSplitView(frame: .zero)
        splitView.isVertical = isVerticalSplit
        splitView.dividerStyle = .thin
        splitView.wantsLayer = true
        splitView.layer?.masksToBounds = false
        if let accessibilityIdentifier {
            splitView.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        splitView.updateDividerColorIfNeeded(
            context.coordinator.resolvedDividerColor(for: splitView.effectiveAppearance)
        )
        splitView.delegate = context.coordinator
        splitView.onDividerMouseDown = { [weak coordinator = context.coordinator] event in
            coordinator?.beginDividerDrag(with: event)
        }
        splitView.onDividerMouseDragged = { [weak coordinator = context.coordinator] event in
            coordinator?.handleMouseDragged(event)
        }
        splitView.onDividerMouseUp = { [weak coordinator = context.coordinator] event in
            coordinator?.handleMouseUp(event)
        }
        splitView.onViewRemoved = { [weak coordinator = context.coordinator] in
            coordinator?.finishDividerDrag(reason: .viewRemoved)
        }
        splitView.onGeometryChanged = { [weak coordinator = context.coordinator] in
            coordinator?.requestApplyAfterGeometryChange()
        }
        splitView.isCustomDividerDragActive = { [weak coordinator = context.coordinator] in
            coordinator?.isDividerDragActive == true
        }

        splitView.addArrangedSubview(context.coordinator.firstHost)
        splitView.addArrangedSubview(context.coordinator.secondHost)

        context.coordinator.attach(splitView)
        context.coordinator.populateInitialHostedContent(
            primary: primary(),
            secondary: secondary()
        )
        context.coordinator.applyDividerPositionIfNeeded(force: true)
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.updateParent(self)
        if splitView.isVertical != isVerticalSplit {
            splitView.isVertical = isVerticalSplit
            splitView.window?.invalidateCursorRects(for: splitView)
        }
        if let accessibilityIdentifier,
            splitView.accessibilityIdentifier() != accessibilityIdentifier
        {
            splitView.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        if let trackingSplitView = splitView as? TrackingSplitView {
            trackingSplitView.updateDividerColorIfNeeded(
                context.coordinator.resolvedDividerColor(for: splitView.effectiveAppearance)
            )
        }
        context.coordinator.updateHostedContent(primary: primary(), secondary: secondary())
        context.coordinator.applyDividerPositionIfNeeded(force: false)
    }

    static func dismantleNSView(_ splitView: NSSplitView, coordinator: Coordinator) {
        coordinator.shutdown(reason: .dismantled)
        splitView.delegate = nil
        (splitView as? TrackingSplitView)?.detachInteractionHandlers()
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        static var watchdogGraceDuration: TimeInterval { 0.2 }
        static var watchdogInterval: TimeInterval { 0.1 }
        static var maximumDragDuration: TimeInterval { 15 }

        var parent: NativeSplitView

        let firstContentHolder = SplitHostedContentHolder()
        let secondContentHolder = SplitHostedContentHolder()
        let firstHost: OverflowHostingView<SplitHostedContentRoot>
        let secondHost: OverflowHostingView<SplitHostedContentRoot>

        private(set) var isDividerDragActive = false
        private(set) var dragBeginCount = 0
        private(set) var dragFinishCount = 0
        private(set) var dragCancellationCount = 0
        private(set) var hostedContentUpdateCount = 0
        private(set) var hostedContentSuppressedCount = 0
        private(set) var hostedContentFlushCount = 0
        private(set) var hostedContentSuppressionIndicationCount = 0
        private(set) var hostedContentFlushIndicationCount = 0
        private(set) var firstRootAssignmentCount = 1
        private(set) var secondRootAssignmentCount = 1
        private(set) var lastFinishReason: DividerDragFinishReason?
        private(set) var activeDragGeneration: UInt64?
        private(set) var deferredApplyScheduleCount = 0
        private(set) var geometryChangeRequestCount = 0
        private(set) var dividerPositionApplyCount = 0

        var initiatingButtonIsPressed: () -> Bool = {
            CGEventSource.buttonState(.combinedSessionState, button: .left)
        }
        var currentTime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

        private(set) weak var splitView: NSSplitView?
        private(set) var localEventMonitor: Any?
        private(set) var globalEventMonitor: Any?
        private(set) var dragObservers: [NSObjectProtocol] = []
        private(set) var watchdogTimer: Timer?

        private var isApplyingProgrammaticPosition = false
        private var isDeferredApplyScheduled = false
        private var pendingDeferredApplyForce = false
        private var pendingHostedContent: (AnyView, AnyView)?
        private var pendingHostedContentRequiresFlush = false
        private var didIndicateHostedContentSuppression = false
        private var isHostedContentApplyScheduled = false
        private var hostedContentApplyGeneration: UInt64 = 0
        private var dragStartedAt: TimeInterval?
        private var nextDragGeneration: UInt64 = 0
        private var isShutdown = false
        private var dividerColorByScheme: [ColorScheme: NSColor] = [:]
        private var dividerThemeSnapshot = DividerThemeSnapshot.capture()
        private var defaultsObserver: NSObjectProtocol?

        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
            category: "native-split-view"
        )
        private let signposter = OSSignposter(
            subsystem: Bundle.main.bundleIdentifier ?? "com.crispyvibe.app",
            category: "native-split-view"
        )

        private struct DividerThemeSnapshot: Equatable {
            let appearancePreferenceRaw: String
            let themePresetRaw: String
            let customThemeJSON: String

            static func capture(defaults: UserDefaults = .standard) -> DividerThemeSnapshot {
                DividerThemeSnapshot(
                    appearancePreferenceRaw: defaults.string(
                        forKey: AppPreferences.appearancePreferenceKey)
                        ?? AppPreferences.defaultAppearancePreference,
                    themePresetRaw: defaults.string(forKey: AppPreferences.appThemePresetKey)
                        ?? AppPreferences.defaultAppThemePreset,
                    customThemeJSON: defaults.string(
                        forKey: AppPreferences.appCustomThemePaletteJSONKey)
                        ?? ""
                )
            }
        }

        init(parent: NativeSplitView) {
            self.parent = parent
            firstHost = OverflowHostingView(
                rootView: SplitHostedContentRoot(holder: firstContentHolder)
            )
            secondHost = OverflowHostingView(
                rootView: SplitHostedContentRoot(holder: secondContentHolder)
            )
            super.init()
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshThemeSnapshotIfNeeded()
                }
            }
        }

        isolated deinit {
            shutdown(reason: .deinitialized)
            if let defaultsObserver {
                NotificationCenter.default.removeObserver(defaultsObserver)
            }
        }

        func attach(_ splitView: NSSplitView) {
            self.splitView = splitView
        }

        func resolvedDividerColor(for appearance: NSAppearance) -> NSColor {
            let systemScheme: ColorScheme =
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            if let cached = dividerColorByScheme[systemScheme] {
                return cached
            }

            let palette = AppThemeResolver.palette(
                appearancePreferenceRaw: dividerThemeSnapshot.appearancePreferenceRaw,
                fallbackSystemColorScheme: systemScheme,
                themePresetRaw: dividerThemeSnapshot.themePresetRaw,
                customThemeJSON: dividerThemeSnapshot.customThemeJSON
            )
            let color = palette.windowBackground.nsColor.withAlphaComponent(1)
            dividerColorByScheme[systemScheme] = color
            return color
        }

        func updateParent(_ updatedParent: NativeSplitView) {
            let configurationChanged =
                parent.isVerticalSplit != updatedParent.isVerticalSplit
                || parent.primaryAtEnd != updatedParent.primaryAtEnd
                || parent.minPrimary != updatedParent.minPrimary
                || parent.maxPrimary != updatedParent.maxPrimary
                || parent.minSecondary != updatedParent.minSecondary
            parent = updatedParent
            if configurationChanged, let activeDragGeneration {
                finishDividerDrag(
                    reason: .configurationChanged,
                    generation: activeDragGeneration
                )
            }
        }

        @discardableResult
        func beginDividerDrag(
            with event: NSEvent? = nil,
            installMonitoring: Bool = true
        ) -> UInt64 {
            if let activeDragGeneration {
                finishDividerDrag(reason: .replacement, generation: activeDragGeneration)
            }

            nextDragGeneration += 1
            let generation = nextDragGeneration
            activeDragGeneration = generation
            isDividerDragActive = true
            dragStartedAt = currentTime()
            didIndicateHostedContentSuppression = false
            dragBeginCount += 1
            installDragObserversAndMonitors(
                installEventMonitors: installMonitoring,
                generation: generation
            )
            installWatchdogTimer(generation: generation)
            updateCursor()
            let orientation = parent.isVerticalSplit ? "vertical" : "horizontal"
            logger.info(
                "Divider drag began orientation=\(orientation, privacy: .public) primaryAtEnd=\(self.parent.primaryAtEnd, privacy: .public)"
            )
            signposter.emitEvent("Divider drag began")
            if let event {
                positionDivider(using: event)
            }
            return generation
        }

        func handleMouseDragged(_ event: NSEvent, generation: UInt64? = nil) {
            guard matchesActiveDrag(generation) else { return }
            positionDivider(using: event)
        }

        func handleMouseUp(_ event: NSEvent, generation: UInt64? = nil) {
            guard matchesActiveDrag(generation) else { return }
            positionDivider(using: event)
            finishDividerDrag(reason: .mouseUp, generation: generation)
        }

        func handleLocalEvent(_ event: NSEvent, generation: UInt64? = nil) -> NSEvent? {
            guard matchesActiveDrag(generation) else { return event }
            switch event.type {
            case .leftMouseDragged:
                handleMouseDragged(event, generation: generation)
                return nil
            case .leftMouseUp:
                handleMouseUp(event, generation: generation)
                return nil
            default:
                return event
            }
        }

        func handleGlobalMouseUp(_ event: NSEvent? = nil, generation: UInt64? = nil) {
            guard matchesActiveDrag(generation) else { return }
            if let event {
                positionDivider(using: event)
            }
            finishDividerDrag(reason: .globalMouseUp, generation: generation)
        }

        func evaluateWatchdog(generation: UInt64? = nil) {
            guard matchesActiveDrag(generation), let dragStartedAt else { return }
            let duration = max(0, currentTime() - dragStartedAt)
            if duration >= Self.maximumDragDuration {
                finishDividerDrag(reason: .maximumDuration, generation: generation)
                return
            }
            guard duration >= Self.watchdogGraceDuration else { return }
            guard !initiatingButtonIsPressed() else { return }
            finishDividerDrag(reason: .initiatingButtonReleased, generation: generation)
        }

        func finishDividerDrag(
            reason: DividerDragFinishReason,
            generation: UInt64? = nil
        ) {
            guard matchesActiveDrag(generation) else { return }
            removeDragResources()

            let startedAt = dragStartedAt ?? currentTime()
            let duration = max(0, currentTime() - startedAt)
            isDividerDragActive = false
            activeDragGeneration = nil
            dragStartedAt = nil
            dragFinishCount += 1
            lastFinishReason = reason
            if !reason.isNormalEnd {
                dragCancellationCount += 1
            }
            schedulePendingHostedContentIfNeeded()
            updateCursor()
            scheduleDeferredApply(force: true)

            let durationMilliseconds = Int(duration * 1_000)
            if reason.isNormalEnd {
                logger.info(
                    "Divider drag ended reason=\(reason.rawValue, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
                )
                signposter.emitEvent("Divider drag ended")
            } else if reason.isErrorDiagnostic {
                logger.error(
                    "Divider drag watchdog recovery reason=\(reason.rawValue, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
                )
                signposter.emitEvent("Divider drag watchdog recovery")
            } else {
                logger.info(
                    "Divider drag stopped for lifecycle reason=\(reason.rawValue, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)"
                )
                signposter.emitEvent("Divider drag lifecycle stop")
            }
        }

        func shutdown(reason: DividerDragFinishReason) {
            guard !isShutdown else { return }
            isShutdown = true
            invalidatePendingHostedContentApplication()
            finishDividerDrag(reason: reason)
            if let defaultsObserver {
                NotificationCenter.default.removeObserver(defaultsObserver)
                self.defaultsObserver = nil
            }
            splitView = nil
        }

        func populateInitialHostedContent(primary: Primary, secondary: Secondary) {
            guard !isShutdown, hostedContentUpdateCount == 0 else { return }
            applyHostedContent(orderedHostedContent(primary: primary, secondary: secondary))
        }

        func updateHostedContent(primary: Primary, secondary: Secondary) {
            guard !isShutdown else { return }
            let orderedContent = orderedHostedContent(primary: primary, secondary: secondary)

            if isDividerDragActive {
                pendingHostedContent = orderedContent
                pendingHostedContentRequiresFlush = true
                hostedContentSuppressedCount += 1
                if !didIndicateHostedContentSuppression {
                    didIndicateHostedContentSuppression = true
                    hostedContentSuppressionIndicationCount += 1
                    logger.debug("Hosted-content updates deferred during divider drag")
                    signposter.emitEvent("Hosted-content updates deferred")
                }
                return
            }
            scheduleHostedContentApply(orderedContent)
        }

        func splitView(
            _ splitView: NSSplitView,
            canCollapseSubview subview: NSView
        ) -> Bool {
            false
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let dividerThickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total.isFinite, total > dividerThickness else { return proposedPosition }

            if parent.primaryAtEnd {
                let proposedPrimary = total - proposedPosition - dividerThickness
                let clampedPrimary = clampedPrimarySize(proposedPrimary, in: splitView)
                persistPrimarySizeIfNeeded(clampedPrimary)
                return total - clampedPrimary - dividerThickness
            }

            let clampedPrimary = clampedPrimarySize(proposedPosition, in: splitView)
            persistPrimarySizeIfNeeded(clampedPrimary)
            return clampedPrimary
        }

        func positionDivider(using event: NSEvent) {
            guard isDividerDragActive,
                let splitView,
                splitView.subviews.count >= 2
            else { return }
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total.isFinite, total > splitView.dividerThickness else { return }
            let point: NSPoint
            if let trackingSplitView = splitView as? TrackingSplitView {
                point = trackingSplitView.eventPointInSplitView(event)
            } else if event.window != nil {
                point = splitView.convert(event.locationInWindow, from: nil)
            } else if let window = splitView.window {
                point = splitView.convert(
                    window.convertPoint(fromScreen: event.locationInWindow), from: nil)
            } else {
                point = event.locationInWindow
            }
            let proposedPosition = splitView.isVertical ? point.x : point.y
            let constrainedPosition = self.splitView(
                splitView,
                constrainSplitPosition: proposedPosition,
                ofSubviewAt: 0
            )
            guard constrainedPosition.isFinite else { return }
            splitView.setPosition(constrainedPosition, ofDividerAt: 0)
            splitView.adjustSubviews()
        }

        func applyDividerPositionIfNeeded(force: Bool) {
            guard !isShutdown,
                let splitView,
                splitView.subviews.count >= 2
            else { return }
            guard !isDividerDragActive else { return }

            let dividerThickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total.isFinite, total > dividerThickness else { return }
            let firstPaneFrame = splitView.subviews[0].frame
            let currentPosition =
                splitView.isVertical ? firstPaneFrame.width : firstPaneFrame.height
            guard currentPosition.isFinite else { return }

            let clampedPrimary = clampedPrimarySize(parent.primarySize, in: splitView)
            let desiredPosition =
                parent.primaryAtEnd
                ? total - clampedPrimary - dividerThickness
                : clampedPrimary
            guard desiredPosition.isFinite else { return }
            guard force || abs(currentPosition - desiredPosition) > 0.5 else { return }

            isApplyingProgrammaticPosition = true
            splitView.setPosition(desiredPosition, ofDividerAt: 0)
            splitView.adjustSubviews()
            dividerPositionApplyCount += 1
            isApplyingProgrammaticPosition = false
        }

        func requestApplyAfterGeometryChange() {
            guard !isShutdown else { return }
            geometryChangeRequestCount += 1
            scheduleDeferredApply(force: true)
        }

        private func installDragObserversAndMonitors(
            installEventMonitors: Bool,
            generation: UInt64
        ) {
            if installEventMonitors {
                localEventMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDragged, .leftMouseUp]
                ) { [weak self] event in
                    self?.handleLocalEvent(event, generation: generation) ?? event
                }
                globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
                    [weak self] event in
                    DispatchQueue.main.async { [weak self] in
                        self?.handleGlobalMouseUp(event, generation: generation)
                    }
                }
            }

            let notificationCenter = NotificationCenter.default
            dragObservers.append(
                notificationCenter.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: NSApp,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.finishDividerDrag(
                            reason: .appResignedActive,
                            generation: generation
                        )
                    }
                })

            if let window = splitView?.window {
                observeWindow(
                    window,
                    notificationCenter: notificationCenter,
                    generation: generation
                )
            }
        }

        private func observeWindow(
            _ window: NSWindow,
            notificationCenter: NotificationCenter,
            generation: UInt64
        ) {
            let notifications: [(Notification.Name, DividerDragFinishReason)] = [
                (NSWindow.didResignKeyNotification, .windowResignedKey),
                (NSWindow.didMiniaturizeNotification, .windowMiniaturized),
                (NSWindow.willCloseNotification, .windowClosed),
            ]
            for (name, reason) in notifications {
                dragObservers.append(
                    notificationCenter.addObserver(
                        forName: name,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.finishDividerDrag(reason: reason, generation: generation)
                        }
                    })
            }
            dragObservers.append(
                notificationCenter.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window, !window.isVisible else { return }
                        self.finishDividerDrag(
                            reason: .windowOrderedOut,
                            generation: generation
                        )
                    }
                })
        }

        private func installWatchdogTimer(generation: UInt64) {
            let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluateWatchdog(generation: generation)
                }
            }
            watchdogTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func removeDragResources() {
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
                self.localEventMonitor = nil
            }
            if let globalEventMonitor {
                NSEvent.removeMonitor(globalEventMonitor)
                self.globalEventMonitor = nil
            }
            for observer in dragObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            dragObservers.removeAll(keepingCapacity: true)
            watchdogTimer?.invalidate()
            watchdogTimer = nil
        }

        private func orderedHostedContent(
            primary: Primary,
            secondary: Secondary
        ) -> (AnyView, AnyView) {
            let primaryContent = AnyView(primary)
            let secondaryContent = AnyView(secondary)
            return parent.primaryAtEnd
                ? (secondaryContent, primaryContent)
                : (primaryContent, secondaryContent)
        }

        private func scheduleHostedContentApply(_ content: (AnyView, AnyView)) {
            pendingHostedContent = content
            schedulePendingHostedContentIfNeeded()
        }

        private func schedulePendingHostedContentIfNeeded() {
            guard !isShutdown,
                pendingHostedContent != nil,
                !isHostedContentApplyScheduled
            else { return }
            isHostedContentApplyScheduled = true
            hostedContentApplyGeneration += 1
            let generation = hostedContentApplyGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                    !self.isShutdown,
                    self.hostedContentApplyGeneration == generation
                else { return }
                self.isHostedContentApplyScheduled = false
                guard !self.isDividerDragActive,
                    let pendingHostedContent = self.pendingHostedContent
                else { return }
                let isDragFlush = self.pendingHostedContentRequiresFlush
                self.pendingHostedContent = nil
                self.pendingHostedContentRequiresFlush = false
                self.applyHostedContent(pendingHostedContent)
                if isDragFlush {
                    self.hostedContentFlushCount += 1
                    self.hostedContentFlushIndicationCount += 1
                    self.logger.debug("Deferred hosted-content updates applied after divider drag")
                    self.signposter.emitEvent("Deferred hosted-content updates applied")
                }
            }
        }

        private func invalidatePendingHostedContentApplication() {
            hostedContentApplyGeneration += 1
            isHostedContentApplyScheduled = false
            pendingHostedContent = nil
            pendingHostedContentRequiresFlush = false
        }

        private func applyHostedContent(_ content: (AnyView, AnyView)) {
            firstContentHolder.update(content.0)
            secondContentHolder.update(content.1)
            hostedContentUpdateCount += 1
        }

        private func clampedPrimarySize(_ proposed: CGFloat, in splitView: NSSplitView) -> CGFloat {
            let dividerThickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            let maximumForPrimary = max(
                parent.minPrimary,
                total - dividerThickness - parent.minSecondary
            )
            let upperBound = min(parent.maxPrimary, maximumForPrimary)
            return clamped(proposed, min: parent.minPrimary, max: upperBound)
        }

        private func persistPrimarySizeIfNeeded(_ clampedPrimary: CGFloat) {
            guard !isApplyingProgrammaticPosition else { return }
            guard isDividerDragActive else { return }
            guard abs(parent.primarySize - clampedPrimary) > 0.5 else { return }
            parent.primarySize = clampedPrimary
        }

        private func scheduleDeferredApply(force: Bool) {
            guard !isShutdown else { return }
            pendingDeferredApplyForce = pendingDeferredApplyForce || force
            guard !isDeferredApplyScheduled else { return }
            isDeferredApplyScheduled = true
            deferredApplyScheduleCount += 1
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDeferredApplyScheduled = false
                let shouldForce = self.pendingDeferredApplyForce
                self.pendingDeferredApplyForce = false
                self.applyDividerPositionIfNeeded(force: shouldForce)
            }
        }

        private func matchesActiveDrag(_ generation: UInt64?) -> Bool {
            guard isDividerDragActive, let activeDragGeneration else { return false }
            return generation == nil || generation == activeDragGeneration
        }

        private func updateCursor() {
            guard let trackingSplitView = splitView as? TrackingSplitView else { return }
            let resizeCursor =
                trackingSplitView.isVertical
                ? NSCursor.resizeLeftRight
                : NSCursor.resizeUpDown
            if isDividerDragActive {
                resizeCursor.set()
            } else if let window = trackingSplitView.window {
                let point = trackingSplitView.convert(
                    window.mouseLocationOutsideOfEventStream,
                    from: nil
                )
                (trackingSplitView.isPointNearDivider(point) ? resizeCursor : .arrow).set()
            } else {
                NSCursor.arrow.set()
            }
            trackingSplitView.window?.invalidateCursorRects(for: trackingSplitView)
        }

        private func refreshThemeSnapshotIfNeeded() {
            let updatedSnapshot = DividerThemeSnapshot.capture()
            guard updatedSnapshot != dividerThemeSnapshot else { return }
            dividerThemeSnapshot = updatedSnapshot
            dividerColorByScheme.removeAll(keepingCapacity: true)
            applyCurrentDividerColorIfNeeded()
        }

        private func applyCurrentDividerColorIfNeeded() {
            guard let splitView,
                let trackingSplitView = splitView as? TrackingSplitView
            else { return }
            trackingSplitView.updateDividerColorIfNeeded(
                resolvedDividerColor(for: splitView.effectiveAppearance)
            )
        }
    }
}
