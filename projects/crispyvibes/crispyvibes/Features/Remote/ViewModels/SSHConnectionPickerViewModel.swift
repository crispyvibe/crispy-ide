// SSHConnectionPickerViewModel.swift — SSH Remote Development
// Drives the SSH connection picker — manages connection state, host key prompt flow.

import Foundation

@MainActor
final class SSHConnectionPickerViewModel: ObservableObject {
    @Published var selectedProfile: SSHConnectionProfile?
    @Published var connectedConnection: SSHConnection?
    @Published var connectError: String?
    @Published var statusMessage: String?
    @Published var isConnecting = false

    @Published var pendingHostKeyFingerprint: String?
    @Published var pendingHostKeyProfile: SSHConnectionProfile?

    let connectionManager: SSHConnectionManager

    init(connectionManager: SSHConnectionManager) {
        self.connectionManager = connectionManager
    }

    func connect(to profile: SSHConnectionProfile) {
        selectedProfile = profile
        isConnecting = true
        connectError = nil
        pendingHostKeyFingerprint = nil
        pendingHostKeyProfile = nil
        statusMessage = "Connecting to \(profile.host)…"

        Task {
            do {
                let connection = try await connectionManager.connect(profile: profile)
                statusMessage = nil
                connectedConnection = connection
            } catch is HostKeyUnknownError {
                statusMessage = "Fetching host key…"
                let fingerprint = await KnownHostsValidator.fetchFingerprint(host: profile.host, port: profile.port)
                statusMessage = nil
                if let fingerprint, fingerprint.hasPrefix("Error:") {
                    connectError = "Host key scan failed: \(fingerprint.dropFirst(7))"
                } else {
                    pendingHostKeyFingerprint = fingerprint ?? "Unable to fetch fingerprint"
                    pendingHostKeyProfile = profile
                }
            } catch is HostKeyChangedError {
                statusMessage = nil
                connectError = "Host key for \(profile.host) has CHANGED. This could indicate a security issue. Remove the old entry from ~/.ssh/known_hosts if you trust this change."
            } catch {
                statusMessage = nil
                connectError = Self.friendlyError(error)
            }
            isConnecting = false
        }
    }

    func acceptHostKeyAndConnect() {
        guard let profile = pendingHostKeyProfile else { return }
        pendingHostKeyFingerprint = nil
        pendingHostKeyProfile = nil
        isConnecting = true
        statusMessage = "Saving host key…"

        Task {
            do {
                let connection = connectionManager.connection(for: profile)
                statusMessage = "Connecting to \(profile.host)…"
                try await connection.acceptAndConnect()
                statusMessage = nil
                connectedConnection = connection
            } catch {
                statusMessage = nil
                connectError = Self.friendlyError(error)
            }
            isConnecting = false
        }
    }

    func rejectHostKey() {
        pendingHostKeyFingerprint = nil
        pendingHostKeyProfile = nil
        connectError = nil
    }

    func goBack() { connectedConnection = nil }

    static func friendlyError(_ error: Error) -> String {
        let msg = "\(error)"
        if msg.contains("connectTimeout") || msg.contains("timed out") { return "Connection timed out — host may be unreachable." }
        if msg.contains("Connection refused") { return "Connection refused — is SSH running on this host?" }
        if msg.contains("No route to host") { return "Cannot reach host — check hostname and network." }
        if msg.contains("Permission denied") || msg.contains("Authentication failed") {
            return "Authentication failed — check your SSH key is authorized on the server."
        }
        return error.localizedDescription
    }
}
