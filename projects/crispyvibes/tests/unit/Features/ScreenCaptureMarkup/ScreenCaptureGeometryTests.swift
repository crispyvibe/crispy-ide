import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F062 canonical screen-to-native geometry.
@MainActor
final class ScreenCaptureGeometryTests: XCTestCase {
    private let display = ScreenCaptureDisplayDescriptor(
        id: 7,
        appKitFrame: CGRect(x: -1_440, y: 120, width: 1_440, height: 900),
        captureKitFrame: CGRect(x: -1_440, y: 0, width: 1_440, height: 900),
        visibleAppKitFrame: CGRect(x: -1_440, y: 120, width: 1_440, height: 875),
        backingScale: 2,
        nativePixelSize: CGSize(width: 2_880, height: 1_800)
    )

    func test_negativeOriginRetinaRegionUsesCoveringPixelsAndTopLeftY() throws {
        let geometry = ScreenCaptureGeometry()
        let appKitRect = CGRect(x: -1_429.75, y: 140.25, width: 100.5, height: 50.5)
        let local = geometry.clampedLocalRect(fromAppKit: appKitRect, on: display)
        XCTAssertEqual(local, CGRect(x: 10.25, y: 20.25, width: 100.5, height: 50.5))

        let pixels = try geometry.nativePixelRect(fromLocalAppKit: local, on: display)
        XCTAssertEqual(pixels.minX, 20)
        XCTAssertEqual(pixels.maxX, 222)
        XCTAssertEqual(pixels.minY, 1_658)
        XCTAssertEqual(pixels.maxY, 1_760)
        XCTAssertEqual(
            try geometry.captureKitSourceRect(fromNativePixelRect: pixels, on: display),
            CGRect(x: 10, y: 829, width: 101, height: 51)
        )
    }

    func test_pointerGeometryUsesTopLeftAndIndependentAxisRatiosWithoutGlobalOffset() throws {
        let mismatched = ScreenCaptureDisplayDescriptor(
            id: 11,
            appKitFrame: CGRect(x: -1_000, y: 250, width: 1_000, height: 600),
            captureKitFrame: CGRect(x: -1_000, y: -200, width: 1_000, height: 400),
            visibleAppKitFrame: CGRect(x: -1_000, y: 250, width: 1_000, height: 560),
            backingScale: 2,
            nativePixelSize: CGSize(width: 2_000, height: 1_200)
        )
        let geometry = ScreenCaptureGeometry()

        let nativePoint = try geometry.nativePixelPoint(
            fromLocalSwiftUIPoint: CGPoint(x: 100, y: 50),
            on: mismatched
        )
        XCTAssertEqual(nativePoint, CGPoint(x: 200, y: 100), "SwiftUI Y is already top-left")
        let nativeRect = try geometry.nativeSampleRect(
            centeredAt: nativePoint,
            size: CGSize(width: 20, height: 20),
            on: mismatched
        )
        XCTAssertEqual(nativeRect, CGRect(x: 190, y: 90, width: 20, height: 20))
        let sourceRect = try geometry.captureKitSourceRect(fromNativePixelRect: nativeRect, on: mismatched)
        XCTAssertEqual(sourceRect.origin.x, 95, accuracy: 0.0001)
        XCTAssertEqual(sourceRect.origin.y, 30, accuracy: 0.0001)
        XCTAssertEqual(sourceRect.width, 10, accuracy: 0.0001)
        XCTAssertEqual(sourceRect.height, 20.0 / 3.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(sourceRect.minX, 0, "Global display origin must not leak into sourceRect")
    }

    func test_pointerSampleShiftsAtEdgesWithoutShrinking() throws {
        let geometry = ScreenCaptureGeometry()
        let topLeft = try geometry.nativePixelPoint(
            fromLocalSwiftUIPoint: CGPoint(x: -50, y: -20),
            on: display
        )
        XCTAssertEqual(topLeft, .zero)
        XCTAssertEqual(
            try geometry.nativeSampleRect(centeredAt: topLeft, size: CGSize(width: 20, height: 20), on: display),
            CGRect(x: 0, y: 0, width: 20, height: 20)
        )

        let bottomRight = try geometry.nativePixelPoint(
            fromLocalSwiftUIPoint: CGPoint(x: 2_000, y: 2_000),
            on: display
        )
        XCTAssertEqual(bottomRight, CGPoint(x: 2_879, y: 1_799))
        let sample = try geometry.nativeSampleRect(
            centeredAt: bottomRight,
            size: CGSize(width: 20, height: 20),
            on: display
        )
        XCTAssertEqual(sample, CGRect(x: 2_860, y: 1_780, width: 20, height: 20))
        XCTAssertTrue(CGRect(origin: .zero, size: display.nativePixelSize).contains(sample))
    }

    func test_crossDisplayDragIsClampedBeforeCommit() {
        let geometry = ScreenCaptureGeometry()
        let crossing = CGRect(x: -100, y: 100, width: 300, height: 1_100)
        XCTAssertEqual(
            geometry.clampedLocalRect(fromAppKit: crossing, on: display),
            CGRect(x: 1_340, y: 0, width: 100, height: 900)
        )
    }
}
