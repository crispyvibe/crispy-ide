import SwiftUI

extension AppSettingsSheetView {
    var terminalEngineCard: some View {
        SettingsCard(
            title: "Rendering Engine",
            description: "Selects the terminal rendering backend used for new terminal views."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terminal engine")
                        .font(AppTypographyTokens.settingsFieldTitle)
                    Text("Ghostty is the default renderer. SwiftTerm remains available as a compatibility fallback.")
                        .font(AppTypographyTokens.settingsFieldDetail)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                    Picker("", selection: terminalEngineBinding) {
                        Text("Ghostty").tag("ghostty")
                        Text("SwiftTerm").tag("swiftterm")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                .accessibilityIdentifier("app.settings.terminal.engine")
            }
        }
    }
}
