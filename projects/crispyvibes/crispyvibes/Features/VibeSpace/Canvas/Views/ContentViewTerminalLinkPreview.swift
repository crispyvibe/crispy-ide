import Foundation

extension ContentView {
    func openTerminalLinkTarget(
        _ url: URL,
        preferredProjectRootURL: URL? = nil,
        preferredProjectIdentifier: String? = nil
    ) {
        if url.isFileURL {
            openTerminalFileSystemTarget(
                TerminalFileSystemTarget(
                    url: url,
                    line: nil,
                    column: nil,
                    projectIdentifier: preferredProjectIdentifier
                ),
                preferredProjectRootURL: preferredProjectRootURL,
                preferredProjectIdentifier: preferredProjectIdentifier
            )
            return
        }

        pushCurrentSpotlightForRestoreIfNeeded()
        presentBrowserSpotlight(
            url: url,
            projectPath: preferredProjectIdentifier
                ?? preferredProjectRootURL?.standardizedFileURL.path
        )
    }

    func openTerminalFileSystemTarget(
        _ target: TerminalFileSystemTarget,
        preferredProjectRootURL: URL? = nil,
        preferredProjectIdentifier: String? = nil
    ) {
        let qualifiedTarget = TerminalFileSystemTarget(
            url: target.url,
            line: target.line,
            column: target.column,
            projectIdentifier: target.projectIdentifier ?? preferredProjectIdentifier
        )
        let resolution = VibeSpaceCanvasFileOpenUseCase().resolveFileSystemTargetFromTerminal(
            qualifiedTarget,
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
