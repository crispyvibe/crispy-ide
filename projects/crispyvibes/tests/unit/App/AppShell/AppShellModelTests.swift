import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class AppShellModelTests: XCTestCase {
    var container: AppContainer!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testAppearancePreferenceMetadata() {
        XCTAssertEqual(AppearancePreference.system.title, "Auto")
        XCTAssertEqual(AppearancePreference.light.title, "Light")
        XCTAssertEqual(AppearancePreference.dark.title, "Dark")
        XCTAssertEqual(AppearancePreference.system.symbolName, "circle.lefthalf.filled")
        XCTAssertEqual(AppearancePreference.light.symbolName, "sun.max")
        XCTAssertEqual(AppearancePreference.dark.symbolName, "moon")
        XCTAssertNil(AppearancePreference.system.colorScheme)
        XCTAssertEqual(AppearancePreference.light.colorScheme, .light)
        XCTAssertEqual(AppearancePreference.dark.colorScheme, .dark)
    }

    func testFirstRunAppearanceDefaultsUseAfterHoursRoundedBorders() {
        XCTAssertEqual(AppPreferences.defaultAppearancePreference, AppearancePreference.system.rawValue)
        XCTAssertEqual(AppPreferences.defaultAppThemePreset, AppThemePreset.ph.rawValue)
        XCTAssertEqual(AppThemePalette.decodeFromJSON(AppPreferences.defaultAppCustomThemePaletteJSON), .ph)
        XCTAssertEqual(CrispyVibesTheme.default.borderShape, .rounded)
        XCTAssertTrue(CrispyVibesTheme.default.borderVisible)
    }

    func testTerminalShellPreferenceMetadataAndResolver() {
        XCTAssertEqual(TerminalShellPreference.zsh.title, "zsh")
        XCTAssertEqual(TerminalShellPreference.bash.title, "bash")
        XCTAssertEqual(TerminalShellPreference.zsh.executablePath, "/bin/zsh")
        XCTAssertEqual(TerminalShellPreference.bash.executablePath, "/bin/bash")
        XCTAssertEqual(TerminalShellLaunchPolicy.startupArguments, ["-l", "-i"])
        XCTAssertEqual(AppPreferences.resolvedTerminalShellPreference(rawValue: "zsh"), .zsh)
        XCTAssertEqual(AppPreferences.resolvedTerminalShellPreference(rawValue: "bash"), .bash)
        XCTAssertEqual(AppPreferences.resolvedTerminalShellPreference(rawValue: "invalid"), .zsh)

        let suiteName = "terminal-shell-pref-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(AppPreferences.storedTerminalShellPreference(userDefaults: defaults))
        defaults.set(TerminalShellPreference.bash.rawValue, forKey: AppPreferences.terminalShellPreferenceKey)
        XCTAssertEqual(AppPreferences.storedTerminalShellPreference(userDefaults: defaults), .bash)
        defaults.set(TerminalShellPreference.zsh.rawValue, forKey: AppPreferences.terminalShellPreferenceKey)
        XCTAssertNil(AppPreferences.storedTerminalShellPreference(userDefaults: defaults))
        defaults.set(true, forKey: AppPreferences.terminalShellPreferenceExplicitSelectionKey)
        XCTAssertEqual(AppPreferences.storedTerminalShellPreference(userDefaults: defaults), .zsh)
        defaults.set("invalid", forKey: AppPreferences.terminalShellPreferenceKey)
        XCTAssertNil(AppPreferences.storedTerminalShellPreference(userDefaults: defaults))

        let precedenceContext = TerminalShellResolutionContext(
            vibespaceDefault: .bash,
            appDefault: .zsh,
            processEnvironmentShell: "/definitely/missing-shell"
        )
        let precedenceResolution = TerminalShellResolver.resolve(context: precedenceContext)
        XCTAssertEqual(precedenceResolution.selected.source, .vibespaceDefault)
        XCTAssertEqual(precedenceResolution.selected.executablePath, "/bin/bash")
        XCTAssertFalse(precedenceResolution.didFallback)

        let fallbackContext = TerminalShellResolutionContext(
            projectOverride: nil,
            vibespaceDefault: nil,
            appDefault: nil,
            processEnvironmentShell: "/definitely/missing-shell"
        )
        let fallbackResolution = TerminalShellResolver.resolve(context: fallbackContext)
        XCTAssertEqual(fallbackResolution.requested.source, .processEnvironment)
        XCTAssertEqual(fallbackResolution.selected.source, .hardcodedDefault)
        XCTAssertEqual(fallbackResolution.selected.executablePath, "/bin/zsh")
        XCTAssertTrue(fallbackResolution.didFallback)

        let processContext = TerminalShellResolutionContext(
            projectOverride: nil,
            vibespaceDefault: nil,
            appDefault: nil,
            processEnvironmentShell: "/bin/bash"
        )
        let processResolution = TerminalShellResolver.resolve(context: processContext)
        XCTAssertEqual(processResolution.selected.source, .processEnvironment)
        XCTAssertEqual(processResolution.selected.executablePath, "/bin/bash")
        XCTAssertFalse(processResolution.didFallback)
    }

    func testTerminalShellLaunchPolicyStartsLoginInteractiveShell() {
        XCTAssertTrue(TerminalShellLaunchPolicy.startupArguments.contains("-l"))
        XCTAssertTrue(TerminalShellLaunchPolicy.startupArguments.contains("-i"))
        XCTAssertEqual(TerminalShellLaunchPolicy.startupArguments.count, 2)
    }

    func testAppThemeResolverReturnsPackagedPresetPalettes() {
        let cases: [(AppThemePreset, AppThemePalette)] = [
            (.midnightMono, .midnightMono),
            (.graphiteDark, .graphiteDark),
            (.oceanDusk, .oceanDusk),
            (.forestNight, .forestNight),
            (.sunlitPaper, .sunlitPaper),
            (.pearlLight, .pearlLight),
            (.mintLight, .mintLight)
        ]

        for (preset, expectedPalette) in cases {
            let resolved = AppThemeResolver.palette(
                appearancePreferenceRaw: AppearancePreference.system.rawValue,
                fallbackSystemColorScheme: .dark,
                themePresetRaw: preset.rawValue,
                customThemeJSON: ""
            )
            XCTAssertEqual(resolved, expectedPalette)
        }
    }

    func testAppThemePaletteRoundTripAndRoleMutation() {
        var palette = AppThemePalette.midnightMono
        XCTAssertTrue(palette.setToken("#112233", for: .accent))
        XCTAssertEqual(palette.token(for: .accent), "#112233")
        XCTAssertFalse(palette.setToken("invalid-color-token", for: .accent))
        XCTAssertEqual(palette.token(for: .accent), "#112233")

        let encoded = AppThemePalette.encodeToJSON(palette)
        let decoded = AppThemePalette.decodeFromJSON(encoded)
        XCTAssertEqual(decoded, palette)
    }

    func testAppThemePaletteDecodeSupportsLegacyBackgroundKeys() throws {
        let encoded = AppThemePalette.encodeToJSON(.graphiteDark)
        let encodedData = try XCTUnwrap(encoded.data(using: .utf8))
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        payload["chromeBackground"] = payload["windowBackground"]
        payload["elevatedBackground"] = payload["canvasSecondaryBackground"]
        payload.removeValue(forKey: "windowBackground")
        payload.removeValue(forKey: "canvasSecondaryBackground")

        let legacyData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let legacyJSON = try XCTUnwrap(String(data: legacyData, encoding: .utf8))
        let decoded = try XCTUnwrap(AppThemePalette.decodeFromJSON(legacyJSON))

        XCTAssertEqual(decoded.windowBackground, AppThemePalette.graphiteDark.windowBackground)
        XCTAssertEqual(
            decoded.canvasSecondaryBackground,
            AppThemePalette.graphiteDark.canvasSecondaryBackground
        )
    }

    func testAppThemePaletteDecodeFallsBackWindowBackgroundToCanvasWhenMissing() throws {
        let encoded = AppThemePalette.encodeToJSON(.graphiteDark)
        let encodedData = try XCTUnwrap(encoded.data(using: .utf8))
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        payload.removeValue(forKey: "windowBackground")
        payload.removeValue(forKey: "chromeBackground")

        let legacyData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let legacyJSON = try XCTUnwrap(String(data: legacyData, encoding: .utf8))
        let decoded = try XCTUnwrap(AppThemePalette.decodeFromJSON(legacyJSON))

        XCTAssertEqual(decoded.windowBackground, decoded.canvasBackground)
        XCTAssertEqual(decoded.canvasBackground, AppThemePalette.graphiteDark.canvasBackground)
        XCTAssertEqual(decoded.accent, AppThemePalette.graphiteDark.accent)
    }

    func testAppThemePalettePreferredColorSchemeMatchesLuminance() {
        XCTAssertEqual(AppThemePalette.graphiteDark.preferredColorScheme, .dark)
        XCTAssertEqual(AppThemePalette.sunlitPaper.preferredColorScheme, .light)
    }

    func testAppThemeResolverResolvesSystemPresetByAppearanceAndFallbackScheme() {
        let resolvedDark = AppThemeResolver.palette(
            appearancePreferenceRaw: AppearancePreference.dark.rawValue,
            fallbackSystemColorScheme: .light,
            themePresetRaw: AppThemePreset.system.rawValue,
            customThemeJSON: ""
        )
        XCTAssertEqual(resolvedDark, .systemDark)

        let resolvedLightFromFallback = AppThemeResolver.palette(
            appearancePreferenceRaw: AppearancePreference.system.rawValue,
            fallbackSystemColorScheme: .light,
            themePresetRaw: AppThemePreset.system.rawValue,
            customThemeJSON: ""
        )
        XCTAssertEqual(resolvedLightFromFallback, .systemLight)
    }

    func testAppThemeResolverUsesCustomThemeJSONAndFallsBackWhenInvalid() {
        var custom = AppThemePalette.graphiteDark
        _ = custom.setToken("#44AA88", for: .accent)
        let encoded = AppThemePalette.encodeToJSON(custom)

        let resolvedCustom = AppThemeResolver.palette(
            appearancePreferenceRaw: AppearancePreference.dark.rawValue,
            fallbackSystemColorScheme: .dark,
            themePresetRaw: AppThemePreset.custom.rawValue,
            customThemeJSON: encoded
        )
        XCTAssertEqual(resolvedCustom, custom)

        let fallback = AppThemeResolver.palette(
            appearancePreferenceRaw: AppearancePreference.dark.rawValue,
            fallbackSystemColorScheme: .dark,
            themePresetRaw: AppThemePreset.custom.rawValue,
            customThemeJSON: "{invalid-json}"
        )
        XCTAssertEqual(fallback, .systemDark)
    }

    func testAppThemeResolverPreferredColorSchemeRemainsAutoForSystemPreset() {
        let preferred = AppThemeResolver.preferredColorScheme(
            appearancePreferenceRaw: AppearancePreference.system.rawValue,
            fallbackSystemColorScheme: .dark,
            themePresetRaw: AppThemePreset.system.rawValue,
            customThemeJSON: ""
        )
        XCTAssertNil(preferred)
    }

    func testAppThemeResolverPreferredColorSchemeRespectsExplicitAppearanceForSystemPreset() {
        let preferred = AppThemeResolver.preferredColorScheme(
            appearancePreferenceRaw: AppearancePreference.light.rawValue,
            fallbackSystemColorScheme: .dark,
            themePresetRaw: AppThemePreset.system.rawValue,
            customThemeJSON: ""
        )
        XCTAssertEqual(preferred, .light)
    }

    func testAppThemeResolverPreferredColorSchemeFollowsFixedPreset() {
        let preferredForLightPreset = AppThemeResolver.preferredColorScheme(
            appearancePreferenceRaw: AppearancePreference.dark.rawValue,
            fallbackSystemColorScheme: .dark,
            themePresetRaw: AppThemePreset.sunlitPaper.rawValue,
            customThemeJSON: ""
        )
        XCTAssertEqual(preferredForLightPreset, .light)

        let preferredForDarkPreset = AppThemeResolver.preferredColorScheme(
            appearancePreferenceRaw: AppearancePreference.light.rawValue,
            fallbackSystemColorScheme: .light,
            themePresetRaw: AppThemePreset.graphiteDark.rawValue,
            customThemeJSON: ""
        )
        XCTAssertEqual(preferredForDarkPreset, .dark)
    }

    func testAppThemePaletteSemanticMappingsUseCentralTokens() {
        let palette = AppThemePalette.graphiteDark

        XCTAssertEqual(
            ProjectColorTag(color: palette.primaryTextColor).storageToken,
            palette.terminalForeground.storageToken
        )
        XCTAssertEqual(
            ProjectColorTag(color: palette.gitAddedStatusColor).storageToken,
            palette.success.storageToken
        )
        XCTAssertEqual(
            ProjectColorTag(color: palette.gitModifiedStatusColor).storageToken,
            palette.warning.storageToken
        )
        XCTAssertEqual(
            ProjectColorTag(color: palette.gitDeletedStatusColor).storageToken,
            palette.error.storageToken
        )
        XCTAssertEqual(
            ProjectColorTag(color: palette.gitRenamedStatusColor).storageToken,
            palette.accent.storageToken
        )
        XCTAssertEqual(
            ProjectColorTag(color: palette.gitConflictStatusColor).storageToken,
            palette.accentStrong.storageToken
        )

        XCTAssertNotEqual(
            ProjectColorTag(color: palette.secondaryTextColor).storageToken,
            palette.terminalForeground.storageToken
        )
    }

    func testAppThemeColorRoleTitlesAndTokenAccessorsCoverAllCases() {
        var palette = AppThemePalette.midnightMono
        for role in AppThemeColorRole.allCases {
            XCTAssertFalse(role.title.isEmpty)
            let originalToken = palette.token(for: role)
            XCTAssertFalse(originalToken.isEmpty)

            XCTAssertTrue(palette.setToken("#123456", for: role))
            XCTAssertEqual(palette.token(for: role), "#123456")
        }
    }

    func testAppThemePaletteDefaultCustomBaseCoversAllPresets() {
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .system), .systemDark)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .midnightMono), .midnightMono)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .graphiteDark), .graphiteDark)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .oceanDusk), .oceanDusk)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .forestNight), .forestNight)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .sunlitPaper), .sunlitPaper)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .pearlLight), .pearlLight)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .mintLight), .mintLight)
        XCTAssertEqual(AppThemePalette.defaultCustomBase(from: .custom), .midnightMono)
    }

    func testAppThemePaletteSelectionAndTerminalAccentHelpers() {
        let darkPalette = AppThemePalette.midnightMono
        let lightPalette = AppThemePalette.sunlitPaper

        let expectedDarkSelectionText = darkPalette.selectionBackground.relativeLuminance < 0.35
            ? "#FFFFFF"
            : "#111111"
        let expectedLightSelectionText = lightPalette.selectionBackground.relativeLuminance < 0.35
            ? "#FFFFFF"
            : "#111111"
        XCTAssertEqual(darkPalette.selectionText.storageToken, expectedDarkSelectionText)
        XCTAssertEqual(lightPalette.selectionText.storageToken, expectedLightSelectionText)

        let darkSelection = darkPalette.terminalSelectionBackground
        let lightSelection = lightPalette.terminalSelectionBackground
        XCTAssertEqual(darkSelection.alpha, 0.54, accuracy: 0.001)
        XCTAssertEqual(lightSelection.alpha, 0.68, accuracy: 0.001)
    }

    func testAppThemePaletteColorTokenFallbackWhenInvalidInputProvided() {
        let token = AppThemePalette.colorToken("invalid-token")
        XCTAssertEqual(token.red, 0.21, accuracy: 0.001)
        XCTAssertEqual(token.green, 0.56, accuracy: 0.001)
        XCTAssertEqual(token.blue, 0.91, accuracy: 0.001)
    }

    func testWindowBackgroundDraggingPolicyAlwaysDisabled() {
        XCTAssertFalse(AppDelegate.windowBackgroundDraggingAllowed(prefersDarkWindowChrome: true))
        XCTAssertFalse(AppDelegate.windowBackgroundDraggingAllowed(prefersDarkWindowChrome: false))
    }
}
