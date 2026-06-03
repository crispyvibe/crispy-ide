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

    func toggleVibeCast() {
        guard activeVibeSpaceID != nil else { return }
        prepareForVibeSpacePresentation()

        if !splitViewStore.activateExistingTab(matching: { $0.kind == .vibeCast }) {
            contentViewerStore.openVibeCast()
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
