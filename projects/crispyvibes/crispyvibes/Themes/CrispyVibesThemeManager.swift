import SwiftUI

final class CrispyVibesThemeManager: ObservableObject {
    static let borderShapeKey = "crispyvibesThemeBorderShape"
    static let borderVisibleKey = "crispyvibesThemeBorderVisible"

    @Published var theme: CrispyVibesTheme {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = Self.load(from: defaults)
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(theme.borderShape.rawValue, forKey: Self.borderShapeKey)
        defaults.set(theme.borderVisible, forKey: Self.borderVisibleKey)
        // fontFamily is already persisted via AppPreferences.codeFontFamilyKey
        defaults.set(theme.fontFamily.rawValue, forKey: AppPreferences.codeFontFamilyKey)
    }

    private static func load(from defaults: UserDefaults) -> CrispyVibesTheme {
        let shapeRaw = defaults.string(forKey: borderShapeKey)
        let shape = CrispyVibesBorderShape(rawValue: shapeRaw ?? "") ?? CrispyVibesTheme.default.borderShape

        let visible: Bool
        if defaults.object(forKey: borderVisibleKey) != nil {
            visible = defaults.bool(forKey: borderVisibleKey)
        } else {
            visible = CrispyVibesTheme.default.borderVisible
        }

        let fontRaw = defaults.string(forKey: AppPreferences.codeFontFamilyKey)
        let font = AppCodeFontFamily(rawValue: fontRaw ?? "") ?? CrispyVibesTheme.default.fontFamily

        return CrispyVibesTheme(borderShape: shape, borderVisible: visible, fontFamily: font)
    }
}

// MARK: - Environment

private struct CrispyVibesThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = CrispyVibesTheme.default
}

extension EnvironmentValues {
    var crispyvibesTheme: CrispyVibesTheme {
        get { self[CrispyVibesThemeEnvironmentKey.self] }
        set { self[CrispyVibesThemeEnvironmentKey.self] = newValue }
    }
}
