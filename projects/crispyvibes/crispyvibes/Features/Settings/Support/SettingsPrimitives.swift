import SwiftUI

enum AppTypographyTokens {
    private static var scale: CrispyVibesUIScale { .current() }

    static func scaledSystem(
        _ baseSize: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> Font {
        if let weight {
            return .system(size: scale.textSize(baseSize), weight: weight, design: design)
        }
        return .system(size: scale.textSize(baseSize), design: design)
    }

    static func scaledIcon(
        _ baseSize: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> Font {
        if let weight {
            return .system(size: scale.iconSize(baseSize), weight: weight, design: design)
        }
        return .system(size: scale.iconSize(baseSize), design: design)
    }

    static func scaledChromeSystem(
        _ baseSize: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> Font {
        if let weight {
            return .system(size: scale.chromeSize(baseSize), weight: weight, design: design)
        }
        return .system(size: scale.chromeSize(baseSize), design: design)
    }

    static var largeTitle: Font { scaledSystem(34, weight: .semibold) }
    static var title2: Font { scaledSystem(22) }
    static var title3: Font { scaledSystem(20) }
    static var title3Semibold: Font { scaledSystem(20, weight: .semibold) }
    static var headline: Font { scaledSystem(13, weight: .semibold) }
    static var subheadline: Font { scaledSystem(12) }
    static var subheadlineSemibold: Font { scaledSystem(12, weight: .semibold) }
    static var panelHeaderTitle: Font { scaledSystem(13, weight: .semibold) }
    static var panelHeaderSubtitle: Font { caption }
    static var panelHeaderBadge: Font { caption2Semibold }
    static var cardHeaderTitle: Font { captionSemibold }
    static var cardHeaderDetail: Font { caption2 }
    static var compactHeaderTitle: Font { caption2Semibold }
    static var callout: Font { scaledSystem(14) }
    static var calloutSemibold: Font { scaledSystem(14, weight: .semibold) }
    static var body: Font { scaledSystem(13) }
    static var bodyMonospaced: Font { scaledSystem(13, design: .monospaced) }
    static var bodyMonospacedDigit: Font { scaledSystem(13).monospacedDigit() }
    static var caption: Font { scaledSystem(12) }
    static var captionSemibold: Font { scaledSystem(12, weight: .semibold) }
    static var captionMonospacedDigit: Font { scaledSystem(12).monospacedDigit() }
    static var captionMonospaced: Font { scaledSystem(12, design: .monospaced) }
    static var caption2: Font { scaledSystem(11) }
    static var caption2Semibold: Font { scaledSystem(11, weight: .semibold) }
    static var caption2Bold: Font { scaledSystem(11, weight: .bold) }
    static var caption2Monospaced: Font { scaledSystem(11, design: .monospaced) }
    static var caption2MonospacedDigit: Font { scaledSystem(11).monospacedDigit() }
    static var footnote: Font { scaledSystem(10) }
    static var title2Semibold: Font { scaledSystem(22, weight: .semibold) }
    static var monospacedCaption: Font { scaledSystem(12, design: .monospaced) }
    static var monospacedCaptionSemibold: Font { scaledSystem(12, weight: .semibold, design: .monospaced) }
    static var monospacedCaption2: Font { scaledSystem(11, design: .monospaced) }
    static var imageStatus: Font { scaledSystem(11, weight: .medium) }
    static var settingsHeaderTitle: Font { scaledChromeSystem(20, weight: .semibold) }
    static var settingsHeaderSubtitle: Font { scaledChromeSystem(11) }
    static var settingsSearchField: Font { scaledChromeSystem(12) }
    static var settingsSidebarLabel: Font { scaledChromeSystem(11, weight: .semibold) }
    static var settingsSidebarIcon: Font { scaledIcon(11, weight: .semibold) }
    static var settingsSidebarTitle: Font { scaledChromeSystem(13, weight: .medium) }
    static var settingsCategoryHeaderTitle: Font { scaledChromeSystem(22, weight: .semibold) }
    static var settingsCardTitle: Font { scaledChromeSystem(12, weight: .semibold) }
    static var settingsFieldTitle: Font { scaledChromeSystem(12, weight: .medium) }
    static var settingsFieldDetail: Font { scaledChromeSystem(11) }
    static var welcomeBrandTitle: Font { scaledChromeSystem(41, weight: .bold, design: .rounded) }
    static var welcomeActionTitle: Font { scaledChromeSystem(28, weight: .semibold) }
    static var welcomeActionIcon: Font { scaledIcon(15, weight: .semibold) }
    static var welcomeActionChevron: Font { scaledIcon(9, weight: .semibold) }
    static var welcomeBody: Font { scaledChromeSystem(14) }
    static var welcomeActionSummary: Font { scaledChromeSystem(12) }
    static var welcomeSectionHeadline: Font { scaledChromeSystem(13, weight: .semibold) }
    static var welcomeStepBadge: Font { scaledChromeSystem(12, weight: .semibold) }
    static var welcomeFieldLabel: Font { scaledChromeSystem(12, weight: .semibold) }
    static var welcomeVibeSpaceName: Font { scaledChromeSystem(14, weight: .semibold) }
    static var welcomeInlineIcon: Font { scaledChromeSystem(12) }
    static var welcomePath: Font { scaledChromeSystem(11) }
}
