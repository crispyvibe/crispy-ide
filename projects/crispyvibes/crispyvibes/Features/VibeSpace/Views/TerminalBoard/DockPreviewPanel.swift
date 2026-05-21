import SwiftUI

struct DockPreviewPanel: View {
    @Environment(\.appThemePalette) private var appThemePalette
    let fileURL: URL
    @ObservedObject var editorGroup: EditorGroupStore
    let containerSize: CGSize
    let onPin: () -> Void
    let onDismiss: () -> Void

    private var panelWidth: CGFloat { containerSize.width * 0.85 }
    private var panelHeight: CGFloat { containerSize.height * 0.85 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MarkdownEditorView(
                viewModel: editorGroup.markdownViewModel,
                showsTopBar: false,
                headerLayout: .embedded
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(appThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(appThemePalette.borderColorValue.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .accessibilityIdentifier("dock.preview-panel")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(AppTypographyTokens.scaledSystem(11))
                .foregroundStyle(appThemePalette.secondaryTextColor)
            Text(fileURL.lastPathComponent)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(appThemePalette.primaryTextColor)
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
            .accessibilityIdentifier("dock.preview-panel.pin")

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(AppTypographyTokens.scaledSystem(9, weight: .semibold))
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dock.preview-panel.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(appThemePalette.canvasSecondaryBackgroundColor)
    }
}
