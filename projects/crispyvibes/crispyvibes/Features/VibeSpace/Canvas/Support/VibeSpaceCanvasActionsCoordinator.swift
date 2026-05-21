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
    private let vibespaceCanvasFileOpenUseCase = VibeSpaceCanvasFileOpenUseCase()
    private let vibespaceProjectFocusUseCase = VibeSpaceProjectFocusUseCase()

    var dockPreviewBridge: DockPreviewBridge?
    var canvasModeProvider: (() -> VibeSpaceCanvasMode)?
    var operationMetricsStore: OperationMetricsStore?

    init(
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore,
        vibespaceManagement: VibeSpaceManagementService,
        vibespaceHydrationCoordinator: VibeSpaceHydrationCoordinator,
        vibespaceInteraction: VibeSpaceInteractionService,
        splitViewStore: SplitViewStore,
        contentViewerStore: ContentViewerStore,
        layoutPersistence: LayoutPersistenceService
    ) {
        self.appShellStore = appShellStore
        self.vibespaceCatalogStore = vibespaceCatalogStore
        self.vibespaceManagement = vibespaceManagement
        self.vibespaceHydrationCoordinator = vibespaceHydrationCoordinator
        self.vibespaceInteraction = vibespaceInteraction
        self.splitViewStore = splitViewStore
        self.contentViewerStore = contentViewerStore
        self.layoutPersistence = layoutPersistence
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
            vibespaceHydrationCoordinator.clearStartupExecutionFlag(
                forProjectPath: removedProjectPath,
                in: vibespaceID
            )
        }
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
