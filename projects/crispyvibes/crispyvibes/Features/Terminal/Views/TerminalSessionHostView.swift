import SwiftUI
import os.signpost
import QuartzCore

private struct TerminalHostOwnershipParticipationEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct TerminalHostOwnershipPriorityBoostKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var terminalHostOwnershipParticipationEnabled: Bool {
        get { self[TerminalHostOwnershipParticipationEnabledKey.self] }
        set { self[TerminalHostOwnershipParticipationEnabledKey.self] = newValue }
    }

    var terminalHostOwnershipPriorityBoost: Int {
        get { self[TerminalHostOwnershipPriorityBoostKey.self] }
        set { self[TerminalHostOwnershipPriorityBoostKey.self] = newValue }
    }
}

struct TerminalSessionHostView: View {
    @Environment(\.boardInlinePickerOverlayController) private var boardInlinePickerOverlayController
    let session: TerminalSession
    let displayDensity: TerminalDisplayDensity
    var isActive: Bool = true
    var allowsOwnershipParticipation: Bool = true
    var accessibilityIdentifier: String? = nil
    var inlineTriggerTerminalTitle: String? = nil
    var inlineTriggerSearchRoots: [URL] = []
    var inlineTriggerShortcuts: [TerminalShortcutDefinition] = []
    var onManageInlineTriggerShortcutsRequested: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onSplitTerminalRequested: (() -> Void)? = nil
    var onTemporaryTerminalRequested: (() -> Void)? = nil
    var onOpenInEditorPaneRequested: (() -> Void)? = nil
    var onLinkTargetActivated: ((URL) -> Void)? = nil
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil

    @AppStorage(AppPreferences.terminalComposeInlineTriggerKey)
    private var configuredInlineTrigger = AppPreferences.defaultTerminalComposeInlineTrigger
    @State private var isHovering = false
    @StateObject private var inlineTriggerController = TerminalInlineTriggerController()

    var body: some View {
        hostRepresentable
            .overlay(alignment: .top) {
                if let summarySession = session.contextSummarySession {
                    TerminalContextSummaryOverlayContainer(
                        summarySession: summarySession,
                        isHovering: isHovering
                    )
                    .padding(.top, 30)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                TerminalScrollbackSearchOverlay(
                    session: session,
                    isHostHovered: isHovering,
                    onSplitTerminal: onSplitTerminalRequested,
                    onTemporaryTerminal: onTemporaryTerminalRequested
                )
            }
            .onAppear {
                syncInlineTriggerController()
                syncBoardInlinePickerOverlay()
            }
            .onDisappear {
                clearBoardInlinePickerOverlay()
                inlineTriggerController.shutdown()
            }
            .onHover { isHovering = $0 }
            .onChange(of: configuredInlineTrigger) { _, _ in
                syncInlineTriggerController()
            }
            .onChange(of: inlineTriggerTerminalTitle) { _, _ in
                syncInlineTriggerController()
            }
            .onChange(of: inlineTriggerSearchRoots.map(\.path)) { _, _ in
                syncInlineTriggerController()
            }
            .onChange(of: inlineTriggerShortcuts.map { "\($0.id.uuidString):\($0.name):\($0.command)" }) { _, _ in
                syncInlineTriggerController()
            }
            .onReceive(inlineTriggerController.objectWillChange) { _ in
                guard boardInlinePickerOverlayController != nil else { return }
                DispatchQueue.main.async {
                    syncBoardInlinePickerOverlay()
                }
            }
    }

    private var hostRepresentable: some View {
        let inlineTriggerControllerRef = inlineTriggerController
        return TerminalSessionHostRepresentable(
            session: session,
            displayDensity: displayDensity,
            isActive: isActive,
            allowsOwnershipParticipation: allowsOwnershipParticipation,
            accessibilityIdentifier: accessibilityIdentifier,
            onInlineTriggerTextInput: { [weak inlineTriggerControllerRef] text in
                inlineTriggerControllerRef?.handleTextInput(text) == true
            },
            onInlineTriggerCommand: { [weak inlineTriggerControllerRef] command in
                inlineTriggerControllerRef?.handleCommand(command) == true
            },
            onDoubleClick: onDoubleClick,
            onSplitTerminalRequested: onSplitTerminalRequested,
            onTemporaryTerminalRequested: onTemporaryTerminalRequested,
            onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
            onLinkTargetActivated: onLinkTargetActivated,
            onFileSystemTargetActivated: onFileSystemTargetActivated
        )
    }

    private var manageShortcutsAction: (() -> Void)? {
        guard onManageInlineTriggerShortcutsRequested != nil else { return nil }
        let inlineTriggerControllerRef = inlineTriggerController
        return { [weak inlineTriggerControllerRef] in
            inlineTriggerControllerRef?.runManageShortcutsAction()
        }
    }

    private func syncInlineTriggerController() {
        inlineTriggerController.configure(
            triggerToken: configuredInlineTrigger,
            searchRoots: inlineTriggerSearchRoots,
            shortcuts: inlineTriggerShortcuts,
            terminalTitle: inlineTriggerTerminalTitle ?? "Terminal",
            currentDirectoryProvider: { [weak session] in
                session?.currentWorkingDirectory
            },
            insertionHandler: { [weak session] text in
                session?.sendRawText(text)
            },
            focusHandler: { [weak session] in
                session?.requestKeyboardFocus()
            },
            manageShortcutsHandler: onManageInlineTriggerShortcutsRequested
        )
        syncBoardInlinePickerOverlay()
    }

    private var boardInlinePickerOverlayOwnerID: String {
        "terminal-session:\(session.id.uuidString)"
    }

    private func syncBoardInlinePickerOverlay() {
        guard let boardInlinePickerOverlayController else { return }
        guard inlineTriggerController.isPresented else {
            boardInlinePickerOverlayController.clear(ownerID: boardInlinePickerOverlayOwnerID)
            return
        }
        let inlineTriggerControllerRef = inlineTriggerController

        boardInlinePickerOverlayController.update(
            ownerID: boardInlinePickerOverlayOwnerID,
            presentation: BoardInlinePickerOverlayPresentation(
                title: AppStrings.Terminal.ComposeTriggers.pickerTitle,
                queryText: inlineTriggerController.queryText,
                featuredAction: inlineTriggerController.featuredPanelAction,
                rows: inlineTriggerController.panelRows,
                statusText: inlineTriggerController.footerText,
                hintText: inlineTriggerController.hintText,
                actionTitle: inlineTriggerController.manageShortcutsActionTitle,
                onAction: manageShortcutsAction,
                onFeaturedAction: { [weak inlineTriggerControllerRef] in
                    inlineTriggerControllerRef?.applyFeaturedAction()
                },
                onDismiss: { [weak inlineTriggerControllerRef] in
                    _ = inlineTriggerControllerRef?.handleCommand(.dismiss)
                },
                onSelect: { [weak inlineTriggerControllerRef] rowID in
                    inlineTriggerControllerRef?.applyResult(id: rowID)
                }
            )
        )
    }

    private func clearBoardInlinePickerOverlay() {
        boardInlinePickerOverlayController?.clear(ownerID: boardInlinePickerOverlayOwnerID)
    }
}

private struct TerminalSessionHostRepresentable: NSViewRepresentable {
    @Environment(\.terminalHostOwnershipParticipationEnabled) private var ownershipParticipationEnabled
    @Environment(\.terminalHostOwnershipPriorityBoost) private var ownershipPriorityBoost
    let session: TerminalSession
    let displayDensity: TerminalDisplayDensity
    var isActive: Bool = true
    var allowsOwnershipParticipation: Bool = true
    var accessibilityIdentifier: String? = nil
    var onInlineTriggerTextInput: ((String) -> Bool)? = nil
    var onInlineTriggerCommand: ((TerminalInlineTriggerCommand) -> Bool)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onSplitTerminalRequested: (() -> Void)? = nil
    var onTemporaryTerminalRequested: (() -> Void)? = nil
    var onOpenInEditorPaneRequested: (() -> Void)? = nil
    var onLinkTargetActivated: ((URL) -> Void)? = nil
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView(
            ownershipCoordinator: session.terminalServices.hostOwnershipCoordinator
        )
        container.configureAccessibility(
            identifier: accessibilityIdentifier
        )
        container.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: displayDensity,
            isActive: isActive,
            allowsOwnershipParticipation: allowsOwnershipParticipation && ownershipParticipationEnabled,
            ownershipPriorityBoost: ownershipPriorityBoost,
            onDoubleClick: onDoubleClick,
            onSplitTerminalRequested: onSplitTerminalRequested,
            onTemporaryTerminalRequested: onTemporaryTerminalRequested,
            onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
            onInlineTriggerTextInput: onInlineTriggerTextInput,
            onInlineTriggerCommand: onInlineTriggerCommand,
            onLinkTargetActivated: onLinkTargetActivated,
            onFileSystemTargetActivated: onFileSystemTargetActivated
        )
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        nsView.configureAccessibility(
            identifier: accessibilityIdentifier
        )
        nsView.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: displayDensity,
            isActive: isActive,
            allowsOwnershipParticipation: allowsOwnershipParticipation && ownershipParticipationEnabled,
            ownershipPriorityBoost: ownershipPriorityBoost,
            onDoubleClick: onDoubleClick,
            onSplitTerminalRequested: onSplitTerminalRequested,
            onTemporaryTerminalRequested: onTemporaryTerminalRequested,
            onOpenInEditorPaneRequested: onOpenInEditorPaneRequested,
            onInlineTriggerTextInput: onInlineTriggerTextInput,
            onInlineTriggerCommand: onInlineTriggerCommand,
            onLinkTargetActivated: onLinkTargetActivated,
            onFileSystemTargetActivated: onFileSystemTargetActivated
        )
    }
}

final class TerminalContainerView: NSView, TerminalSessionOwnershipHost {
    private let ownershipCoordinator: TerminalHostOwnershipCoordinator
    private let hostOwnershipID = UUID()
    private let horizontalContentInset: CGFloat = 8
    private var diagnosticsSnapshot: TerminalDiagnosticsSnapshot?
    private var hasRegisteredDiagnosticsHost = false
    private var attachedTerminalView: NSView?
    private let opticalViewport = TerminalOpticalViewport(frame: .zero)
    private weak var desiredTerminalView: NSView?
    private weak var desiredSession: TerminalSession?
    private var desiredSessionID: UUID?
    private var desiredDisplayDensity: TerminalDisplayDensity = .regular
    private var desiredIsActive = true
    private var desiredAllowsOwnershipParticipation = true
    private var desiredOwnershipPriorityBoost = 0
    private var appliedDisplayDensity: TerminalDisplayDensity?
    private var firstOutputObserverToken: UUID?
    private weak var observedOutputSession: TerminalSession?
    private var configuredAccessibilityIdentifier: String?
    private var lastAccessibilityReadiness: String?
    private var lastAccessibilityLabelValue: String?
    private var lastAppliedTerminalViewIdentifier: ObjectIdentifier?
    private var lastAppliedThemeSignature: ThemeSignature?
    private var lastPublishedDiagnosticsSessionID: UUID?
    private var lastPublishedPresentationSource: TerminalPresentationSource?
    private var lastPublishedVisibility: Bool?
    private weak var cachedTerminalScroller: NSScroller?
    private var cachedTerminalScrollerOwnerID: ObjectIdentifier?
    private var lastAppliedTerminalFrame: NSRect?
    private var lastScrollerVisibilitySignature: ScrollerVisibilitySignature?
    private var themePreferenceSnapshot = ThemePreferenceSnapshot.capture()
    private var fontPreferenceSnapshot = FontPreferenceSnapshot.capture()
    private var defaultsDidChangeObserver: NSObjectProtocol?
    private var windowNotificationObservers: [NSObjectProtocol] = []
    private var lastObservedSystemScheme: ColorScheme?
    private var desiredOnDoubleClick: (() -> Void)?
    private var desiredOnSplitTerminalRequested: (() -> Void)?
    private var desiredOnTemporaryTerminalRequested: (() -> Void)?
    private var desiredOnOpenInEditorPaneRequested: (() -> Void)?
    private var desiredOnInlineTriggerTextInput: ((String) -> Bool)?
    private var desiredOnInlineTriggerCommand: ((TerminalInlineTriggerCommand) -> Bool)?
    private var desiredOnLinkTargetActivated: ((URL) -> Void)?
    private var desiredOnFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    private struct ThemePreferenceSnapshot: Equatable {
        let appearancePreferenceRaw: String
        let themePresetRaw: String
        let customThemeJSON: String

        static func capture(defaults: UserDefaults = .standard) -> ThemePreferenceSnapshot {
            ThemePreferenceSnapshot(
                appearancePreferenceRaw: defaults.string(forKey: AppPreferences.appearancePreferenceKey)
                    ?? AppPreferences.defaultAppearancePreference,
                themePresetRaw: defaults.string(forKey: AppPreferences.appThemePresetKey)
                    ?? AppPreferences.defaultAppThemePreset,
                customThemeJSON: defaults.string(forKey: AppPreferences.appCustomThemePaletteJSONKey)
                    ?? ""
            )
        }
    }

    private struct FontPreferenceSnapshot: Equatable {
        let fontFamily: String
        let fontSize: Double
        let railFontScale: String

        static func capture(defaults: UserDefaults = .standard) -> FontPreferenceSnapshot {
            FontPreferenceSnapshot(
                fontFamily: defaults.string(forKey: AppPreferences.codeFontFamilyKey)
                    ?? AppPreferences.defaultCodeFontFamily,
                fontSize: (defaults.object(forKey: AppPreferences.codeFontSizeKey) as? Double)
                    ?? AppPreferences.defaultCodeFontSize,
                railFontScale: defaults.string(forKey: AppPreferences.railTerminalFontScaleKey)
                    ?? AppPreferences.defaultRailTerminalFontScale
            )
        }
    }

    private struct ThemeSignature: Equatable {
        let preferences: ThemePreferenceSnapshot
        let systemScheme: ColorScheme
    }

    private struct ScrollerVisibilitySignature: Equatable {
        let terminalID: ObjectIdentifier
        let isFocused: Bool
        let isActive: Bool
    }

    private func systemColorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private func observeThemePreferences() {
        defaultsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            self?.refreshThemePreferencesIfNeeded()
            self?.refreshFontPreferencesIfNeeded()
        }
    }

    init(
        ownershipCoordinator: TerminalHostOwnershipCoordinator,
        frame frameRect: NSRect = .zero
    ) {
        self.ownershipCoordinator = ownershipCoordinator
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        configureOpticalViewport()
        configurePinchZoom()
        registerHostOwnership()
        observeThemePreferences()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureOpticalViewport() {
        addSubview(opticalViewport)
    }

    private func configurePinchZoom() {
        addGestureRecognizer(
            NSMagnificationGestureRecognizer(
                target: self,
                action: #selector(handlePinchZoom(_:))
            )
        )
    }

    @objc private func handlePinchZoom(_ recognizer: NSMagnificationGestureRecognizer) {
        guard recognizer.state == .changed,
              attachedTerminalView is GhosttyTerminalView,
              let session = desiredSession else {
            return
        }
        let delta = recognizer.magnification
        recognizer.magnification = 0
        guard delta.isFinite, delta > -1 else { return }
        session.setDisplayMagnification(session.displayMagnification * (1 + delta))
        applyOpticalMagnification(
            session.displayMagnification,
            centeredAt: recognizer.location(in: opticalViewport)
        )
    }

    deinit {
        relinquishOwnership(for: desiredSessionID)
        ownershipCoordinator.unregisterHost(ownershipID: hostOwnershipID)
        teardownOutputObserver()
        teardownWindowObservation()
        if let defaultsDidChangeObserver {
            NotificationCenter.default.removeObserver(defaultsDidChangeObserver)
        }
        MainActor.assumeIsolated {
            if hasRegisteredDiagnosticsHost {
                diagnosticsSnapshot?.hostCount -= 1
            }
        }
    }

    func attach(
        _ terminalView: NSView,
        session: TerminalSession,
        sessionID: UUID,
        displayDensity: TerminalDisplayDensity,
        isActive: Bool,
        allowsOwnershipParticipation: Bool = true,
        ownershipPriorityBoost: Int = 0,
        onDoubleClick: (() -> Void)? = nil,
        onSplitTerminalRequested: (() -> Void)?,
        onTemporaryTerminalRequested: (() -> Void)?,
        onOpenInEditorPaneRequested: (() -> Void)?,
        onInlineTriggerTextInput: ((String) -> Bool)? = nil,
        onInlineTriggerCommand: ((TerminalInlineTriggerCommand) -> Bool)? = nil,
        onLinkTargetActivated: ((URL) -> Void)?,
        onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    ) {
        let previousSessionID = desiredSessionID
        let previousTerminalIdentifier = desiredTerminalView.map(terminalIdentifier(for:))
        let nextTerminalIdentifier = terminalIdentifier(for: terminalView)
        let shouldLogAttachRequest =
            previousSessionID != sessionID
            || previousTerminalIdentifier != nextTerminalIdentifier
            || desiredDisplayDensity != displayDensity
            || desiredIsActive != isActive
            || desiredAllowsOwnershipParticipation != allowsOwnershipParticipation
            || desiredOwnershipPriorityBoost != ownershipPriorityBoost
        if previousSessionID != sessionID {
            relinquishOwnership(for: previousSessionID)
            opticalViewport.resetTransform()
        }
        if previousTerminalIdentifier != nextTerminalIdentifier {
            cachedTerminalScroller = nil
            cachedTerminalScrollerOwnerID = nil
            lastAppliedTerminalFrame = nil
            lastScrollerVisibilitySignature = nil
        }
        desiredTerminalView = terminalView
        desiredSession = session
        desiredSessionID = sessionID
        desiredDisplayDensity = displayDensity
        desiredIsActive = isActive
        desiredAllowsOwnershipParticipation = allowsOwnershipParticipation
        desiredOwnershipPriorityBoost = ownershipPriorityBoost
        desiredOnDoubleClick = onDoubleClick
        desiredOnSplitTerminalRequested = onSplitTerminalRequested
        desiredOnTemporaryTerminalRequested = onTemporaryTerminalRequested
        desiredOnOpenInEditorPaneRequested = onOpenInEditorPaneRequested
        desiredOnInlineTriggerTextInput = onInlineTriggerTextInput
        desiredOnInlineTriggerCommand = onInlineTriggerCommand
        desiredOnLinkTargetActivated = onLinkTargetActivated
        desiredOnFileSystemTargetActivated = onFileSystemTargetActivated
        updateOutputObserver(for: session)
        if !hasRegisteredDiagnosticsHost {
            diagnosticsSnapshot = session.terminalServices.diagnosticsSnapshot
            diagnosticsSnapshot?.hostCount += 1
            hasRegisteredDiagnosticsHost = true
        }

        let presentationSource = Self.presentationSource(
            for: configuredAccessibilityIdentifier,
            density: displayDensity
        )
        if lastPublishedDiagnosticsSessionID != sessionID
            || lastPublishedPresentationSource != presentationSource
            || lastPublishedVisibility != allowsOwnershipParticipation {
            session.terminalServices.diagnosticsSnapshot.update(sessionID: sessionID) { entry in
                entry.source = presentationSource
                entry.isVisible = allowsOwnershipParticipation
            }
            lastPublishedDiagnosticsSessionID = sessionID
            lastPublishedPresentationSource = presentationSource
            lastPublishedVisibility = allowsOwnershipParticipation
        }

        refreshAccessibilityState()
        applySystemAppearance()
        applyTerminalScrollerConfiguration(to: terminalView)
        if shouldLogAttachRequest {
            AppDiagnostics.hostDebug("attach requested session=\(sessionID.uuidString) terminal=\(nextTerminalIdentifier) container=\(containerIdentifier) density=\(densityLabel(displayDensity))")
            AppDiagnostics.record(
                category: .terminalHost,
                level: .debug,
                event: "terminal_attach_requested",
                metadata: [
                    "container": containerIdentifier,
                    "session": sessionID.uuidString,
                    "terminal": nextTerminalIdentifier,
                    "density": densityLabel(displayDensity)
                ]
            )
            os_signpost(
                .event,
                log: AppDiagnostics.terminalHostSignpostLog,
                name: "TerminalAttachRequested",
                "container=%{public}@ session=%{public}@ terminal=%{public}@ density=%{public}@",
                containerIdentifier,
                sessionID.uuidString,
                nextTerminalIdentifier,
                densityLabel(displayDensity)
            )
        }
        attemptAttachIfNeeded(trigger: "attach")
    }

    override func layout() {
        super.layout()
        if let attachedTerminalView,
           !isHostedInOpticalViewport(attachedTerminalView) {
            if opticalViewport.documentView === attachedTerminalView {
                opticalViewport.documentView = nil
            }
            self.attachedTerminalView = nil
            appliedDisplayDensity = nil
        }
        layoutAttachedTerminalViewFrame()
        attemptAttachIfNeeded(trigger: "layout")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowObservation(for: window)
        guard window != nil else {
            detachAttachedTerminalIfNeeded()
            return
        }
        attemptAttachIfNeeded(trigger: "moveToWindow")
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil else {
            releaseDesiredTargets()
            return
        }
        attemptAttachIfNeeded(trigger: "moveToSuperview")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            detachAttachedTerminalIfNeeded()
            teardownWindowObservation()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let resolvedSystemScheme = systemColorScheme(for: effectiveAppearance)
        guard resolvedSystemScheme != lastObservedSystemScheme else {
            return
        }
        lastObservedSystemScheme = resolvedSystemScheme
        applySystemAppearance()
    }

    private func attemptAttachIfNeeded(trigger: String) {
        guard ensureDesiredSessionOwnership() else {
            if let attachedTerminalView {
                if isHostedInOpticalViewport(attachedTerminalView) {
                    detachFromOpticalViewport(attachedTerminalView)
                } else if opticalViewport.documentView === attachedTerminalView {
                    opticalViewport.documentView = nil
                }
            }
            self.attachedTerminalView = nil
            appliedDisplayDensity = nil
            refreshAccessibilityState()
            return
        }
        guard let terminalView = desiredTerminalView else { return }
        guard window != nil else {
            detachAttachedTerminalIfNeeded()
            return
        }
        let sessionIDText = desiredSessionID?.uuidString ?? "unknown"
        configureOpticalInputMapping(for: terminalView)

        if attachedTerminalView === terminalView,
           isHostedInOpticalViewport(terminalView) {
            restoreGhosttySurfaceIfNeeded(for: terminalView)
            applyDesiredDensityIfNeeded()
            applyOpticalMagnification(desiredSession?.displayMagnification ?? 1)
            applyTerminalScrollerConfiguration(to: terminalView)
            applyTerminalActionConfiguration()
            layoutAttachedTerminalViewFrame()
            desiredSession?.startIfNeeded()
            return
        }

        if let attachedTerminalView,
           attachedTerminalView !== terminalView,
           isHostedInOpticalViewport(attachedTerminalView) {
            detachFromOpticalViewport(attachedTerminalView)
        }

        if !isHostedInOpticalViewport(terminalView) {
            terminalView.removeFromSuperview()
            terminalView.frame = NSRect(origin: .zero, size: terminalViewFrame(in: bounds).size)
            terminalView.autoresizingMask = []
            opticalViewport.documentView = terminalView
            AppDiagnostics.hostDebug("terminal attached trigger=\(trigger) session=\(sessionIDText) terminal=\(terminalIdentifier(for: terminalView)) container=\(containerIdentifier)")
            AppDiagnostics.record(
                category: .terminalHost,
                level: .debug,
                event: "terminal_attached",
                metadata: [
                    "container": containerIdentifier,
                    "session": sessionIDText,
                    "terminal": terminalIdentifier(for: terminalView),
                    "trigger": trigger
                ]
            )
            os_signpost(
                .event,
                log: AppDiagnostics.terminalHostSignpostLog,
                name: "TerminalAttached",
                "container=%{public}@ session=%{public}@ terminal=%{public}@ trigger=%{public}@",
                containerIdentifier,
                sessionIDText,
                terminalIdentifier(for: terminalView),
                trigger
            )
        }

        attachedTerminalView = terminalView
        restoreGhosttySurfaceIfNeeded(for: terminalView)
        applyDesiredDensityIfNeeded()
        applyOpticalMagnification(desiredSession?.displayMagnification ?? 1)
        applyTerminalScrollerConfiguration(to: terminalView)
        applyTerminalActionConfiguration()
        desiredSession?.startIfNeeded()
    }

    private func detachAttachedTerminalIfNeeded() {
        guard let attachedTerminalView else { return }
        detachFromOpticalViewport(attachedTerminalView)
        if let ghosttyView = attachedTerminalView as? GhosttyTerminalView {
            ghosttyView.engine?.syncOutputPollingToVisibility()
        }
        self.attachedTerminalView = nil
        appliedDisplayDensity = nil
        cachedTerminalScroller = nil
        cachedTerminalScrollerOwnerID = nil
        lastAppliedTerminalFrame = nil
        lastScrollerVisibilitySignature = nil
        refreshAccessibilityState()
    }

    private func releaseDesiredTargets() {
        detachAttachedTerminalIfNeeded()
        relinquishOwnership(for: desiredSessionID)
        desiredTerminalView = nil
        desiredSession = nil
        desiredSessionID = nil
        desiredOnDoubleClick = nil
        desiredOnSplitTerminalRequested = nil
        desiredOnTemporaryTerminalRequested = nil
        desiredOnOpenInEditorPaneRequested = nil
        desiredOnInlineTriggerTextInput = nil
        desiredOnInlineTriggerCommand = nil
        desiredOnLinkTargetActivated = nil
        desiredOnFileSystemTargetActivated = nil
        updateOutputObserver(for: nil)
        refreshAccessibilityState()
    }

    private func applyTerminalActionConfiguration() {
        desiredSession?.updateActionHandlers(
            TerminalSessionActionHandlers(
                onSplitTerminalRequested: desiredOnSplitTerminalRequested,
                onTemporaryTerminalRequested: desiredOnTemporaryTerminalRequested,
                onOpenInEditorPaneRequested: desiredOnOpenInEditorPaneRequested,
                onLinkTargetActivated: desiredOnLinkTargetActivated,
                onFileSystemTargetActivated: desiredOnFileSystemTargetActivated,
                onInlineTriggerTextInput: desiredOnInlineTriggerTextInput,
                onInlineTriggerCommand: desiredOnInlineTriggerCommand,
                currentDirectoryProvider: { [weak desiredSession] in
                    desiredSession?.currentWorkingDirectory
                }
            )
        )
    }

    private func registerHostOwnership() {
        ownershipCoordinator.registerHost(self)
    }

    private func relinquishOwnership(for sessionID: UUID?) {
        ownershipCoordinator.releaseOwnership(for: sessionID, ownerID: hostOwnershipID)
    }

    private var canParticipateInOwnership: Bool {
        desiredAllowsOwnershipParticipation &&
            desiredSessionID != nil &&
            superview != nil &&
            window != nil
    }

    private func ensureDesiredSessionOwnership() -> Bool {
        ownershipCoordinator.ensureOwnership(
            for: desiredSessionID,
            ownerID: hostOwnershipID,
            canParticipate: canParticipateInOwnership
        )
    }

    private func applySystemAppearance() {
        guard let terminalView = desiredTerminalView ?? attachedTerminalView else { return }
        let signature = ThemeSignature(
            preferences: themePreferenceSnapshot,
            systemScheme: systemColorScheme(for: terminalView.effectiveAppearance)
        )
        let terminalIdentifier = ObjectIdentifier(terminalView)
        if lastAppliedTerminalViewIdentifier == terminalIdentifier,
           lastAppliedThemeSignature == signature {
            return
        }

        lastAppliedTerminalViewIdentifier = terminalIdentifier
        lastAppliedThemeSignature = signature
        desiredSession?.applySystemAppearance()
    }

    private func applyTerminalScrollerConfiguration(to terminalView: NSView) {
        let isFocused = isTerminalResponderFocused(for: terminalView)
        let signature = ScrollerVisibilitySignature(
            terminalID: ObjectIdentifier(terminalView),
            isFocused: isFocused,
            isActive: desiredIsActive
        )
        guard signature != lastScrollerVisibilitySignature else { return }
        guard let scroller = findTerminalScroller(in: terminalView) else { return }
        let shouldShowScroller = desiredIsActive && isFocused

        scroller.scrollerStyle = .overlay
        scroller.controlSize = .small
        scroller.isHidden = !shouldShowScroller
        scroller.alphaValue = shouldShowScroller ? 1 : 0

        let thinWidth: CGFloat = 7
        updateTerminalScrollerWidthConstraint(for: scroller, width: thinWidth)
        terminalView.needsLayout = true
        lastScrollerVisibilitySignature = signature
    }

    private func isTerminalResponderFocused(for terminalView: NSView) -> Bool {
        guard let window, window.isKeyWindow else { return false }
        guard let responderView = window.firstResponder as? NSView else { return false }
        return responderView === terminalView || responderView.isDescendant(of: terminalView)
    }

    private func configureWindowObservation(for window: NSWindow?) {
        teardownWindowObservation()
        guard let window else { return }

        // Scroller visibility on any window update
        windowNotificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.refreshScrollerVisibility()
            }
        )
        windowNotificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.cancelAttachedPointerInteraction()
            }
        )
        windowNotificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                self?.cancelAttachedPointerInteraction()
            }
        )

        refreshScrollerVisibility()
    }

    private func teardownWindowObservation() {
        for observer in windowNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowNotificationObservers.removeAll()
    }

    private func refreshScrollerVisibility() {
        if let attachedTerminalView {
            applyTerminalScrollerConfiguration(to: attachedTerminalView)
        } else if let desiredTerminalView {
            applyTerminalScrollerConfiguration(to: desiredTerminalView)
        }
    }

    private func cancelAttachedPointerInteraction() {
        (attachedTerminalView as? GhosttyTerminalView)?.cancelPointerInteraction()
    }

    private func findTerminalScroller(in terminalView: NSView) -> NSScroller? {
        let terminalID = ObjectIdentifier(terminalView)
        if cachedTerminalScrollerOwnerID == terminalID,
           let cachedTerminalScroller,
           cachedTerminalScroller.isDescendant(of: terminalView) {
            return cachedTerminalScroller
        }

        var scrollers: [NSScroller] = []
        collectTerminalScrollers(in: terminalView, into: &scrollers)
        let resolved = scrollers.first(where: { $0.bounds.height >= $0.bounds.width }) ?? scrollers.first
        cachedTerminalScroller = resolved
        cachedTerminalScrollerOwnerID = terminalID
        return resolved
    }

    private func collectTerminalScrollers(in view: NSView, into scrollers: inout [NSScroller]) {
        if let scroller = view as? NSScroller {
            scrollers.append(scroller)
        }
        for subview in view.subviews {
            collectTerminalScrollers(in: subview, into: &scrollers)
        }
    }

    private func updateTerminalScrollerWidthConstraint(for scroller: NSScroller, width: CGFloat) {
        let superviewConstraints = scroller.superview?.constraints.filter {
            ($0.firstItem as AnyObject?) === scroller || ($0.secondItem as AnyObject?) === scroller
        } ?? []
        let candidateConstraints = scroller.constraints + superviewConstraints

        for constraint in candidateConstraints {
            let firstMatches = (constraint.firstItem as AnyObject?) === scroller
            let secondMatches = (constraint.secondItem as AnyObject?) === scroller
            let touchesWidth =
                (firstMatches && constraint.firstAttribute == .width) ||
                (secondMatches && constraint.secondAttribute == .width)
            guard touchesWidth else { continue }
            constraint.constant = width
        }
    }

    private func refreshThemePreferencesIfNeeded() {
        let updatedSnapshot = ThemePreferenceSnapshot.capture()
        guard updatedSnapshot != themePreferenceSnapshot else { return }
        themePreferenceSnapshot = updatedSnapshot
        lastAppliedThemeSignature = nil
        applySystemAppearance()
    }

    private func refreshFontPreferencesIfNeeded() {
        let updatedSnapshot = FontPreferenceSnapshot.capture()
        guard updatedSnapshot != fontPreferenceSnapshot else { return }
        fontPreferenceSnapshot = updatedSnapshot
        appliedDisplayDensity = nil
        applyDesiredDensityIfNeeded()
    }

    private var containerIdentifier: String {
        String(describing: ObjectIdentifier(self))
    }

    private func terminalIdentifier(for terminalView: NSView) -> String {
        String(describing: ObjectIdentifier(terminalView))
    }

    private func applyDesiredDensityIfNeeded() {
        if appliedDisplayDensity == desiredDisplayDensity {
            return
        }
        guard let session = desiredSession else { return }
        session.setDisplayDensity(desiredDisplayDensity)
        appliedDisplayDensity = desiredDisplayDensity
    }

    private func densityLabel(_ density: TerminalDisplayDensity) -> String {
        switch density {
        case .regular:
            return "regular"
        case .compact:
            return "compact"
        }
    }

    private func layoutAttachedTerminalViewFrame() {
        let frame = terminalViewFrame(in: bounds)
        if opticalViewport.frame != frame {
            opticalViewport.frame = frame
        }
        guard let attachedTerminalView else { return }
        let documentFrame = NSRect(origin: .zero, size: frame.size)
        guard lastAppliedTerminalFrame != frame || attachedTerminalView.frame != documentFrame else { return }
        attachedTerminalView.frame = documentFrame
        opticalViewport.refreshTransform()
        lastAppliedTerminalFrame = frame
    }

    private func isHostedInOpticalViewport(_ terminalView: NSView) -> Bool {
        terminalView.superview === opticalViewport
    }

    private func detachFromOpticalViewport(_ terminalView: NSView) {
        guard isHostedInOpticalViewport(terminalView) else { return }
        if let ghosttyView = terminalView as? GhosttyTerminalView {
            ghosttyView.cancelPointerInteraction()
            ghosttyView.onDoubleClick = nil
            ghosttyView.opticalViewportPointerMapper = nil
            ghosttyView.opticalViewportPointMapper = nil
            ghosttyView.opticalViewportRectMapper = nil
        }
        if opticalViewport.documentView === terminalView {
            opticalViewport.documentView = nil
        } else {
            terminalView.removeFromSuperview()
        }
    }

    private func configureOpticalInputMapping(for terminalView: NSView) {
        guard let ghosttyView = terminalView as? GhosttyTerminalView else { return }
        ghosttyView.onDoubleClick = desiredOnDoubleClick
        ghosttyView.opticalViewportPointerMapper = { [weak opticalViewport, weak ghosttyView] event in
            opticalViewport?.terminalPoint(for: event)
                ?? ghosttyView?.convert(event.locationInWindow, from: nil)
                ?? .zero
        }
        ghosttyView.opticalViewportPointMapper = { [weak opticalViewport] point in
            opticalViewport?.viewportPoint(forTerminalPoint: point) ?? point
        }
        ghosttyView.opticalViewportRectMapper = { [weak opticalViewport] rect in
            opticalViewport?.viewportRect(forTerminalRect: rect) ?? rect
        }
    }

    private func applyOpticalMagnification(
        _ magnification: CGFloat,
        centeredAt point: CGPoint? = nil
    ) {
        guard opticalViewport.hostedDocumentView is GhosttyTerminalView else {
            opticalViewport.setMagnification(1, centeredAt: .zero)
            return
        }
        let center = point ?? CGPoint(x: opticalViewport.bounds.midX, y: opticalViewport.bounds.midY)
        opticalViewport.setMagnification(magnification, centeredAt: center)
    }

    private func restoreGhosttySurfaceIfNeeded(for terminalView: NSView) {
        guard let ghosttyView = terminalView as? GhosttyTerminalView else { return }
        if ghosttyView.surface == nil {
            ghosttyView.createSurfaceIfNeeded()
        } else {
            ghosttyView.applyCurrentDisplayIDIfAvailable()
            ghosttyView.syncSurfaceGeometry()
        }
        ghosttyView.engine?.syncOutputPollingToVisibility()
    }

    private func terminalViewFrame(in containerBounds: NSRect) -> NSRect {
        let maxInset = max(0, (containerBounds.width - 1) / 2)
        let inset = min(horizontalContentInset, maxInset)
        return containerBounds.insetBy(dx: inset, dy: 0)
    }

    private func updateOutputObserver(for session: TerminalSession?) {
        guard observedOutputSession !== session else { return }
        teardownOutputObserver()
        observedOutputSession = session
        guard let session else { return }
        firstOutputObserverToken = session.addFirstOutputObserver { [weak self] in
            self?.refreshAccessibilityState()
        }
    }

    private func teardownOutputObserver() {
        if let observedOutputSession,
           let firstOutputObserverToken {
            observedOutputSession.removeFirstOutputObserver(firstOutputObserverToken)
        }
        firstOutputObserverToken = nil
        observedOutputSession = nil
    }

    private func refreshAccessibilityState() {
        let readiness = desiredSession?.hasReceivedOutput == true ? "ready" : "pending"
        let renderableSample = desiredSession?.firstRenderableTextSample ?? ""
        let readinessChanged = lastAccessibilityReadiness != readiness
        let labelChanged = lastAccessibilityLabelValue != renderableSample

        setAccessibilityValue(readiness)
        setAccessibilityLabel(renderableSample)
        lastAccessibilityReadiness = readiness
        lastAccessibilityLabelValue = renderableSample

        guard readinessChanged || labelChanged else { return }
        NSAccessibility.post(element: self, notification: .valueChanged)
        if labelChanged {
            NSAccessibility.post(element: self, notification: .titleChanged)
        }
    }

    func configureAccessibility(identifier: String?) {
        guard configuredAccessibilityIdentifier != identifier else { return }
        configuredAccessibilityIdentifier = identifier
        setAccessibilityIdentifier(identifier)
    }

    var sessionOwnershipID: UUID { hostOwnershipID }

    private static func presentationSource(for identifier: String?, density: TerminalDisplayDensity) -> TerminalPresentationSource {
        switch identifier {
        case "terminal.spotlight.host": return .spotlight
        case "vibespace.terminal-board.session": return .board
        default:
            return density == .compact ? .rail : .detailed
        }
    }
    func configureOpticalViewportForTesting(
        magnification: CGFloat,
        centeredAt point: CGPoint,
        panDelta: CGPoint
    ) {
        opticalViewport.setMagnification(magnification, centeredAt: point)
        opticalViewport.pan(by: panDelta)
    }

    func opticalWindowPointForTesting(terminalPoint: CGPoint) -> CGPoint {
        let viewportPoint = opticalViewport.viewportPoint(forTerminalPoint: terminalPoint)
        return opticalViewport.convert(viewportPoint, to: nil)
    }

    var opticalMagnificationForTesting: CGFloat { opticalViewport.magnification }
    var opticalVisibleOriginForTesting: CGPoint { opticalViewport.visibleOrigin }
    var hasOpticalDocumentReferenceForTesting: Bool { opticalViewport.documentView != nil }

    func hostsTerminalView(_ terminalView: NSView) -> Bool {
        attachedTerminalView === terminalView && isHostedInOpticalViewport(terminalView)
    }

    var desiredSessionIDForOwnership: UUID? { desiredSessionID }
    var canParticipateInOwnershipArbitration: Bool { canParticipateInOwnership }
    var ownershipArbitrationPriority: Int {
        if configuredAccessibilityIdentifier == "terminal.spotlight.host" {
            return 300
        }

        let basePriority: Int
        switch desiredDisplayDensity {
        case .regular:
            basePriority = desiredIsActive ? 200 : 180
        case .compact:
            basePriority = desiredIsActive ? 120 : 100
        }
        return basePriority + desiredOwnershipPriorityBoost
    }

    func retryOwnershipAcquisition() {
        attemptAttachIfNeeded(trigger: "ownershipReleased")
    }
}

struct TerminalOpticalTransform: Equatable {
    var scale: CGFloat = 1
    var visibleOrigin: CGPoint = .zero

    var layerTransform: CATransform3D {
        CATransform3DMakeAffineTransform(
            CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: -visibleOrigin.x, y: -visibleOrigin.y)
        )
    }

    func terminalPoint(fromViewport point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / max(scale, 0.001) + visibleOrigin.x,
            y: point.y / max(scale, 0.001) + visibleOrigin.y
        )
    }

    func viewportPoint(fromTerminal point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - visibleOrigin.x) * scale,
            y: (point.y - visibleOrigin.y) * scale
        )
    }

    mutating func setScale(
        _ newScale: CGFloat,
        anchoredAt anchor: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize
    ) {
        let terminalAnchor = terminalPoint(fromViewport: anchor)
        scale = max(newScale, 1)
        visibleOrigin = CGPoint(
            x: terminalAnchor.x - anchor.x / scale,
            y: terminalAnchor.y - anchor.y / scale
        )
        constrain(contentSize: contentSize, viewportSize: viewportSize)
    }

    mutating func pan(
        by delta: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize
    ) {
        visibleOrigin.x -= delta.x / max(scale, 0.001)
        visibleOrigin.y += delta.y / max(scale, 0.001)
        constrain(contentSize: contentSize, viewportSize: viewportSize)
    }

    mutating func constrain(contentSize: CGSize, viewportSize: CGSize) {
        visibleOrigin.x = Self.constrainedOrigin(
            visibleOrigin.x,
            contentLength: contentSize.width,
            viewportLength: viewportSize.width,
            scale: scale
        )
        visibleOrigin.y = Self.constrainedOrigin(
            visibleOrigin.y,
            contentLength: contentSize.height,
            viewportLength: viewportSize.height,
            scale: scale
        )
    }

    private static func constrainedOrigin(
        _ origin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        let visibleLength = viewportLength / max(scale, 0.001)
        guard visibleLength < contentLength else {
            return (contentLength - visibleLength) / 2
        }
        return min(max(origin, 0), contentLength - visibleLength)
    }
}

private final class TerminalOpticalViewport: NSView {
    weak var documentView: NSView? {
        didSet {
            if oldValue !== documentView, oldValue?.superview === self {
                oldValue?.removeFromSuperview()
            }
            if let documentView, documentView.superview !== self {
                documentView.removeFromSuperview()
                addSubview(documentView)
            }
            refreshTransform()
        }
    }

    private var opticalTransform = TerminalOpticalTransform()
    var magnification: CGFloat { opticalTransform.scale }
    var visibleOrigin: CGPoint { opticalTransform.visibleOrigin }
    var hostedDocumentView: NSView? {
        guard documentView?.superview === self else { return nil }
        return documentView
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        refreshTransform()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        if let event = NSApp.currentEvent,
           event.type == .scrollWheel,
           magnification > 1.001,
           !event.modifierFlags.contains(.option) {
            return self
        }
        guard let documentView = hostedDocumentView else { return self }
        let terminalPoint = opticalTransform.terminalPoint(fromViewport: localPoint)
        guard documentView.frame.contains(terminalPoint) else { return self }
        let documentLocalPoint = CGPoint(
            x: terminalPoint.x - documentView.frame.minX,
            y: terminalPoint.y - documentView.frame.minY
        )
        return documentView.hitTest(documentLocalPoint) ?? documentView
    }

    override func scrollWheel(with event: NSEvent) {
        if magnification > 1.001,
           !event.modifierFlags.contains(.option) {
            pan(by: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        } else {
            hostedDocumentView?.scrollWheel(with: event)
        }
    }

    func setMagnification(_ magnification: CGFloat, centeredAt point: CGPoint) {
        opticalTransform.setScale(
            magnification,
            anchoredAt: point,
            contentSize: hostedDocumentView?.frame.size ?? bounds.size,
            viewportSize: bounds.size
        )
        applyLayerTransform()
    }

    func pan(by delta: CGPoint) {
        opticalTransform.pan(
            by: delta,
            contentSize: hostedDocumentView?.frame.size ?? bounds.size,
            viewportSize: bounds.size
        )
        applyLayerTransform()
    }

    func resetTransform() {
        opticalTransform = TerminalOpticalTransform()
        refreshTransform()
    }

    func refreshTransform() {
        opticalTransform.constrain(
            contentSize: hostedDocumentView?.frame.size ?? bounds.size,
            viewportSize: bounds.size
        )
        applyLayerTransform()
    }

    func terminalPoint(for event: NSEvent) -> CGPoint {
        let viewportPoint = convert(event.locationInWindow, from: nil)
        let point = opticalTransform.terminalPoint(fromViewport: viewportPoint)
        guard let documentView = hostedDocumentView else { return point }
        return CGPoint(
            x: point.x - documentView.frame.minX,
            y: point.y - documentView.frame.minY
        )
    }

    func viewportPoint(forTerminalPoint point: CGPoint) -> CGPoint {
        guard let documentView = hostedDocumentView else {
            return opticalTransform.viewportPoint(fromTerminal: point)
        }
        return opticalTransform.viewportPoint(
            fromTerminal: CGPoint(
                x: point.x + documentView.frame.minX,
                y: point.y + documentView.frame.minY
            )
        )
    }

    func viewportRect(forTerminalRect rect: CGRect) -> CGRect {
        CGRect(
            origin: viewportPoint(forTerminalPoint: rect.origin),
            size: CGSize(
                width: rect.width * magnification,
                height: rect.height * magnification
            )
        )
    }

    private func applyLayerTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayerTransform = opticalTransform.layerTransform
        CATransaction.commit()
        (hostedDocumentView as? GhosttyTerminalView)?.invalidateOpticalCharacterCoordinates()
    }
}
