// ProjectSessionFactory.swift — SSH Remote Development

import Foundation

/// Factory for creating local and remote project sessions.
/// Injected into VibeSpaceState to decouple session creation from concrete types.
protocol ProjectSessionFactory {
    @MainActor func makeLocal(rootURL: URL) -> AnyProjectSession
    @MainActor func makeRemote(connection: any SSHConnectionProviding, remotePath: String) -> AnyProjectSession
}
