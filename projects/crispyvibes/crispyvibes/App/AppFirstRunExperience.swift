import Foundation

enum AppFirstRunExperience {
    enum AppSettings {
        static let appearancePreference = AppearancePreference.system
        static let themePreset = AppThemePreset.ph
        static let customThemePalette = AppThemePalette.ph
        static let codeFontFamily = AppCodeFontFamily.systemMonospaced
        static let codeFontSize: Double = 13.0
        static let railTerminalCompactFontSize: Double = 5.0
        static let railTerminalFontScale = TerminalRailFontScale.half
        static let terminalShellPreference = TerminalShellPreference.zsh
        static let sideMenuDockPosition = AppSideMenuDockPosition.right
        static let autoUpdateChecksEnabled = true
        static let textServiceCLIProfile = TextServiceCLIProfile.kiro
        static let textServiceCLITrustMode = CLITrustMode.standard
        static let textServiceDefaultAgent = ""
        static let textServiceRephrasePrompt = """
        Rewrite the text below to be clearer and smoother.
        Keep the original meaning.
        Return only the rewritten text.
        """
        static let textServiceResearchPrompt = """
        Improve the text below with concise, useful research context.
        Keep it accurate and practical.
        Return only the improved text.
        """

        static var customThemePaletteJSON: String {
            AppThemePalette.encodeToJSON(customThemePalette)
        }

        static var textServiceCLICommand: String {
            AppPreferences.defaultTextServiceCLIConfiguration(
                profile: textServiceCLIProfile,
                trustMode: textServiceCLITrustMode
            ).command
        }

        static var textServiceCLIArguments: String {
            AppPreferences.defaultTextServiceCLIConfiguration(
                profile: textServiceCLIProfile,
                trustMode: textServiceCLITrustMode
            ).arguments
        }

        static var textServicePassAgentFlag: Bool {
            AppPreferences.defaultTextServiceCLIConfiguration(
                profile: textServiceCLIProfile,
                trustMode: textServiceCLITrustMode
            ).passAgentFlag
        }

        static var authCognitoDomain: String {
            infoPlistString("CrispyVibesCognitoDomain") ?? "auth.crispyvibe.com"
        }

        static var authCognitoMacClientId: String {
            infoPlistString("CrispyVibesCognitoMacClientId") ?? ""
        }

        static var appUpdateFeedURL: String {
            infoPlistString("CrispyVibesAppUpdateFeedURL")
                ?? "https://crispyvibe.com/updates/macos/appcast.xml"
        }
    }

    enum Layout {
        static let defaultRailPosition = ProjectRailPosition.left
        static let defaultCanvasMode = VibeSpaceCanvasMode.detailed
        static let defaultTerminalOnlyLayoutOrientation = VibeSpaceTerminalOnlyLayoutOrientation.vertical
        static let defaultLeftRailWidth: Double = 300
        static let defaultRightRailWidth: Double = 300
        static let defaultTopRailHeight: Double = 250
        static let defaultBottomRailHeight: Double = 250
        static let defaultDetailedTerminalPaneHeight: Double = 300
        static let defaultVibeSpaceSidebarWidth: Double = 180
    }

    enum VibeSpace {
        static let defaultStartupTerminalCount = 1
        static let defaultStartupProfiles: [VibeSpaceTerminalStartupProfile] = [.empty]
        static let defaultFocusTerminalOnProjectSwitch = true
    }

    private static func infoPlistString(_ key: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}
