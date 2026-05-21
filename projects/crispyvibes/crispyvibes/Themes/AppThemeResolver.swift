import SwiftUI

enum AppThemeResolver {
    static func resolvedColorScheme(
        appearancePreferenceRaw: String,
        fallbackSystemColorScheme: ColorScheme
    ) -> ColorScheme {
        let selectedAppearance = AppearancePreference(rawValue: appearancePreferenceRaw) ?? .system
        return selectedAppearance.colorScheme ?? fallbackSystemColorScheme
    }

    static func palette(
        appearancePreferenceRaw: String,
        fallbackSystemColorScheme: ColorScheme,
        themePresetRaw: String,
        customThemeJSON: String
    ) -> AppThemePalette {
        let resolvedScheme = resolvedColorScheme(
            appearancePreferenceRaw: appearancePreferenceRaw,
            fallbackSystemColorScheme: fallbackSystemColorScheme
        )
        let preset = AppThemePreset(rawValue: themePresetRaw) ?? .system

        switch preset {
        case .system:
            return resolvedScheme == .dark ? .systemDark : .systemLight
        case .midnightMono:
            return .midnightMono
        case .graphiteDark:
            return .graphiteDark
        case .oceanDusk:
            return .oceanDusk
        case .forestNight:
            return .forestNight
        case .nordFrost:
            return .nordFrost
        case .draculaNight:
            return .draculaNight
        case .solarizedNight:
            return .solarizedNight
        case .sunlitPaper:
            return .sunlitPaper
        case .pearlLight:
            return .pearlLight
        case .mintLight:
            return .mintLight
        case .latteBloom:
            return .latteBloom
        case .alucardLight:
            return .alucardLight
        case .beachDay:
            return .beachDay
        case .mallGoth:
            return .mallGoth
        case .gasStationSlushie:
            return .gasStationSlushie
        case .citrusDeadline:
            return .citrusDeadline
        case .mossyFaxMachine:
            return .mossyFaxMachine
        case .arcadeCarpet:
            return .arcadeCarpet
        case .tomatoBisque:
            return .tomatoBisque
        case .poolTile:
            return .poolTile
        case .radioactiveSpreadsheet:
            return .radioactiveSpreadsheet
        case .christmas:
            return .christmas
        case .stPatrick:
            return .stPatrick
        case .diwali:
            return .diwali
        case .fourthOfJuly:
            return .fourthOfJuly
        case .ph:
            return .ph
        case .gruvboxDark:
            return .gruvboxDark
        case .rosePine:
            return .rosePine
        case .tokyoNight:
            return .tokyoNight
        case .mochaMood:
            return .mochaMood
        case .lavenderHaze:
            return .lavenderHaze
        case .highContrast:
            return .highContrast
        case .valentine:
            return .valentine
        case .oneDark:
            return .oneDark
        case .synthwave84:
            return .synthwave84
        case .halloween:
            return .halloween
        case .rosePineDawn:
            return .rosePineDawn
        case .highContrastLight:
            return .highContrastLight
        case .blossomPink:
            return .blossomPink
        case .midnightPink:
            return .midnightPink
        case .kintsugi:
            return .kintsugi
        case .ukiyoe:
            return .ukiyoe
        case .yushi:
            return .yushi
        case .denglong:
            return .denglong
        case .shuimo:
            return .shuimo
        case .sichou:
            return .sichou
        case .hanbok:
            return .hanbok
        case .cheongja:
            return .cheongja
        case .dancheong:
            return .dancheong
        case .mehendi:
            return .mehendi
        case .rangoli:
            return .rangoli
        case .mayur:
            return .mayur
        case .tiranga:
            return .tiranga
        case .custom:
            return AppThemePalette.decodeFromJSON(customThemeJSON)
                ?? (resolvedScheme == .dark ? .systemDark : .systemLight)
        }
    }

    static func preferredColorScheme(
        appearancePreferenceRaw: String,
        fallbackSystemColorScheme: ColorScheme,
        themePresetRaw: String,
        customThemeJSON: String
    ) -> ColorScheme? {
        let selectedAppearance = AppearancePreference(rawValue: appearancePreferenceRaw) ?? .system
        let preset = AppThemePreset(rawValue: themePresetRaw) ?? .system

        if preset == .system {
            return selectedAppearance.colorScheme
        }

        return palette(
            appearancePreferenceRaw: appearancePreferenceRaw,
            fallbackSystemColorScheme: fallbackSystemColorScheme,
            themePresetRaw: themePresetRaw,
            customThemeJSON: customThemeJSON
        ).preferredColorScheme
    }
}
