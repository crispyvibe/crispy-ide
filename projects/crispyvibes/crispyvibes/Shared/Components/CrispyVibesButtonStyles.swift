import SwiftUI

/// Standard text button with hover feedback and neutral text color.
/// Icons use accent color via CrispyVibesIconButton; text buttons use this style.
struct CrispyVibesTextButtonStyle: ButtonStyle {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypographyTokens.scaledChromeSystem(12, weight: .semibold))
            .foregroundStyle(isEnabled ? palette.primaryTextColor : palette.secondaryTextColor)
            .padding(.horizontal, uiScale.spacing(10))
            .padding(.vertical, uiScale.spacing(5))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed
                        ? palette.canvasSecondaryBackgroundColor.opacity(0.8)
                        : palette.canvasSecondaryBackgroundColor.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.borderColorValue.opacity(0.5), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Primary action text button — uses accent background with contrasting text.
struct CrispyVibesPrimaryButtonStyle: ButtonStyle {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypographyTokens.scaledChromeSystem(12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, uiScale.spacing(10))
            .padding(.vertical, uiScale.spacing(5))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed
                        ? palette.accentColor.opacity(0.7)
                        : palette.accentColor)
            )
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ButtonStyle where Self == CrispyVibesTextButtonStyle {
    static var crispyvibesText: CrispyVibesTextButtonStyle { CrispyVibesTextButtonStyle() }
}

extension ButtonStyle where Self == CrispyVibesPrimaryButtonStyle {
    static var crispyvibesPrimary: CrispyVibesPrimaryButtonStyle { CrispyVibesPrimaryButtonStyle() }
}
