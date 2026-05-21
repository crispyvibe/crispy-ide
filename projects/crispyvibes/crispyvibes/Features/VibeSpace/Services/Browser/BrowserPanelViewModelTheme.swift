import AppKit
import Foundation

// MARK: - Theme Mode

extension BrowserPanelViewModel {
    func setThemeMode(_ mode: BrowserThemeMode) {
        themeMode = mode
        switch mode {
        case .system: webView.appearance = nil
        case .light: webView.appearance = NSAppearance(named: .aqua)
        case .dark: webView.appearance = NSAppearance(named: .darkAqua)
        }
        let scheme = mode == .system ? "null" : "'\(mode.rawValue)'"
        webView.evaluateJavaScript("""
        (() => { const r = document.documentElement; if (\(scheme)) { r.style.setProperty('color-scheme', \(scheme), 'important'); } else { r.style.removeProperty('color-scheme'); } })();
        """)
        onSessionStateChanged?()
    }
}
