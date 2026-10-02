import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CrispyVibes

/// F009 Phase 2: rotate / flip / straighten / resize replay and export formats.
final class RasterImageGeometryTests: XCTestCase {
    private let fixtures = RasterImageTestFixtures.self
    private let renderer = RasterImageRenderer()
    private let canvas = CGSize(width: 100, height: 60)

    private func render(_ operations: [ImageEditOperation], width: Int = 100, height: Int = 60) throws -> CGImage {
        try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: width, height: height), baseCanvasSize: canvas, operations: operations))
    }

    /// Quadrant color index found at each output quadrant center (TL, TR, BL, BR).
    private func quadrants(_ image: CGImage) -> [Int?] {
        let w = image.width, h = image.height
        return [(w / 4, h / 4), (3 * w / 4, h / 4), (w / 4, 3 * h / 4), (3 * w / 4, 3 * h / 4)].map { x, y in
            let pixel = fixtures.pixel(image, x: x, y: y)
            return fixtures.quadrantColors.firstIndex { fixtures.matches(pixel, $0, tolerance: 4) }
        }
    }

    func test_rotateClockwise_andCounterClockwise() throws {
        let cw = try render([.rotate(quarterTurns: 1)])
        XCTAssertEqual(cw.width, 60)
        XCTAssertEqual(cw.height, 100)
        XCTAssertEqual(quadrants(cw), [2, 0, 3, 1])
        let ccw = try render([.rotate(quarterTurns: 3)])
        XCTAssertEqual(quadrants(ccw), [1, 3, 0, 2])
        XCTAssertEqual(quadrants(try render([.rotate(quarterTurns: 2)])), [3, 2, 1, 0])
    }

    func test_fourRotations_andDoubleFlips_areIdentity() throws {
        XCTAssertEqual(quadrants(try render(Array(repeating: .rotate(quarterTurns: 1), count: 4))), [0, 1, 2, 3])
        XCTAssertEqual(quadrants(try render([.flip(horizontal: true), .flip(horizontal: true)])), [0, 1, 2, 3])
    }

    func test_flips() throws {
        XCTAssertEqual(quadrants(try render([.flip(horizontal: true)])), [1, 0, 3, 2])
        XCTAssertEqual(quadrants(try render([.flip(horizontal: false)])), [2, 3, 0, 1])
    }

    func test_cropAfterRotate_usesRotatedCanvas() throws {
        // After a clockwise turn the canvas is 60×100; its top-right quarter holds red (index 0).
        let image = try render([.rotate(quarterTurns: 1), .crop(CGRect(x: 30, y: 0, width: 30, height: 50))])
        XCTAssertEqual(image.width, 30)
        XCTAssertEqual(image.height, 50)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 15, y: 25), fixtures.quadrantColors[0], tolerance: 2))
    }

    func test_strokeBeforeRotate_rotatesWithPixels() throws {
        let stroke = ImageEditOperation.stroke(RasterStroke(points: [CGPoint(x: 0, y: 2), CGPoint(x: 100, y: 2)],
                                                            color: RasterColor(red: 1, green: 1, blue: 1), lineWidth: 4))
        let image = try render([stroke, .rotate(quarterTurns: 1)])
        // A line along the top edge ends up along the right edge after a clockwise turn.
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 58, y: 50), (255, 255, 255), tolerance: 10))
        XCTAssertFalse(fixtures.matches(fixtures.pixel(image, x: 2, y: 50), (255, 255, 255), tolerance: 10))
    }

    func test_straighten_cropsToInscribedRectangle_withoutTransparentCorners() throws {
        let radians = 10.0 * .pi / 180
        let expected = ImageEditOperation.straightenedSize(for: canvas, radians: radians)
        XCTAssertLessThan(expected.width, 100)
        XCTAssertEqual(expected.width / expected.height, 100.0 / 60.0, accuracy: 0.0001)
        let image = try render([.straighten(radians: radians)], width: 400, height: 240)
        XCTAssertEqual(Double(image.width), Double(expected.width * 4), accuracy: 1)
        let context = fixtures.makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(1, 1), (image.width - 2, 1), (1, image.height - 2), (image.width - 2, image.height - 2)] {
            XCTAssertGreaterThan(data[y * context.bytesPerRow + x * 4 + 3], 200, "corner (\(x),\(y)) must be opaque")
        }
    }

    func test_resize_scalesPixels_andPreservesLayout() throws {
        let image = try render([.resize(CGSize(width: 50, height: 30))])
        XCTAssertEqual(image.width, 50)
        XCTAssertEqual(image.height, 30)
        XCTAssertEqual(quadrants(image), [0, 1, 2, 3])
        let proxy = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 50, height: 30), baseCanvasSize: canvas,
                                                  operations: [.resize(CGSize(width: 200, height: 120))]))
        XCTAssertEqual(proxy.width, 100, "proxy keeps its own pixel scale")
    }

    func test_geometryTransform_mapsPointsConsistently() {
        let rotate = ImageEditOperation.rotate(quarterTurns: 1).geometry(for: canvas)
        XCTAssertEqual(rotate.size, CGSize(width: 60, height: 100))
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(rotate.transform), CGPoint(x: 60, y: 0))
        XCTAssertEqual(CGPoint(x: 100, y: 60).applying(rotate.transform), CGPoint(x: 0, y: 100))
        let flip = ImageEditOperation.flip(horizontal: false).geometry(for: canvas)
        XCTAssertEqual(CGPoint(x: 10, y: 0).applying(flip.transform), CGPoint(x: 10, y: 60))
    }

    func test_exportOptions_encodeRequestedFormatAndQuality() throws {
        let image = fixtures.quadrantImage(width: 64, height: 64)
        let url = URL(fileURLWithPath: "/tmp/ignored.png")
        let encoder = RasterImageEncoder()
        let high = try encoder.encodedData(for: image, destinationURL: url, options: RasterImageExportOptions(format: .jpeg, quality: 1))
        let low = try encoder.encodedData(for: image, destinationURL: url, options: RasterImageExportOptions(format: .jpeg, quality: 0.1))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(high as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier, "options override the .png extension")
        XCTAssertLessThan(low.count, high.count)
        let heic = try encoder.encodedData(for: image, destinationURL: url, options: RasterImageExportOptions(format: .heic, quality: 0.8))
        XCTAssertEqual(CGImageSourceGetType(try XCTUnwrap(CGImageSourceCreateWithData(heic as CFData, nil))) as String?, UTType.heic.identifier)
    }

    func test_exportFormat_fromExtension() {
        XCTAssertEqual(RasterImageExportFormat(fileExtension: "JPEG"), .jpeg)
        XCTAssertEqual(RasterImageExportFormat(fileExtension: "tif"), .tiff)
        XCTAssertNil(RasterImageExportFormat(fileExtension: "gif"))
        XCTAssertEqual(RasterImageExportFormat.jpeg.fileExtension, "jpg")
        XCTAssertFalse(RasterImageExportFormat.jpeg.supportsAlpha)
    }

    // MARK: - Canonical geometry (Phase 2 audit)

    @MainActor
    func test_repeatedStraighten_keepsModelAndRenderedPixelsInSync() throws {
        let base = fixtures.quadrantImage(width: 100, height: 60)
        let session = RasterImageEditSession.inMemory(base, canvasSize: CGSize(width: 100, height: 60))
        for operation: ImageEditOperation in [.straighten(radians: 0.17), .straighten(radians: 0.17), .rotate(quarterTurns: 1),
                                              .straighten(radians: -0.05), .resize(CGSize(width: 33, height: 51))] {
            XCTAssertTrue(session.commit(operation))
            let predicted = session.exportTransform.pixelSize
            XCTAssertEqual(session.canvasSize.width, session.canvasSize.width.rounded(), accuracy: 1e-9, "canvas stays integral")
            let output = try RasterImageExportService.run(session.makeExportJob(destinationURL: nil), handle: nil,
                                                          decoder: RasterImageDecoder(), renderer: renderer, encoder: RasterImageEncoder()).get()
            XCTAssertEqual(output.image.width, predicted.width, "after \(operation)")
            XCTAssertEqual(output.image.height, predicted.height, "after \(operation)")
        }
    }

    func test_fixedScaleReplay_onOddProxy_tracksCanonicalSize() throws {
        let canvas = CGSize(width: 1001, height: 333)
        let ops: [ImageEditOperation] = [
            .straighten(radians: 0.1, outputSize: CGSize(width: 900, height: 299)),
            .rotate(quarterTurns: 1),
            .resize(CGSize(width: 150, height: 451))
        ]
        let full = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 1001, height: 333), baseCanvasSize: canvas, operations: ops))
        XCTAssertEqual(full.width, 150)
        XCTAssertEqual(full.height, 451)
        let proxy = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 301, height: 100), baseCanvasSize: canvas, operations: ops))
        XCTAssertEqual(Double(proxy.width), 150 * 100.0 / 333.0, accuracy: 1.0, "proxy follows canonical size, not compounded rounding")
        XCTAssertEqual(Double(proxy.height), 451 * 301.0 / 1001.0, accuracy: 1.0)
    }
}
