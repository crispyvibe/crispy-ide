// AnyProjectSession+BackwardCompat.swift — SSH Remote Development
// Convenience properties for migrating existing code that used ProjectSession directly.

import Foundation

extension AnyProjectSession {
    /// The underlying ProjectSession, if this wraps a local project.
    var projectSession: ProjectSession? { _wrapped as? ProjectSession }

    /// Concrete FolderExplorerViewModel for views that need local-specific features.
    /// Returns nil for remote projects — use folderExplorer for protocol-based access.
    var folderExplorerViewModel: FolderExplorerViewModel? { projectSession?.folderExplorerViewModel }

    /// Concrete TerminalViewModel. Non-optional — both local and remote projects use it.
    var terminalViewModel: TerminalViewModel {
        if let local = projectSession { return local.terminalViewModel }
        if let remote = _wrapped as? RemoteProjectSession, let vm = remote.terminal as? TerminalViewModel { return vm }
        fatalError("Project has no TerminalViewModel — unexpected ProjectProviding implementation")
    }

    var sshConnection: SSHConnection? {
        (_wrapped as? RemoteProjectSession)?.sshConnection
    }

    /// Root URL (local path or remote path as file URL).
    var rootURL: URL { metadata.rootDirectoryURL }

    /// Unique key for settings storage. Local: normalized path. Remote: SSH URI + path.
    var projectIdentifier: String { metadata.identifier }

    /// Display title for the project.
    var title: String { metadata.displayName }

    /// Legacy helper retained while older call sites migrate to the type-erased wrapper.
    func activateIfNeeded() { activate() }

    /// Legacy helper retained while older call sites migrate to the type-erased wrapper.
    func ensureExplorerLoadedIfNeeded() { ensureExplorerLoaded() }
}
