import AppKit
import SwiftUI

struct ExternalAgentSessionPreviewPanel: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let transcript: ExternalAgentTranscript
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            metadata
                            ForEach(transcript.entries.prefix(200)) { entry in
                                transcriptEntry(entry)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(
                    width: min(max(proxy.size.width * 0.72, 720), proxy.size.width - 80),
                    height: min(max(proxy.size.height * 0.78, 520), proxy.size.height - 80)
                )
                .background(palette.canvasBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.borderColorValue.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .accessibilityIdentifier("external-agent-session.preview-panel")
    }

    private var header: some View {
        HStack(spacing: 9) {
            providerIcon(transcript.session.provider)
            VStack(alignment: .leading, spacing: 2) {
                Text(transcript.session.title)
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)
                Text("\(transcript.session.providerName) - \(transcript.session.projectDisplayName)")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(AppStrings.Sidebar.ExternalSessions.copyResumeCommand) {
                copy(transcript.session.resumeCommand)
            }
            .buttonStyle(.crispyvibesPrimary)
            .controlSize(.small)
            CrispyVibesIconButton(systemName: "xmark.circle.fill", size: 12, padding: 4, color: palette.secondaryTextColor, accessibilityLabel: AppStrings.Common.close) {
                onDismiss()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.canvasSecondaryBackgroundColor)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            labeledValue(AppStrings.Sidebar.ExternalSessions.sourcePath, transcript.session.sourcePath)
            labeledValue(AppStrings.Sidebar.ExternalSessions.sessionId, transcript.session.sessionId)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(AppTypographyTokens.caption2Semibold)
                .foregroundStyle(palette.secondaryTextColor)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func transcriptEntry(_ entry: ExternalAgentTranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.role.capitalized)
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(palette.secondaryTextColor)
                if !entry.timestamp.isEmpty {
                    Text(entry.timestamp)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor.opacity(0.7))
                }
            }
            ACPSelectableText(
                text: entry.text,
                foregroundColor: palette.primaryTextColor,
                onLinkTargetActivated: nil,
                onFileSystemTargetActivated: nil
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func providerIcon(_ provider: ExternalAgentSessionProvider) -> some View {
        let symbol: String = switch provider {
        case .codex: "sparkles"
        case .claude: "c.circle"
        case .kiro: "ghost.fill"
        }
        Image(systemName: symbol)
            .font(AppTypographyTokens.scaledIcon(12))
            .foregroundStyle(palette.accentColor)
            .frame(width: uiScale.iconSize(16))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
