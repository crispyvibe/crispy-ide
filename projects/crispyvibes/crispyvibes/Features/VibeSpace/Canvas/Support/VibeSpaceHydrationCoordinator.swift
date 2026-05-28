import AppKit
import Foundation

@MainActor
final class VibeSpaceHydrationCoordinator: ObservableObject {
    let appShellStore: AppShellStore
    let vibespaceCatalogStore: VibeSpaceCatalogStore
    let layoutPersistence: LayoutPersistenceService
    let splitViewStore: SplitViewStore
    let contentViewerStore: ContentViewerStore
    let vibespaceHydrationUseCase = VibeSpaceHydrationUseCase()
    let vibespaceCanvasFileOpenUseCase: VibeSpaceCanvasFileOpenUseCase

    private var vibespaceHydrationTask: Task<Void, Never>?
    private var editorSessionSaveWorkItem: DispatchWorkItem?
    /// VibeSpace ID most recently hydrated via `scheduleVibeSpaceTerminalHydration`.
    /// Used to suppress the redundant restore that `handleActiveVibeSpaceChange` would
    /// otherwise perform when SwiftUI's `onChange(of: activeVibeSpaceID)` fires after
    /// an explicit hydration for the same vibespace.
    private var lastHydratedVibeSpaceID: UUID?
    var startupExecutedProjectPathsByVibeSpace: [UUID: Set<String>] = [:]

    var operationMetricsStore: OperationMetricsStore?
    /// Owned at the service layer (created in `AppContainer.makeContentViewDependencies`)
    /// so the board store is reachable independent of SwiftUI view lifecycle. This is
    /// required for the Agent CLI to manipulate board tiles before any view has
    /// rendered (e.g., `crispy browser open` arriving while the user is in
    /// `.detailed` canvas mode where the board view is not in the hierarchy).
    var boardStore: VibeSpaceTerminalBoardStore?
    var dockPreviewBridge: DockPreviewBridge?
    var canvasModeProvider: (() -> VibeSpaceCanvasMode)?
    weak var dockedBrowserCoordinator: DockedBrowserCoordinator?

    init(
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore,
        layoutPersistence: LayoutPersistenceService,
        splitViewStore: SplitViewStore,
        contentViewerStore: ContentViewerStore,
        commentLifecycle: CommentLifecycleCoordinator? = nil
    ) {
        self.appShellStore = appShellStore
        self.vibespaceCatalogStore = vibespaceCatalogStore
        self.layoutPersistence = layoutPersistence
        self.splitViewStore = splitViewStore
        self.contentViewerStore = contentViewerStore
        self.vibespaceCanvasFileOpenUseCase = VibeSpaceCanvasFileOpenUseCase(commentLifecycle: commentLifecycle)
    }

    func cancelVibeSpaceHydration() {
        vibespaceHydrationTask?.cancel()
        vibespaceHydrationTask = nil
    }

    func scheduleVibeSpaceTerminalHydration(for vibespaceID: UUID) {
        cancelVibeSpaceHydration()
        guard let vibespace = vibespaceState(for: vibespaceID) else { return }

        let preparation = vibespaceHydrationUseCase.prepareHydration(
            for: vibespaceID,
            vibespace: vibespace,
            layoutPersistence: layoutPersistence
        )
        primeRemoteProjectsForRestore(in: vibespace)
        restoreEditorSessionState(preparation.editorSessionState)
        restoreBrowserTilesFromLayout(for: vibespaceID)
        lastHydratedVibeSpaceID = vibespaceID
        vibespaceHydrationTask = Task { [weak self] in
            await self?.hydrateVibeSpaceTerminals(for: vibespaceID, targets: preparation.targets)
        }
    }

    func scheduleEditorSessionStateSave() {
        editorSessionSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistEditorSessionStateNow()
        }
        editorSessionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func persistEditorSessionStateNow() {
        editorSessionSaveWorkItem?.cancel()
        guard let vibespaceID = appShellStore.activeVibeSpaceID else { return }
        let state = splitViewStore.snapshot(viewerScope: contentViewerStore.viewerScope)
        layoutPersistence.saveEditorSessionState(state, for: vibespaceID)
    }

    func handleActiveVibeSpaceChange(from oldID: UUID?, to newID: UUID?) {
        guard oldID != newID else { return }
        operationMetricsStore?.beginTrace(name: "vibespace.open", projectContext: newID?.uuidString)

        // Save old vibespace state only if splitViewStore still reflects it.
        // If `scheduleVibeSpaceTerminalHydration(newID)` already ran (from the call site that
        // changed activeVibeSpaceID), splitViewStore now holds newID's state — saving it as
        // oldID would corrupt oldID's persisted state. The explicit hydration path is
        // expected to have saved oldID separately (via persistEditorSessionStateNow or the
        // debounced save observer) before switching.
        if let oldID, lastHydratedVibeSpaceID != newID {
            let state = splitViewStore.snapshot(viewerScope: contentViewerStore.viewerScope)
            layoutPersistence.saveEditorSessionState(state, for: oldID)
        }

        // If newID was already hydrated synchronously (e.g. via loadCatalogFromConfig →
        // persistAndHydrateVibeSpace → scheduleVibeSpaceTerminalHydration) before SwiftUI's
        // onChange fired, skip the duplicate teardown + restore. A second restore here would
        // tear down the browser tiles and ACP stores that were just rebuilt, and would also
        // race the buffer observation chain in MarkdownViewModel (the cause of F039-related
        // empty-content bugs when reopening the app in terminal-only mode).
        guard lastHydratedVibeSpaceID != newID else {
            operationMetricsStore?.endTrace()
            return
        }

        dockedBrowserCoordinator?.removeAll()
        contentViewerStore.teardownStandaloneACPStores()
        // Update board store's vibespaceID from the service layer so it works even
        // when the board view is not in the SwiftUI hierarchy (e.g., user is in
        // .detailed canvas mode). The view's resyncBoard(for:) will be a no-op when
        // the IDs already match.
        boardStore?.updateVibeSpaceID(newID)
        if let newID, let state = layoutPersistence.loadEditorSessionState(for: newID) {
            restoreEditorSessionState(state)
        } else {
            splitViewStore.reset()
            contentViewerStore.viewerScope = .allProjects
        }

        if let newID {
            lastHydratedVibeSpaceID = newID
        } else {
            lastHydratedVibeSpaceID = nil
        }

        operationMetricsStore?.endTrace()
    }

    func refreshTerminalShellResolutionContexts(for vibespaceID: UUID) {
        guard let projects = vibespaceCatalogStore.vibespaceValue(for: vibespaceID, { $0.projects }) else { return }
        for project in projects {
            applyTerminalShellResolutionContext(to: project, vibespaceID: vibespaceID)
        }
    }

    func applyTerminalShellResolutionContext(
        to project: AnyProjectSession,
        vibespaceID: UUID
    ) {
        guard let vibespace = vibespaceState(for: vibespaceID) else {
            project.terminal.updateShellResolutionContext(
                TerminalShellResolutionContext(appDefault: appDefaultTerminalShell())
            )
            return
        }

        project.terminal.updateShellResolutionContext(
            TerminalShellResolutionContext(
                vibespaceDefault: vibespace.defaultTerminalShell,
                appDefault: appDefaultTerminalShell()
            )
        )
    }

    func requestTerminalFocusWithStabilization(for terminal: AnyTerminalProvider) {
        terminal.focusActiveTerminal()
    }

    func markStartupExecuted(forProjectPath projectPath: String, in vibespaceID: UUID) {
        var executedPaths = startupExecutedProjectPathsByVibeSpace[vibespaceID] ?? Set<String>()
        executedPaths.insert(projectPath)
        startupExecutedProjectPathsByVibeSpace[vibespaceID] = executedPaths
    }

    func clearStartupExecutionFlag(forProjectPath projectPath: String, in vibespaceID: UUID) {
        let normalizedPath = VibeSpaceState.normalizedPath(from: projectPath)
        guard var executedPaths = startupExecutedProjectPathsByVibeSpace[vibespaceID] else { return }
        executedPaths.remove(normalizedPath)
        if executedPaths.isEmpty {
            startupExecutedProjectPathsByVibeSpace.removeValue(forKey: vibespaceID)
        } else {
            startupExecutedProjectPathsByVibeSpace[vibespaceID] = executedPaths
        }
    }

    func clearStartupExecutionFlags(for vibespaceID: UUID) {
        startupExecutedProjectPathsByVibeSpace.removeValue(forKey: vibespaceID)
    }

    func resetStartupExecutionFlags() {
        startupExecutedProjectPathsByVibeSpace.removeAll()
    }

    func activateProjectForPresentation(
        _ project: AnyProjectSession,
        vibespaceID: UUID,
        includeVibeSpaceDefault: Bool,
        requestTerminalFocus: Bool,
        transitionID: String? = nil
    ) {
        prepareProjectRuntime(
            project,
            vibespaceID: vibespaceID,
            includeVibeSpaceDefault: includeVibeSpaceDefault,
            transitionID: transitionID,
            startIfCreated: true
        )
        guard requestTerminalFocus else { return }
        requestTerminalFocusWithStabilization(for: project.terminal)
    }

    private func hydrateVibeSpaceTerminals(for vibespaceID: UUID, targets: [VibeSpaceHydrationTarget]) async {
        _ = operationMetricsStore?.beginTrace(name: "vibespace.hydration", projectContext: vibespaceID.uuidString)
        await hydrateVibeSpaceTerminalsBody(for: vibespaceID, targets: targets)
        operationMetricsStore?.endTrace()
    }

    private func hydrateVibeSpaceTerminalsBody(for vibespaceID: UUID, targets: [VibeSpaceHydrationTarget]) async {
        guard let vibespace = vibespaceState(for: vibespaceID) else { return }
        guard let focusedTarget = targets.first,
              let focused = vibespace.projects.first(where: { $0.id == focusedTarget.projectID }) else { return }

        let hydrationProjectsByID = Dictionary(uniqueKeysWithValues: vibespace.projects.map { ($0.id, $0) })

        activateProjectForPresentation(
            focused,
            vibespaceID: vibespaceID,
            includeVibeSpaceDefault: focusedTarget.includeVibeSpaceDefault,
            requestTerminalFocus: false,
            transitionID: "vibespace-hydration-focused"
        )
        await Task.yield()

        let remainingTargets = targets.dropFirst()
        guard !remainingTargets.isEmpty else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for target in remainingTargets {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    guard let project = hydrationProjectsByID[target.projectID] else { return }
                    self.prepareProjectForBackgroundHydration(
                        project,
                        vibespaceID: vibespaceID,
                        includeVibeSpaceDefault: target.includeVibeSpaceDefault
                    )
                    await Task.yield()
                }
            }
            await group.waitForAll()
        }
    }

    func prepareProjectForBackgroundHydration(
        _ project: AnyProjectSession,
        vibespaceID: UUID,
        includeVibeSpaceDefault: Bool
    ) {
        prepareProjectRuntime(
            project,
            vibespaceID: vibespaceID,
            includeVibeSpaceDefault: includeVibeSpaceDefault,
            transitionID: "vibespace-hydration-background",
            startIfCreated: false
        )
    }


    private func restoreEditorSessionState(_ state: EditorSessionState?) {
        guard let state else {
            contentViewerStore.teardownStandaloneACPStores()
            splitViewStore.reset()
            return
        }
        let startTime = Date()
        splitViewStore.restore(
            from: state,
            fileReferenceResolver: { [weak self] reference in
                guard let self else { return nil }
                if let projectIdentifier = reference.projectIdentifier {
                    guard let activeVibeSpaceID = appShellStore.activeVibeSpaceID,
                          let project = vibespaceCatalogStore.vibespaceValue(for: activeVibeSpaceID, { vibespace in
                              vibespace.projects.first(where: { $0.metadata.identifier == projectIdentifier })
                          }) else {
                        return nil
                    }
                    return SplitViewStore.RestoredFileDocument(
                        reference: FileDocumentReference(url: reference.url, projectIdentifier: projectIdentifier),
                        fileContentProvider: project.fileContent
                    )
                }
                guard FileManager.default.fileExists(atPath: reference.filePath) else { return nil }
                return SplitViewStore.RestoredFileDocument(reference: reference, fileContentProvider: nil)
            }
        )
        if let scope = state.viewerScope { contentViewerStore.viewerScope = scope }
        operationMetricsStore?.recordOperation(name: "editor.sessionRestore", startTime: startTime)
    }

    private func restoreBrowserTilesFromLayout(for vibespaceID: UUID) {
        guard let coordinator = dockedBrowserCoordinator else { return }
        let layout = layoutPersistence.terminalBoardLayout(for: vibespaceID)
        let allBrowserTiles = layout.tiles.filter(\.isBrowser) + layout.minimizedTiles.filter(\.isBrowser)
        for tile in allBrowserTiles {
            if let snapshot = tile.browserSession {
                coordinator.restoreTile(id: tile.id, snapshot: snapshot)
            } else if let url = tile.browserURL {
                _ = coordinator.viewModel(for: tile.id, url: url)
            }
        }
    }

    func vibespaceState(for vibespaceID: UUID) -> VibeSpaceState? {
        vibespaceCatalogStore.vibespaceValue(for: vibespaceID) { $0 }
    }

    func appDefaultTerminalShell() -> TerminalShellPreference? {
        AppPreferences.storedTerminalShellPreference()
    }

    deinit {
        vibespaceHydrationTask?.cancel()
        editorSessionSaveWorkItem?.cancel()
    }
}
