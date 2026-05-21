import SwiftUI

struct CrispyVibesUIScale: Equatable {
    let codeFontSize: Double

    static let `default` = CrispyVibesUIScale(codeFontSize: AppPreferences.defaultCodeFontSize)

    init(codeFontSize: Double) {
        self.codeFontSize = AppPreferences.clampedCodeFontSize(codeFontSize)
    }

    static func current(userDefaults: UserDefaults = .standard) -> CrispyVibesUIScale {
        CrispyVibesUIScale(codeFontSize: Double(AppPreferences.codeFontSize(userDefaults: userDefaults)))
    }

    var textScale: CGFloat {
        progressiveScale(exponent: 0.45, minimum: 0.75)
    }

    var iconScale: CGFloat {
        progressiveScale(exponent: 0.34, minimum: 0.85)
    }

    var chromeScale: CGFloat {
        progressiveScale(exponent: 0.30, minimum: 0.85)
    }

    var spacingScale: CGFloat {
        progressiveScale(exponent: 0.22, minimum: 0.90)
    }

    var controlSize: ControlSize {
        if textScale >= 1.35 {
            return .large
        }
        if textScale <= 0.88 {
            return .small
        }
        return .regular
    }

    func textSize(_ baseSize: CGFloat) -> CGFloat {
        round(baseSize * textScale)
    }

    func iconSize(_ baseSize: CGFloat) -> CGFloat {
        round(baseSize * iconScale)
    }

    func chromeSize(_ baseSize: CGFloat) -> CGFloat {
        round(baseSize * chromeScale)
    }

    func spacing(_ baseSize: CGFloat) -> CGFloat {
        round(baseSize * spacingScale)
    }

    private func progressiveScale(exponent: Double, minimum: CGFloat) -> CGFloat {
        let ratio = max(codeFontSize, 1) / max(AppPreferences.defaultCodeFontSize, 1)
        return max(minimum, CGFloat(pow(ratio, exponent)))
    }
}

private struct AppThemePaletteKey: EnvironmentKey {
    static let defaultValue: AppThemePalette = .ph
}

private struct CrispyVibesUIScaleKey: EnvironmentKey {
    static let defaultValue = CrispyVibesUIScale.default
}

extension EnvironmentValues {
    var appThemePalette: AppThemePalette {
        get { self[AppThemePaletteKey.self] }
        set { self[AppThemePaletteKey.self] = newValue }
    }

    var crispyvibesUIScale: CrispyVibesUIScale {
        get { self[CrispyVibesUIScaleKey.self] }
        set { self[CrispyVibesUIScaleKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func applyingAppAccentTheme(_ tintColor: Color?) -> some View {
        if let tintColor {
            self
                .tint(tintColor)
                .accentColor(tintColor)
        } else {
            self
        }
    }

    func applyingAppThemePalette(_ palette: AppThemePalette) -> some View {
        environment(\.appThemePalette, palette)
    }

    func applyingCrispyVibesUIScale(_ scale: CrispyVibesUIScale) -> some View {
        environment(\.crispyvibesUIScale, scale)
    }
}
