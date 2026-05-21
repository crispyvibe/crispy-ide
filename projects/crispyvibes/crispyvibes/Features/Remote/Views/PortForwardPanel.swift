// PortForwardPanel.swift — SSH Remote Development

import SwiftUI

/// Panel for managing port forwards on a connection.
struct PortForwardPanel: View {
    @ObservedObject var service: SSHPortForwardService
    @ObservedObject var connection: SSHConnection

    @State private var localPort = ""
    @State private var remoteHost = "localhost"
    @State private var remotePort = ""
    @State private var error: String?
    @State private var isAddingForward = false

    private var canAddForward: Bool {
        connection.state == .connected && !localPort.isEmpty && !remotePort.isEmpty && !isAddingForward
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Port Forwarding").font(AppTypographyTokens.subheadlineSemibold)
            Text("This Mac's localhost forwards through \(connection.profile.displayName) to a host reachable from that SSH machine.")
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("SSH Host")
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(.secondary)
                Text(connection.profile.connectionString)
                    .font(AppTypographyTokens.caption2Monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if service.activeForwards.isEmpty {
                Text("No active port forwards").font(AppTypographyTokens.caption).foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                ForEach(service.activeForwards) { rule in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.arrow.left").font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                        Text(rule.displayString).font(AppTypographyTokens.caption).lineLimit(1)
                        Spacer()
                        Button { Task { try? await connection.removePortForward(rule) } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain).controlSize(.small)
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                TextField("Mac Port", text: $localPort).textFieldStyle(.roundedBorder).frame(width: 72)
                Image(systemName: "arrow.right").font(AppTypographyTokens.caption).foregroundStyle(.secondary)
                TextField("Remote Host", text: $remoteHost).textFieldStyle(.roundedBorder).frame(width: 100)
                TextField("Remote Port", text: $remotePort).textFieldStyle(.roundedBorder).frame(width: 84)
                Button {
                    addForward()
                } label: {
                    if isAddingForward {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .controlSize(.small)
                .disabled(!canAddForward)
            }

            Text("Example: `3000 -> localhost:3000` means open `localhost:3000` on this Mac and proxy it to port `3000` on \(connection.profile.displayName).")
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(.secondary)

            if connection.state != .connected {
                Text("Connect this host before starting a port forward.")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(.secondary)
            }

            if isAddingForward {
                Text("Starting local listener...")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error { Text(error).font(AppTypographyTokens.caption2).foregroundStyle(.red) }
        }
    }

    private func addForward() {
        guard let lp = UInt16(localPort), let rp = UInt16(remotePort) else {
            error = "Invalid port"
            return
        }
        error = nil
        isAddingForward = true
        let trimmedRemoteHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = PortForwardRule(
            id: UUID(),
            localPort: lp,
            remoteHost: trimmedRemoteHost.isEmpty ? "localhost" : trimmedRemoteHost,
            remotePort: rp,
            autoDetected: false
        )
        Task {
            defer { isAddingForward = false }
            do {
                try await connection.addPortForward(rule)
                localPort = ""
                remotePort = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
