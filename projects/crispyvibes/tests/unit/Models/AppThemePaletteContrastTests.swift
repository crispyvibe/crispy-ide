import XCTest
@testable import CrispyVibes

/// Guards every built-in theme against the contrast floors that keep themes
/// readable. New presets that fail these floors should be fixed, not exempted.
final class AppThemePaletteContrastTests: XCTestCase {
    private static let bodyTextFloor = 6.0
    private static let mutedTextFloor = 4.5
    private static let statusColorFloor = 3.0
    private static let selectionTextFloor = 4.5
    private static let borderRange = 1.3...3.1

    // High-contrast themes intentionally exceed the border ceiling.
    private static let borderCeilingExempt: Set<AppThemePreset> = [.highContrast, .highContrastLight]

    private var presetsUnderTest: [(AppThemePreset, AppThemePalette)] {
        var entries: [(AppThemePreset, AppThemePalette)] = AppThemePreset.allCases
            .filter { $0 != .custom }
            .map { ($0, AppThemePalette.defaultCustomBase(from: $0)) }
        entries.append((.system, .systemLight))
        return entries
    }

    private func contrastRatio(_ lhs: ProjectColorTag, _ rhs: ProjectColorTag) -> Double {
        let l1 = lhs.relativeLuminance
        let l2 = rhs.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func minContrast(_ color: ProjectColorTag, against surfaces: [ProjectColorTag]) -> Double {
        surfaces.map { contrastRatio(color, $0) }.min() ?? 0
    }

    func testBodyAndMutedTextAreReadableOnAllSurfaces() {
        for (preset, palette) in presetsUnderTest {
            let surfaces = [palette.windowBackground, palette.canvasBackground, palette.canvasSecondaryBackground]
            XCTAssertGreaterThanOrEqual(
                minContrast(palette.terminalForeground, against: surfaces),
                Self.bodyTextFloor,
                "\(preset.rawValue): terminalForeground fails body text floor"
            )
            XCTAssertGreaterThanOrEqual(
                minContrast(palette.mutedForeground, against: surfaces),
                Self.mutedTextFloor,
                "\(preset.rawValue): mutedForeground fails muted text floor"
            )
        }
    }

    func testAccentAndStatusColorsMeetMinimumContrast() {
        for (preset, palette) in presetsUnderTest {
            let surfaces = [palette.canvasBackground, palette.canvasSecondaryBackground]
            let roles: [(String, ProjectColorTag)] = [
                ("accent", palette.accent),
                ("success", palette.success),
                ("warning", palette.warning),
                ("error", palette.error),
            ]
            for (role, color) in roles {
                XCTAssertGreaterThanOrEqual(
                    minContrast(color, against: surfaces),
                    Self.statusColorFloor,
                    "\(preset.rawValue): \(role) fails status color floor"
                )
            }
        }
    }

    func testBordersAreVisibleButNotLoud() {
        for (preset, palette) in presetsUnderTest {
            let ratio = contrastRatio(palette.borderColor, palette.canvasBackground)
            XCTAssertGreaterThanOrEqual(
                ratio, Self.borderRange.lowerBound,
                "\(preset.rawValue): border is invisible against canvas"
            )
            if !Self.borderCeilingExempt.contains(preset) {
                XCTAssertLessThanOrEqual(
                    ratio, Self.borderRange.upperBound,
                    "\(preset.rawValue): border is louder than a hairline"
                )
            }
        }
    }

    func testSelectionMatchesThemePolarityAndKeepsTextReadable() {
        for (preset, palette) in presetsUnderTest {
            let isDarkTheme = palette.prefersDarkWindowChrome
            let selectionIsDark = palette.selectionBackground.relativeLuminance < 0.35
            XCTAssertEqual(
                selectionIsDark, isDarkTheme,
                "\(preset.rawValue): selection background flips theme polarity"
            )
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.selectionText, palette.selectionBackground),
                Self.selectionTextFloor,
                "\(preset.rawValue): selection text is unreadable on selection background"
            )
        }
    }

    func testCustomThemeJSONRoundTripPreservesMutedForeground() {
        let palette = AppThemePalette.oceanDusk
        let json = AppThemePalette.encodeToJSON(palette)
        let decoded = AppThemePalette.decodeFromJSON(json)
        XCTAssertEqual(decoded, palette)
    }

    func testLegacyCustomThemeJSONDecodesWithDerivedMutedForeground() throws {
        let json = AppThemePalette.encodeToJSON(.oceanDusk)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        object.removeValue(forKey: "mutedForeground")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacyJSON = try XCTUnwrap(String(data: legacyData, encoding: .utf8))

        let decoded = try XCTUnwrap(
            AppThemePalette.decodeFromJSON(legacyJSON),
            "legacy custom theme JSON without mutedForeground must still decode"
        )
        XCTAssertEqual(decoded.terminalForeground, AppThemePalette.oceanDusk.terminalForeground)
    }
}
