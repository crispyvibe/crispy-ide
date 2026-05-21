// DefaultProjectSessionFactory.swift — SSH Remote Development

import Foundation

/// Default factory for creating local and remote project sessions.
/// Injected into VibeSpaceState to decouple session creation from concrete types.
struct DefaultProjectSessionFactory: ProjectSessionFactory {
    let makeProjectSessionDependencies: @MainActor (UUID?) -> ProjectSessionDependencies
    let terminalViewModelFactory: @MainActor () -> TerminalViewModel
    let vibespaceID: UUID?

    @MainActor
    func makeLocal(rootURL: URL) -> AnyProjectSession {
        let deps = makeProjectSessionDependencies(vibespaceID)
        let session = ProjectSession(rootURL: rootURL, dependencies: deps)
        return AnyProjectSession(session)
    }

    @MainActor
    func makeRemote(connection: any SSHConnectionProviding, remotePath: String) -> AnyProjectSession {
        guard let sshConnection = connection as? SSHConnection else {
            fatalError("DefaultProjectSessionFactory requires SSHConnection")
        }
        let deps = makeProjectSessionDependencies(vibespaceID)
        let session = RemoteProjectSession(
            connection: sshConnection,
            remotePath: remotePath,
            terminalViewModelFactory: terminalViewModelFactory,
            vibespaceManagement: deps.vibespaceManagement,
            vibespaceID: deps.vibespaceID
        )
        return AnyProjectSession(session)
    }
}
