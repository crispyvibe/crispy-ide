// SSHConnectionPicker.swift — SSH Remote Development

import SwiftUI

/// Full-flow picker: profile list → host key prompt → remote file browser → select folder.
struct SSHConnectionPicker: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    @ObservedObject var viewModel: SSHConnectionPickerViewModel
    let profileStore: SSHProfileStore
    let onFolderSelected: (SSHConnection, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Remote Connection").font(AppTypographyTokens.headline)
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            Divider()

            Group {
                if let connection = viewModel.connectedConnection {
                    RemoteFileBrowserView(
                        connection: connection,
                        onSelect: { remotePath in onFolderSelected(connection, remotePath) },
                        onBack: { viewModel.goBack() }
                    )
                } else if let fingerprint = viewModel.pendingHostKeyFingerprint {
                    SSHHostKeyPromptView(
                        host: viewModel.pendingHostKeyProfile?.host ?? "",
                        fingerprint: fingerprint,
                        onAccept: { viewModel.acceptHostKeyAndConnect() },
                        onReject: { viewModel.rejectHostKey() }
                    )
                } else {
                    profileListView
                }
            }
            .padding(20)
        }
        .frame(width: 480).frame(minHeight: 320)
        .scrollAssistGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 6)
    }

    private var profileListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if profileStore.profiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network.slash").font(AppTypographyTokens.largeTitle).foregroundStyle(.secondary.opacity(0.5))
                    Text("No SSH profiles configured").font(AppTypographyTokens.calloutSemibold).foregroundStyle(.secondary)
                    Text("Add a connection in Settings → Connections, or import from ~/.ssh/config.")
                        .font(AppTypographyTokens.caption).foregroundStyle(.secondary.opacity(0.7)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ForEach(profileStore.profiles) { profile in
                    Button { viewModel.connect(to: profile) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(AppTypographyTokens.scaledIcon(20))
                                .foregroundStyle(.secondary)
                                .frame(width: uiScale.iconSize(28))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName).font(AppTypographyTokens.calloutSemibold)
                                HStack(spacing: 4) {
                                    Text(profile.connectionString)
                                    Text("•")
                                    Text(profile.authMethod == .agent ? "SSH Agent" : "Key File")
                                }.font(AppTypographyTokens.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.isConnecting && viewModel.selectedProfile?.id == profile.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right").font(AppTypographyTokens.caption).foregroundStyle(.secondary.opacity(0.5))
                            }
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(Color.secondary.opacity(0.06)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isConnecting)
                }
            }

            if let status = viewModel.statusMessage {
                HStack(spacing: 8) { ProgressView().controlSize(.mini); Text(status).font(AppTypographyTokens.caption).foregroundStyle(.secondary) }
            }

            if let error = viewModel.connectError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(AppTypographyTokens.caption)
                    Text(error).font(AppTypographyTokens.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.06)).cornerRadius(6)
            }
        }
    }
}
