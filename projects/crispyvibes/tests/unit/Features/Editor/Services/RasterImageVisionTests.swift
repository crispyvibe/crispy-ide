import AppKit
import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F009 Phase 4: on-device OCR and background removal.
@MainActor
final class RasterImageVisionTests: XCTestCase {
    private let fixtures = RasterImageTestFixtures.self

    /// White image with black text lines drawn top to bottom.
    private func textImage(_ lines: [String], width: Int = 800, height: Int = 300) -> CGImage {
        let context = fixtures.makeContext(width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        for (index, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: [
                .font: NSFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: NSColor.black
            ]).draw(at: CGPoint(x: 30, y: CGFloat(height) - 90 - CGFloat(index) * 110))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    private func waitFor<T>(_ body: (@escaping @MainActor (T) -> Void) -> Void) -> T? {
        var value: T?
        let done = expectation(description: "vision")
        body { value = $0; done.fulfill() }
        wait(for: [done], timeout: 30)
        return value
    }

    func test_recognizeText_findsLinesInReadingOrder_withTopLeftBoxes() throws {
        let image = textImage(["HELLO WORLD", "SECOND LINE"])
        let result = waitFor { completion in RasterImageVisionService().recognizeText(in: image, completion: completion) }
        let lines = try XCTUnwrap(try result?.get())
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines[0].text.uppercased().contains("HELLO"), "got \(lines.map(\.text))")
        XCTAssertTrue(lines[1].text.uppercased().contains("SECOND"))
        XCTAssertLessThan(lines[0].normalizedBox.midY, lines[1].normalizedBox.midY, "top-left origin: first line is above")
        let box = lines[0].box(in: CGSize(width: 800, height: 300))
        XCTAssertLessThan(box.minY, 150, "first line sits in the top half")
    }

    func test_recognizeText_onBlankImage_reportsNoText() {
        let blank = fixtures.makeContext(width: 64, height: 64)
        blank.setFillColor(CGColor(gray: 1, alpha: 1))
        blank.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let result = waitFor { completion in RasterImageVisionService().recognizeText(in: blank.makeImage()!, completion: completion) }
        guard case .failure(let error)? = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? RasterImageAnalysisError, .noTextFound)
    }

    func test_removeBackground_makesMaskedOutPixelsTransparent_atAnyScale() throws {
        // Mask keeps only the left half.
        let maskContext = CGContext(data: nil, width: 50, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        maskContext.setFillColor(gray: 0, alpha: 1)
        maskContext.fill(CGRect(x: 0, y: 0, width: 50, height: 30))
        maskContext.setFillColor(gray: 1, alpha: 1)
        maskContext.fill(CGRect(x: 0, y: 0, width: 25, height: 30))
        let mask = RasterImageMask(image: maskContext.makeImage()!)
        let renderer = RasterImageRenderer()
        for (w, h) in [(100, 60), (400, 240)] {
            let image = try XCTUnwrap(renderer.render(base: fixtures.quadrantImage(width: w, height: h),
                                                      baseCanvasSize: CGSize(width: 100, height: 60),
                                                      operations: [.removeBackground(mask)]))
            let context = fixtures.makeContext(width: image.width, height: image.height)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            let alpha = { (x: Int, y: Int) in data[y * context.bytesPerRow + x * 4 + 3] }
            XCTAssertGreaterThan(alpha(w / 4, h / 4), 250, "kept half is opaque at \(w)")
            XCTAssertLessThan(alpha(3 * w / 4, h / 4), 5, "removed half is transparent at \(w)")
        }
    }

    func test_removeBackground_flattensEarlierMarkup_andIsUndoable() {
        let session = RasterImageEditSession.inMemory(fixtures.quadrantImage(width: 100, height: 60), canvasSize: CGSize(width: 100, height: 60))
        session.commit(.markup(RasterMarkupItem(kind: .rectangle(CGRect(x: 1, y: 1, width: 5, height: 5)), style: .default)))
        let mask = RasterImageMask(image: fixtures.quadrantImage(width: 10, height: 6))
        XCTAssertTrue(session.commit(.removeBackground(mask)))
        XCTAssertTrue(session.markupEntries.isEmpty)
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.markupEntries.count, 1)
        XCTAssertEqual(ImageEditOperation.removeBackground(mask), .removeBackground(mask))
        XCTAssertNotEqual(ImageEditOperation.removeBackground(mask), .removeBackground(RasterImageMask(image: mask.image)))
    }
}
