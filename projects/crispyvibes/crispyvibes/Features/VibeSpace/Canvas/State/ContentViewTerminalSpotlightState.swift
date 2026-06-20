import AppKit
import SwiftUI

enum SpotlightSwipeDirection {
    case none, leading, trailing
}

enum SpotlightItem {
    case terminal(project: AnyProjectSession, tab: TerminalTab)
    case vibeCast
    case acp(tileID: UUID, storeID: UUID, title: String, accentColor: Color?)
    case file(tileID: UUID, fileURL: URL)
    case browser(tileID: UUID, url: URL)
}

struct TerminalSpotlightState: Identifiable {
    enum Source {
        case persistent(terminalViewModel: TerminalViewModel, tabID: UUID)
        case transient(session: TerminalSession)
        case vibeCast
        case todos
        case acp(tileID: UUID, storeID: UUID)
        case filePreview(target: TerminalFileSystemTarget, group: EditorGroupStore)
        case file(tileID: UUID, fileURL: URL)
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
    let isTemporary: Bool
    let owningProjectRootURL: URL?
    let surfaceID: UUID?

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
        isTemporary: Bool,
        owningProjectRootURL: URL?,
        surfaceID: UUID? = nil
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
        self.isTemporary = isTemporary
        self.owningProjectRootURL = owningProjectRootURL
        self.surfaceID = surfaceID
    }
}

enum SpotlightRestoreDescriptor {
    case terminal(projectRootURL: URL, tabID: UUID)
    case transient(
        title: String,
        accentColor: Color?,
        directoryURL: URL,
        shellResolutionProvider: @Sendable () -> TerminalShellResolution,
        sessionConfigurator: ((TerminalSession) -> Void)?,
        onSplitTerminalRequested: (() -> Void)?,
        owningProjectRootURL: URL?
    )
    case filePreview(target: TerminalFileSystemTarget, projectPath: String?)
    case file(tileID: UUID, fileURL: URL)
    case acp(tileID: UUID, storeID: UUID)
    case vibeCast
    case browserPreview(snapshot: BrowserSessionSnapshot, projectPath: String?)
    case browser(tileID: UUID, url: URL)
}

extension TerminalSpotlightState.Source {
    var supportsCarouselNavigation: Bool {
        switch self {
        case .persistent, .vibeCast, .acp, .file, .browser:
            return true
        case .transient, .todos, .filePreview, .browserPreview:
            return false
        }
    }

    var showsTemporaryBadge: Bool {
        switch self {
        case .transient, .filePreview, .browserPreview:
            return true
        case .persistent, .vibeCast, .todos, .acp, .file, .browser:
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
        case .vibeCast, .todos, .acp, .filePreview, .file, .browserPreview, .browser:
            return false
        }
    }

    var canBeRestored: Bool {
        switch self {
        case .persistent, .transient, .vibeCast, .acp, .filePreview, .file, .browserPreview, .browser:
            return true
        case .todos:
            return false
        }
    }
}

extension TerminalSpotlightState {
    var supportsCarouselNavigation: Bool { source.supportsCarouselNavigation }
    var showsTemporaryBadge: Bool { source.showsTemporaryBadge || isTemporary }
    var headerIconName: String { source.headerIconName }
}

@MainActor
final class TerminalSpotlightCoordinator: ObservableObject {
    private let diagnosticsSnapshot: TerminalDiagnosticsSnapshot
    @Published var spotlight: TerminalSpotlightState?
    @Published var swipeDirection: SpotlightSwipeDirection = .none
    @Published var swipeOffset: CGFloat = 0
    @Published var tabPageOffset: Int = 0

    private var scrollMonitor: Any?
    private(set) var restoreStack: [SpotlightRestoreDescriptor] = []
    private let maxRestoreStackDepth = 8

    init(diagnosticsSnapshot: TerminalDiagnosticsSnapshot) {
        self.diagnosticsSnapshot = diagnosticsSnapshot
    }

    deinit {
        MainActor.assumeIsolated {
            removeScrollMonitor()
            releaseTerminalSpotlightIfNeeded(spotlight, replacingWith: nil)
        }
    }

    func installScrollMonitor(onSwitchSpotlight: @escaping (Int) -> Void) {
        guard scrollMonitor == nil else { return }
        var cumulativeDeltaX: CGFloat = 0
        var cumulativeDeltaY: CGFloat = 0
        var isTracking = false
        var isHorizontalGesture = false
        var isVerticalGesture = false

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            guard spotlight?.supportsCarouselNavigation == true else { return event }
            guard event.hasPreciseScrollingDeltas else { return event }
            if event.momentumPhase != [] { return isHorizontalGesture ? nil : event }

            switch event.phase {
            case .began:
                cumulativeDeltaX = 0
                cumulativeDeltaY = 0
                isTracking = true
                isHorizontalGesture = false
                isVerticalGesture = false
            case .changed where isTracking:
                cumulativeDeltaX += event.scrollingDeltaX
                cumulativeDeltaY += event.scrollingDeltaY
                if !isHorizontalGesture {
                    if isVerticalGesture {
                        return event
                    }
                    if abs(cumulativeDeltaY) > 12 && abs(cumulativeDeltaY) > abs(cumulativeDeltaX) {
                        isVerticalGesture = true
                        return event
                    }
                    if abs(cumulativeDeltaX) > 20 && abs(cumulativeDeltaX) > abs(cumulativeDeltaY) * 2 {
                        isHorizontalGesture = true
                    } else {
                        return event
                    }
                }
                let dampened = cumulativeDeltaX * 0.35
                withAnimation(.interactiveSpring(response: 0.08, dampingFraction: 0.9)) {
                    self.swipeOffset = dampened
                }
            case .ended, .cancelled:
                guard isTracking else { return event }
                isTracking = false
                guard isHorizontalGesture else { return event }
                isHorizontalGesture = false
                if abs(cumulativeDeltaX) > 50 {
                    onSwitchSpotlight(cumulativeDeltaX < 0 ? 1 : -1)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        self.swipeOffset = 0
                    }
                }
                return nil
            default:
                return event
            }
            return isHorizontalGesture ? nil : event
        }
    }

    func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    func prepareSwitchTransition(offset: Int) -> CGFloat {
        swipeDirection = offset > 0 ? .trailing : .leading
        return offset > 0 ? 200 : -200
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
        swipeDirection = .none
        swipeOffset = 0
        tabPageOffset = 0
        removeScrollMonitor()
        restoreStack.removeAll()
        releaseTerminalSpotlightIfNeeded(spotlight, replacingWith: nil)
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                spotlight = nil
            }
        } else {
            spotlight = nil
        }
    }

    /// Build a restore descriptor from the current spotlight state.
    func descriptorForCurrentSpotlight(
        browserPreviewSnapshotProvider: (() -> BrowserSessionSnapshot?)? = nil
    ) -> SpotlightRestoreDescriptor? {
        guard let spotlight, spotlight.source.canBeRestored else { return nil }
        switch spotlight.source {
        case let .persistent(_, tabID):
            guard let rootURL = spotlight.owningProjectRootURL else { return nil }
            return .terminal(projectRootURL: rootURL, tabID: tabID)
        case let .transient(session):
            return .transient(
                title: spotlight.title,
                accentColor: spotlight.accentColor,
                directoryURL: session.currentWorkingDirectory.standardizedFileURL,
                shellResolutionProvider: session.shellResolutionProvider,
                sessionConfigurator: nil,
                onSplitTerminalRequested: spotlight.onSplitTerminalRequested,
                owningProjectRootURL: spotlight.owningProjectRootURL
            )
        case .vibeCast:
            return .vibeCast
        case .todos:
            return nil
        case let .acp(tileID, storeID):
            return .acp(tileID: tileID, storeID: storeID)
        case let .filePreview(target, _):
            return .filePreview(
                target: target,
                projectPath: spotlight.owningProjectRootURL?.path
            )
        case let .file(tileID, fileURL):
            return .file(tileID: tileID, fileURL: fileURL)
        case let .browserPreview(snapshot):
            let previewSnapshot = browserPreviewSnapshotProvider?() ?? snapshot
            return .browserPreview(
                snapshot: previewSnapshot,
                projectPath: spotlight.owningProjectRootURL?.path
            )
        case let .browser(tileID, url):
            return .browser(tileID: tileID, url: url)
        }
    }

    /// Push the current spotlight onto the restore stack before replacing it.
    func pushCurrentSpotlightForRestore(
        browserPreviewSnapshotProvider: (() -> BrowserSessionSnapshot?)? = nil
    ) {
        guard let descriptor = descriptorForCurrentSpotlight(
            browserPreviewSnapshotProvider: browserPreviewSnapshotProvider
        ) else { return }
        if restoreStack.count >= maxRestoreStackDepth {
            restoreStack.removeFirst()
        }
        restoreStack.append(descriptor)
    }

    /// Pop and return the next valid restore descriptor, or nil if exhausted.
    func popRestoreDescriptor() -> SpotlightRestoreDescriptor? {
        restoreStack.popLast()
    }

    func setSpotlight(
        _ nextSpotlight: TerminalSpotlightState?,
        animated: Bool = true,
        onFocusSpotlight: ((TerminalSpotlightState) -> Void)? = nil
    ) {
        releaseTerminalSpotlightIfNeeded(spotlight, replacingWith: nextSpotlight)
        diagnosticsSnapshot.spotlightActive = nextSpotlight != nil
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                spotlight = nextSpotlight
            }
        } else {
            spotlight = nextSpotlight
        }
        if let nextSpotlight {
            DispatchQueue.main.async {
                onFocusSpotlight?(nextSpotlight)
            }
        }
    }

    private func releaseTerminalSpotlightIfNeeded(
        _ spotlight: TerminalSpotlightState?,
        replacingWith nextSpotlight: TerminalSpotlightState?
    ) {
        guard let spotlight else { return }
        guard spotlight.id != nextSpotlight?.id else { return }
        guard case let .transient(session) = spotlight.source else { return }
        session.onProcessTerminated = nil
        session.terminate()
    }
}

extension ContentView {
    private func spotlightShortcutDefinitions(
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

    private func spotlightManageShortcuts() {
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
        animated: Bool = true
    ) {
        if case let .persistent(_, existingTabID) = terminalSpotlightCoordinator.spotlight?.source, existingTabID == tabID {
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
                    owningProjectRootURL: owningProjectRootURL
                )
            },
            shortcutDefinitions: shortcutDefinitions,
            onShortcutSelected: { shortcut in
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
                            initialCommand: shortcut.command
                        )
                    }
                )
            },
            onManageShortcutsRequested: spotlightManageShortcuts,
            isTemporary: false,
            owningProjectRootURL: owningProjectRootURL,
            surfaceID: surfaceID
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
        initialCommand: String? = nil,
        pushCurrentToRestore: Bool = true
    ) {
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
            guard coordinator?.spotlight?.id == spotlightID else { return }
            if coordinator?.restoreStack.isEmpty == false {
                NotificationCenter.default.post(name: .spotlightRestoreRequested, object: nil)
            } else {
                coordinator?.dismiss()
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
                        initialCommand: command
                    )
                case .newPermanentTerminal:
                    if let project = spotlightProject(rootURL: owningProjectRootURL) {
                        project.terminalViewModel.runShortcut(shortcut, defaultDirectory: normalizedDirectoryURL)
                        requestTerminalFocusWithStabilization(for: project.terminal)
                    } else {
                        session.startIfNeeded()
                        session.sendStartupCommand(command)
                    }
                }
            },
            onManageShortcutsRequested: spotlightManageShortcuts,
            isTemporary: true,
            owningProjectRootURL: owningProjectRootURL
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
            guard let tab = terminalViewModel.tabs.first(where: { $0.id == tabID }) else { return }
            terminalViewModel.selectTab(tab)
        case let .transient(session):
            session.startIfNeeded()
        case .vibeCast:
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
        switch descriptor {
        case let .terminal(projectRootURL, tabID):
            guard let project = vibespaceView.activeVibeSpaceProjects.first(where: {
                $0.rootURL.standardizedFileURL == projectRootURL.standardizedFileURL
            }) else { return false }
            guard let tab = project.terminal.tabs.first(where: { $0.id == tabID }) else { return false }
            let accentColor = vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color ?? activeThemePalette.accentColor
            presentTerminalSpotlight(
                terminalViewModel: project.terminalViewModel,
                tabID: tab.id,
                title: tab.title.isEmpty ? project.title : tab.title,
                accentColor: accentColor,
                owningProjectRootURL: project.rootURL
            )
            return true
        case let .transient(title, accentColor, directoryURL, shellResolutionProvider, sessionConfigurator, onSplitTerminalRequested, owningProjectRootURL):
            presentTemporaryTerminalSpotlight(
                title: title,
                accentColor: accentColor,
                directoryURL: directoryURL,
                shellResolutionProvider: shellResolutionProvider,
                sessionConfigurator: sessionConfigurator,
                onSplitTerminalRequested: onSplitTerminalRequested,
                owningProjectRootURL: owningProjectRootURL,
                pushCurrentToRestore: false
            )
            return true
        case let .filePreview(target, projectPath):
            presentFilePreviewSpotlight(
                target: target,
                owningProjectRootURL: projectPath.map(URL.init(fileURLWithPath:)),
                animated: false
            )
            return true
        case let .file(tileID, fileURL):
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
            presentFileSpotlight(tileID: tileID, fileURL: fileURL)
            return true
        case .vibeCast:
            presentVibeCastSpotlight()
            return true
        case let .acp(tileID, storeID):
            guard vibespaceHydrationCoordinator.boardStore?.tile(for: tileID, includeMinimized: true)?.acpSnapshot?.id == storeID,
                  contentViewerStore.acpStore(for: storeID) != nil else { return false }
            presentACPSpotlight(tileID: tileID, storeID: storeID, animated: false)
            return true
        case let .browserPreview(snapshot, projectPath):
            dockedBrowserCoordinator.restorePreview(from: snapshot, projectPath: projectPath)
            presentBrowserSpotlight(snapshot: snapshot, projectPath: projectPath)
            return true
        case let .browser(tileID, url):
            guard vibespaceHydrationCoordinator.boardStore?.tile(for: tileID, includeMinimized: true) != nil else { return false }
            presentBrowserSpotlight(tileID: tileID, url: url)
            return true
        }
    }

    func setTerminalSpotlight(_ nextSpotlight: TerminalSpotlightState?, animated: Bool = true) {
        terminalSpotlightCoordinator.setSpotlight(
            nextSpotlight,
            animated: animated,
            onFocusSpotlight: focusSpotlightTerminal
        )
    }

    func presentACPSpotlight(
        tileID: UUID,
        storeID: UUID,
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
            owningProjectRootURL: owningProjectRootURL
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }
}
