import SwiftUI

extension AppSettingsSheetView {
    var experimentalCategoryContent: some View {
        SettingsCard(
            title: AppStrings.Settings.Experimental.cardTitle,
            description: AppStrings.Settings.Experimental.cardDescription
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    isOn: Binding(
                        get: { experimentalACPObservability },
                        set: { isEnabled in
                            experimentalACPObservability = isEnabled
                            if !isEnabled {
                                experimentalACPObservabilityVerbose = false
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.Settings.Experimental.acpObservabilityTitle)
                            .font(AppTypographyTokens.settingsFieldTitle)
                        Text(AppStrings.Settings.Experimental.acpObservabilityDescription)
                            .font(AppTypographyTokens.settingsFieldDetail)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                    }
                }
                .accessibilityIdentifier("app.settings.experimental.acp-observability")
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $experimentalTerminalInsight) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Terminal Insight")
                            .font(AppTypographyTokens.settingsFieldTitle)
                        Text("Shows your last command at the top of each terminal.")
                            .font(AppTypographyTokens.settingsFieldDetail)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                    }
                }
                .accessibilityIdentifier("app.settings.experimental.terminal-insight")
                .toggleStyle(.switch)
            }
        }
    }
}
