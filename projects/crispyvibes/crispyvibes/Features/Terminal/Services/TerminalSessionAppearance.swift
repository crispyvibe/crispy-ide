import AppKit
import SwiftUI

@MainActor
extension TerminalSession {
    func applySystemAppearance() {
        engine.applyThemePalette(Self.resolvedThemePalette(for: engine.effectiveAppearance))
    }

    static func resolvedThemePalette(for appearance: NSAppearance) -> AppThemePalette {
        let defaults = UserDefaults.standard
        let systemScheme: ColorScheme =
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        return AppThemeResolver.palette(
            appearancePreferenceRaw: defaults.string(forKey: AppPreferences.appearancePreferenceKey)
                ?? AppPreferences.defaultAppearancePreference,
            fallbackSystemColorScheme: systemScheme,
            themePresetRaw: defaults.string(forKey: AppPreferences.appThemePresetKey)
                ?? AppPreferences.defaultAppThemePreset,
            customThemeJSON: defaults.string(forKey: AppPreferences.appCustomThemePaletteJSONKey)
                ?? ""
        )
    }

    static let minimumDisplayMagnification: CGFloat = 0.5
    static let maximumDisplayMagnification: CGFloat = 3

    nonisolated static func normalizedDisplayMagnification(_ magnification: CGFloat) -> CGFloat {
        guard magnification.isFinite else { return 1 }
        let clamped = min(maximumDisplayMagnification, max(minimumDisplayMagnification, magnification))
        guard clamped < 1 else { return clamped }

        let scaled = clamped * 10
        let lowerStep = floor(scaled)
        let isMidpoint = abs((scaled - lowerStep) - 0.5) <= 0.000_000_1
        let snappedStep = isMidpoint ? lowerStep + 1 : scaled.rounded(.toNearestOrAwayFromZero)
        return snappedStep / 10
    }

    func setDisplayDensity(_ density: TerminalDisplayDensity) {
        let resolvedFontSize = density.fontSize
        let defaults = UserDefaults.standard
        let fontFamilyRawValue = defaults.string(forKey: AppPreferences.codeFontFamilyKey)
            ?? AppPreferences.defaultCodeFontFamily
        let resolvedFont = AppPreferences.codeFont(
            familyRawValue: fontFamilyRawValue,
            size: resolvedFontSize
        )

        guard density != currentDisplayDensity
            || abs(engine.font.pointSize - resolvedFont.pointSize) >= 0.1
            || engine.font.fontName != resolvedFont.fontName else {
            return
        }
        currentDisplayDensity = density
        engine.font = resolvedFont
    }

    func adjustDisplayMagnification(by delta: CGFloat) {
        guard delta.isFinite, delta != 0 else { return }
        setDisplayMagnification(displayMagnification + delta)
    }

    func setDisplayMagnification(_ magnification: CGFloat) {
        displayMagnification = Self.normalizedDisplayMagnification(magnification)
    }

    func cancelKeyboardFocusRequest() {
        focusRequestGeneration &+= 1
    }

    func requestKeyboardFocus(retryCount: Int) {
        let generation: UInt
        if retryCount == 0 {
            focusRequestGeneration &+= 1
            generation = focusRequestGeneration
        } else {
            generation = focusRequestGeneration
        }
        guard retryCount <= focusRetryLimit else { return }
        guard let window = hostedView.window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self, self.focusRequestGeneration == generation else { return }
                self.requestKeyboardFocus(retryCount: retryCount + 1)
            }
            return
        }

        if !window.isKeyWindow {
            window.makeKey()
        }

        if window.firstResponder === hostedView {
            return
        }

        let focused = window.makeFirstResponder(hostedView)
        if !focused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self, self.focusRequestGeneration == generation else { return }
                self.requestKeyboardFocus(retryCount: retryCount + 1)
            }
        }
    }
}
