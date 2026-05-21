// ConnectionState.swift — SSH Remote Development

import Foundation

/// Represents the lifecycle state of an SSH connection.
enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}
