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
        projectPath: String?
    ) -> TerminalSpotlightState {
        TerminalSpotlightState(
            id: UUID(),
            source: source,
            title: title,
            accentColor: activeThemePalette.accentColor,
            workingDirectoryURL: browserSpotlightWorkingDirectoryURL,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            isTemporary: false,
            owningProjectRootURL: projectPath.map { URL(fileURLWithPath: $0) }
        )
    }

    func spotlightBrowserPreviewViewModel(
        snapshot: BrowserSessionSnapshot,
        projectPath: String?
    ) -> BrowserPanelViewModel {
        if let existing = dockedBrowserCoordinator.previewViewModel {
            return existing
        }
        return dockedBrowserCoordinator.restorePreview(from: snapshot, projectPath: projectPath)
    }

    func presentBrowserSpotlight(url: URL?, projectPath: String? = nil, animated: Bool = true) {
        dockedBrowserCoordinator.dismissPreview()
        let resolvedURL = url ?? URL(string: "about:blank")!
        let snapshot = BrowserSessionSnapshot(urlString: resolvedURL.absoluteString)
        let spotlight = browserSpotlightState(
            source: .browserPreview(snapshot: snapshot),
            title: browserSpotlightTitle(for: resolvedURL),
            projectPath: projectPath
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentBrowserSpotlight(
        snapshot: BrowserSessionSnapshot,
        projectPath: String? = nil,
        animated: Bool = true
    ) {
        let effectiveSnapshot = dockedBrowserCoordinator.previewSnapshot() ?? snapshot
        let resolvedURL = effectiveSnapshot.urlString.flatMap(URL.init(string:))
        let spotlight = browserSpotlightState(
            source: .browserPreview(snapshot: effectiveSnapshot),
            title: browserSpotlightTitle(for: resolvedURL),
            projectPath: projectPath
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }

    func presentBrowserSpotlight(tileID: UUID, url: URL, animated: Bool = true) {
        let tile = vibespaceHydrationCoordinator.boardStore?.tile(for: tileID)
        let spotlight = browserSpotlightState(
            source: .browser(tileID: tileID, url: url),
            title: browserSpotlightTitle(for: url),
            projectPath: tile?.projectPath
        )
        setTerminalSpotlight(spotlight, animated: animated)
    }
}
