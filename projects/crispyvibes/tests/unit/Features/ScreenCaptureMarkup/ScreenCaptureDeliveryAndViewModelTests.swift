import AppKit
import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F062 unified Studio delivery and presentation boundary coverage.
@MainActor
final class ScreenCaptureDeliveryAndViewModelTests: XCTestCase {
    func test_studioToolbarStartsWithMarkupPenAndExcludesPan() throws {
        let viewModel = RasterImageEditorViewModel(services: .makeDefault())
        viewModel.selectMode(.markup)
        viewModel.selectMarkupTool(.pen)

        XCTAssertEqual(viewModel.editingMode, .markup)
        XCTAssertEqual(viewModel.markupTool, .pen)
        XCTAssertEqual(RasterImageEditorToolbarConfiguration.screenCapture.modes, [.markup, .crop])
        XCTAssertFalse(RasterImageEditorToolbarConfiguration.screenCapture.modes.contains(.pan))
    }

    func test_appKitClipboardReplacesExistingContentsWithEagerPNGAndTIFF() throws {
        let pasteboard = NSPasteboard(name: .init("F062.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let png = try encodedImage(type: .png)
        let tiff = try encodedImage(type: .tiff)

        try AppKitScreenCaptureClipboard(pasteboard: pasteboard)
            .writeCompleteRepresentations(.init(png: png, tiff: tiff))

        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        XCTAssertEqual(pasteboard.data(forType: .tiff), tiff)
    }

    func test_outputServiceEagerlyEncodesDecodablePNGAndTIFF() async throws {
        let image = try makeCapturedImage()
        let service = ScreenCaptureOutputService(encoder: RasterImageEncoder())

        let output = try await service.encode(image)

        XCTAssertFalse(output.png.isEmpty)
        XCTAssertFalse(output.tiff.isEmpty)
        XCTAssertNotNil(NSImage(data: output.png))
        XCTAssertNotNil(NSImage(data: output.tiff))
    }

    func test_studioPresentationFitsCapturedDisplayAndReportsSizePolicy() {
        let visible = CGRect(x: 200, y: 100, width: 1_000, height: 700)
        let presentation = ScreenshotStudioPresentation.resolve(
            canvasSize: CGSize(width: 2_000, height: 1_000),
            visibleFrame: visible
        )

        XCTAssertLessThanOrEqual(presentation.frame.width, visible.width * 0.8 + 0.5)
        XCTAssertLessThanOrEqual(presentation.frame.height, visible.height * 0.8 + 0.5)
        XCTAssertEqual(presentation.minimumSize.width, 520)
        XCTAssertEqual(presentation.maximumSize, CGSize(width: 800, height: 560))
    }

    private func encodedImage(type: NSBitmapImageRep.FileType) throws -> Data {
        let image = try makeCGImage()
        let representation = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(representation.representation(using: type, properties: [:]))
    }

    private func makeCapturedImage() throws -> CapturedScreenImage {
        let image = try makeCGImage()
        return CapturedScreenImage(
            cgImage: image,
            canvasSize: CGSize(width: image.width, height: image.height),
            exportScale: 1,
            nativePixelSize: CGSize(width: image.width, height: image.height),
            colorSpaceName: nil,
            placement: .init(
                displayID: 1,
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
            )
        )
    }

    private func makeCGImage() throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try XCTUnwrap(context.makeImage())
    }
}
