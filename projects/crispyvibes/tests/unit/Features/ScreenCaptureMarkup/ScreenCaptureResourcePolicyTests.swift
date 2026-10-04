import XCTest
@testable import CrispyVibes

/// F062 capture defaults and pre-allocation resource boundaries.
@MainActor
final class ScreenCaptureResourcePolicyTests: XCTestCase {
    func test_firstUseDefaultsToRegionWithoutPointerOrDelay() {
        let preferences = ScreenCapturePreferences.default
        XCTAssertEqual(preferences.schemaVersion, ScreenCapturePreferences.currentSchemaVersion)
        XCTAssertEqual(preferences.mode, .region)
        XCTAssertEqual(preferences.options, .default)
        XCTAssertFalse(preferences.options.includesPointer)
        XCTAssertEqual(preferences.options.delay, .none)
    }

    func test_acceptsExact64MegapixelBoundaryWithin512MiB() throws {
        let bytes = try ScreenCaptureResourcePolicy().validate(pixelWidth: 8_000, pixelHeight: 8_000)
        XCTAssertEqual(bytes, 512_000_000)
    }

    func test_rejectsPixelLimitAndMultiplicationOverflowBeforeAllocation() {
        XCTAssertThrowsError(try ScreenCaptureResourcePolicy().validate(pixelWidth: 8_001, pixelHeight: 8_000))
        XCTAssertThrowsError(try ScreenCaptureResourcePolicy().validate(pixelWidth: Int.max, pixelHeight: Int.max))
    }
}
