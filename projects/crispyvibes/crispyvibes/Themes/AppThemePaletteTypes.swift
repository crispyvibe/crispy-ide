import SwiftUI

enum AppThemePreset: String, CaseIterable, Identifiable {
    case system
    case midnightMono
    case graphiteDark
    case oceanDusk
    case forestNight
    case nordFrost
    case draculaNight
    case solarizedNight
    case sunlitPaper
    case pearlLight
    case mintLight
    case latteBloom
    case alucardLight
    case beachDay
    case mallGoth
    case gasStationSlushie
    case citrusDeadline
    case mossyFaxMachine
    case arcadeCarpet
    case tomatoBisque
    case poolTile
    case radioactiveSpreadsheet
    case christmas
    case stPatrick
    case diwali
    case fourthOfJuly
    case ph
    case gruvboxDark
    case rosePine
    case tokyoNight
    case mochaMood
    case lavenderHaze
    case highContrast
    case valentine
    case oneDark
    case synthwave84
    case halloween
    case rosePineDawn
    case highContrastLight
    case blossomPink
    case midnightPink
    case kintsugi
    case ukiyoe
    case yushi
    case denglong
    case shuimo
    case sichou
    case hanbok
    case cheongja
    case dancheong
    case mehendi
    case rangoli
    case mayur
    case tiranga
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System Vibes"
        case .midnightMono:
            return "Midnight Mono Vibes"
        case .graphiteDark:
            return "Graphite Dark Vibes"
        case .oceanDusk:
            return "Ocean Dusk Vibes"
        case .forestNight:
            return "Forest Night Vibes"
        case .nordFrost:
            return "Nord Frost Vibes"
        case .draculaNight:
            return "Dracula Night Vibes"
        case .solarizedNight:
            return "Solarized Night Vibes"
        case .sunlitPaper:
            return "Sunlit Paper Vibes"
        case .pearlLight:
            return "Pearl Light Vibes"
        case .mintLight:
            return "Mint Light Vibes"
        case .latteBloom:
            return "Latte Bloom Vibes"
        case .alucardLight:
            return "Alucard Light Vibes"
        case .beachDay:
            return "Beach Day Vibes"
        case .mallGoth:
            return "Mall Goth Vibes"
        case .gasStationSlushie:
            return "Gas Station Slushie Vibes"
        case .citrusDeadline:
            return "Citrus Deadline Vibes"
        case .mossyFaxMachine:
            return "Mossy Fax Machine Vibes"
        case .arcadeCarpet:
            return "Arcade Carpet Vibes"
        case .tomatoBisque:
            return "Tomato Bisque Vibes"
        case .poolTile:
            return "Pool Tile Vibes"
        case .radioactiveSpreadsheet:
            return "Radioactive Spreadsheet Vibes"
        case .christmas:
            return "Christmas Vibes"
        case .stPatrick:
            return "St. Patrick Vibes"
        case .diwali:
            return "Diwali Vibes"
        case .fourthOfJuly:
            return "4th of July Vibes"
        case .ph:
            return "After Hours Vibes"
        case .gruvboxDark:
            return "Gruvbox Dark Vibes"
        case .rosePine:
            return "Rosé Pine Vibes"
        case .tokyoNight:
            return "Tokyo Night Vibes"
        case .mochaMood:
            return "Mocha Mood Vibes"
        case .lavenderHaze:
            return "Lavender Haze Vibes"
        case .highContrast:
            return "High Contrast Vibes"
        case .valentine:
            return "Valentine Vibes"
        case .oneDark:
            return "One Dark Vibes"
        case .synthwave84:
            return "Synthwave '84 Vibes"
        case .halloween:
            return "Halloween Vibes"
        case .rosePineDawn:
            return "Rosé Pine Dawn Vibes"
        case .highContrastLight:
            return "High Contrast Light Vibes"
        case .blossomPink:
            return "Blossom Pink Vibes"
        case .midnightPink:
            return "Midnight Pink Vibes"
        case .kintsugi:
            return "Kintsugi (金継ぎ) Vibes"
        case .ukiyoe:
            return "Ukiyo-e (浮世絵) Vibes"
        case .yushi:
            return "Yùshí (玉石) Vibes"
        case .denglong:
            return "Dēnglóng (灯笼) Vibes"
        case .shuimo:
            return "Shuǐmò (水墨) Vibes"
        case .sichou:
            return "Sīchóu (丝绸) Vibes"
        case .hanbok:
            return "Hanbok (한복) Vibes"
        case .cheongja:
            return "Cheongja (청자) Vibes"
        case .dancheong:
            return "Dancheong (단청) Vibes"
        case .mehendi:
            return "Mehendi (मेहंदी) Vibes"
        case .rangoli:
            return "Rangoli (रंगोली) Vibes"
        case .mayur:
            return "Mayur (मयूर) Vibes"
        case .tiranga:
            return "Tiranga (तिरंगा) Vibes"
        case .custom:
            return "Custom Vibes"
        }
    }
}

enum AppThemeColorRole: String, CaseIterable, Identifiable {
    case windowBackground
    case canvasBackground
    case canvasSecondaryBackground
    case borderColor
    case accent
    case success
    case warning
    case error
    case selectionBackground
    case terminalForeground

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowBackground:
            return "Window"
        case .canvasBackground:
            return "Canvas"
        case .canvasSecondaryBackground:
            return "Canvas Secondary"
        case .borderColor:
            return "Border"
        case .accent:
            return "Accent"
        case .success:
            return "Success"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        case .selectionBackground:
            return "Selection Background"
        case .terminalForeground:
            return "Terminal Foreground"
        }
    }

    var usageDetail: String {
        switch self {
        case .windowBackground:
            return "Window frame and title bar chrome."
        case .canvasBackground:
            return "Primary pane/canvas surface behind core content."
        case .canvasSecondaryBackground:
            return "Secondary pane cards, tool sections, and elevated surfaces."
        case .borderColor:
            return "Split lines, strokes, and separator outlines."
        case .accent:
            return "Primary interactive emphasis, highlights, and active controls."
        case .success:
            return "Positive statuses and completion indicators."
        case .warning:
            return "Warning and caution statuses."
        case .error:
            return "Error and destructive states."
        case .selectionBackground:
            return "Selection highlight color for selected content."
        case .terminalForeground:
            return "Default editor and terminal text color."
        }
    }

    var keyPath: WritableKeyPath<AppThemePalette, ProjectColorTag> {
        switch self {
        case .windowBackground:
            return \.windowBackground
        case .canvasBackground:
            return \.canvasBackground
        case .canvasSecondaryBackground:
            return \.canvasSecondaryBackground
        case .borderColor:
            return \.borderColor
        case .accent:
            return \.accent
        case .success:
            return \.success
        case .warning:
            return \.warning
        case .error:
            return \.error
        case .selectionBackground:
            return \.selectionBackground
        case .terminalForeground:
            return \.terminalForeground
        }
    }
}
