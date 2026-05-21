// RemoteProjectMetadata.swift — SSH Remote Development

import Combine
import Foundation

/// ProjectMetadata for remote (SSH) projects.
/// identifier is the SSH URI + remote path. hostLabel shows the SSH host display name.
struct RemoteProjectMetadata: ProjectMetadata {
    let identifier: String
    let displayName: String
    let displayPath: String
    let hostLabel: String?
    let rootDirectoryURL: URL
    private let _connectionState: AnyPublisher<ConnectionState, Never>?

    var connectionState: AnyPublisher<ConnectionState, Never>? { _connectionState }

    @MainActor
    init(connection: SSHConnection, remotePath: String) {
        self.identifier = "\(connection.profile.sshURI)\(remotePath)"
        self.displayName = (remotePath as NSString).lastPathComponent
        self.displayPath = "\(connection.profile.host):\(remotePath)"
        self.hostLabel = connection.profile.displayName
        self.rootDirectoryURL = URL(fileURLWithPath: remotePath)
        self._connectionState = connection.statePublisher
    }
}
