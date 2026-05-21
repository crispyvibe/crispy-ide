import SwiftUI

struct AgentDockPreviewPanel: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: ACPStandaloneSessionStore
    let title: String
    let projects: [AnyProjectSession]
    let containerSize: CGSize
    let onPin: () -> Void
    let onDismiss: () -> Void

    private var panelWidth: CGFloat { containerSize.width * 0.85 }
    private var panelHeight: CGFloat { containerSize.height * 0.85 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ACPChatView(
                viewModel: store.chatViewModel,
                title: store.agentTitle,
                subtitle: store.selectedProject(from: projects)?.title,
                showsHeader: false,
                showsHeaderSessionControls: false,
                displayMode: .preview,
                historyKey: store.id,
                isConnecting: store.isConnecting,
                connectionError: store.connectionError,
                onReconnect: { Task { await store.connect(projects: projects) } },
                onLinkTargetActivated: nil,
                onFileSystemTargetActivated: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(palette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(palette.borderColorValue.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .accessibilityIdentifier("dock.agent-preview-panel")
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let agentID = store.selectedAgentID,
               let nsImage = ACPAgentRegistry.agentIconImage(for: agentID, size: 14) {
                Image(nsImage: nsImage)
                    .frame(width: uiScale.iconSize(14), height: uiScale.iconSize(14))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(AppTypographyTokens.scaledIcon(11))
                    .foregroundStyle(palette.secondaryTextColor)
            }
            Text(title)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1)
            Spacer()
            Button {
                onPin()
            } label: {
                Label("Pin to Dock", systemImage: "pin")
                    .font(AppTypographyTokens.caption2)
            }
            .buttonStyle(.crispyvibesPrimary)
            .controlSize(.small)
            .accessibilityIdentifier("dock.agent-preview-panel.pin")

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(AppTypographyTokens.scaledSystem(9, weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dock.agent-preview-panel.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.canvasSecondaryBackgroundColor)
    }
}
