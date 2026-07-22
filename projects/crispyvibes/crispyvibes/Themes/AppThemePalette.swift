import AppKit
import SwiftUI

struct AppThemePalette: Codable, Equatable {
    var windowBackground: ProjectColorTag
    var canvasBackground: ProjectColorTag
    var canvasSecondaryBackground: ProjectColorTag
    var borderColor: ProjectColorTag
    var accent: ProjectColorTag
    var success: ProjectColorTag
    var warning: ProjectColorTag
    var error: ProjectColorTag
    var selectionBackground: ProjectColorTag
    var terminalForeground: ProjectColorTag
    var mutedForeground: ProjectColorTag

    init(
        windowBackground: ProjectColorTag,
        canvasBackground: ProjectColorTag,
        canvasSecondaryBackground: ProjectColorTag,
        borderColor: ProjectColorTag,
        accent: ProjectColorTag,
        success: ProjectColorTag,
        warning: ProjectColorTag,
        error: ProjectColorTag,
        selectionBackground: ProjectColorTag,
        terminalForeground: ProjectColorTag,
        mutedForeground: ProjectColorTag? = nil
    ) {
        self.windowBackground = windowBackground
        self.canvasBackground = canvasBackground
        self.canvasSecondaryBackground = canvasSecondaryBackground
        self.borderColor = borderColor
        self.accent = accent
        self.success = success
        self.warning = warning
        self.error = error
        self.selectionBackground = selectionBackground
        self.terminalForeground = terminalForeground
        self.mutedForeground = mutedForeground
            ?? Self.legacyMutedForeground(terminalForeground: terminalForeground, borderColor: borderColor)
    }

    // Fallback for palettes authored before mutedForeground existed (e.g. persisted
    // custom themes): reproduces the old secondary-text blend so they keep their look.
    private static func legacyMutedForeground(
        terminalForeground: ProjectColorTag,
        borderColor: ProjectColorTag
    ) -> ProjectColorTag {
        ProjectColorTag(
            red: terminalForeground.red * 0.54 + borderColor.red * 0.46,
            green: terminalForeground.green * 0.54 + borderColor.green * 0.46,
            blue: terminalForeground.blue * 0.54 + borderColor.blue * 0.46,
            alpha: terminalForeground.alpha * 0.54 + borderColor.alpha * 0.46
        )
    }

    static let midnightMono = AppThemePalette(
        windowBackground: colorToken("#0C1118"),
        canvasBackground: colorToken("#000000"),
        canvasSecondaryBackground: colorToken("#0E1420"),
        borderColor: colorToken("#3A4558"),
        accent: colorToken("#6BA4FF"),
        success: colorToken("#53D8A5"),
        warning: colorToken("#E3B36D"),
        error: colorToken("#E06F78"),
        selectionBackground: colorToken("#004CD5"),
        terminalForeground: colorToken("#DCE3EF"),
        mutedForeground: colorToken("#878B93")
    )

    static let graphiteDark = AppThemePalette(
        windowBackground: colorToken("#0B1118"),
        canvasBackground: colorToken("#10151E"),
        canvasSecondaryBackground: colorToken("#1A2230"),
        borderColor: colorToken("#3D4F6C"),
        accent: colorToken("#8AA8FF"),
        success: colorToken("#5FD7B8"),
        warning: colorToken("#E5B56D"),
        error: colorToken("#E37D87"),
        selectionBackground: colorToken("#0042ED"),
        terminalForeground: colorToken("#DFE6F2"),
        mutedForeground: colorToken("#9097A1")
    )

    static let systemLight = AppThemePalette(
        windowBackground: colorToken("#F0F0F0"),
        canvasBackground: colorToken("#FFFFFF"),
        canvasSecondaryBackground: colorToken("#F7F8FA"),
        borderColor: colorToken("#C9C9C9"),
        accent: colorToken("#005FB8"),
        success: colorToken("#2E9F43"),
        warning: colorToken("#895503"),
        error: colorToken("#F84E46"),
        selectionBackground: colorToken("#BED6ED"),
        terminalForeground: colorToken("#3B3B3B"),
        mutedForeground: colorToken("#616161")
    )

    static let systemDark = AppThemePalette(
        windowBackground: colorToken("#181818"),
        canvasBackground: colorToken("#1F1F1F"),
        canvasSecondaryBackground: colorToken("#222222"),
        borderColor: colorToken("#424242"),
        accent: colorToken("#0078D4"),
        success: colorToken("#2EA043"),
        warning: colorToken("#9E6A03"),
        error: colorToken("#F85149"),
        selectionBackground: colorToken("#264778"),
        terminalForeground: colorToken("#CCCCCC"),
        mutedForeground: colorToken("#969696")
    )

    static let oceanDusk = AppThemePalette(
        windowBackground: colorToken("#0A1721"),
        canvasBackground: colorToken("#0E1E2B"),
        canvasSecondaryBackground: colorToken("#153042"),
        borderColor: colorToken("#315772"),
        accent: colorToken("#57B7FF"),
        success: colorToken("#3ED6A4"),
        warning: colorToken("#E8BC74"),
        error: colorToken("#E67A86"),
        selectionBackground: colorToken("#005C9B"),
        terminalForeground: colorToken("#D7E8F3"),
        mutedForeground: colorToken("#94A5B1")
    )

    static let forestNight = AppThemePalette(
        windowBackground: colorToken("#0D1613"),
        canvasBackground: colorToken("#111D18"),
        canvasSecondaryBackground: colorToken("#1D2F28"),
        borderColor: colorToken("#425647"),
        accent: colorToken("#79D39A"),
        success: colorToken("#6EDFB2"),
        warning: colorToken("#E6C17A"),
        error: colorToken("#E89191"),
        selectionBackground: colorToken("#216635"),
        terminalForeground: colorToken("#DEE9E2"),
        mutedForeground: colorToken("#98A39D")
    )

    static let nordFrost = AppThemePalette(
        windowBackground: colorToken("#2E3440"),
        canvasBackground: colorToken("#3B4252"),
        canvasSecondaryBackground: colorToken("#434C5E"),
        borderColor: colorToken("#576279"),
        accent: colorToken("#88C0D0"),
        success: colorToken("#A3BE8C"),
        warning: colorToken("#EBCB8B"),
        error: colorToken("#D08B92"),
        selectionBackground: colorToken("#3C5C7B"),
        terminalForeground: colorToken("#ECEFF4"),
        mutedForeground: colorToken("#C9CDD4")
    )

    static let draculaNight = AppThemePalette(
        windowBackground: colorToken("#191A21"),
        canvasBackground: colorToken("#282A36"),
        canvasSecondaryBackground: colorToken("#343746"),
        borderColor: colorToken("#44475A"),
        accent: colorToken("#BD93F9"),
        success: colorToken("#50FA7B"),
        warning: colorToken("#FFB86C"),
        error: colorToken("#FF5555"),
        selectionBackground: colorToken("#4B5881"),
        terminalForeground: colorToken("#F8F8F2"),
        mutedForeground: colorToken("#AFB0B0")
    )

    static let solarizedNight = AppThemePalette(
        windowBackground: colorToken("#002B36"),
        canvasBackground: colorToken("#073642"),
        canvasSecondaryBackground: colorToken("#0B3A46"),
        borderColor: colorToken("#586E75"),
        accent: colorToken("#268BD2"),
        success: colorToken("#859900"),
        warning: colorToken("#B58900"),
        error: colorToken("#E1504E"),
        selectionBackground: colorToken("#484EB2"),
        terminalForeground: colorToken("#B2BCBC"),
        mutedForeground: colorToken("#A1AEB0")
    )

    static let sunlitPaper = AppThemePalette(
        windowBackground: colorToken("#F5EFE3"),
        canvasBackground: colorToken("#FFFDF7"),
        canvasSecondaryBackground: colorToken("#FAF5E8"),
        borderColor: colorToken("#AFADA8"),
        accent: colorToken("#2767D8"),
        success: colorToken("#2F8A57"),
        warning: colorToken("#A06D10"),
        error: colorToken("#CC4A4A"),
        selectionBackground: colorToken("#D6E4FF"),
        terminalForeground: colorToken("#2E2B26"),
        mutedForeground: colorToken("#64615C")
    )

    static let pearlLight = AppThemePalette(
        windowBackground: colorToken("#F3ECE5"),
        canvasBackground: colorToken("#FFFCF9"),
        canvasSecondaryBackground: colorToken("#F8F3EE"),
        borderColor: colorToken("#B0ACA6"),
        accent: colorToken("#2E6EDB"),
        success: colorToken("#2E8A62"),
        warning: colorToken("#A06E14"),
        error: colorToken("#C74E4E"),
        selectionBackground: colorToken("#DDE8FF"),
        terminalForeground: colorToken("#2B2925"),
        mutedForeground: colorToken("#625F5C")
    )

    static let mintLight = AppThemePalette(
        windowBackground: colorToken("#EAF4EF"),
        canvasBackground: colorToken("#F7FFFB"),
        canvasSecondaryBackground: colorToken("#F1FAF5"),
        borderColor: colorToken("#9DB2A7"),
        accent: colorToken("#1E7C67"),
        success: colorToken("#2B8E6F"),
        warning: colorToken("#8A6A1A"),
        error: colorToken("#BE5058"),
        selectionBackground: colorToken("#CFECE2"),
        terminalForeground: colorToken("#22312B"),
        mutedForeground: colorToken("#586560")
    )

    static let latteBloom = AppThemePalette(
        windowBackground: colorToken("#DCE0E8"),
        canvasBackground: colorToken("#EFF1F5"),
        canvasSecondaryBackground: colorToken("#E6E9EF"),
        borderColor: colorToken("#9CA0B0"),
        accent: colorToken("#1E66F5"),
        success: colorToken("#3B9328"),
        warning: colorToken("#B47317"),
        error: colorToken("#D20F39"),
        selectionBackground: colorToken("#A0AEFE"),
        terminalForeground: colorToken("#494C65"),
        mutedForeground: colorToken("#53566E")
    )

    static let alucardLight = AppThemePalette(
        windowBackground: colorToken("#BCBAB3"),
        canvasBackground: colorToken("#DEDCCF"),
        canvasSecondaryBackground: colorToken("#ECE9DF"),
        borderColor: colorToken("#9E9A8F"),
        accent: colorToken("#007CCE"),
        success: colorToken("#088C08"),
        warning: colorToken("#857A10"),
        error: colorToken("#D54723"),
        selectionBackground: colorToken("#BCA9E9"),
        terminalForeground: colorToken("#2C2A26"),
        mutedForeground: colorToken("#413F3A")
    )

    static let beachDay = AppThemePalette(
        windowBackground: colorToken("#EEE8D5"),
        canvasBackground: colorToken("#FDF6E3"),
        canvasSecondaryBackground: colorToken("#F8F1DE"),
        borderColor: colorToken("#93A1A1"),
        accent: colorToken("#268BD2"),
        success: colorToken("#7D8F00"),
        warning: colorToken("#AA8100"),
        error: colorToken("#DC322F"),
        selectionBackground: colorToken("#ADB0DE"),
        terminalForeground: colorToken("#46555B"),
        mutedForeground: colorToken("#515F63")
    )

    static let mallGoth = AppThemePalette(
        windowBackground: colorToken("#120E16"),
        canvasBackground: colorToken("#1A1321"),
        canvasSecondaryBackground: colorToken("#261A2E"),
        borderColor: colorToken("#5D466C"),
        accent: colorToken("#FF7BD5"),
        success: colorToken("#85E0B1"),
        warning: colorToken("#F4B96E"),
        error: colorToken("#FF667D"),
        selectionBackground: colorToken("#6B3C83"),
        terminalForeground: colorToken("#F3E8F6"),
        mutedForeground: colorToken("#99909E")
    )

    static let gasStationSlushie = AppThemePalette(
        windowBackground: colorToken("#07141A"),
        canvasBackground: colorToken("#0A232B"),
        canvasSecondaryBackground: colorToken("#113743"),
        borderColor: colorToken("#325B65"),
        accent: colorToken("#27F0FF"),
        success: colorToken("#88FFB8"),
        warning: colorToken("#FFE066"),
        error: colorToken("#FF4FA0"),
        selectionBackground: colorToken("#0E728D"),
        terminalForeground: colorToken("#E7FCFF"),
        mutedForeground: colorToken("#96ADB2")
    )

    static let citrusDeadline = AppThemePalette(
        windowBackground: colorToken("#FFF0C2"),
        canvasBackground: colorToken("#FFF8E2"),
        canvasSecondaryBackground: colorToken("#FFE9B6"),
        borderColor: colorToken("#D2A155"),
        accent: colorToken("#F23F00"),
        success: colorToken("#2D945B"),
        warning: colorToken("#A87B0D"),
        error: colorToken("#D94A57"),
        selectionBackground: colorToken("#E8A84A"),
        terminalForeground: colorToken("#3E2B17"),
        mutedForeground: colorToken("#6C5C47")
    )

    static let mossyFaxMachine = AppThemePalette(
        windowBackground: colorToken("#E6E1D1"),
        canvasBackground: colorToken("#F2EBDD"),
        canvasSecondaryBackground: colorToken("#DDD6C1"),
        borderColor: colorToken("#A3A285"),
        accent: colorToken("#556B2F"),
        success: colorToken("#2B8453"),
        warning: colorToken("#936E24"),
        error: colorToken("#A9534D"),
        selectionBackground: colorToken("#B7C59A"),
        terminalForeground: colorToken("#2F3827"),
        mutedForeground: colorToken("#4E5444")
    )

    static let arcadeCarpet = AppThemePalette(
        windowBackground: colorToken("#1B1020"),
        canvasBackground: colorToken("#261127"),
        canvasSecondaryBackground: colorToken("#351A32"),
        borderColor: colorToken("#7A3A63"),
        accent: colorToken("#00D5FF"),
        success: colorToken("#5FF2A5"),
        warning: colorToken("#FFB347"),
        error: colorToken("#FF5A7A"),
        selectionBackground: colorToken("#A83878"),
        terminalForeground: colorToken("#F7E7F3"),
        mutedForeground: colorToken("#A593A3")
    )

    static let tomatoBisque = AppThemePalette(
        windowBackground: colorToken("#F7D9CC"),
        canvasBackground: colorToken("#FFF1EA"),
        canvasSecondaryBackground: colorToken("#FBDCCF"),
        borderColor: colorToken("#C79D94"),
        accent: colorToken("#D44832"),
        success: colorToken("#2D8D5E"),
        warning: colorToken("#A97212"),
        error: colorToken("#BA2F3B"),
        selectionBackground: colorToken("#F4B4A1"),
        terminalForeground: colorToken("#3C231F"),
        mutedForeground: colorToken("#69524D")
    )

    static let poolTile = AppThemePalette(
        windowBackground: colorToken("#DDF4F7"),
        canvasBackground: colorToken("#F2FDFF"),
        canvasSecondaryBackground: colorToken("#CBEFF2"),
        borderColor: colorToken("#88B3BD"),
        accent: colorToken("#008CAF"),
        success: colorToken("#15896B"),
        warning: colorToken("#A37A1A"),
        error: colorToken("#C94E63"),
        selectionBackground: colorToken("#8EDAE5"),
        terminalForeground: colorToken("#17333C"),
        mutedForeground: colorToken("#496168")
    )

    static let radioactiveSpreadsheet = AppThemePalette(
        windowBackground: colorToken("#0A130A"),
        canvasBackground: colorToken("#101C10"),
        canvasSecondaryBackground: colorToken("#162816"),
        borderColor: colorToken("#385926"),
        accent: colorToken("#B8FF3B"),
        success: colorToken("#6CFF9B"),
        warning: colorToken("#FFD84C"),
        error: colorToken("#FF5D64"),
        selectionBackground: colorToken("#355F18"),
        terminalForeground: colorToken("#E6FFD4"),
        mutedForeground: colorToken("#8A9E80")
    )

    static let christmas = AppThemePalette(
        windowBackground: colorToken("#0E1A13"),
        canvasBackground: colorToken("#132319"),
        canvasSecondaryBackground: colorToken("#1B3224"),
        borderColor: colorToken("#7E2D33"),
        accent: colorToken("#D94452"),
        success: colorToken("#3FBF6F"),
        warning: colorToken("#E0B94A"),
        error: colorToken("#FF6B6B"),
        selectionBackground: colorToken("#9C3040"),
        terminalForeground: colorToken("#F3F7F1"),
        mutedForeground: colorToken("#9CA59D")
    )

    static let stPatrick = AppThemePalette(
        windowBackground: colorToken("#08170E"),
        canvasBackground: colorToken("#0D2114"),
        canvasSecondaryBackground: colorToken("#15301D"),
        borderColor: colorToken("#465A25"),
        accent: colorToken("#2FCB5F"),
        success: colorToken("#67E08A"),
        warning: colorToken("#E0C14C"),
        error: colorToken("#D95D5D"),
        selectionBackground: colorToken("#32591E"),
        terminalForeground: colorToken("#F1F9E8"),
        mutedForeground: colorToken("#96A393")
    )

    static let diwali = AppThemePalette(
        windowBackground: colorToken("#2A1206"),
        canvasBackground: colorToken("#351807"),
        canvasSecondaryBackground: colorToken("#47240B"),
        borderColor: colorToken("#7C4A12"),
        accent: colorToken("#FFB11B"),
        success: colorToken("#65C27A"),
        warning: colorToken("#FFD35A"),
        error: colorToken("#FF6A3D"),
        selectionBackground: colorToken("#8A3B10"),
        terminalForeground: colorToken("#FFF1D6"),
        mutedForeground: colorToken("#B39F88")
    )

    static let fourthOfJuly = AppThemePalette(
        windowBackground: colorToken("#091321"),
        canvasBackground: colorToken("#0F1C31"),
        canvasSecondaryBackground: colorToken("#182945"),
        borderColor: colorToken("#2E5193"),
        accent: colorToken("#E43F5A"),
        success: colorToken("#5ED0A5"),
        warning: colorToken("#F4C95D"),
        error: colorToken("#FF5A6E"),
        selectionBackground: colorToken("#315A9C"),
        terminalForeground: colorToken("#F7FAFF"),
        mutedForeground: colorToken("#979EAA")
    )

    static let ph = AppThemePalette(
        windowBackground: colorToken("#0D0D0D"),
        canvasBackground: colorToken("#131313"),
        canvasSecondaryBackground: colorToken("#1D1D1D"),
        borderColor: colorToken("#5A5A5A"),
        accent: colorToken("#F7931E"),
        success: colorToken("#5CCB8A"),
        warning: colorToken("#FFBE55"),
        error: colorToken("#FF6B57"),
        selectionBackground: colorToken("#6C3A00"),
        terminalForeground: colorToken("#F5F5F5"),
        mutedForeground: colorToken("#929292")
    )

    static let gruvboxDark = AppThemePalette(
        windowBackground: colorToken("#1D2021"),
        canvasBackground: colorToken("#282828"),
        canvasSecondaryBackground: colorToken("#32302F"),
        borderColor: colorToken("#504945"),
        accent: colorToken("#FE8019"),
        success: colorToken("#B8BB26"),
        warning: colorToken("#FABD2F"),
        error: colorToken("#FB4934"),
        selectionBackground: colorToken("#5B4A3A"),
        terminalForeground: colorToken("#EBDBB2"),
        mutedForeground: colorToken("#B1A589")
    )

    static let rosePine = AppThemePalette(
        windowBackground: colorToken("#191724"),
        canvasBackground: colorToken("#1F1D2E"),
        canvasSecondaryBackground: colorToken("#26233A"),
        borderColor: colorToken("#403D52"),
        accent: colorToken("#C4A7E7"),
        success: colorToken("#9CCFD8"),
        warning: colorToken("#F6C177"),
        error: colorToken("#EB6F92"),
        selectionBackground: colorToken("#4A3E6B"),
        terminalForeground: colorToken("#E0DEF4"),
        mutedForeground: colorToken("#9A98AC")
    )

    static let tokyoNight = AppThemePalette(
        windowBackground: colorToken("#16161E"),
        canvasBackground: colorToken("#1A1B26"),
        canvasSecondaryBackground: colorToken("#24283B"),
        borderColor: colorToken("#3B4261"),
        accent: colorToken("#7AA2F7"),
        success: colorToken("#9ECE6A"),
        warning: colorToken("#E0AF68"),
        error: colorToken("#F7768E"),
        selectionBackground: colorToken("#33467C"),
        terminalForeground: colorToken("#C0CAF5"),
        mutedForeground: colorToken("#959CBF")
    )

    static let mochaMood = AppThemePalette(
        windowBackground: colorToken("#11111B"),
        canvasBackground: colorToken("#1E1E2E"),
        canvasSecondaryBackground: colorToken("#313244"),
        borderColor: colorToken("#45475A"),
        accent: colorToken("#CBA6F7"),
        success: colorToken("#A6E3A1"),
        warning: colorToken("#F9E2AF"),
        error: colorToken("#F38BA8"),
        selectionBackground: colorToken("#585B70"),
        terminalForeground: colorToken("#CDD6F4"),
        mutedForeground: colorToken("#A2A9C4")
    )

    static let lavenderHaze = AppThemePalette(
        windowBackground: colorToken("#E8E0F0"),
        canvasBackground: colorToken("#F8F5FC"),
        canvasSecondaryBackground: colorToken("#F0EAF6"),
        borderColor: colorToken("#9B8FB8"),
        accent: colorToken("#7C3AED"),
        success: colorToken("#2B9467"),
        warning: colorToken("#9A7018"),
        error: colorToken("#C94060"),
        selectionBackground: colorToken("#D4C4F0"),
        terminalForeground: colorToken("#2D2640"),
        mutedForeground: colorToken("#5D576C")
    )

    static let highContrast = AppThemePalette(
        windowBackground: colorToken("#000000"),
        canvasBackground: colorToken("#0A0A0A"),
        canvasSecondaryBackground: colorToken("#1C1C1C"),
        borderColor: colorToken("#888888"),
        accent: colorToken("#4FC1FF"),
        success: colorToken("#3BDB85"),
        warning: colorToken("#FFD426"),
        error: colorToken("#FF6B68"),
        selectionBackground: colorToken("#264F78"),
        terminalForeground: colorToken("#FFFFFF"),
        mutedForeground: colorToken("#919191")
    )

    static let valentine = AppThemePalette(
        windowBackground: colorToken("#1A0A12"),
        canvasBackground: colorToken("#220E18"),
        canvasSecondaryBackground: colorToken("#2E1422"),
        borderColor: colorToken("#6B3A52"),
        accent: colorToken("#E8456B"),
        success: colorToken("#6ECFA0"),
        warning: colorToken("#F0C06A"),
        error: colorToken("#FF5577"),
        selectionBackground: colorToken("#7A2848"),
        terminalForeground: colorToken("#FDE8EF"),
        mutedForeground: colorToken("#A18C94")
    )

    static let oneDark = AppThemePalette(
        windowBackground: colorToken("#21252B"),
        canvasBackground: colorToken("#282C34"),
        canvasSecondaryBackground: colorToken("#2C313A"),
        borderColor: colorToken("#3E4451"),
        accent: colorToken("#61AFEF"),
        success: colorToken("#98C379"),
        warning: colorToken("#E5C07B"),
        error: colorToken("#E06C75"),
        selectionBackground: colorToken("#3E4451"),
        terminalForeground: colorToken("#AEB4C1"),
        mutedForeground: colorToken("#A1A7B3")
    )

    static let synthwave84 = AppThemePalette(
        windowBackground: colorToken("#1A1028"),
        canvasBackground: colorToken("#241B2F"),
        canvasSecondaryBackground: colorToken("#2E2240"),
        borderColor: colorToken("#524076"),
        accent: colorToken("#FF7EDB"),
        success: colorToken("#72F1B8"),
        warning: colorToken("#FEDE5D"),
        error: colorToken("#FE4450"),
        selectionBackground: colorToken("#463465"),
        terminalForeground: colorToken("#F0E8FF"),
        mutedForeground: colorToken("#A199AE")
    )

    static let halloween = AppThemePalette(
        windowBackground: colorToken("#0D0A14"),
        canvasBackground: colorToken("#14101E"),
        canvasSecondaryBackground: colorToken("#1E1728"),
        borderColor: colorToken("#4A3566"),
        accent: colorToken("#FF8C1A"),
        success: colorToken("#7BCC5E"),
        warning: colorToken("#FFD54F"),
        error: colorToken("#E04545"),
        selectionBackground: colorToken("#5C2E00"),
        terminalForeground: colorToken("#F0E6D3"),
        mutedForeground: colorToken("#968E89")
    )

    static let rosePineDawn = AppThemePalette(
        windowBackground: colorToken("#F2E9E1"),
        canvasBackground: colorToken("#FAF4ED"),
        canvasSecondaryBackground: colorToken("#FFFAF3"),
        borderColor: colorToken("#9893A5"),
        accent: colorToken("#907AA9"),
        success: colorToken("#55929D"),
        warning: colorToken("#C27814"),
        error: colorToken("#B4637A"),
        selectionBackground: colorToken("#DFDAD9"),
        terminalForeground: colorToken("#555076"),
        mutedForeground: colorToken("#5F5A7D")
    )

    static let highContrastLight = AppThemePalette(
        windowBackground: colorToken("#F0F0F0"),
        canvasBackground: colorToken("#FFFFFF"),
        canvasSecondaryBackground: colorToken("#F5F5F5"),
        borderColor: colorToken("#333333"),
        accent: colorToken("#0050A0"),
        success: colorToken("#1A7F37"),
        warning: colorToken("#7D5600"),
        error: colorToken("#CF222E"),
        selectionBackground: colorToken("#B6D7FF"),
        terminalForeground: colorToken("#000000"),
        mutedForeground: colorToken("#616161")
    )

    static let blossomPink = AppThemePalette(
        windowBackground: colorToken("#FDE8F0"),
        canvasBackground: colorToken("#FFF5F9"),
        canvasSecondaryBackground: colorToken("#FCEEF4"),
        borderColor: colorToken("#D4A0B8"),
        accent: colorToken("#E05399"),
        success: colorToken("#35976E"),
        warning: colorToken("#B37C1D"),
        error: colorToken("#D44060"),
        selectionBackground: colorToken("#F8C8DC"),
        terminalForeground: colorToken("#3D1F2E"),
        mutedForeground: colorToken("#725965")
    )

    static let midnightPink = AppThemePalette(
        windowBackground: colorToken("#200A1A"),
        canvasBackground: colorToken("#2A0F22"),
        canvasSecondaryBackground: colorToken("#3A162F"),
        borderColor: colorToken("#8C3D6E"),
        accent: colorToken("#FF6EC7"),
        success: colorToken("#6EE7A8"),
        warning: colorToken("#FBBF60"),
        error: colorToken("#FF5C8A"),
        selectionBackground: colorToken("#8B2A60"),
        terminalForeground: colorToken("#FFE0F0"),
        mutedForeground: colorToken("#AD8FA0")
    )

    static let kintsugi = AppThemePalette(
        windowBackground: colorToken("#1A1714"),
        canvasBackground: colorToken("#22201C"),
        canvasSecondaryBackground: colorToken("#2D2A25"),
        borderColor: colorToken("#5C5347"),
        accent: colorToken("#D4A843"),
        success: colorToken("#7EBF8E"),
        warning: colorToken("#E8C55A"),
        error: colorToken("#C75D5D"),
        selectionBackground: colorToken("#4A3D20"),
        terminalForeground: colorToken("#EDE6DA"),
        mutedForeground: colorToken("#A49F95")
    )

    static let ukiyoe = AppThemePalette(
        windowBackground: colorToken("#F0E6D6"),
        canvasBackground: colorToken("#FAF3E6"),
        canvasSecondaryBackground: colorToken("#F5ECDB"),
        borderColor: colorToken("#B7A38A"),
        accent: colorToken("#2B4C7E"),
        success: colorToken("#4A7C59"),
        warning: colorToken("#AA7C0A"),
        error: colorToken("#C23B22"),
        selectionBackground: colorToken("#D4C4A8"),
        terminalForeground: colorToken("#1C1410"),
        mutedForeground: colorToken("#635B54")
    )

    static let yushi = AppThemePalette(
        windowBackground: colorToken("#0A1210"),
        canvasBackground: colorToken("#0F1A16"),
        canvasSecondaryBackground: colorToken("#172520"),
        borderColor: colorToken("#3D6B55"),
        accent: colorToken("#3DBFA8"),
        success: colorToken("#8ED8A0"),
        warning: colorToken("#D4A843"),
        error: colorToken("#E06060"),
        selectionBackground: colorToken("#1E4A38"),
        terminalForeground: colorToken("#E0F0E8"),
        mutedForeground: colorToken("#8C9A93")
    )

    static let denglong = AppThemePalette(
        windowBackground: colorToken("#1A1210"),
        canvasBackground: colorToken("#221816"),
        canvasSecondaryBackground: colorToken("#2E201C"),
        borderColor: colorToken("#6B4030"),
        accent: colorToken("#D43D2F"),
        success: colorToken("#6EBF7E"),
        warning: colorToken("#E8B830"),
        error: colorToken("#FF4D4D"),
        selectionBackground: colorToken("#5C2218"),
        terminalForeground: colorToken("#F5E8D8"),
        mutedForeground: colorToken("#A1968B")
    )

    static let shuimo = AppThemePalette(
        windowBackground: colorToken("#141414"),
        canvasBackground: colorToken("#1C1B1A"),
        canvasSecondaryBackground: colorToken("#262524"),
        borderColor: colorToken("#4A4845"),
        accent: colorToken("#B8B0A6"),
        success: colorToken("#8CAA8C"),
        warning: colorToken("#C4A86A"),
        error: colorToken("#B86060"),
        selectionBackground: colorToken("#3A3835"),
        terminalForeground: colorToken("#E8E4DF"),
        mutedForeground: colorToken("#9C9996")
    )

    static let sichou = AppThemePalette(
        windowBackground: colorToken("#F5E8E0"),
        canvasBackground: colorToken("#FDF6F0"),
        canvasSecondaryBackground: colorToken("#F8EEE5"),
        borderColor: colorToken("#C0A488"),
        accent: colorToken("#8B2252"),
        success: colorToken("#4A7A5A"),
        warning: colorToken("#AC7E0A"),
        error: colorToken("#A03030"),
        selectionBackground: colorToken("#EFD5C8"),
        terminalForeground: colorToken("#2A1A10"),
        mutedForeground: colorToken("#695C53")
    )

    static let hanbok = AppThemePalette(
        windowBackground: colorToken("#F0EAE0"),
        canvasBackground: colorToken("#FBF8F2"),
        canvasSecondaryBackground: colorToken("#F5F0E8"),
        borderColor: colorToken("#B6A896"),
        accent: colorToken("#C7305A"),
        success: colorToken("#2A8C6A"),
        warning: colorToken("#AC7E1C"),
        error: colorToken("#D43050"),
        selectionBackground: colorToken("#D4E8E0"),
        terminalForeground: colorToken("#1A2A2A"),
        mutedForeground: colorToken("#56615F")
    )

    static let cheongja = AppThemePalette(
        windowBackground: colorToken("#E4EDE8"),
        canvasBackground: colorToken("#F2F8F5"),
        canvasSecondaryBackground: colorToken("#E8F2EC"),
        borderColor: colorToken("#7A9E8C"),
        accent: colorToken("#2E7A5A"),
        success: colorToken("#3B9663"),
        warning: colorToken("#A08030"),
        error: colorToken("#B85050"),
        selectionBackground: colorToken("#C8DED2"),
        terminalForeground: colorToken("#1A2E24"),
        mutedForeground: colorToken("#52625A")
    )

    static let dancheong = AppThemePalette(
        windowBackground: colorToken("#1C1410"),
        canvasBackground: colorToken("#261C16"),
        canvasSecondaryBackground: colorToken("#322620"),
        borderColor: colorToken("#6B4A35"),
        accent: colorToken("#307F91"),
        success: colorToken("#2E8B57"),
        warning: colorToken("#D4A020"),
        error: colorToken("#E04040"),
        selectionBackground: colorToken("#1A4A55"),
        terminalForeground: colorToken("#F2EBD8"),
        mutedForeground: colorToken("#A49C8E")
    )

    static let mehendi = AppThemePalette(
        windowBackground: colorToken("#F0E6D6"),
        canvasBackground: colorToken("#FAF4E8"),
        canvasSecondaryBackground: colorToken("#F2EADC"),
        borderColor: colorToken("#B4A58B"),
        accent: colorToken("#B85C3A"),
        success: colorToken("#3A7A4A"),
        warning: colorToken("#AC791C"),
        error: colorToken("#C04040"),
        selectionBackground: colorToken("#E0D0B8"),
        terminalForeground: colorToken("#2A1E14"),
        mutedForeground: colorToken("#655B50")
    )

    static let rangoli = AppThemePalette(
        windowBackground: colorToken("#181412"),
        canvasBackground: colorToken("#221C1A"),
        canvasSecondaryBackground: colorToken("#2C2522"),
        borderColor: colorToken("#7A5C42"),
        accent: colorToken("#FF8C2A"),
        success: colorToken("#30B87A"),
        warning: colorToken("#F0C030"),
        error: colorToken("#E04070"),
        selectionBackground: colorToken("#5A3220"),
        terminalForeground: colorToken("#FAF2E6"),
        mutedForeground: colorToken("#A19A92")
    )

    static let mayur = AppThemePalette(
        windowBackground: colorToken("#0A1218"),
        canvasBackground: colorToken("#0F1A22"),
        canvasSecondaryBackground: colorToken("#16242E"),
        borderColor: colorToken("#2E5A6A"),
        accent: colorToken("#1EAAB8"),
        success: colorToken("#4AD4A0"),
        warning: colorToken("#D4A843"),
        error: colorToken("#E06070"),
        selectionBackground: colorToken("#1A4050"),
        terminalForeground: colorToken("#E4F4F0"),
        mutedForeground: colorToken("#8B999A")
    )

    static let tiranga = AppThemePalette(
        windowBackground: colorToken("#FF9933"),
        canvasBackground: colorToken("#FFFFFF"),
        canvasSecondaryBackground: colorToken("#D5EAC8"),
        borderColor: colorToken("#1CCA0C"),
        accent: colorToken("#C56200"),
        success: colorToken("#138808"),
        warning: colorToken("#A2760A"),
        error: colorToken("#D03030"),
        selectionBackground: colorToken("#FFD494"),
        terminalForeground: colorToken("#1A1A4D"),
        mutedForeground: colorToken("#353562")
    )

    var windowBackgroundColor: Color { windowBackground.color }
    var canvasBackgroundColor: Color { canvasBackground.color }
    var canvasSecondaryBackgroundColor: Color { canvasSecondaryBackground.color }
    var chromeBackground: ProjectColorTag {
        get { windowBackground }
        set { windowBackground = newValue }
    }
    var chromeBackgroundColor: Color { windowBackgroundColor }
    var elevatedBackground: ProjectColorTag {
        get { canvasSecondaryBackground }
        set { canvasSecondaryBackground = newValue }
    }
    var elevatedBackgroundColor: Color { canvasSecondaryBackgroundColor }
    var borderColorValue: Color { borderColor.color }
    var accentColor: Color { accent.color }
    var accentStrong: ProjectColorTag {
        blendedTag(primary: accent, secondary: selectionBackground, ratio: 0.38)
    }
    var accentStrongColor: Color { accentStrong.color }
    var successColor: Color { success.color }
    var warningColor: Color { warning.color }
    var errorColor: Color { error.color }
    var selectionBackgroundColor: Color { selectionBackground.color }
    var selectionText: ProjectColorTag {
        selectionBackground.relativeLuminance < 0.35
            ? AppThemePalette.colorToken("#FFFFFF")
            : AppThemePalette.colorToken("#111111")
    }
    var selectionTextColor: Color { selectionText.color }
    var terminalForegroundColor: Color { terminalForeground.color }
    var terminalCaret: ProjectColorTag { accent }
    var terminalCaretColor: Color { terminalCaret.color }
    var terminalSelectionBackground: ProjectColorTag {
        let base = blendedTag(primary: selectionBackground, secondary: accent, ratio: 0.30)
        let alpha = prefersDarkWindowChrome ? 0.54 : 0.68
        return ProjectColorTag(red: base.red, green: base.green, blue: base.blue, alpha: alpha)
    }
    var terminalSelectionBackgroundColor: Color { terminalSelectionBackground.color }
    var primaryTextColor: Color { terminalForegroundColor }
    var mutedForegroundColor: Color { mutedForeground.color }
    var secondaryTextColor: Color { mutedForegroundColor }
    var tertiaryTextColor: Color {
        blendedColor(primary: mutedForeground, secondary: canvasBackground, ratio: 0.22)
    }
    var directoryIconColor: Color { accentStrongColor }
    var gitAddedStatusColor: Color { successColor }
    var gitModifiedStatusColor: Color { warningColor }
    var gitDeletedStatusColor: Color { errorColor }
    var gitRenamedStatusColor: Color { accentColor }
    var gitConflictStatusColor: Color { accentStrongColor }

    var nsWindowBackgroundColor: NSColor {
        windowBackground.nsColor
    }

    var prefersDarkWindowChrome: Bool {
        windowBackground.relativeLuminance < 0.28
    }

    var preferredColorScheme: ColorScheme {
        prefersDarkWindowChrome ? .dark : .light
    }

    func token(for role: AppThemeColorRole) -> String {
        self[keyPath: role.keyPath].storageToken
    }

    func color(for role: AppThemeColorRole) -> Color {
        self[keyPath: role.keyPath].color
    }

    mutating func setToken(_ token: String, for role: AppThemeColorRole) -> Bool {
        guard let parsed = ProjectColorTag(storageToken: token) else { return false }
        self[keyPath: role.keyPath] = parsed
        return true
    }

    static func colorToken(_ token: String) -> ProjectColorTag {
        ProjectColorTag(storageToken: token)
            ?? ProjectColorTag(red: 0.21, green: 0.56, blue: 0.91)
    }

    static func encodeToJSON(_ palette: AppThemePalette) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(palette),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }

    static func decodeFromJSON(_ raw: String) -> AppThemePalette? {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AppThemePalette.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case windowBackground
        case canvasBackground
        case canvasSecondaryBackground
        case chromeBackground
        case elevatedBackground
        case borderColor
        case accent
        case success
        case warning
        case error
        case selectionBackground
        case terminalForeground
        case mutedForeground
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canvasBackground = try container.decode(ProjectColorTag.self, forKey: .canvasBackground)
        windowBackground = try container.decodeIfPresent(ProjectColorTag.self, forKey: .windowBackground)
            ?? container.decodeIfPresent(ProjectColorTag.self, forKey: .chromeBackground)
            ?? canvasBackground
        canvasSecondaryBackground = try container.decodeIfPresent(ProjectColorTag.self, forKey: .canvasSecondaryBackground)
            ?? container.decodeIfPresent(ProjectColorTag.self, forKey: .elevatedBackground)
            ?? canvasBackground
        borderColor = try container.decode(ProjectColorTag.self, forKey: .borderColor)
        accent = try container.decode(ProjectColorTag.self, forKey: .accent)
        success = try container.decode(ProjectColorTag.self, forKey: .success)
        warning = try container.decode(ProjectColorTag.self, forKey: .warning)
        error = try container.decode(ProjectColorTag.self, forKey: .error)
        selectionBackground = try container.decode(ProjectColorTag.self, forKey: .selectionBackground)
        terminalForeground = try container.decode(ProjectColorTag.self, forKey: .terminalForeground)
        mutedForeground = try container.decodeIfPresent(ProjectColorTag.self, forKey: .mutedForeground)
            ?? Self.legacyMutedForeground(terminalForeground: terminalForeground, borderColor: borderColor)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowBackground, forKey: .windowBackground)
        try container.encode(canvasBackground, forKey: .canvasBackground)
        try container.encode(canvasSecondaryBackground, forKey: .canvasSecondaryBackground)
        try container.encode(borderColor, forKey: .borderColor)
        try container.encode(accent, forKey: .accent)
        try container.encode(success, forKey: .success)
        try container.encode(warning, forKey: .warning)
        try container.encode(error, forKey: .error)
        try container.encode(selectionBackground, forKey: .selectionBackground)
        try container.encode(terminalForeground, forKey: .terminalForeground)
        try container.encode(mutedForeground, forKey: .mutedForeground)
    }

    static func defaultCustomBase(from preset: AppThemePreset) -> AppThemePalette {
        switch preset {
        case .system:
            return .systemDark
        case .graphiteDark:
            return .graphiteDark
        case .midnightMono:
            return .midnightMono
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
            return .midnightMono
        }
    }

    private func blendedColor(
        primary: ProjectColorTag,
        secondary: ProjectColorTag,
        ratio: Double
    ) -> Color {
        blendedTag(primary: primary, secondary: secondary, ratio: ratio).color
    }

    private func blendedTag(
        primary: ProjectColorTag,
        secondary: ProjectColorTag,
        ratio: Double
    ) -> ProjectColorTag {
        let clamped = max(0.0, min(1.0, ratio))
        let inverse = 1.0 - clamped
        return ProjectColorTag(
            red: primary.red * inverse + secondary.red * clamped,
            green: primary.green * inverse + secondary.green * clamped,
            blue: primary.blue * inverse + secondary.blue * clamped,
            alpha: primary.alpha * inverse + secondary.alpha * clamped
        )
    }
}
