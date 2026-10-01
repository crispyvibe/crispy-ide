import SwiftUI
import WebKit

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

/// Applies the global document text-size ratio to app-authored WebView surfaces.
/// Browser, notebook, whiteboard, PDF, and raster-image zoom remain domain-owned.
@MainActor
enum WebViewPresentationScale {
    static let minimumPageZoom: CGFloat = 0.25
    static let maximumPageZoom: CGFloat = 5.0

    static func pageZoom(for uiScale: CrispyVibesUIScale) -> CGFloat {
        let defaultSize = max(AppPreferences.defaultCodeFontSize, 1)
        let ratio = CGFloat(uiScale.codeFontSize / defaultSize)
        return min(maximumPageZoom, max(minimumPageZoom, ratio))
    }

    static func apply(_ uiScale: CrispyVibesUIScale, to webView: WKWebView) {
        let resolvedZoom = pageZoom(for: uiScale)
        guard abs(webView.pageZoom - resolvedZoom) > 0.0001 else { return }
        webView.pageZoom = resolvedZoom
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
