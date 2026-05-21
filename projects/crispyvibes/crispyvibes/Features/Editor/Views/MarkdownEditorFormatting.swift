import Foundation
import SwiftUI

enum EditorFormattingCommand: String, CaseIterable {
    case bold
    case italic
    case heading1
    case heading2
    case unorderedList
    case orderedList
    case blockQuote
    case codeBlock
    case link
    case image
    case table
    case horizontalRule
}

struct EditorCommandRequest {
    let id = UUID()
    let command: EditorFormattingCommand
}

struct MarkupEditorThemeTokenBuilder {
    let palette: AppThemePalette
    let colorScheme: ColorScheme

    func build() -> [String: String] {
        let syntaxTheme = SyntaxTheme.fromPalette(palette, colorScheme: colorScheme)
        let accent = palette.accent.nsColor
        let accentStrong = palette.accentStrong.nsColor
        let success = palette.success.nsColor
        let warning = palette.warning.nsColor
        let error = palette.error.nsColor
        let text = palette.terminalForeground.nsColor
        let border = palette.borderColor.nsColor
        let isDark = colorScheme == .dark

        let mutedText = Self.mix(text, with: border, ratio: isDark ? 0.56 : 0.64)
        let mutedBackground = palette.canvasSecondaryBackground.nsColor
        let neutralMutedBackground = border.withAlphaComponent(isDark ? 0.20 : 0.14)
        let attentionMutedBackground = warning.withAlphaComponent(isDark ? 0.22 : 0.18)
        let mutedBorder = border.withAlphaComponent(isDark ? 0.58 : 0.36)
        let neutralMutedBorder = border.withAlphaComponent(isDark ? 0.48 : 0.30)

        let deletedBackground = error.withAlphaComponent(isDark ? 0.24 : 0.16)
        let insertedBackground = success.withAlphaComponent(isDark ? 0.22 : 0.16)
        let changedBackground = warning.withAlphaComponent(isDark ? 0.22 : 0.16)
        let ignoredBackground = accent.withAlphaComponent(isDark ? 0.26 : 0.18)

        return [
            "--focus-outlineColor": Self.cssColor(accent),
            "--fgColor-default": Self.cssColor(text),
            "--fgColor-muted": Self.cssColor(mutedText),
            "--fgColor-accent": Self.cssColor(accent),
            "--fgColor-success": Self.cssColor(success),
            "--fgColor-attention": Self.cssColor(warning),
            "--fgColor-danger": Self.cssColor(error),
            "--fgColor-done": Self.cssColor(accentStrong),
            "--bgColor-default": Self.cssColor(palette.canvasBackground.nsColor),
            "--bgColor-muted": Self.cssColor(mutedBackground),
            "--bgColor-neutral-muted": Self.cssColor(neutralMutedBackground),
            "--bgColor-attention-muted": Self.cssColor(attentionMutedBackground),
            "--borderColor-default": Self.cssColor(border),
            "--borderColor-muted": Self.cssColor(mutedBorder),
            "--borderColor-neutral-muted": Self.cssColor(neutralMutedBorder),
            "--borderColor-accent-emphasis": Self.cssColor(accent),
            "--borderColor-success-emphasis": Self.cssColor(success),
            "--borderColor-attention-emphasis": Self.cssColor(warning),
            "--borderColor-danger-emphasis": Self.cssColor(error),
            "--borderColor-done-emphasis": Self.cssColor(accentStrong),
            "--color-prettylights-syntax-comment": Self.cssColor(syntaxTheme.comment),
            "--color-prettylights-syntax-constant": Self.cssColor(syntaxTheme.number),
            "--color-prettylights-syntax-constant-other-reference-link": Self.cssColor(accentStrong),
            "--color-prettylights-syntax-entity": Self.cssColor(syntaxTheme.class),
            "--color-prettylights-syntax-storage-modifier-import": Self.cssColor(text),
            "--color-prettylights-syntax-entity-tag": Self.cssColor(syntaxTheme.function),
            "--color-prettylights-syntax-keyword": Self.cssColor(syntaxTheme.keyword),
            "--color-prettylights-syntax-string": Self.cssColor(syntaxTheme.string),
            "--color-prettylights-syntax-variable": Self.cssColor(syntaxTheme.variable),
            "--color-prettylights-syntax-brackethighlighter-unmatched": Self.cssColor(error),
            "--color-prettylights-syntax-brackethighlighter-angle": Self.cssColor(mutedText),
            "--color-prettylights-syntax-invalid-illegal-text": Self.cssColor(text),
            "--color-prettylights-syntax-invalid-illegal-bg": Self.cssColor(deletedBackground),
            "--color-prettylights-syntax-carriage-return-text": Self.cssColor(text),
            "--color-prettylights-syntax-carriage-return-bg": Self.cssColor(deletedBackground),
            "--color-prettylights-syntax-string-regexp": Self.cssColor(success),
            "--color-prettylights-syntax-markup-list": Self.cssColor(syntaxTheme.variable),
            "--color-prettylights-syntax-markup-heading": Self.cssColor(accent),
            "--color-prettylights-syntax-markup-italic": Self.cssColor(text),
            "--color-prettylights-syntax-markup-bold": Self.cssColor(text),
            "--color-prettylights-syntax-markup-deleted-text": Self.cssColor(error),
            "--color-prettylights-syntax-markup-deleted-bg": Self.cssColor(deletedBackground),
            "--color-prettylights-syntax-markup-inserted-text": Self.cssColor(success),
            "--color-prettylights-syntax-markup-inserted-bg": Self.cssColor(insertedBackground),
            "--color-prettylights-syntax-markup-changed-text": Self.cssColor(warning),
            "--color-prettylights-syntax-markup-changed-bg": Self.cssColor(changedBackground),
            "--color-prettylights-syntax-markup-ignored-text": Self.cssColor(text),
            "--color-prettylights-syntax-markup-ignored-bg": Self.cssColor(ignoredBackground),
            "--color-prettylights-syntax-meta-diff-range": Self.cssColor(accentStrong),
            "--color-prettylights-syntax-sublimelinter-gutter-mark": Self.cssColor(mutedBorder),
            "--crispyvibes-editor-fg": Self.cssColor(text),
            "--crispyvibes-editor-muted-bg": Self.cssColor(mutedBackground),
            "--crispyvibes-editor-border": Self.cssColor(mutedBorder)
        ]
    }

    private static func cssColor(_ color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        let alpha = max(0.0, min(1.0, srgb.alphaComponent))

        if alpha >= 0.999 {
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
        return String(format: "rgba(%d, %d, %d, %.3f)", red, green, blue, alpha)
    }

    private static func mix(_ left: NSColor, with right: NSColor, ratio: CGFloat) -> NSColor {
        let clampedRatio = max(0, min(1, ratio))
        let leftSRGB = left.usingColorSpace(.sRGB) ?? left
        let rightSRGB = right.usingColorSpace(.sRGB) ?? right
        let inverse = 1 - clampedRatio
        return NSColor(
            srgbRed: leftSRGB.redComponent * inverse + rightSRGB.redComponent * clampedRatio,
            green: leftSRGB.greenComponent * inverse + rightSRGB.greenComponent * clampedRatio,
            blue: leftSRGB.blueComponent * inverse + rightSRGB.blueComponent * clampedRatio,
            alpha: leftSRGB.alphaComponent * inverse + rightSRGB.alphaComponent * clampedRatio
        )
    }
}
