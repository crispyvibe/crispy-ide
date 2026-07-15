import AppKit
import Foundation
import SwiftUI
import os.signpost

@MainActor
final class VibeSpaceCanvasActionsCoordinator {
    private let appShellStore: AppShellStore
    private let vibespaceCatalogStore: VibeSpaceCatalogStore
    private let vibespaceManagement: VibeSpaceManagementService
    private let vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator
    private let vibespaceInteraction: VibeSpaceInteractionService
    private let splitViewStore: SplitViewStore
    private let contentViewerStore: ContentViewerStore
    private let layoutPersistence: LayoutPersistenceService
    private let vibespaceCanvasFileOpenUseCase: VibeSpaceCanvasFileOpenUseCase
    private let vibespaceProjectFocusUseCase = VibeSpaceProjectFocusUseCase()

    var dockPreviewBridge: DockPreviewBridge?
    var canvasModeProvider: (() -> VibeSpaceCanvasMode)?
    var operationMetricsStore: OperationMetricsStore?
    /// F012-R18 / F021-R10: docked browser coordinator hook used to enumerate
    /// and tear down all browsers belonging to a project being removed or
    /// parked. Wired by `AppContainer` after construction.
    weak var dockedBrowserCoordinator: DockedBrowserCoordinator?

    /// Floating agent-conversation preview used when surfacing a conversation
    /// thread in board mode. Wired by `AppContainer` after construction.
    weak var dockedAgentPreviewCoordinator: DockedAgentPreviewCoordinator?

    init(
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore,
        vibespaceManagement: VibeSpaceManagementService,
        vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator,
        vibespaceInteraction: VibeSpaceInteractionService,
        splitViewStore: SplitViewStore,
        contentViewerStore: ContentViewerStore,
        layoutPersistence: LayoutPersistenceService,
        commentLifecycle: CommentLifecycleCoordinator? = nil
    ) {
        self.appShellStore = appShellStore
        self.vibespaceCatalogStore = vibespaceCatalogStore
        self.vibespaceManagement = vibespaceManagement
        self.vibespaceHydrationCoordinator = vibespaceHydrationCoordinator
        self.vibespaceInteraction = vibespaceInteraction
        self.splitViewStore = splitViewStore
        self.contentViewerStore = contentViewerStore
        self.layoutPersistence = layoutPersistence
        self.vibespaceCanvasFileOpenUseCase = VibeSpaceCanvasFileOpenUseCase(commentLifecycle: commentLifecycle)
    }

    func toggleVibeCast() { present(.vibeCast) }

    func toggleTodos() { present(.todos) }

    func openVibeLanes() { present(.vibeLanes) }

    /// Single entry point for surfacing content in a vibespace. Consults
    /// `ContentSurfacePolicy` for the active canvas mode, then routes to the
    /// correct surface — so callers never branch on canvas mode or force a
    /// layout switch themselves. New content types and entry points should go
    /// through here (or, for flows with bespoke creation like terminal/file,
    /// at least consult `ContentSurfacePolicy`) rather than re-deriving the
    /// decision per call site.
    func present(_ content: PresentableContent) {
        guard let vibespaceID = activeVibeSpaceID else { return }
        prepareForVibeSpacePresentation()

        switch ContentSurfacePolicy.surface(for: content.kind, mode: selectedCanvasMode) {
        case .detailTab:
            layoutPersistence.setCanvasMode(.detailed, for: vibespaceID)
            presentInDetailTab(content, vibespaceID: vibespaceID)
        case .boardTile:
            presentOnBoard(content, vibespaceID: vibespaceID)
        case .dockedPreview:
            presentAsDockedPreview(content, vibespaceID: vibespaceID)
        case .spotlight:
            // No PresentableContent case resolves to spotlight today (terminal
            // owns that dispatch).
            fallbackToDetailTab(content, vibespaceID: vibespaceID,
                                "PresentableContent \(content.kind) unexpectedly routed to .spotlight")
        }
    }

    /// Defensive fallback for a (content, surface) combination the policy does
    /// not produce today. Asserts in debug so a future policy change that
    /// breaks the invariant is caught loudly, while never dropping the action
    /// in production.
    private func fallbackToDetailTab(_ content: PresentableContent, vibespaceID: UUID, _ reason: @autoclosure () -> String) {
        assertionFailure(reason())
        layoutPersistence.setCanvasMode(.detailed, for: vibespaceID)
        presentInDetailTab(content, vibespaceID: vibespaceID)
    }

    private func presentInDetailTab(_ content: PresentableContent, vibespaceID: UUID) {
        switch content {
        case let .agentChat(project, preferredAgentID):
            _ = contentViewerStore.openACPPane(
                focusedProject: project,
                preferredAgentID: preferredAgentID,
                vibespaceID: vibespaceID
            )
        case let .conversationThread(thread):
            _ = contentViewerStore.openACPPaneForThread(
                agentId: thread.agentId,
                projectPath: thread.projectPath,
                threadId: thread.id,
                projects: activeVibeSpace?.projects ?? [],
                vibespaceID: vibespaceID
            )
        case .todos:
            if !splitViewStore.activateExistingTab(matching: { $0.kind == .todos }) {
                contentViewerStore.openTodos()
            }
        case .vibeLanes:
            if !splitViewStore.activateExistingTab(matching: { $0.kind == .vibeLanes }) {
                contentViewerStore.openVibeLanes()
            }
        case .vibeCast:
            if !splitViewStore.activateExistingTab(matching: { $0.kind == .vibeCast }) {
                contentViewerStore.openVibeCast()
            }
        }
    }

    private func presentOnBoard(_ content: PresentableContent, vibespaceID: UUID) {
        switch content {
        case let .agentChat(project, _):
            // Scope the board's new agent to the requested project (no-op if
            // it's already focused), then add a tile — staying in board view.
            if let project, activeVibeSpace?.focusedProjectID != project.id {
                focusProject(project)
            }
            NotificationCenter.default.post(name: .addACPTileToBoard, object: nil)
        case .conversationThread, .todos, .vibeLanes, .vibeCast:
            // Policy never routes these to the board today.
            fallbackToDetailTab(content, vibespaceID: vibespaceID,
                                "PresentableContent \(content.kind) unexpectedly routed to .boardTile")
        }
    }

    private func presentAsDockedPreview(_ content: PresentableContent, vibespaceID: UUID) {
        switch content {
        case let .conversationThread(thread):
            guard let dockedAgentPreviewCoordinator else {
                // Should be wired by AppContainer; assert on misconfiguration
                // but never drop the action.
                fallbackToDetailTab(content, vibespaceID: vibespaceID,
                                    "dockedAgentPreviewCoordinator not wired")
                return
            }
            let project = activeVibeSpace?.focusedProject ?? activeVibeSpace?.projects.first
            dockedAgentPreviewCoordinator.showPreview(
                threadId: thread.id,
                title: thread.title,
                agentId: thread.agentId,
                projectIdentifier: project?.projectIdentifier,
                vibespaceID: vibespaceID
            )
        case .agentChat, .todos, .vibeLanes, .vibeCast:
            // Policy never routes these to a docked preview today.
            fallbackToDetailTab(content, vibespaceID: vibespaceID,
                                "PresentableContent \(content.kind) unexpectedly routed to .dockedPreview")
        }
    }

    func wireProjectFileOpenHandler(_ project: AnyProjectSession) {
        vibespaceCanvasFileOpenUseCase.wireProjectFileOpenHandler(
            project,
            contentViewerStore: contentViewerStore,
            splitViewStore: splitViewStore,
            appShellStore: appShellStore,
            vibespaceCatalogStore: vibespaceCatalogStore,
            dockPreviewBridge: dockPreviewBridge,
            canvasModeProvider: canvasModeProvider
        )
    }

    func openSourceControlDiff(
        repositoryRootURL: URL,
        item: VibeSpaceSourceControlStatusItem
    ) {
        // A git diff has no board surface. In board mode, show the file in the
        // floating docked preview (consistent with every other file open on the
        // board) instead of yanking the layout to detailed; the diff view itself
        // is a detailed-view feature. Decision comes from the central policy.
        if ContentSurfacePolicy.surface(for: .file, mode: selectedCanvasMode) == .dockedPreview {
            dockPreviewBridge?.requestPreview(for: item.url.standardizedFileURL)
            return
        }
        vibespaceCanvasFileOpenUseCase.openSourceControlDiff(
            repositoryRootURL: repositoryRootURL,
            item: item,
            focusedProject: activeVibeSpace?.focusedProject,
            projects: activeVibeSpace?.projects ?? [],
            contentViewerStore: contentViewerStore,
            prepareVibeSpacePresentation: { [weak self] in
                self?.openDetailedVibeSpaceView()
            },
            wireProjectFileOpenHandler: { [weak self] project in
                self?.wireProjectFileOpenHandler(project)
            }
        )
    }

    func removeProject(id: UUID) {
        var vibespaceID: UUID?
        var removedProjectPath: String?
        mutateActiveVibeSpace { vibespace, resolvedVibeSpaceID in
            vibespaceID = resolvedVibeSpaceID
            removedProjectPath = vibespace.projects.first(where: { $0.id == id })?.rootURL.path
            vibespace.removeProject(id: id)
        }
        guard let vibespaceID else { return }
        if let removedProjectPath {
            // F012-R18: tear down all browsers owned by the removed project
            // AFTER state mutation. Browser close runs notification handlers
            // that may activate fallback tabs in the content viewer; those
            // activations post `.contentViewerTabActivated`, which the
            // click-to-select listener consumes. By mutating state first,
            // the listener's `projects.first(where:)` returns nil for the
            // removed path and short-circuits — no stray focus changes
            // re-enter while removal is mid-flight.
            dockedBrowserCoordinator?.closeBrowsers(forProjectPath: removedProjectPath)
            vibespaceHydrationCoordinator.clearStartupExecutionFlag(
                forProjectPath: removedProjectPath,
                in: vibespaceID
            )
        }
        persistVibeSpaceCatalog()
    }

    /// F021-R10 + F012-R18: park the project with the given session ID.
    ///
    /// Order of operations (matters — see "Re-entrancy guard" below):
    /// 1. Capture browser session entries owned by the project and persist them
    ///    into the project's `ProjectConfigFile.browserSessionEntries`.
    /// 2. Mark `isParked = true` in the project's config file.
    /// 3. Mutate live vibespace state via `vibespace.parkProject(id:)` (which
    ///    shuts down the live `ProjectSession` and moves the path to
    ///    `parkedProjectPaths`). After this, the project is no longer in
    ///    `state.projects`.
    /// 4. Dispatch close requests for the browsers via the standard
    ///    `.closeBrowserRequested` notification pipeline.
    /// 5. Persist the vibespace catalog so `parkedProjectPaths` is durable.
    ///
    /// **Re-entrancy guard:** browser-close runs notification handlers
    /// synchronously, which can activate fallback tabs in the content viewer.
    /// Tab activation posts `.contentViewerTabActivated`, which the
    /// click-to-select listener consumes and may call `focusProject` on the
    /// activated tab's owning project. If state mutation happened *after*
    /// browser close (the previous order), the parked project would still be
    /// in `state.projects` during the fallback-tab activation, and a stray
    /// focus change could re-enter while parking was mid-flight. By mutating
    /// state first, the listener's `projects.first(where:)` returns nil for
    /// the parked path during browser close — the listener short-circuits
    /// and parking completes deterministically.
    func parkProject(id: UUID) {
        var vibespaceID: UUID?
        var parkedProjectPath: String?

        // Resolve project path BEFORE mutating state.
        if let vibespace = activeVibeSpace {
            vibespaceID = activeVibeSpaceID
            parkedProjectPath = vibespace.projects.first(where: { $0.id == id })?.projectIdentifier
        }
        guard let vibespaceID, let parkedProjectPath else { return }

        // 1. Capture browser sessions while VMs are still resolvable.
        let browserEntries = dockedBrowserCoordinator?
            .snapshotBrowserSessions(forProjectPath: parkedProjectPath) ?? []
        if !browserEntries.isEmpty {
            vibespaceManagement.saveBrowserSessions(
                browserEntries,
                forProject: parkedProjectPath,
                in: vibespaceID
            )
        }

        // 2. Mark parked in the per-project config.
        vibespaceManagement.setProjectParked(true, forProject: parkedProjectPath, in: vibespaceID)

        // 3. Mutate live state (shuts down ProjectSession including folder
        // explorer per F021-S25; removes from projects[]; appends to
        // parkedProjectPaths). Do this BEFORE closing browsers so that any
        // fallback-tab activation triggered by browser close cannot re-focus
        // the now-parked project (the click-to-select listener will see no
        // live project for that path and short-circuit).
        mutateActiveVibeSpace { vibespace, _ in
            vibespace.parkProject(id: id)
        }

        // 4. Close all browsers for this project. Fallback-tab activations
        // emitted during this loop are safe — the project is already gone
        // from state.projects.
        dockedBrowserCoordinator?.closeBrowsers(forProjectPath: parkedProjectPath)

        // 5. Clear hydration-execution flag so re-hydrating after unpark
        // behaves like a fresh load.
        vibespaceHydrationCoordinator.clearStartupExecutionFlag(
            forProjectPath: parkedProjectPath,
            in: vibespaceID
        )

        persistVibeSpaceCatalog()
    }

    /// F021-R11: activate (unpark) the project at the given path.
    ///
    /// Recreates the live `ProjectSession`, restores persisted browser sessions
    /// for the project, clears the parked flag, and persists the catalog.
    @discardableResult
    func unparkProject(path: String) -> AnyProjectSession? {
        guard let vibespaceID = activeVibeSpaceID else { return nil }

        var unparked: AnyProjectSession?
        mutateActiveVibeSpace { vibespace, _ in
            unparked = vibespace.unparkProject(path: path)
        }
        guard let unparked else { return nil }

        // Clear parked flag in per-project config.
        vibespaceManagement.setProjectParked(false, forProject: unparked.projectIdentifier, in: vibespaceID)

        // Restore persisted browser sessions for this project (F012-R20 / F021-R11).
        let entries = vibespaceManagement.loadBrowserSessions(
            forProject: unparked.projectIdentifier,
            in: vibespaceID
        )
        for entry in entries {
            if let pinnedTileID = entry.pinnedTileID {
                // Board tile browser — restore via tile factory if a tile slot exists.
                // Note: actual board-tile reconstruction happens via the board
                // hydration flow; here we ensure the VM is ready when the tile
                // hydrates.
                dockedBrowserCoordinator?.restoreTile(id: pinnedTileID, snapshot: entry.snapshot)
            } else {
                let url = entry.snapshot.urlString.flatMap(URL.init(string:))
                let reference = BrowserTabReference(
                    browserID: entry.browserID,
                    url: url,
                    projectPath: unparked.projectIdentifier,
                    linkedTileID: nil
                )
                dockedBrowserCoordinator?.restoreDetailedBrowser(
                    reference: reference,
                    snapshot: entry.snapshot
                )
                // Re-open as a content-viewer tab so the user sees the browser
                // in detailed mode (R19). Active vibespace's content viewer is
                // the natural surface; fall back silently if not in detailed
                // mode — restoreDetailedBrowser keeps the VM ready until the
                // surface materializes.
                if canvasModeProvider?() == .detailed, let url {
                    contentViewerStore.openWebPage(
                        url: url,
                        projectPath: unparked.projectIdentifier,
                        browserID: entry.browserID
                    )
                }
            }
        }

        // Activate the new session and refocus.
        vibespaceHydrationCoordinator.activateProjectForPresentation(
            unparked,
            vibespaceID: vibespaceID,
            includeVibeSpaceDefault: true,
            requestTerminalFocus: false,
            transitionID: UUID().uuidString
        )

        persistVibeSpaceCatalog()
        return unparked
    }

    /// F021-R19: remove a parked project (drop from `parkedProjectPaths` and
    /// clear its associated per-project state) without activating it. Mirrors
    /// `removeProject(id:)` for the parked collection; no live session exists,
    /// so there are no terminals/browsers to tear down.
    func removeParkedProject(path: String) {
        guard let vibespaceID = activeVibeSpaceID else { return }
        let normalized = VibeSpaceState.normalizedPath(from: path)
        mutateActiveVibeSpace { vibespace, _ in
            vibespace.removeParkedProject(path: normalized)
        }
        vibespaceHydrationCoordinator.clearStartupExecutionFlag(
            forProjectPath: normalized,
            in: vibespaceID
        )
        persistVibeSpaceCatalog()
    }

    func colorTag(for project: AnyProjectSession) -> ProjectColorTag? {
        activeVibeSpace?.colorTag(for: project)
    }

    func setColorTag(_ tag: ProjectColorTag?, for project: AnyProjectSession) {
        mutateActiveVibeSpace { vibespace, _ in
            vibespace.setColorTag(tag, for: project.id)
        }
        persistVibeSpaceCatalog()
    }

    /// Focus a project by its identifier (e.g. from the "Make Current Project"
    /// context-menu command). No-op if the id doesn't resolve to a live project
    /// in the active vibespace.
    func focusProject(id: UUID, forceTerminalFocus: Bool = false) {
        guard let project = activeVibeSpace?.projects.first(where: { $0.id == id }) else { return }
        focusProject(project, forceTerminalFocus: forceTerminalFocus)
    }

    func focusProject(_ project: AnyProjectSession, forceTerminalFocus: Bool = false) {
        let startTime = Date()
        guard let vibespace = activeVibeSpace,
              let vibespaceID = activeVibeSpaceID else { return }
        prepareForVibeSpacePresentation()
        let shouldFocusTerminalOnSwitch = forceTerminalFocus || vibespace
            .startupSettings
            .normalized()
            .focusTerminalOnProjectSwitch
        let previousFocusedID = vibespace.focusedProjectID
        let transitionID = UUID().uuidString
        let signpostID = OSSignpostID(log: AppDiagnostics.vibespaceSignpostLog)

        os_signpost(
            .begin,
            log: AppDiagnostics.vibespaceSignpostLog,
            name: "ProjectFocusSwitch",
            signpostID: signpostID,
            "transition=%{public}@ vibespace=%{public}@ from=%{public}@ to=%{public}@",
            transitionID,
            vibespaceID.uuidString,
            previousFocusedID?.uuidString ?? "none",
            project.id.uuidString
        )

        AppDiagnostics.record(
            category: .vibespaceLifecycle,
            level: .notice,
            event: "project_focus_switch",
            metadata: [
                "transition": transitionID,
                "vibespace": vibespaceID.uuidString,
                "from": previousFocusedID?.uuidString ?? "none",
                "to": project.id.uuidString,
                "project_path": AppDiagnostics.pathToken(project.rootURL.path)
            ]
        )

        mutateActiveVibeSpace { vibespace, _ in
            vibespace.focusedProjectID = project.id
        }
        vibespaceHydrationCoordinator.activateProjectForPresentation(
            project,
            vibespaceID: vibespaceID,
            includeVibeSpaceDefault: true,
            requestTerminalFocus: shouldFocusTerminalOnSwitch,
            transitionID: transitionID
        )
        persistVibeSpaceCatalog()

        os_signpost(
            .end,
            log: AppDiagnostics.vibespaceSignpostLog,
            name: "ProjectFocusSwitch",
            signpostID: signpostID,
            "transition=%{public}@",
            transitionID
        )
        operationMetricsStore?.recordOperation(name: "project.focus", projectContext: project.rootURL.path, startTime: startTime)
    }

    func removeUnavailableProject(from vibespaceID: UUID, missingPath: String) {
        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.removeUnresolvedProject(path: missingPath)
        }
        vibespaceHydrationCoordinator.clearStartupExecutionFlag(forProjectPath: missingPath, in: vibespaceID)
        persistVibeSpaceCatalog()
    }

    func relinkUnavailableProject(in vibespaceID: UUID, missingPath: String) {
        guard vibespaceState(for: vibespaceID) != nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Relink Missing Folder"

        let suggestedDirectory = URL(fileURLWithPath: missingPath)
            .deletingLastPathComponent()
            .standardizedFileURL
        if VibeSpaceState.isExistingDirectory(path: suggestedDirectory.path) {
            panel.directoryURL = suggestedDirectory
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        var focusedProject: AnyProjectSession?
        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
            focusedProject = vibespace.relinkUnresolvedProject(path: missingPath, to: selectedURL)
        }

        if activeVibeSpaceID == vibespaceID,
           let focused = focusedProject {
            vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
                vibespace.focusedProjectID = focused.id
            }
            vibespaceHydrationCoordinator.activateProjectForPresentation(
                focused,
                vibespaceID: vibespaceID,
                includeVibeSpaceDefault: true,
                requestTerminalFocus: false,
                transitionID: "vibespace-relink-focused"
            )
        }

        persistVibeSpaceCatalog()
    }

    func shortcutProjectIndex(from notification: Notification) -> Int? {
        vibespaceProjectFocusUseCase.shortcutProjectIndex(from: notification)
    }

    func focusProject(numbered index: Int) {
        guard let vibespace = activeVibeSpace else { return }

        switch vibespaceProjectFocusUseCase.shortcutFocusCommand(index: index, in: vibespace) {
        case let .focusProject(project):
            focusProject(project, forceTerminalFocus: true)
        case let .cycleTerminal(project, tabID):
            setActiveTerminalTab(tabID, for: project, requestFocus: true)
        case .noOp:
            break
        }
    }

    func focusAdjacentProject(offset: Int) {
        let projects = activeVibeSpace?.projects ?? []
        guard let project = vibespaceProjectFocusUseCase.adjacentProject(
            offset: offset,
            focusedProjectID: activeVibeSpace?.focusedProjectID,
            projects: projects
        ) else { return }
        focusProject(project, forceTerminalFocus: true)
    }

    func focusAdjacentTerminal(inFocusedProjectBy offset: Int) {
        switch vibespaceProjectFocusUseCase.adjacentTerminalCommand(
            offset: offset,
            focusedProject: activeVibeSpace?.focusedProject,
            projects: activeVibeSpace?.projects ?? []
        ) {
        case let .focusProject(project):
            focusProject(project, forceTerminalFocus: true)
        case let .selectTab(project, tabID):
            setActiveTerminalTab(tabID, for: project, requestFocus: true)
        case nil:
            break
        }
    }

    func focusAdjacentTerminalInTerminalOnly(by offset: Int) {
        guard offset != 0 else { return }
        guard selectedCanvasMode == .terminalOnly else { return }
        // Terminal Board mode uses independent tiles instead of per-project terminal tabs.
        // Focus traversal in this mode is controlled by tile interaction.
    }

    func setActiveTerminalTab(_ tabID: UUID, for project: AnyProjectSession, requestFocus: Bool) {
        guard activeVibeSpace?.projects.contains(where: { $0.id == project.id }) == true else { return }
        guard let tab = project.terminal.tabs.first(where: { $0.id == tabID }) else { return }

        if activeVibeSpace?.focusedProjectID != project.id {
            focusProject(project, forceTerminalFocus: false)
        }

        project.terminal.selectTab(tab)
        guard requestFocus else { return }
        vibespaceHydrationCoordinator.requestTerminalFocusWithStabilization(for: project.terminal)
    }

    func openDetailedVibeSpaceView() {
        guard activeVibeSpaceID != nil else { return }
        let startTime = Date()
        prepareForVibeSpacePresentation()
        layoutPersistence.setCanvasMode(.detailed, for: activeVibeSpaceID)
        operationMetricsStore?.recordOperation(name: "canvas.modeSwitch", startTime: startTime)
    }

    func openTerminalOnlyVibeSpaceView() {
        guard activeVibeSpaceID != nil else { return }
        let startTime = Date()
        prepareForVibeSpacePresentation()
        layoutPersistence.setCanvasMode(.terminalOnly, for: activeVibeSpaceID)
        operationMetricsStore?.recordOperation(name: "canvas.modeSwitch", startTime: startTime)
    }

    /// F044-R80: add projects to the active vibespace via the agent CLI,
    /// mirroring the UI's "Add Project" flow but with no NSOpenPanel and no
    /// ContentView dependency. Returns the focused project (last added).
    @discardableResult
    func addProjectsViaCLI(urls: [URL]) -> AnyProjectSession? {
        var focused: AnyProjectSession?
        mutateActiveVibeSpace { vibespace, _ in
            focused = vibespace.addProjects(from: urls)
        }
        persistVibeSpaceCatalog()
        if let focused {
            // F021-S03: new project becomes focused with terminals ensured.
            // Reuse the existing focusProject path so hydration + signposting
            // stay consistent with UI-driven flows.
            focusProject(focused)
        }
        return focused
    }

    private var activeVibeSpaceID: UUID? {
        appShellStore.activeVibeSpaceID
    }

    private var activeVibeSpace: VibeSpaceState? {
        vibespaceCatalogStore.activeVibeSpaceValue(for: activeVibeSpaceID) { vibespace, _ in vibespace }
    }

    private var selectedCanvasMode: VibeSpaceCanvasMode {
        layoutPersistence.canvasMode(for: activeVibeSpaceID)
    }

    private func vibespaceState(for vibespaceID: UUID) -> VibeSpaceState? {
        vibespaceCatalogStore.vibespaceValue(for: vibespaceID) { $0 }
    }

    private func mutateActiveVibeSpace(_ update: (inout VibeSpaceState, UUID) -> Void) {
        vibespaceCatalogStore.mutateActiveVibeSpace(for: activeVibeSpaceID, update)
    }

    private func prepareForVibeSpacePresentation() {
        appShellStore.dismissHome()
    }

    private func presentTerminalTargetVibeSpace(
        vibespaceID: UUID,
        project: AnyProjectSession,
        requestTerminalFocus: Bool
    ) {
        appShellStore.showVibeSpace(vibespaceID)
        prepareForVibeSpacePresentation()
        vibespaceCatalogStore.mutateVibeSpace(id: vibespaceID) { vibespace in
            vibespace.focusedProjectID = project.id
        }
        vibespaceHydrationCoordinator.activateProjectForPresentation(
            project,
            vibespaceID: vibespaceID,
            includeVibeSpaceDefault: true,
            requestTerminalFocus: requestTerminalFocus,
            transitionID: "terminal-file-target"
        )
        persistVibeSpaceCatalog()
    }

    private func persistVibeSpaceCatalog() {
        for vibespace in vibespaceCatalogStore.vibespaces.prefix(1) {
            vibespaceManagement.persistVibeSpaceState(vibespace)
        }
    }
}

