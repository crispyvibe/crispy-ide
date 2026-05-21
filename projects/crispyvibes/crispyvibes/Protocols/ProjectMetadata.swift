// ProjectMetadata.swift — SSH Remote Development

import Combine
import Foundation

/// Identity and display information for a project session.
/// Local projects have hostLabel == nil and connectionState == nil.
/// Remote projects expose the SSH host label and connection state publisher.
protocol ProjectMetadata {
    /// Unique key for settings storage. Local: normalized file path. Remote: SSH URI + path.
    var identifier: String { get }

    /// Short display name (e.g. "myproject").
    var displayName: String { get }

    /// Full display path (e.g. "/path/to/myproject" or "devserver:~/myproject").
    var displayPath: String { get }

    /// Remote host label, or nil for local projects.
    var hostLabel: String? { get }

    /// Connection state publisher. nil for local projects (always connected).
    var connectionState: AnyPublisher<ConnectionState, Never>? { get }

    /// Root directory URL. Local: filesystem path. Remote: remote path as file URL.
    var rootDirectoryURL: URL { get }
}
