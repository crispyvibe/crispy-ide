import AppKit
import Foundation

enum TerminalFileSystemTargetResolution {
    case previewFile(target: TerminalFileSystemTarget, owningProjectRootURL: URL?)
    case revealDirectoryInFinder(URL)
}

@MainActor
struct VibeSpaceCanvasFileOpenUseCase {
    private let projectRoutingUseCase = VibeSpaceProjectRoutingUseCase()

    func wireProjectFileOpenHandler(
        _ project: AnyProjectSession,
        contentViewerStore: ContentViewerStore,
        splitViewStore: SplitViewStore,
        appShellStore: AppShellStore,
        vibespaceCatalogStore: VibeSpaceCatalogStore,
        dockPreviewBridge: DockPreviewBridge? = nil,
        canvasModeProvider: (() -> VibeSpaceCanvasMode)? = nil
    ) {
        let projectRootURL = project.rootURL
        if project.onFileOpenRequested == nil {
            let fileContentProvider = project.fileContent
            let projectIdentifier = project.metadata.identifier
            project.onFileOpenRequested = { request in
                if let canvasModeProvider, canvasModeProvider() == .terminalOnly,
                   let dockPreviewBridge,
                   request.action == .preview || request.action == .openTab {
                    dockPreviewBridge.requestPreview(for: request.fileURL)
                    return
                }
                switch request.action {
                case .preview:
                    contentViewerStore.previewFile(
                        at: request.fileURL,
                        projectIdentifier: projectIdentifier,
                        fileContentProvider: fileContentProvider
                    )
                case .openTab:
                    contentViewerStore.openFileInTab(
                        at: request.fileURL,
                        projectIdentifier: projectIdentifier,
                        fileContentProvider: fileContentProvider
                    )
                case .openWindow:
                    break
                case .openInSplitHorizontal:
                    splitViewStore.splitActiveWithTab(
                        .file(url: request.fileURL, projectIdentifier: projectIdentifier),
                        orientation: .horizontal,
                        fileContentProvider: fileContentProvider
                    )
                case .openInSplitVertical:
                    splitViewStore.splitActiveWithTab(
                        .file(url: request.fileURL, projectIdentifier: projectIdentifier),
                        orientation: .vertical,
                        fileContentProvider: fileContentProvider
                    )
                case let .compareGitStatus(code, relativePath):
                    if code.contains("D") {
                        contentViewerStore.previewGitFileContent(
                            rootURL: projectRootURL,
                            fileURL: request.fileURL,
                            relativePath: relativePath,
                            titleSuffix: "Deleted",
                            projectIdentifier: projectIdentifier
                        )
                    } else {
                        contentViewerStore.previewGitDiff(
                            rootURL: projectRootURL,
                            fileURL: request.fileURL,
                            relativePath: relativePath,
                            statusCode: code,
                            projectIdentifier: projectIdentifier
                        )
                    }
                }
            }
        }

        if project.onFileRenamed == nil {
            project.onFileRenamed = { event in
                contentViewerStore.retargetFileSystemLocation(from: event.oldURL, to: event.newURL)
            }
        }

        contentViewerStore.onActiveFileCleared = { [weak appShellStore, weak vibespaceCatalogStore] in
            guard let activeVibeSpaceID = appShellStore?.activeVibeSpaceID,
                  let focusedProject = vibespaceCatalogStore?.vibespaceValue(for: activeVibeSpaceID, { $0.focusedProject }) else {
                return
            }
            focusedProject.folderExplorer.selectedFileURL = nil
        }
    }

    func resolveFileSystemTargetFromTerminal(
        _ target: TerminalFileSystemTarget,
        preferredProjectRootURL: URL? = nil,
        candidates: [(vibespaceID: UUID, project: AnyProjectSession)]
    ) -> TerminalFileSystemTargetResolution {
        let normalizedURL = target.standardizedFileURL

        if normalizedURL.hasDirectoryPath {
            return .revealDirectoryInFinder(normalizedURL)
        }

        if let match = projectRoutingUseCase.terminalProjectMatch(
            for: normalizedURL,
            preferredProjectRootURL: preferredProjectRootURL,
            candidates: candidates
        ) {
            return .previewFile(
                target: TerminalFileSystemTarget(
                    url: normalizedURL,
                    line: target.line,
                    column: target.column
                ),
                owningProjectRootURL: match.project.rootURL.standardizedFileURL
            )
        }

        return .previewFile(
            target: TerminalFileSystemTarget(
                url: normalizedURL,
                line: target.line,
                column: target.column
            ),
            owningProjectRootURL: nil
        )
    }

    func openSourceControlDiff(
        repositoryRootURL: URL,
        item: VibeSpaceSourceControlStatusItem,
        focusedProject: AnyProjectSession?,
        projects: [AnyProjectSession],
        contentViewerStore: ContentViewerStore,
        prepareVibeSpacePresentation: () -> Void,
        wireProjectFileOpenHandler: (AnyProjectSession) -> Void
    ) {
        let normalizedRepositoryRootURL = repositoryRootURL.standardizedFileURL
        let normalizedFileURL = item.url.standardizedFileURL

        prepareVibeSpacePresentation()

        let targetProject = projectRoutingUseCase.sourceControlProjectMatch(
            for: normalizedFileURL,
            repositoryRootURL: normalizedRepositoryRootURL,
            focusedProject: focusedProject,
            projects: projects
        ) ?? focusedProject ?? projects.first

        guard let targetProject else { return }

        wireProjectFileOpenHandler(targetProject)
        if item.isDeleted {
            contentViewerStore.previewGitFileContent(
                rootURL: normalizedRepositoryRootURL,
                fileURL: normalizedFileURL,
                relativePath: item.relativePath,
                titleSuffix: "Deleted"
            )
            return
        }

        if item.lacksCommittedHistory {
            contentViewerStore.openFileInTab(at: normalizedFileURL)
            return
        }

        contentViewerStore.previewGitDiff(
            rootURL: normalizedRepositoryRootURL,
            fileURL: normalizedFileURL,
            relativePath: item.relativePath,
            statusCode: item.code
        )
    }
}
