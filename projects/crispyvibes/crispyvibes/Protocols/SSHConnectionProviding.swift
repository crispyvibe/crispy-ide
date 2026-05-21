// SSHConnectionProviding.swift — SSH Remote Development

import Combine
import Foundation

/// Port forwarding rule for SSH local port forwarding (equivalent to ssh -L).
struct PortForwardRule: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var localPort: UInt16
    var remoteHost: String
    var remotePort: UInt16
    var autoDetected: Bool

    var displayString: String { "localhost:\(localPort) → \(remoteHost):\(remotePort)" }
}

/// Abstraction over an SSH connection with lifecycle and port forwarding.
@MainActor
protocol SSHConnectionProviding: AnyObject {
    var profile: SSHConnectionProfile { get }
    var state: ConnectionState { get }
    var statePublisher: AnyPublisher<ConnectionState, Never> { get }
    func connect() async throws
    func disconnect() async
    func addPortForward(_ rule: PortForwardRule) async throws
    func removePortForward(_ rule: PortForwardRule) async throws
}
