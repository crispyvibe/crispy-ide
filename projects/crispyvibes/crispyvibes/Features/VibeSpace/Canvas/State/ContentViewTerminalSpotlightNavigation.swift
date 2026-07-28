import SwiftUI

extension ContentView {
    private var spotlightHomeDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    private func makeSpotlightState(
        source: TerminalSpotlightState.Source,
        title: String,
        workingDirectoryURL: URL,
        owningProjectRootURL: URL? = nil
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
            owningProjectRootURL: owningProjectRootURL
        )
    }

    func resolvedFileOpenContext(
        for fileURL: URL,
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
            for tile in boardStore.layout.tiles {
                guard let snapshot = tile.acpSnapshot,
                      let store = contentViewerStore.acpStore(for: snapshot.id) else { continue }
                let accentColor = store.selectedProject(from: vibespaceView.activeVibeSpaceProjects)
                    .flatMap { vibespaceCanvasActionsCoordinator.colorTag(for: $0)?.color }
                items.append(.acp(tileID: tile.id, storeID: snapshot.id, title: store.tabTitle, accentColor: accentColor))
            }
        }
        for entry in dockedFileViewerCoordinator.dockedFiles {
            items.append(.file(tileID: entry.id, fileURL: entry.fileURL))
        }
        if let boardStore = vibespaceHydrationCoordinator.boardStore {
            for tile in boardStore.layout.tiles where tile.isBrowser {
                if let url = tile.browserURL {
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

    private func vibespaceSpotlightTerminalEntries() -> [
        (identity: VibeSpaceSpotlightTerminalOrderEntry, item: SpotlightItem)
    ] {
        vibespaceView.activeVibeSpaceProjects.flatMap { project in
            let projectPath = project.rootURL.standardizedFileURL.path
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
            projectPath: project.rootURL.standardizedFileURL.path,
            tabID: tab.id
        )
    }

    func spotlightItemIndex(for spotlight: TerminalSpotlightState) -> Int? {
        let items = flatSpotlightItems
        switch spotlight.source {
        case let .persistent(_, tabID):
            return items.firstIndex(where: {
                if case let .terminal(_, tab) = $0 { return tab.id == tabID }
                return false
            })
        case .vibeCast:
            return items.firstIndex(where: {
                if case .vibeCast = $0 { return true }
                return false
            })
        case .vibeLanes:
            return items.firstIndex(where: {
                if case .vibeLanes = $0 { return true }
                return false
            })
        case let .acp(tileID, _):
            return items.firstIndex(where: {
                if case let .acp(id, _, _, _) = $0 { return id == tileID }
                return false
            })
        case .filePreview, .todos:
            return nil
        case let .file(_, fileURL):
            return items.firstIndex(where: {
                if case let .file(_, url) = $0 { return url == fileURL }
                return false
            })
        case .browserPreview:
            return nil
        case let .browser(tileID, _):
            return items.firstIndex(where: {
                if case let .browser(id, _) = $0 { return id == tileID }
                return false
            })
        case .transient:
            return nil
        }
    }

    func installSpotlightScrollMonitor() {
        terminalSpotlightCoordinator.installScrollMonitor(onSwitchSpotlight: switchSpotlight(by:))
    }

    func removeSpotlightScrollMonitor() {
        terminalSpotlightCoordinator.removeScrollMonitor()
    }

    func switchSpotlight(by offset: Int) {
        guard let spotlight = terminalSpotlightCoordinator.spotlight,
              spotlight.supportsCarouselNavigation else { return }
        let items = flatSpotlightItems
        guard items.count > 1 else {
            terminalSpotlightCoordinator.animateSwipeOffset(0, animation: .spring(response: 0.35, dampingFraction: 0.7))
            return
        }
        guard let currentIndex = spotlightItemIndex(for: spotlight) else { return }
        let nextIndex = (currentIndex + offset + items.count) % items.count
        let entryOffset = terminalSpotlightCoordinator.prepareSwitchTransition(offset: offset)

        switch items[nextIndex] {
        case let .terminal(project, tab):
            let accentColor = vibespaceCanvasActionsCoordinator.colorTag(for: project)?.color ?? activeThemePalette.accentColor
            presentTerminalSpotlight(
                terminalViewModel: project.terminalViewModel,
                tabID: tab.id,
                title: tab.title.isEmpty ? project.title : tab.title,
                accentColor: accentColor,
                owningProjectRootURL: project.rootURL,
                surfaceID: spotlight.surfaceID,
                animated: false
            )
        case .vibeCast:
            presentVibeCastSpotlight(animated: false)
        case .vibeLanes:
            presentVibeLanesSpotlight(animated: false)
        case let .acp(tileID, storeID, _, _):
            presentACPSpotlight(tileID: tileID, storeID: storeID, animated: false)
        case let .file(tileID, fileURL):
            presentFileSpotlight(tileID: tileID, fileURL: fileURL, animated: false)
        case let .browser(tileID, url):
            presentBrowserSpotlight(tileID: tileID, url: url, animated: false)
        }

        terminalSpotlightCoordinator.animateSwipeOffset(entryOffset)
        terminalSpotlightCoordinator.animateSwipeOffset(0, animation: .spring(response: 0.35, dampingFraction: 0.82))
    }

    func presentVibeCastSpotlight(animated: Bool = true) {
        let spotlight = makeSpotlightState(
            source: .vibeCast,
            title: AppStrings.VibeCast.title,
            workingDirectoryURL: spotlightHomeDirectoryURL
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentVibeLanesSpotlight(animated: Bool = true) {
        let spotlight = makeSpotlightState(
            source: .vibeLanes,
            title: AppStrings.VibeLanes.title,
            workingDirectoryURL: spotlightHomeDirectoryURL
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentTodosSpotlight(animated: Bool = true) {
        let spotlight = makeSpotlightState(
            source: .todos,
            title: AppStrings.Todos.title,
            workingDirectoryURL: spotlightHomeDirectoryURL
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentFilePreviewSpotlight(
        target: TerminalFileSystemTarget,
        owningProjectRootURL: URL? = nil,
        animated: Bool = true
    ) {
        let normalizedTarget = TerminalFileSystemTarget(
            url: target.standardizedFileURL,
            line: target.line,
            column: target.column
        )
        let group = appContainer.makeEditorGroupStore(bufferStore: DocumentBufferStore())
        let fileContext = resolvedFileOpenContext(
            for: normalizedTarget.url,
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
            owningProjectRootURL: fileContext.owningProjectRootURL ?? owningProjectRootURL
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentFileSpotlight(
        tileID: UUID,
        fileURL: URL,
        owningProjectRootURL: URL? = nil,
        animated: Bool = true
    ) {
        let fileContext = resolvedFileOpenContext(
            for: fileURL,
            preferredProjectRootURL: owningProjectRootURL
        )
        let spotlight = makeSpotlightState(
            source: .file(tileID: tileID, fileURL: fileURL),
            title: fileURL.lastPathComponent,
            workingDirectoryURL: fileURL.deletingLastPathComponent(),
            owningProjectRootURL: fileContext.owningProjectRootURL ?? owningProjectRootURL
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }
}
