import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import CrispyVibes

/// F009 Phase 1: operation replay, display/export parity, and full-resolution export.
@MainActor
final class RasterImageRendererTests: XCTestCase {
    private let fixtures = RasterImageTestFixtures.self
    private let renderer = RasterImageRenderer()
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RasterRendererTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func test_replayIsDeterministicAcrossScales() throws {
        let canvas = CGSize(width: 100, height: 60)
        let operations: [ImageEditOperation] = [
            .stroke(RasterStroke(points: [CGPoint(x: 0, y: 10), CGPoint(x: 100, y: 10)], lineWidth: 6)),
            .crop(CGRect(x: 50, y: 0, width: 50, height: 30))
        ]
        let full = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 400, height: 240), baseCanvasSize: canvas, operations: operations))
        let proxy = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 100, height: 60), baseCanvasSize: canvas, operations: operations))
        XCTAssertEqual(full.width, 200)
        XCTAssertEqual(full.height, 120)
        XCTAssertEqual(proxy.width, 50)
        XCTAssertEqual(proxy.height, 30)
        // Same relative positions show the same content at both scales.
        for (fx, fy) in [(0.5, 0.75), (0.25, 0.08)] {
            let a = fixtures.pixel(full, x: Int(Double(full.width) * fx), y: Int(Double(full.height) * fy))
            let b = fixtures.pixel(proxy, x: Int(Double(proxy.width) * fx), y: Int(Double(proxy.height) * fy))
            XCTAssertTrue(fixtures.matches(a, b, tolerance: 30), "(\(fx),\(fy)) full \(a) proxy \(b)")
        }
        XCTAssertTrue(fixtures.matches(fixtures.pixel(full, x: 100, y: 90), fixtures.quadrantColors[1], tolerance: 2))
    }

    func test_strokeBeforeCrop_isClippedByCrop_andTranslated() throws {
        let operations: [ImageEditOperation] = [
            .stroke(RasterStroke(points: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)], color: RasterColor(red: 1, green: 1, blue: 1), lineWidth: 4)),
            .crop(CGRect(x: 0, y: 30, width: 100, height: 30))
        ]
        let image = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 100, height: 60), baseCanvasSize: CGSize(width: 100, height: 60), operations: operations))
        XCTAssertEqual(image.height, 30)
        let onStroke = fixtures.pixel(image, x: 20, y: 20)
        XCTAssertTrue(fixtures.matches(onStroke, (255, 255, 255), tolerance: 10), "stroke at canvas y=50 lands at cropped y=20, got \(onStroke)")
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 20, y: 5), fixtures.quadrantColors[2], tolerance: 2))
    }

    func test_operationsAfterCrop_useCroppedCanvasSpace() throws {
        let operations: [ImageEditOperation] = [
            .crop(CGRect(x: 50, y: 30, width: 50, height: 30)),
            .stroke(RasterStroke(points: [CGPoint(x: 0, y: 2), CGPoint(x: 50, y: 2)], color: RasterColor(red: 0, green: 0, blue: 0), lineWidth: 4))
        ]
        let image = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 100, height: 60), baseCanvasSize: CGSize(width: 100, height: 60), operations: operations))
        XCTAssertEqual(image.width, 50)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 25, y: 1), (0, 0, 0), tolerance: 20))
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 25, y: 20), fixtures.quadrantColors[3], tolerance: 2))
    }

    func test_sequentialCrops_compose() throws {
        let operations: [ImageEditOperation] = [
            .crop(CGRect(x: 50, y: 0, width: 50, height: 60)),
            .crop(CGRect(x: 0, y: 30, width: 50, height: 30))
        ]
        let image = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 100, height: 60), baseCanvasSize: CGSize(width: 100, height: 60), operations: operations))
        XCTAssertEqual(image.width, 50)
        XCTAssertEqual(image.height, 30)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 25, y: 15), fixtures.quadrantColors[3], tolerance: 2))
    }

    func test_exportFromFile_usesFullResolutionNotDisplayProxy() throws {
        let url = tempRoot.appendingPathComponent("large.png")
        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 600, height: 400)], type: .png, to: url))
        var smallDecoder = RasterImageDecoder()
        smallDecoder.fullResolutionEdgeLimit = 16
        let decoded = try XCTUnwrap(smallDecoder.decode(contentsOf: url, maxPixelSize: 150))
        XCTAssertLessThan(decoded.image.width, 600, "display uses a proxy")

        let session = RasterImageEditSession(
            document: RasterImageDocument(source: .file(url), baseCanvasSize: CGSize(width: 600, height: 400), exportScale: 1),
            displayImage: decoded.image,
            sourceInfo: decoded.sourceInfo,
            renderer: renderer
        )
        XCTAssertEqual(session.applyCrop(selection: CGRect(x: 300, y: 0, width: 300, height: 200)), .success)
        XCTAssertLessThan(session.flattenedDisplayImage.width, 300)

        let output = try RasterImageExportService.run(
            session.makeExportJob(destinationURL: tempRoot.appendingPathComponent("out.png")),
            handle: nil, decoder: smallDecoder, renderer: renderer, encoder: RasterImageEncoder()
        ).get()
        XCTAssertEqual(output.image.width, 300)
        XCTAssertEqual(output.image.height, 200)
        XCTAssertNotNil(output.data)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(output.image, x: 150, y: 100), fixtures.quadrantColors[1], tolerance: 2))
    }

    func test_exportService_deliversOnMain_andHonorsCancellation() {
        let service = RasterImageExportService(decoder: RasterImageDecoder(), renderer: renderer, encoder: RasterImageEncoder())
        let job = RasterImageExportJob(
            source: .memory(fixtures.quadrantImage(width: 20, height: 20)),
            baseCanvasSize: CGSize(width: 20, height: 20),
            operations: [],
            revision: 7,
            destinationURL: nil
        )
        let delivered = expectation(description: "delivered")
        service.export(job) { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(try? result.get().revision, 7)
            delivered.fulfill()
        }
        let cancelled = expectation(description: "cancelled job never completes")
        cancelled.isInverted = true
        service.export(job) { _ in cancelled.fulfill() }.cancel()
        wait(for: [delivered, cancelled], timeout: 1)
    }

    func test_exportFromMissingFile_fails() {
        let job = RasterImageExportJob(
            source: .file(tempRoot.appendingPathComponent("missing.png")),
            baseCanvasSize: CGSize(width: 10, height: 10),
            operations: [],
            revision: 0,
            destinationURL: nil
        )
        let result = RasterImageExportService.run(job, handle: nil, decoder: RasterImageDecoder(), renderer: renderer, encoder: RasterImageEncoder())
        XCTAssertThrowsError(try result.get())
    }
}
