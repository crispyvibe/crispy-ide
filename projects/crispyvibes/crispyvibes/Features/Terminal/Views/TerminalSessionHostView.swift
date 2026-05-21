import SwiftUI
import os.signpost

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
                if let observer = session.insightObserver {
                    TerminalContextSummaryOverlayContainer(
                        observer: observer,
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
        registerHostOwnership()
        observeThemePreferences()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
           attachedTerminalView.superview !== self {
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
            if let attachedTerminalView,
               attachedTerminalView.superview === self {
                attachedTerminalView.removeFromSuperview()
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

        if attachedTerminalView === terminalView,
           terminalView.superview === self {
            restoreGhosttySurfaceIfNeeded(for: terminalView)
            applyDesiredDensityIfNeeded()
            applyTerminalScrollerConfiguration(to: terminalView)
            applyTerminalActionConfiguration()
            layoutAttachedTerminalViewFrame()
            desiredSession?.startIfNeeded()
            return
        }

        if let attachedTerminalView,
           attachedTerminalView !== terminalView,
           attachedTerminalView.superview === self {
            attachedTerminalView.removeFromSuperview()
        }

        if terminalView.superview !== self {
            terminalView.removeFromSuperview()
            terminalView.frame = terminalViewFrame(in: bounds)
            terminalView.autoresizingMask = [.width, .height]
            addSubview(terminalView)
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
        applyTerminalScrollerConfiguration(to: terminalView)
        applyTerminalActionConfiguration()
        desiredSession?.startIfNeeded()
    }

    private func detachAttachedTerminalIfNeeded() {
        guard let attachedTerminalView else { return }
        if attachedTerminalView.superview === self {
            attachedTerminalView.removeFromSuperview()
        }
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
        guard let attachedTerminalView else { return }
        let frame = terminalViewFrame(in: bounds)
        guard lastAppliedTerminalFrame != frame || attachedTerminalView.frame != frame else { return }
        attachedTerminalView.frame = frame
        lastAppliedTerminalFrame = frame
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
