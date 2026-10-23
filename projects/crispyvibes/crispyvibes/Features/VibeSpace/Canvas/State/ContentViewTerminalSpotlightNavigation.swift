import SwiftUI

extension ContentView {
    var directMainSpotlightSurfaceID: UUID? {
        selectedVibeSpaceCanvasMode == .terminalOnly
            ? VibeSpaceTerminalBoardState.primarySurfaceID
            : nil
    }

    private var spotlightHomeDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    private func makeSpotlightState(
        source: TerminalSpotlightState.Source,
        title: String,
        workingDirectoryURL: URL,
        owningProjectRootURL: URL? = nil,
        owningProjectIdentifier: String? = nil,
        surfaceID: UUID? = nil
    ) -> TerminalSpotlightState {
        TerminalSpotlightState(
            id: UUID(),
            source: source,
            title: title,
            accentColor: activeThemePalette.accentColor,
            workingDirectoryURL: workingDirectoryURL,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: owningProjectRootURL,
            owningProjectIdentifier: owningProjectIdentifier,
            surfaceID: surfaceID
        )
    }

    func resolvedFileOpenContext(
        for fileURL: URL,
        preferredProjectIdentifier: String? = nil,
        preferredProjectRootURL: URL? = nil
    ) -> (
        reference: FileDocumentReference,
        fileContentProvider: (any FileContentProviding)?,
        owningProjectRootURL: URL?
    ) {
        let normalizedURL = fileURL.standardizedFileURL
        let project = VibeSpaceProjectRoutingUseCase()
            .terminalProjectMatch(
                for: normalizedURL,
                preferredProjectIdentifier: preferredProjectIdentifier,
                preferredProjectRootURL: preferredProjectRootURL,
                candidates: vibespaceCatalogStore.allProjects()
            )?
            .project

        return (
            reference: FileDocumentReference(
                url: normalizedURL,
                projectIdentifier: project?.metadata.identifier
            ),
            fileContentProvider: project?.fileContent,
            owningProjectRootURL: project?.rootURL.standardizedFileURL
        )
    }

    var flatSpotlightItems: [SpotlightItem] {
        let terminalEntries = vibespaceSpotlightTerminalEntries()
        let terminalItemsByIdentity = terminalEntries.reduce(into: [VibeSpaceSpotlightTerminalOrderEntry: SpotlightItem]()) {
            result, entry in
            result[entry.identity] = entry.item
        }
        var items = layoutPersistence
            .vibespaceSpotlightTerminalOrder(
                liveIdentities: terminalEntries.map(\.identity),
                for: activeVibeSpaceID
            )
            .compactMap { terminalItemsByIdentity[$0] }

        if items.isEmpty {
            items = terminalEntries.map(\.item)
        }
        if let boardStore = vibespaceHydrationCoordinator.boardStore {
            let primarySurfaceID = boardStore.primarySurfaceID
            let primaryLayout = boardStore.layout(for: primarySurfaceID)
            items.append(contentsOf: boardStore.spotlightTerminalItems(
                surfaceID: primarySurfaceID,
                projects: vibespaceView.activeVibeSpaceProjects,
                includeProjectTerminals: false
            ))
            for tile in primaryLayout.tiles + primaryLayout.minimizedTiles {
                if let snapshot = tile.acpSnapshot,
                   let store = contentViewerStore.acpStore(for: snapshot.id) {
                    let accentColor = store.selectedProject(from: vibespaceView.activeVibeSpaceProjects)
                        .flatMap { vibespaceCanvasActionsCoordinator.colorTag(for: $0)?.color }
                    items.append(.acp(tileID: tile.id, storeID: snapshot.id, title: store.tabTitle, accentColor: accentColor))
                } else if let fileURL = tile.fileURL {
                    items.append(.file(tileID: tile.id, fileURL: fileURL))
                } else if let url = tile.browserURL {
                    items.append(.browser(tileID: tile.id, url: url))
                }
            }
        }
        if contentViewerStore.vibeCastStore.targetTabID != nil || !items.isEmpty {
            items.append(.vibeCast)
        }
        if !items.isEmpty {
            items.append(.vibeLanes)
        }
        return items
    }

    func spotlightState(for item: SpotlightItem) -> TerminalSpotlightState? {
        spotlightState(
            for: item,
            inheritingSurfaceID: terminalSpotlightCoordinator.spotlight?.surfaceID
        )
    }

    func spotlightState(
        for item: SpotlightItem,
        inheritingSurfaceID inheritedSurfaceID: UUID?
    ) -> TerminalSpotlightState? {
        switch item {
        case let .terminal(project, tab):
            let surfaceID = inheritedSurfaceID
            let title = tab.title.isEmpty ? project.title : tab.title
            let accentColor = vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color
            let workingDirectoryURL = tab.workingDirectory.standardizedFileURL
            let terminalViewModel = project.terminalViewModel
            return TerminalSpotlightState(
                id: UUID(),
                source: .persistent(terminalViewModel: terminalViewModel, tabID: tab.id),
                title: title,
                accentColor: accentColor,
                workingDirectoryURL: workingDirectoryURL,
                onSplitTerminalRequested: {
                    createSplitTerminal(
                        in: terminalViewModel,
                        directoryURL: workingDirectoryURL,
                        surfaceID: surfaceID,
                        owningProjectRootURL: project.rootURL,
                        owningProjectIdentifier: project.projectIdentifier
                    )
                },
                onTemporaryTerminalRequested: {
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
                                owningProjectRootURL: project.rootURL,
                                owningProjectIdentifier: project.projectIdentifier
                            )
                        },
                        owningProjectRootURL: project.rootURL,
                        owningProjectIdentifier: project.projectIdentifier
                    )
                },
                shortcutDefinitions: spotlightShortcutDefinitions(
                    for: project.rootURL,
                    projectIdentifier: project.projectIdentifier,
                    fallback: terminalViewModel.shortcutCommands
                ),
                onShortcutSelected: { shortcut in
                    if shortcut.launchBehavior == .newPermanentTerminal,
                       let surfaceID,
                       let boardStore = vibespaceHydrationCoordinator.boardStore,
                       DetachedPermanentShortcutTileLauncher.launch(
                            shortcut,
                            directoryURL: workingDirectoryURL,
                            owningProjectRootURL: project.rootURL,
                            owningProjectIdentifier: project.projectIdentifier,
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
                                        owningProjectRootURL: project.rootURL,
                                        owningProjectIdentifier: project.projectIdentifier
                                    )
                                },
                                owningProjectRootURL: project.rootURL,
                                owningProjectIdentifier: project.projectIdentifier,
                                initialCommand: shortcut.command
                            )
                        }
                    )
                },
                onManageShortcutsRequested: spotlightManageShortcuts,
                agentPresets: terminalViewModel.availablePresets,
                onAgentPresetSelected: { [weak terminalViewModel] preset, mode in
                    guard let session = terminalViewModel?.session(for: tab.id) else { return }
                    session.requestKeyboardFocus()
                    session.sendUICommand(preset.command(for: mode))
                },
                isTemporary: false,
                owningProjectRootURL: project.rootURL,
                owningProjectIdentifier: project.projectIdentifier,
                surfaceID: surfaceID,
                navigationIdentityOverride: .terminal(
                    projectScope: .projectPath(project.projectIdentifier),
                    tabID: tab.id
                )
            )
        case let .standaloneTerminal(surfaceID, tileID, terminalViewModel, tab):
            return TerminalSpotlightState(
                id: UUID(),
                source: .persistent(terminalViewModel: terminalViewModel, tabID: tab.id),
                title: tab.title.isEmpty ? AppStrings.Spotlight.terminal : tab.title,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: tab.workingDirectory,
                onSplitTerminalRequested: {
                    createSplitTerminal(
                        in: terminalViewModel,
                        directoryURL: tab.workingDirectory,
                        surfaceID: surfaceID,
                        owningProjectRootURL: nil
                    )
                },
                onTemporaryTerminalRequested: {
                    presentTemporaryTerminalSpotlight(
                        title: tab.title.isEmpty ? AppStrings.Spotlight.terminal : tab.title,
                        accentColor: activeThemePalette.accentColor,
                        directoryURL: tab.workingDirectory,
                        shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                        onSplitTerminalRequested: {
                            createSplitTerminal(
                                in: terminalViewModel,
                                directoryURL: tab.workingDirectory,
                                surfaceID: surfaceID,
                                owningProjectRootURL: nil
                            )
                        },
                        owningProjectRootURL: nil
                    )
                },
                shortcutDefinitions: spotlightShortcutDefinitions(
                    for: nil,
                    fallback: terminalViewModel.shortcutCommands
                ),
                onShortcutSelected: { shortcut in
                    if shortcut.launchBehavior == .newPermanentTerminal,
                       let boardStore = vibespaceHydrationCoordinator.boardStore,
                       DetachedPermanentShortcutTileLauncher.launch(
                            shortcut,
                            directoryURL: tab.workingDirectory,
                            owningProjectRootURL: nil,
                            surfaceID: surfaceID,
                            boardStore: boardStore
                       ) {
                        return
                    }
                    executeTerminalShortcut(
                        shortcut,
                        viewModel: terminalViewModel,
                        defaultDirectory: tab.workingDirectory,
                        onTemporaryShortcutRequested: { shortcut, directoryURL in
                            presentTemporaryTerminalSpotlight(
                                title: shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? (tab.title.isEmpty ? AppStrings.Spotlight.terminal : tab.title)
                                    : shortcut.name,
                                accentColor: activeThemePalette.accentColor,
                                directoryURL: directoryURL,
                                shellResolutionProvider: { terminalViewModel.shellResolutionProviderStore.resolve() },
                                onSplitTerminalRequested: {
                                    createSplitTerminal(
                                        in: terminalViewModel,
                                        directoryURL: directoryURL,
                                        surfaceID: surfaceID,
                                        owningProjectRootURL: nil
                                    )
                                },
                                owningProjectRootURL: nil,
                                initialCommand: shortcut.command
                            )
                        }
                    )
                },
                onManageShortcutsRequested: spotlightManageShortcuts,
                agentPresets: terminalViewModel.availablePresets,
                onAgentPresetSelected: { [weak terminalViewModel] preset, mode in
                    guard let session = terminalViewModel?.session(for: tab.id) else { return }
                    session.requestKeyboardFocus()
                    session.sendUICommand(preset.command(for: mode))
                },
                isTemporary: false,
                owningProjectRootURL: nil,
                surfaceID: surfaceID,
                navigationIdentityOverride: .terminal(projectScope: .unscoped(tileID), tabID: tab.id)
            )
        case .vibeCast:
            return TerminalSpotlightState(
                id: UUID(), source: .vibeCast, title: AppStrings.VibeCast.title,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil, onTemporaryTerminalRequested: nil,
                isTemporary: false, owningProjectRootURL: nil,
                surfaceID: inheritedSurfaceID
            )
        case .vibeLanes:
            return TerminalSpotlightState(
                id: UUID(), source: .vibeLanes, title: AppStrings.VibeLanes.title,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil, onTemporaryTerminalRequested: nil,
                isTemporary: false, owningProjectRootURL: nil,
                surfaceID: inheritedSurfaceID
            )
        case let .acp(tileID, storeID, title, accentColor):
            let selectedProject = contentViewerStore.acpStore(for: storeID)?
                .selectedProject(from: vibespaceView.activeVibeSpaceProjects)
            let owningProjectRootURL = selectedProject?.rootURL.standardizedFileURL
            return TerminalSpotlightState(
                id: UUID(), source: .acp(tileID: tileID, storeID: storeID), title: title,
                accentColor: accentColor,
                workingDirectoryURL: owningProjectRootURL ?? URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil, onTemporaryTerminalRequested: nil,
                isTemporary: false, owningProjectRootURL: owningProjectRootURL,
                owningProjectIdentifier: selectedProject?.projectIdentifier,
                surfaceID: inheritedSurfaceID
            )
        case let .file(tileID, fileURL):
            let boardStore = vibespaceHydrationCoordinator.boardStore
            let surfaceID = inheritedSurfaceID ?? boardStore?.primarySurfaceID
            let tile = surfaceID.flatMap { surfaceID in
                boardStore?.tile(for: tileID, includeMinimized: true, surfaceID: surfaceID)
            }
            let context = resolvedFileOpenContext(
                for: fileURL,
                preferredProjectIdentifier: tile?.projectIdentifier,
                preferredProjectRootURL: tile?.projectPath.map(URL.init(fileURLWithPath:))
            )
            let group = dockedFileViewerCoordinator.assignedEditorGroup(for: tileID)
                ?? dockedFileViewerCoordinator.editorGroup(
                    for: tileID, fileURL: fileURL, documentReference: context.reference,
                    fileContentProvider: context.fileContentProvider
                )
            return TerminalSpotlightState(
                id: UUID(),
                source: .file(tileID: tileID, fileURL: fileURL, group: group),
                title: fileURL.lastPathComponent,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: fileURL.deletingLastPathComponent(),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: false,
                owningProjectRootURL: context.owningProjectRootURL,
                owningProjectIdentifier: tile?.projectIdentifier,
                surfaceID: inheritedSurfaceID
            )
        case let .browser(tileID, url):
            let boardStore = vibespaceHydrationCoordinator.boardStore
            let surfaceID = inheritedSurfaceID ?? boardStore?.primarySurfaceID
            let tile = surfaceID.flatMap { surfaceID in
                boardStore?.tile(for: tileID, includeMinimized: true, surfaceID: surfaceID)
            }
            let owningProjectRootURL = tile?.projectIdentifier.flatMap { identifier in
                vibespaceView.activeVibeSpaceProjects.first(where: {
                    $0.projectIdentifier == identifier
                })?.rootURL
            } ?? tile?.projectPath.map(URL.init(fileURLWithPath:))
            return TerminalSpotlightState(
                id: UUID(),
                source: .browser(tileID: tileID, url: url),
                title: SpotlightSafeMetadata.browserLocation(url).host,
                accentColor: activeThemePalette.accentColor,
                workingDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
                onSplitTerminalRequested: nil,
                onTemporaryTerminalRequested: nil,
                isTemporary: false,
                owningProjectRootURL: owningProjectRootURL,
                owningProjectIdentifier: tile?.projectIdentifier,
                surfaceID: inheritedSurfaceID
            )
        }
    }

    private func vibespaceSpotlightTerminalEntries() -> [
        (identity: VibeSpaceSpotlightTerminalOrderEntry, item: SpotlightItem)
    ] {
        vibespaceView.activeVibeSpaceProjects.flatMap { project in
            let projectPath = project.projectIdentifier
            return project.terminal.tabs.map { tab in
                (
                    identity: VibeSpaceSpotlightTerminalOrderEntry(
                        projectPath: projectPath,
                        tabID: tab.id
                    ),
                    item: SpotlightItem.terminal(project: project, tab: tab)
                )
            }
        }
    }

    func vibespaceSpotlightTerminalIdentities() -> [VibeSpaceSpotlightTerminalOrderEntry] {
        vibespaceSpotlightTerminalEntries().map(\.identity)
    }

    func vibespaceSpotlightTerminalIdentity(
        for project: AnyProjectSession,
        tab: TerminalTab
    ) -> VibeSpaceSpotlightTerminalOrderEntry {
        VibeSpaceSpotlightTerminalOrderEntry(
            projectPath: project.projectIdentifier,
            tabID: tab.id
        )
    }

    func installSpotlightScrollMonitor() {
        terminalSpotlightCoordinator.installScrollMonitor(onSwitchSpotlight: switchSpotlight(by:))
    }

    func removeSpotlightScrollMonitor() {
        terminalSpotlightCoordinator.removeScrollMonitor()
    }

    func switchSpotlight(by offset: Int) {
        guard let spotlight = terminalSpotlightCoordinator.spotlight,
              spotlight.supportsCarouselNavigation,
              let currentIdentity = spotlight.navigationIdentity else { return }
        let items = flatSpotlightItems
        let snapshot = layoutPersistence.spotlightLayout(
            liveIDs: items.map(\.persistentID),
            for: activeVibeSpaceID
        )
        guard snapshot.positions.count > 1 else {
            terminalSpotlightCoordinator.animateSwipeOffset(
                0,
                animation: .spring(response: 0.35, dampingFraction: 0.7)
            )
            return
        }
        guard let selection = SpotlightPositionNavigationResolver.relativeSelection(
            offset: offset,
            currentIdentity: currentIdentity,
            snapshot: snapshot,
            items: items
        ) else { return }
        performSpotlightSwitch(selection)
    }

    func selectSpotlightItem(_ targetIdentity: SpotlightNavigationIdentity) {
        guard let currentIdentity = terminalSpotlightCoordinator.spotlight?.navigationIdentity else { return }
        let items = flatSpotlightItems
        let snapshot = layoutPersistence.spotlightLayout(
            liveIDs: items.map(\.persistentID),
            for: activeVibeSpaceID
        )
        guard let selection = SpotlightPositionNavigationResolver.selection(
            targetIdentity: targetIdentity,
            currentIdentity: currentIdentity,
            snapshot: snapshot,
            items: items
        ) else { return }
        performSpotlightSwitch(selection)
    }

    func performSpotlightSwitch(_ selection: SpotlightNavigationSelection) {
        let previousSpotlightID = terminalSpotlightCoordinator.spotlight?.id
        let originatingSurfaceID = terminalSpotlightCoordinator.spotlight?.surfaceID
        let transaction = selection.direction == 0
            ? nil
            : terminalSpotlightCoordinator.beginCarouselSwitch(selection)

        if let state = spotlightState(
            for: selection.item,
            inheritingSurfaceID: originatingSurfaceID
        ) {
            setTerminalSpotlight(state, animated: false)
        }

        if let transaction,
           terminalSpotlightCoordinator.spotlight?.id == previousSpotlightID {
            terminalSpotlightCoordinator.cancelCarouselSwitch(transaction)
        }
    }

    func presentVibeCastSpotlight(
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        let spotlight = makeSpotlightState(
            source: .vibeCast,
            title: AppStrings.VibeCast.title,
            workingDirectoryURL: spotlightHomeDirectoryURL,
            surfaceID: surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentVibeLanesSpotlight(
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        let spotlight = makeSpotlightState(
            source: .vibeLanes,
            title: AppStrings.VibeLanes.title,
            workingDirectoryURL: spotlightHomeDirectoryURL,
            surfaceID: surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentTodosSpotlight(
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        let spotlight = makeSpotlightState(
            source: .todos,
            title: AppStrings.Todos.title,
            workingDirectoryURL: spotlightHomeDirectoryURL,
            surfaceID: surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentFilePreviewSpotlight(
        target: TerminalFileSystemTarget,
        owningProjectRootURL: URL? = nil,
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        let normalizedTarget = TerminalFileSystemTarget(
            url: target.standardizedFileURL,
            line: target.line,
            column: target.column,
            projectIdentifier: target.projectIdentifier
        )
        let group = appContainer.makeEditorGroupStore(bufferStore: DocumentBufferStore())
        let fileContext = resolvedFileOpenContext(
            for: normalizedTarget.url,
            preferredProjectIdentifier: normalizedTarget.projectIdentifier,
            preferredProjectRootURL: owningProjectRootURL
        )
        group.openFileInTab(
            at: normalizedTarget.url,
            line: normalizedTarget.line,
            column: normalizedTarget.column,
            documentReference: fileContext.reference,
            fileContentProvider: fileContext.fileContentProvider
        )
        let spotlight = makeSpotlightState(
            source: .filePreview(target: normalizedTarget, group: group),
            title: normalizedTarget.url.lastPathComponent,
            workingDirectoryURL: normalizedTarget.url.deletingLastPathComponent(),
            owningProjectRootURL: fileContext.owningProjectRootURL ?? owningProjectRootURL,
            owningProjectIdentifier: normalizedTarget.projectIdentifier,
            surfaceID: surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentFileSpotlight(
        tileID: UUID,
        fileURL: URL,
        owningProjectRootURL: URL? = nil,
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        let boardStore = vibespaceHydrationCoordinator.boardStore
        let resolvedSurfaceID = surfaceID ?? boardStore?.primarySurfaceID
        let tile = resolvedSurfaceID.flatMap { surfaceID in
            boardStore?.tile(for: tileID, includeMinimized: true, surfaceID: surfaceID)
        }
        let fileContext = resolvedFileOpenContext(
            for: fileURL,
            preferredProjectIdentifier: tile?.projectIdentifier,
            preferredProjectRootURL: tile?.projectPath.map(URL.init(fileURLWithPath:))
                ?? owningProjectRootURL
        )
        let group = dockedFileViewerCoordinator.assignedEditorGroup(for: tileID)
            ?? dockedFileViewerCoordinator.editorGroup(
                for: tileID,
                fileURL: fileURL,
                documentReference: fileContext.reference,
                fileContentProvider: fileContext.fileContentProvider
            )
        let spotlight = makeSpotlightState(
            source: .file(tileID: tileID, fileURL: fileURL, group: group),
            title: fileURL.lastPathComponent,
            workingDirectoryURL: fileURL.deletingLastPathComponent(),
            owningProjectRootURL: fileContext.owningProjectRootURL ?? owningProjectRootURL,
            owningProjectIdentifier: tile?.projectIdentifier,
            surfaceID: resolvedSurfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }
}
