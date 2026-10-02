import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F009 Phase 0: crop selection → pixel rectangle mapping (top-left origin, floor/ceil edges).
final class RasterImageCropGeometryTests: XCTestCase {
    func test_topSelection_mapsToTopPixelRows_withoutVerticalInversion() {
        let rect = RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 0, y: 0, width: 100, height: 20),
            imagePointSize: CGSize(width: 100, height: 80),
            pixelWidth: 100,
            pixelHeight: 80
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 100, height: 20))
    }

    func test_fractionalEdges_roundOutward() {
        let rect = RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 10.4, y: 5.6, width: 20.2, height: 10.1),
            imagePointSize: CGSize(width: 100, height: 100),
            pixelWidth: 100,
            pixelHeight: 100
        )
        // minX floor(10.4)=10, maxX ceil(30.6)=31, minY floor(5.6)=5, maxY ceil(15.7)=16
        XCTAssertEqual(rect, CGRect(x: 10, y: 5, width: 21, height: 11))
    }

    func test_retinaScale_convertsBeforeRounding() {
        let rect = RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 10.25, y: 10.75, width: 5.5, height: 4),
            imagePointSize: CGSize(width: 50, height: 50),
            pixelWidth: 100,
            pixelHeight: 100
        )
        // ×2: minX 20.5→20, maxX 31.5→32, minY 21.5→21, maxY 29.5→30
        XCTAssertEqual(rect, CGRect(x: 20, y: 21, width: 12, height: 9))
    }

    func test_nonUniformScale_usesPerAxisScale() {
        let rect = RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 10, y: 10, width: 10, height: 10),
            imagePointSize: CGSize(width: 100, height: 100),
            pixelWidth: 200,
            pixelHeight: 300
        )
        XCTAssertEqual(rect, CGRect(x: 20, y: 30, width: 20, height: 30))
    }

    func test_selectionOutsideBounds_isClampedOnce() {
        let rect = RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: -20, y: 70, width: 60, height: 60),
            imagePointSize: CGSize(width: 100, height: 80),
            pixelWidth: 100,
            pixelHeight: 80
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 70, width: 40, height: 10))
    }

    func test_reverseDrag_negativeSizeIsStandardized() {
        let rect = RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 50, y: 40, width: -30, height: -20),
            imagePointSize: CGSize(width: 100, height: 80),
            pixelWidth: 100,
            pixelHeight: 80
        )
        XCTAssertEqual(rect, CGRect(x: 20, y: 20, width: 30, height: 20))
    }

    func test_tinyOrDegenerateSelection_isRejected() {
        XCTAssertNil(RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 10, y: 10, width: 0.5, height: 0.5),
            imagePointSize: CGSize(width: 100, height: 100),
            pixelWidth: 100,
            pixelHeight: 100
        ))
        XCTAssertNil(RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 200, y: 200, width: 10, height: 10),
            imagePointSize: CGSize(width: 100, height: 100),
            pixelWidth: 100,
            pixelHeight: 100
        ))
        XCTAssertNil(RasterImageCropGeometry.pixelRect(
            forSelection: CGRect(x: 0, y: 0, width: 10, height: 10),
            imagePointSize: .zero,
            pixelWidth: 100,
            pixelHeight: 100
        ))
    }

    func test_pointRect_roundTripsPixelRect() {
        let point = RasterImageCropGeometry.pointRect(
            forPixelRect: CGRect(x: 20, y: 30, width: 40, height: 50),
            imagePointSize: CGSize(width: 50, height: 100),
            pixelWidth: 100,
            pixelHeight: 200
        )
        XCTAssertEqual(point, CGRect(x: 10, y: 15, width: 20, height: 25))
    }

    func test_coveringPixelRect_snapsFloatingErrorInsteadOfGrowing() {
        // 33 px of a 300 px bitmap over a 100-unit canvas is 11.000000000000002 units.
        let units = 33 * (100.0 / 300.0)
        let rect = RasterImageCropGeometry.coveringPixelRect(
            forCanvasRect: CGRect(x: units, y: units, width: units, height: units),
            canvasSize: CGSize(width: 100, height: 100),
            pixelWidth: 300,
            pixelHeight: 300
        )
        XCTAssertEqual(rect, CGRect(x: 33, y: 33, width: 33, height: 33))
    }

    func test_coveringPixelRect_usesIndependentAxisScalesForRoundedProxies() {
        // A 1000×333 canvas shown through a 300×100 proxy (height rounded independently).
        let rect = RasterImageCropGeometry.coveringPixelRect(
            forCanvasRect: CGRect(x: 500, y: 0, width: 500, height: 333),
            canvasSize: CGSize(width: 1000, height: 333),
            pixelWidth: 300,
            pixelHeight: 100
        )
        XCTAssertEqual(rect, CGRect(x: 150, y: 0, width: 150, height: 100))
    }

    func test_coveringPixelRect_stillRoundsGenuineFractionsOutward() {
        let rect = RasterImageCropGeometry.coveringPixelRect(
            forCanvasRect: CGRect(x: 10.001, y: 0, width: 9.998, height: 10),
            canvasSize: CGSize(width: 100, height: 100),
            pixelWidth: 100,
            pixelHeight: 100
        )
        XCTAssertEqual(rect, CGRect(x: 10, y: 0, width: 10, height: 10))
    }
}
