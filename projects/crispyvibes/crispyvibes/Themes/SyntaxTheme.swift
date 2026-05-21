import SwiftUI

/// Defines colors for syntax highlighting
public struct SyntaxTheme {
    public let keyword: NSColor
    public let string: NSColor
    public let comment: NSColor
    public let number: NSColor
    public let function: NSColor
    public let `class`: NSColor
    public let `operator`: NSColor
    public let variable: NSColor
    public let background: NSColor
    public let text: NSColor
    
    public init(
        keyword: NSColor,
        string: NSColor,
        comment: NSColor,
        number: NSColor,
        function: NSColor,
        class: NSColor,
        operator: NSColor,
        variable: NSColor,
        background: NSColor,
        text: NSColor
    ) {
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.function = function
        self.class = `class`
        self.operator = `operator`
        self.variable = variable
        self.background = background
        self.text = text
    }

    public static let light = fromPalette(.systemLight, colorScheme: .light)
    public static let dark = fromPalette(.systemDark, colorScheme: .dark)

    static func fromPalette(_ palette: AppThemePalette, colorScheme: ColorScheme) -> SyntaxTheme {
        let isDark = colorScheme == .dark
        let background = normalizedOpaque(palette.canvasBackground.nsColor)
        let text = readableTextColor(
            candidate: palette.terminalForeground.nsColor,
            background: background
        )
        let accent = normalizedOpaque(palette.accent.nsColor)
        let success = normalizedOpaque(palette.success.nsColor)
        let warning = normalizedOpaque(palette.warning.nsColor)
        let error = normalizedOpaque(palette.error.nsColor)
        let accentStrong = normalizedOpaque(palette.accentStrong.nsColor)

        return SyntaxTheme(
            keyword: mix(accent, with: accentStrong, ratio: isDark ? 0.35 : 0.50),
            string: mix(warning, with: text, ratio: isDark ? 0.22 : 0.45),
            comment: mix(success, with: text, ratio: isDark ? 0.45 : 0.58),
            number: mix(accent, with: text, ratio: isDark ? 0.30 : 0.52),
            function: mix(accentStrong, with: success, ratio: isDark ? 0.28 : 0.38),
            class: mix(warning, with: accentStrong, ratio: isDark ? 0.35 : 0.45),
            operator: mix(accentStrong, with: text, ratio: isDark ? 0.22 : 0.48),
            variable: mix(error, with: warning, ratio: isDark ? 0.60 : 0.52),
            background: background,
            text: text
        )
    }

    private static func normalizedOpaque(_ color: NSColor) -> NSColor {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return NSColor(
            srgbRed: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent,
            alpha: 1.0
        )
    }

    private static func readableTextColor(candidate: NSColor, background: NSColor) -> NSColor {
        let preferred = normalizedOpaque(candidate)
        let contrast = contrastRatio(preferred, background)
        if contrast >= 2.8 {
            return preferred
        }

        let lightFallback = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1.0)
        let darkFallback = NSColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1.0)
        let lightContrast = contrastRatio(lightFallback, background)
        let darkContrast = contrastRatio(darkFallback, background)
        return lightContrast >= darkContrast ? lightFallback : darkFallback
    }

    private static func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let l1 = relativeLuminance(lhs)
        let l2 = relativeLuminance(rhs)
        let high = max(l1, l2)
        let low = min(l1, l2)
        return (high + 0.05) / (low + 0.05)
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB) ?? color
        func channel(_ value: CGFloat) -> CGFloat {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        let r = channel(c.redComponent)
        let g = channel(c.greenComponent)
        let b = channel(c.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func mix(_ a: NSColor, with b: NSColor, ratio: CGFloat) -> NSColor {
        let clampedRatio = max(0, min(1, ratio))
        let left = a.usingColorSpace(.sRGB) ?? a
        let right = b.usingColorSpace(.sRGB) ?? b
        let inv = 1 - clampedRatio
        return NSColor(
            srgbRed: left.redComponent * inv + right.redComponent * clampedRatio,
            green: left.greenComponent * inv + right.greenComponent * clampedRatio,
            blue: left.blueComponent * inv + right.blueComponent * clampedRatio,
            alpha: left.alphaComponent * inv + right.alphaComponent * clampedRatio
        )
    }

    public static var current: SyntaxTheme {
        NSApp.effectiveAppearance.name == .darkAqua ? .dark : .light
    }
}
