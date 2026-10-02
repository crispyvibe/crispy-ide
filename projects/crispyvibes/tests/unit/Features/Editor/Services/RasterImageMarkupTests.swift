import AppKit
import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F009 Phase 3: editable markup, pixel effects, adjustments, and history coalescing.
@MainActor
final class RasterImageMarkupTests: XCTestCase {
    private let fixtures = RasterImageTestFixtures.self
    private let renderer = RasterImageRenderer()
    private let canvasSize = CGSize(width: 100, height: 60)
    private let white = RasterColor(red: 1, green: 1, blue: 1)

    private func session() -> RasterImageEditSession {
        .inMemory(fixtures.quadrantImage(width: 100, height: 60), canvasSize: canvasSize)
    }

    private func render(_ operations: [ImageEditOperation]) throws -> CGImage {
        try XCTUnwrap(renderer.renderAdjusted(base: fixtures.quadrantImage(width: 100, height: 60), baseCanvasSize: canvasSize, operations: operations))
    }

    private func item(_ kind: RasterMarkupItem.Kind, stroke: RasterColor? = nil, fill: RasterColor? = nil, width: CGFloat = 4) -> RasterMarkupItem {
        var style = RasterMarkupStyle.default
        if let stroke { style.strokeColor = stroke }
        style.fillColor = fill
        style.lineWidth = width
        return RasterMarkupItem(kind: kind, style: style)
    }

    // MARK: - Rendering

    func test_redact_isOpaque_andUnderlyingPixelsAreGone() throws {
        let image = try render([.markup(item(.redact(CGRect(x: 0, y: 0, width: 50, height: 30))))])
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 25, y: 15), (0, 0, 0), tolerance: 1))
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 75, y: 15), fixtures.quadrantColors[1], tolerance: 2))
    }

    func test_pixelate_replacesDetailWithinRectOnly() throws {
        // Stripe pattern: pixelating with large cells averages it out.
        let stripes = ImageEditOperation.markup(item(.rectangle(CGRect(x: 10, y: 10, width: 20, height: 1)), stroke: white, width: 1))
        let image = try render([stripes, .markup(item(.pixelate(CGRect(x: 0, y: 0, width: 50, height: 30))))])
        let outside = fixtures.pixel(image, x: 75, y: 15)
        XCTAssertTrue(fixtures.matches(outside, fixtures.quadrantColors[1], tolerance: 2), "outside untouched")
        let cell = fixtures.pixel(image, x: 2, y: 2)
        let neighbour = fixtures.pixel(image, x: 3, y: 3)
        XCTAssertTrue(fixtures.matches(cell, neighbour, tolerance: 1), "pixels within one cell are uniform")
    }

    func test_blur_softensEdgeInsideRect_andLeavesOutsideSharp() throws {
        // Blur straddling the vertical quadrant boundary (x = 50) in the top half.
        let image = try render([.markup(item(.blur(CGRect(x: 30, y: 0, width: 40, height: 30))))])
        let atEdge = fixtures.pixel(image, x: 50, y: 15)
        XCTAssertGreaterThan(Int(atEdge.r), 30, "red bleeds across the edge")
        XCTAssertGreaterThan(Int(atEdge.g), 30, "green bleeds across the edge")
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 50, y: 45), fixtures.quadrantColors[3], tolerance: 2) ||
                      fixtures.matches(fixtures.pixel(image, x: 50, y: 45), fixtures.quadrantColors[2], tolerance: 2),
                      "below the blur rect stays sharp")
    }

    func test_blurUsesPixelsComposedSoFar_includingEarlierMarkup() throws {
        let line = ImageEditOperation.markup(item(.rectangle(CGRect(x: 0, y: 14, width: 100, height: 2)), stroke: white, fill: white, width: 1))
        let blurred = try render([line, .markup(item(.blur(CGRect(x: 0, y: 0, width: 100, height: 30))))])
        let sharp = try render([line])
        XCTAssertNotEqual(Int(fixtures.pixel(blurred, x: 75, y: 10).r), Int(fixtures.pixel(sharp, x: 75, y: 10).r), "the white line is blurred into its surroundings")
    }

    func test_arrowAndShapesRenderAtTheirCoordinates() throws {
        let image = try render([
            .markup(item(.arrow(from: CGPoint(x: 5, y: 50), to: CGPoint(x: 45, y: 50)), stroke: white, width: 4)),
            .markup(item(.ellipse(CGRect(x: 60, y: 5, width: 30, height: 20)), stroke: white, fill: white, width: 1))
        ])
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 20, y: 50), (255, 255, 255), tolerance: 10), "arrow shaft")
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 75, y: 15), (255, 255, 255), tolerance: 10), "filled ellipse")
        XCTAssertTrue(fixtures.matches(fixtures.pixel(image, x: 61, y: 6), fixtures.quadrantColors[1], tolerance: 2), "outside ellipse corner")
    }

    func test_proxyAndFullResolutionMarkupMatch() throws {
        let ops: [ImageEditOperation] = [
            .markup(item(.redact(CGRect(x: 10, y: 10, width: 30, height: 15)))),
            .markup(item(.pixelate(CGRect(x: 60, y: 30, width: 30, height: 20))))
        ]
        let full = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 400, height: 240), baseCanvasSize: canvasSize, operations: ops))
        let proxy = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: 100, height: 60), baseCanvasSize: canvasSize, operations: ops))
        XCTAssertTrue(fixtures.matches(fixtures.pixel(full, x: 100, y: 70), fixtures.pixel(proxy, x: 25, y: 17), tolerance: 2))
    }

    // MARK: - Adjustments

    func test_adjustments_changeBaseColors_andComposeWithMarkup() throws {
        let darker = try render([.adjust(RasterImageAdjustments(exposure: -1))])
        XCTAssertLessThan(Int(fixtures.pixel(darker, x: 25, y: 15).r), 200)
        let gray = try render([.adjust(RasterImageAdjustments(saturation: -1))])
        let p = fixtures.pixel(gray, x: 75, y: 15)
        XCTAssertLessThan(abs(Int(p.r) - Int(p.g)), 12, "desaturated green has near-equal channels")
        // Markup is drawn after adjustments, so a white redact-like fill stays white.
        let withMarkup = try render([.adjust(RasterImageAdjustments(exposure: -2)),
                                     .markup(item(.rectangle(CGRect(x: 0, y: 0, width: 20, height: 20)), stroke: white, fill: white, width: 1))])
        XCTAssertTrue(fixtures.matches(fixtures.pixel(withMarkup, x: 10, y: 10), (255, 255, 255), tolerance: 6))
    }

    func test_temperature_warmsAndCools() throws {
        let gray = RasterImageTestFixtures.makeContext(width: 4, height: 4)
        gray.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        gray.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let base = try XCTUnwrap(gray.makeImage())
        let effects = RasterImageEffects()
        let warm = try XCTUnwrap(effects.apply(RasterImageAdjustments(temperature: 1), to: base))
        let cool = try XCTUnwrap(effects.apply(RasterImageAdjustments(temperature: -1), to: base))
        let w = fixtures.pixel(warm, x: 1, y: 1), c = fixtures.pixel(cool, x: 1, y: 1)
        XCTAssertGreaterThan(Int(w.r) - Int(w.b), Int(c.r) - Int(c.b), "warm has more red relative to blue than cool")
        XCTAssertGreaterThan(Int(w.r), Int(w.b))
    }

    func test_onlyLastAdjustCounts() {
        let ops: [ImageEditOperation] = [.adjust(RasterImageAdjustments(exposure: 1)), .adjust(RasterImageAdjustments(contrast: 0.5))]
        XCTAssertEqual(ops.effectiveAdjustments, RasterImageAdjustments(contrast: 0.5))
        XCTAssertTrue(([] as [ImageEditOperation]).effectiveAdjustments.isIdentity)
    }

    func test_sessionAdjust_rerendersFlattenedDisplay_andUndoRestores() throws {
        let session = session()
        let before = fixtures.pixel(session.flattenedDisplayImage, x: 25, y: 15)
        XCTAssertTrue(session.commit(.adjust(RasterImageAdjustments(exposure: -1.5))))
        let after = fixtures.pixel(session.flattenedDisplayImage, x: 25, y: 15)
        XCTAssertLessThan(Int(after.r), Int(before.r))
        XCTAssertTrue(session.commit(.crop(CGRect(x: 0, y: 0, width: 50, height: 30))))
        XCTAssertLessThan(Int(fixtures.pixel(session.flattenedDisplayImage, x: 25, y: 15).r), Int(before.r), "adjustment survives a crop")
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.undo())
        XCTAssertTrue(fixtures.matches(fixtures.pixel(session.flattenedDisplayImage, x: 25, y: 15), before, tolerance: 1))
    }

    func test_exportAppliesAdjustmentsAtFullResolution() throws {
        let session = RasterImageEditSession.inMemory(fixtures.quadrantImage(width: 400, height: 240), canvasSize: canvasSize)
        XCTAssertTrue(session.commit(.adjust(RasterImageAdjustments(saturation: -1))))
        let output = try RasterImageExportService.run(session.makeExportJob(destinationURL: nil), handle: nil,
                                                      decoder: RasterImageDecoder(), renderer: renderer, encoder: RasterImageEncoder()).get()
        XCTAssertEqual(output.image.width, 400)
        let p = fixtures.pixel(output.image, x: 300, y: 50)
        XCTAssertLessThan(abs(Int(p.r) - Int(p.g)), 12)
    }

    // MARK: - Editing and history

    func test_updateAndDeleteMarkup_areUndoable() throws {
        let session = session()
        let rect = item(.rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)))
        XCTAssertTrue(session.commit(.markup(rect)))
        XCTAssertTrue(session.updateMarkup(id: rect.id, to: rect.translated(by: CGVector(dx: 5, dy: 0))))
        XCTAssertEqual(session.markupItem(id: rect.id)?.rect?.minX, 15)
        XCTAssertTrue(session.deleteMarkup(id: rect.id))
        XCTAssertNil(session.markupItem(id: rect.id))
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.markupItem(id: rect.id)?.rect?.minX, 15)
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.markupItem(id: rect.id)?.rect?.minX, 10)
        XCTAssertTrue(session.redo())
        XCTAssertTrue(session.redo())
        XCTAssertNil(session.markupItem(id: rect.id))
    }

    func test_coalescedUpdates_formOneUndoStep() throws {
        let session = session()
        let text = item(.text("a", origin: CGPoint(x: 5, y: 5)))
        XCTAssertTrue(session.commit(.markup(text)))
        for value in ["ab", "abc", "abcd"] {
            XCTAssertTrue(session.updateMarkup(id: text.id, to: text.withText(value), coalescingKey: "text"))
        }
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.markupItem(id: text.id)?.kind, .text("a", origin: CGPoint(x: 5, y: 5)), "typing undoes in one step")
    }

    func test_markupBeforeGeometricEdit_isFlattenedAndNoLongerEditable() {
        let session = session()
        let rect = item(.rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)))
        XCTAssertTrue(session.commit(.markup(rect)))
        XCTAssertEqual(session.markupEntries.count, 1)
        XCTAssertTrue(session.commit(.rotate(quarterTurns: 1)))
        XCTAssertTrue(session.markupEntries.isEmpty)
        XCTAssertFalse(session.updateMarkup(id: rect.id, to: rect))
    }

    // MARK: - Geometry helpers

    func test_hitTesting_andTranslation() {
        let line = item(.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), width: 2)
        XCTAssertTrue(RasterImageOverlayPainter.hitTest(line, at: CGPoint(x: 50, y: 3), tolerance: 3))
        XCTAssertFalse(RasterImageOverlayPainter.hitTest(line, at: CGPoint(x: 50, y: 10), tolerance: 3))
        let moved = line.translated(by: CGVector(dx: 1, dy: 2))
        XCTAssertEqual(moved.endpoints?.to, CGPoint(x: 101, y: 2))
        XCTAssertEqual(moved.id, line.id)
        let box = item(.blur(CGRect(x: 0, y: 0, width: 10, height: 10)))
        XCTAssertEqual(box.withRect(CGRect(x: 1, y: 1, width: 2, height: 2)).rect, CGRect(x: 1, y: 1, width: 2, height: 2))
        XCTAssertTrue(box.isPixelEffect)
        XCTAssertFalse(item(.redact(.zero)).isPixelEffect)
    }
}
