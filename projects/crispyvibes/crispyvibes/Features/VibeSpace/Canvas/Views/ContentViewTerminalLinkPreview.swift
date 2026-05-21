import Foundation

extension ContentView {
    func openTerminalLinkTarget(_ url: URL, preferredProjectRootURL: URL? = nil) {
        if url.isFileURL {
            openTerminalFileSystemTarget(
                TerminalFileSystemTarget(url: url, line: nil, column: nil),
                preferredProjectRootURL: preferredProjectRootURL
            )
            return
        }

        pushCurrentSpotlightForRestoreIfNeeded()
        presentBrowserSpotlight(
            url: url,
            projectPath: preferredProjectRootURL?.standardizedFileURL.path
        )
    }

    func openTerminalFileSystemTarget(
        _ target: TerminalFileSystemTarget,
        preferredProjectRootURL: URL? = nil
    ) {
        let resolution = VibeSpaceCanvasFileOpenUseCase().resolveFileSystemTargetFromTerminal(
            target,
            preferredProjectRootURL: preferredProjectRootURL,
            candidates: vibespaceCatalogStore.allProjects()
        )

        switch resolution {
        case let .previewFile(resolvedTarget, owningProjectRootURL):
            if case .filePreview = terminalSpotlightCoordinator.spotlight?.source {
                // Replace existing file preview — don't stack
            } else {
                pushCurrentSpotlightForRestoreIfNeeded()
            }
            presentFilePreviewSpotlight(
                target: resolvedTarget,
                owningProjectRootURL: owningProjectRootURL
            )
        case let .revealDirectoryInFinder(directoryURL):
            appContainer.vibespaceInteraction.revealInFinder(directoryURL)
        }
    }

    private func pushCurrentSpotlightForRestoreIfNeeded() {
        guard terminalSpotlightCoordinator.spotlight != nil else { return }
        pushCurrentSpotlightForRestore()
    }
}
