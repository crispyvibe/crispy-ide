// SSHHostKeyPromptView.swift — SSH Remote Development

import SwiftUI

/// Prompt shown when connecting to an unknown SSH host for the first time.
struct SSHHostKeyPromptView: View {
    let host: String
    let fingerprint: String
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield").font(AppTypographyTokens.title2).foregroundStyle(.orange)
                Text("Unknown Host Key").font(AppTypographyTokens.headline)
            }

            Text("The authenticity of host '\(host)' can't be established.")
                .font(AppTypographyTokens.callout)

            Text(fingerprint)
                .font(AppTypographyTokens.captionMonospaced)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

            Text("Are you sure you want to continue connecting?")
                .font(AppTypographyTokens.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Reject") { onReject() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Accept & Connect") { onAccept() }
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
