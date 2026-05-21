// RemoteConnectionStatusPopover.swift — SSH Remote Development

import AppKit
import SwiftUI

/// Popover showing vibespace SSH connections with reconnect/retry actions.
struct RemoteConnectionStatusPopover: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    @ObservedObject var connectionManager: SSHConnectionManager
    let projects: [AnyProjectSession]

    private var vibespaceConnections: [SSHConnection] {
        var seen = Set<ObjectIdentifier>()
        return projects.compactMap(\.sshConnection).filter { connection in
            seen.insert(ObjectIdentifier(connection)).inserted
        }
    }

    private var retryableConnections: [SSHConnection] {
        vibespaceConnections.filter {
            switch $0.state {
            case .failed, .disconnected:
                return true
            case .connected, .connecting:
                return false
            }
        }
    }

    private var maximumPopoverHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) * 0.6
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Remote Connections").font(AppTypographyTokens.subheadlineSemibold)
                    Spacer()
                    if !retryableConnections.isEmpty {
                        Button("Retry All") {
                            for connection in retryableConnections {
                                Task { try? await connection.connect() }
                            }
                        }
                        .controlSize(.small)
                    }
                }

                if vibespaceConnections.isEmpty {
                    Text("No remote projects in this vibe space")
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vibespaceConnections, id: \.profile.id) { connection in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: statusSymbol(for: connection.state))
                                    .font(AppTypographyTokens.scaledIcon(13))
                                    .foregroundStyle(statusColor(for: connection.state))
                                    .frame(width: uiScale.iconSize(16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connection.profile.displayName).font(AppTypographyTokens.calloutSemibold)
                                    Text(connection.profile.connectionString)
                                        .font(AppTypographyTokens.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                connectionAction(for: connection)
                            }

                            if case .failed(let message) = connection.state {
                                Text(message)
                                    .font(AppTypographyTokens.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            PortForwardPanel(
                                service: connection.portForwardService,
                                connection: connection
                            )
                            .padding(.leading, 24)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: maximumPopoverHeight)
    }

    @ViewBuilder
    private func connectionAction(for connection: SSHConnection) -> some View {
        switch connection.state {
        case .connected:
            Button("Disconnect") {
                Task { await connection.disconnect() }
            }
            .controlSize(.small)
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting")
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(.secondary)
            }
        case .disconnected, .failed:
            Button("Retry") {
                Task { try? await connection.connect() }
            }
            .controlSize(.small)
        }
    }

    private func statusColor(for state: ConnectionState) -> Color {
        switch state {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .secondary
        case .failed: .red
        }
    }

    private func statusSymbol(for state: ConnectionState) -> String {
        switch state {
        case .connected: return "server.rack"
        case .connecting: return "arrow.triangle.2.circlepath.circle.fill"
        case .disconnected: return "server.rack"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// Toolbar button showing vibespace SSH status and surfacing problems.
struct RemoteConnectionStatusButton: View {
    @ObservedObject var connectionManager: SSHConnectionManager
    let projects: [AnyProjectSession]
    @State private var isShowingPopover = false

    private enum Severity {
        case healthy
        case connecting
        case issue
    }

    private var vibespaceConnections: [SSHConnection] {
        var seen = Set<ObjectIdentifier>()
        return projects.compactMap(\.sshConnection).filter { connection in
            seen.insert(ObjectIdentifier(connection)).inserted
        }
    }

    private var severity: Severity {
        if vibespaceConnections.contains(where: {
            if case .failed = $0.state { return true }
            return $0.state == .disconnected
        }) {
            return .issue
        }
        if vibespaceConnections.contains(where: { $0.state == .connecting }) {
            return .connecting
        }
        return .healthy
    }

    private var issueCount: Int {
        vibespaceConnections.reduce(into: 0) { count, connection in
            switch connection.state {
            case .failed, .disconnected:
                count += 1
            case .connected, .connecting:
                break
            }
        }
    }

    var body: some View {
        Button { isShowingPopover.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .foregroundStyle(symbolColor)
                if issueCount > 0 {
                    Text("\(issueCount)")
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(symbolColor)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover) {
            RemoteConnectionStatusPopover(
                connectionManager: connectionManager,
                projects: projects
            )
        }
        .help(helpText)
    }

    private var symbolName: String {
        switch severity {
        case .healthy:
            return "server.rack"
        case .connecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .issue:
            return "exclamationmark.triangle.fill"
        }
    }

    private var symbolColor: Color {
        switch severity {
        case .healthy:
            return .secondary
        case .connecting:
            return .orange
        case .issue:
            return .red
        }
    }

    private var helpText: String {
        switch severity {
        case .healthy:
            return "Remote projects available"
        case .connecting:
            return "Remote connection in progress"
        case .issue:
            let suffix = issueCount == 1 ? "" : "s"
            return "\(issueCount) remote connection\(suffix) need attention"
        }
    }
}
