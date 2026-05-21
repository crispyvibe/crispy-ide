import SwiftUI

struct SettingsDetailPanel<Content: View>: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(appThemePalette.canvasBackgroundColor)
    }
}

struct SettingsCategoryHeader: View {
    @Environment(\.appThemePalette) private var appThemePalette
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypographyTokens.settingsCategoryHeaderTitle)
            Text(description)
                .font(AppTypographyTokens.settingsHeaderSubtitle)
                .foregroundStyle(appThemePalette.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let title: String
    let description: String?
    @ViewBuilder let content: () -> Content

    private var isDarkPalette: Bool {
        appThemePalette.prefersDarkWindowChrome
    }

    private var cardBackgroundColor: Color {
        appThemePalette.canvasSecondaryBackgroundColor.opacity(isDarkPalette ? 0.62 : 0.92)
    }

    private var cardBorderColor: Color {
        appThemePalette.borderColorValue.opacity(isDarkPalette ? 0.38 : 0.22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypographyTokens.settingsCardTitle)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(AppTypographyTokens.settingsFieldDetail)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                }
            }

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }
}

struct SettingsFieldRow<Control: View>: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesUIScale) private var uiScale
    let title: String
    let detail: String?
    var labelWidth: CGFloat = 198
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypographyTokens.settingsFieldTitle)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppTypographyTokens.settingsFieldDetail)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: labelWidth, alignment: .leading)

            control()
                .font(AppTypographyTokens.scaledChromeSystem(13))
                .controlSize(uiScale.controlSize)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
