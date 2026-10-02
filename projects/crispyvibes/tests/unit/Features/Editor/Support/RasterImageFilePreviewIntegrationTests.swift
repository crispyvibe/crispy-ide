import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import CrispyVibes

/// F009 end-to-end: real preview hierarchy → async decode → crop → full-resolution save → reopen.
@MainActor
final class RasterImageFilePreviewIntegrationTests: XCTestCase {
    private let fixtures = RasterImageTestFixtures.self
    private var tempRoot: URL!
    private var hostingView: NSHostingView<AnyView>?

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RasterPreviewIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        hostingView = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func mount(_ fileURL: URL, viewModel: RasterImageEditorViewModel) {
        let view = RasterImageFilePreview(fileURL: fileURL, viewModel: viewModel, onDirtyStateChange: { _ in })
            .frame(width: 800, height: 600)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hostingView = hosting
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    func test_exifRotatedJPEG_cropAndSave_writesUprightFullResolutionCrop() throws {
        // Raw 1200×600 landscape tagged orientation 6 → displayed as 600×1200 portrait.
        let url = tempRoot.appendingPathComponent("photo.jpg")
        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 1200, height: 600)], type: .jpeg, to: url, orientation: 6))

        let viewModel = RasterImageEditorViewModel(services: .makeDefault())
        mount(url, viewModel: viewModel)
        XCTAssertTrue(waitUntil { viewModel.hasRenderableImage }, "image decodes asynchronously")
        let canvas = try XCTUnwrap(viewModel.canvas as? EditableRasterImageCanvasView)
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 600, height: 1200))
        XCTAssertNil(viewModel.saveBlockReason)

        // Crop the displayed top-right quadrant (raw top-left = red).
        canvas.cropSelection = CGRect(x: 300, y: 0, width: 300, height: 600)
        viewModel.canvasStateDidChange(canvas.state)
        viewModel.applyCrop()
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 300, height: 600))

        viewModel.save()
        XCTAssertTrue(waitUntil { !viewModel.isSaving }, "save completes")
        XCTAssertEqual(viewModel.statusLine, AppStrings.ImageEditor.statusSaved)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? UInt32 ?? 1, 1)
        let saved = try XCTUnwrap(RasterImageDecoder().fullResolutionImage(contentsOf: url))
        XCTAssertEqual(saved.width, 300)
        XCTAssertEqual(saved.height, 600)
        XCTAssertTrue(fixtures.matches(fixtures.pixel(saved, x: 150, y: 300), fixtures.quadrantColors[0]),
                      "saved crop must be the red quadrant, upright; got \(fixtures.pixel(saved, x: 150, y: 300))")

        // Our own write must not raise an external-change conflict or reload over the new baseline.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(viewModel.hasExternalChangeConflict)
        XCTAssertFalse(canvas.hasPendingEdits)
    }

    func test_externalWriteWithPendingEdits_raisesConflictInsteadOfReloading() throws {
        let url = tempRoot.appendingPathComponent("shared.png")
        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 80, height: 40)], type: .png, to: url))
        let viewModel = RasterImageEditorViewModel(services: .makeDefault())
        mount(url, viewModel: viewModel)
        XCTAssertTrue(waitUntil { viewModel.hasRenderableImage })
        let canvas = try XCTUnwrap(viewModel.canvas as? EditableRasterImageCanvasView)
        canvas.commit(.stroke(RasterStroke(points: [CGPoint(x: 1, y: 1), CGPoint(x: 30, y: 30)])))

        XCTAssertTrue(fixtures.write([fixtures.quadrantImage(width: 20, height: 20)], type: .png, to: url))
        XCTAssertTrue(waitUntil { viewModel.hasExternalChangeConflict }, "conflict is reported")
        XCTAssertTrue(canvas.hasPendingEdits, "edits are not discarded")
        XCTAssertEqual(canvas.session?.canvasSize, CGSize(width: 80, height: 40))

        viewModel.reloadFromDisk()
        XCTAssertTrue(waitUntil { canvas.session?.canvasSize == CGSize(width: 20, height: 20) })
        XCTAssertFalse(canvas.hasPendingEdits)
    }

    func test_animatedGIF_isReadOnlyForOverwrite() throws {
        let url = tempRoot.appendingPathComponent("anim.gif")
        let frame = fixtures.quadrantImage(width: 16, height: 16)
        XCTAssertTrue(fixtures.write([frame, frame], type: .gif, to: url))
        let original = try Data(contentsOf: url)
        let viewModel = RasterImageEditorViewModel(services: .makeDefault())
        mount(url, viewModel: viewModel)
        XCTAssertTrue(waitUntil { viewModel.hasRenderableImage })
        XCTAssertEqual(viewModel.saveBlockReason, .multipleFrames(count: 2))
        (viewModel.canvas as? EditableRasterImageCanvasView)?.commit(.stroke(RasterStroke(points: [.zero, CGPoint(x: 5, y: 5)])))
        viewModel.save()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
