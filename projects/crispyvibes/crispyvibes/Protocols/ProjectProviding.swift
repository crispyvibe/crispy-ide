// ProjectProviding.swift — SSH Remote Development

import Foundation

/// Abstraction over a project session (local or remote).
/// Local: backed by ProjectSession (renamed to LocalProjectSession).
/// Remote: backed by RemoteProjectSession.
/// Views consume this protocol via AnyProjectSession type-erased wrapper.
@MainActor
protocol ProjectProviding: AnyObject, Identifiable where ID == UUID {
    var id: UUID { get }
    var metadata: any ProjectMetadata { get }
    var folderExplorer: any FolderExploring { get }
    var gitExplorer: any GitExploring { get }
    var terminal: any TerminalProviding { get }
    var fileContent: any FileContentProviding { get }
    var paneLayout: ProjectPaneLayoutState { get set }

    var onFileOpenRequested: ((ExplorerOpenRequest) -> Void)? { get set }
    var onFileRenamed: ((ExplorerRenameEvent) -> Void)? { get set }

    func activate()
    func ensureExplorerLoaded()
    func shutdown()
}
