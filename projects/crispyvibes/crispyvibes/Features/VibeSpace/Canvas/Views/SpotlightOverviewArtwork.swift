import SwiftUI

/// Metadata-only artwork for a Spotlight overview tile. It never reads live content.
@MainActor
struct SpotlightOverviewArtwork: View {
    @Environment(\.appThemePalette) private var palette
    let entry: SpotlightItemMetadata
    let compact: Bool

    var body: some View {
        ZStack {
            palette.canvasSecondaryBackgroundColor
            artwork
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch entry.item {
        case .terminal, .standaloneTerminal:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.activityState?.isActive == true
                            ? (entry.accentColor ?? palette.accentColor)
                            : palette.secondaryTextColor.opacity(0.42))
                        .frame(width: 7, height: 7)
                    Text(entry.secondary)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                }
                ForEach(Array(entry.statusLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(AppTypographyTokens.scaledSystem(compact ? 9 : 10, design: .monospaced))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(compact ? 14 : 18)
        case .browser:
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.secondary)
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: compact ? 23 : 28)
                    .background(palette.canvasBackgroundColor, in: RoundedRectangle(cornerRadius: 6))
                Label(entry.title, systemImage: "globe")
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
            }
            .padding(compact ? 14 : 18)
        case .file:
            Label {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title).font(AppTypographyTokens.captionSemibold)
                    Text(entry.secondary).font(AppTypographyTokens.caption2)
                }
            } icon: {
                Image(systemName: "doc.text")
                    .font(AppTypographyTokens.scaledSystem(compact ? 30 : 42, weight: .light))
            }
            .foregroundStyle(palette.secondaryTextColor)
        case .acp:
            icon("sparkles")
        case .vibeCast:
            icon("antenna.radiowaves.left.and.right")
        case .vibeLanes:
            icon(VibeLaneVisualIdentity.symbolName)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(AppTypographyTokens.scaledSystem(compact ? 34 : 46, weight: .light))
            .foregroundStyle(palette.secondaryTextColor.opacity(0.65))
    }
}
