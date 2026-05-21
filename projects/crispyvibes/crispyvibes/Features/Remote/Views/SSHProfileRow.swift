// SSHProfileRow.swift — SSH Remote Development

import SwiftUI

/// Row displaying an SSH connection profile with key status, test connection, edit/delete actions.
struct SSHProfileRow: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    let profile: SSHConnectionProfile
    @ObservedObject var profileStore: SSHProfileStore
    @ObservedObject var testVM: SSHProfileTestViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var keyStatus: SSHProfileTestViewModel.KeyStatus {
        testVM.keyStatuses[profile.id] ?? .unchecked
    }
    private var testStatus: SSHProfileTestViewModel.TestStatus {
        testVM.testStatuses[profile.id] ?? .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: profile.authMethod == .agent ? "key" : "doc.text")
                    .font(AppTypographyTokens.scaledIcon(13))
                    .foregroundStyle(.secondary).frame(width: uiScale.iconSize(16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName).font(AppTypographyTokens.calloutSemibold).lineLimit(1)
                    Text(profile.connectionString).font(AppTypographyTokens.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if profile.importedFromConfig {
                    Text("SSH Config").font(AppTypographyTokens.caption2).foregroundStyle(.secondary)
                }
                if case .testing = testStatus {
                    ProgressView().controlSize(.mini)
                } else if case .idle = testStatus {
                    Button("Test") { testVM.testConnection(for: profile) }
                        .font(AppTypographyTokens.caption2).controlSize(.small)
                }
                Button { onEdit() } label: { Image(systemName: "pencil") }.controlSize(.small)
                Button { onDelete() } label: { Image(systemName: "trash") }.controlSize(.small)
            }

            keyStatusView
            testStatusView
        }
        .padding(.vertical, 6)
        .onAppear { if keyStatus == .unchecked { testVM.validateKey(for: profile) } }
    }

    @ViewBuilder
    private var keyStatusView: some View {
        switch keyStatus {
        case .valid(let desc):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(AppTypographyTokens.caption2)
                Text(desc).font(AppTypographyTokens.caption2).foregroundStyle(.secondary)
            }.padding(.leading, 26)
        case .rsaIncompatible:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(AppTypographyTokens.caption2)
                Text("RSA key — not compatible. Use Ed25519.").font(AppTypographyTokens.caption2).foregroundStyle(.orange)
                if testVM.fixInProgress == profile.id {
                    ProgressView().controlSize(.mini)
                } else {
                    Button("Generate Ed25519") {
                        testVM.generateReplacementKey(for: profile, profileStore: profileStore)
                    }
                    .font(AppTypographyTokens.caption2)
                    .controlSize(.small)
                }
            }
            .padding(.leading, 26)
        case .invalid(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(AppTypographyTokens.caption2)
                Text(msg).font(AppTypographyTokens.caption2).foregroundStyle(.red)
            }.padding(.leading, 26)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testStatus {
        case .testing(let step):
            HStack(alignment: .top, spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(step).font(AppTypographyTokens.caption2).foregroundStyle(.secondary).lineLimit(nil)
            }.padding(.leading, 26)
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(AppTypographyTokens.caption2)
                Text("Connected successfully").font(AppTypographyTokens.caption2).foregroundStyle(.green)
            }.padding(.leading, 26)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(AppTypographyTokens.caption2)
                    Text("Connection Failed").font(AppTypographyTokens.caption2Bold).foregroundStyle(.red)
                }
                Text(msg)
                    .font(AppTypographyTokens.caption2Monospaced)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.leading, 26)
        default: EmptyView()
        }
    }
}
