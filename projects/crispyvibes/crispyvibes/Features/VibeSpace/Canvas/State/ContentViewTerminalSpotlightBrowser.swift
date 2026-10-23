import SwiftUI

extension ContentView {
    private var browserSpotlightWorkingDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    private func browserSpotlightTitle(for url: URL?) -> String {
        url?.host ?? "New Tab"
    }

    private func browserSpotlightState(
        source: TerminalSpotlightState.Source,
        title: String,
        projectPath: String?,
        surfaceID: UUID?
    ) -> TerminalSpotlightState {
        let owningProjectRootURL = projectPath.flatMap { identity in
            vibespaceView.activeVibeSpaceProjects.first(where: {
                $0.projectIdentifier == identity
                    || $0.rootURL.standardizedFileURL.path == identity
            })?.rootURL
        }
        return TerminalSpotlightState(
            id: UUID(),
            source: source,
            title: title,
            accentColor: activeThemePalette.accentColor,
            workingDirectoryURL: browserSpotlightWorkingDirectoryURL,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: owningProjectRootURL,
            owningProjectIdentifier: projectPath,
            surfaceID: surfaceID
        )
    }

    func spotlightBrowserPreviewViewModel(
        snapshot: BrowserSessionSnapshot,
        projectPath: String?
    ) -> BrowserPanelViewModel {
        if let existing = dockedBrowserCoordinator.previewViewModel,
           dockedBrowserCoordinator.previewProjectPath == projectPath,
           existing.projectPath == projectPath {
            return existing
        }
        return dockedBrowserCoordinator.restorePreview(from: snapshot, projectPath: projectPath)
    }

    func presentBrowserSpotlight(
        url: URL?,
        projectPath: String? = nil,
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        dockedBrowserCoordinator.dismissPreview()
        let resolvedURL = url ?? URL(string: "about:blank")!
        let snapshot = BrowserSessionSnapshot(urlString: resolvedURL.absoluteString)
        let spotlight = browserSpotlightState(
            source: .browserPreview(snapshot: snapshot),
            title: browserSpotlightTitle(for: resolvedURL),
            projectPath: projectPath,
            surfaceID: surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentBrowserSpotlight(
        snapshot: BrowserSessionSnapshot,
        projectPath: String? = nil,
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        _ = dockedBrowserCoordinator.restorePreview(from: snapshot, projectPath: projectPath)
        let resolvedURL = snapshot.urlString.flatMap(URL.init(string:))
        let spotlight = browserSpotlightState(
            source: .browserPreview(snapshot: snapshot),
            title: browserSpotlightTitle(for: resolvedURL),
            projectPath: projectPath,
            surfaceID: surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentBrowserSpotlight(
        tileID: UUID,
        url: URL,
        surfaceID: UUID? = nil,
        animated: Bool = true
    ) {
        let boardStore = vibespaceHydrationCoordinator.boardStore
        let resolvedSurfaceID = surfaceID ?? terminalSpotlightCoordinator.spotlight?.surfaceID
        let tileSurfaceID = resolvedSurfaceID ?? boardStore?.primarySurfaceID
        let tile = tileSurfaceID.flatMap { tileSurfaceID in
            boardStore?.tile(for: tileID, includeMinimized: true, surfaceID: tileSurfaceID)
        }
        let spotlight = browserSpotlightState(
            source: .browser(tileID: tileID, url: url),
            title: browserSpotlightTitle(for: url),
            projectPath: tile.flatMap { $0.projectIdentifier ?? $0.projectPath },
            surfaceID: resolvedSurfaceID
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }
}
