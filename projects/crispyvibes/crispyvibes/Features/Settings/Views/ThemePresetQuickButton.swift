import SwiftUI

struct ThemePresetQuickButton: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let preset: AppThemePreset
    let palette: AppThemePalette
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    swatch(palette.windowBackgroundColor)
                    swatch(palette.canvasBackgroundColor)
                    swatch(palette.canvasSecondaryBackgroundColor)
                    swatch(palette.borderColorValue)
                    swatch(palette.accentColor)
                }
                Text(preset.title)
                    .font(AppTypographyTokens.captionSemibold)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8))
                    .fill(
                        isSelected
                            ? appThemePalette.selectionBackgroundColor.opacity(0.40)
                            : appThemePalette.canvasSecondaryBackgroundColor.opacity(0.2)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8))
                    .stroke(
                        isSelected
                            ? appThemePalette.borderColorValue
                            : appThemePalette.borderColorValue.opacity(0.45),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: crispyvibesTheme.radius(3))
            .fill(color)
            .frame(width: 16, height: 10)
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(3))
                    .stroke(appThemePalette.borderColorValue.opacity(0.55), lineWidth: 1)
            )
    }
}
