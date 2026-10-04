import AppKit
import XCTest
@testable import CrispyVibes

/// F062 markup-host regressions that preserve the file-backed F009 coordinator path.
@MainActor
final class RasterImageMemoryPreviewHostTests: XCTestCase {
    func test_initialFitPolicyRejectsInvalidViewportInsteadOfReturningMinimumZoom() {
        XCTAssertNil(RasterImageInitialFitPolicy.magnification(
            imageSize: CGSize(width: 1_200, height: 800),
            viewportSize: .zero
        ))
        XCTAssertNil(RasterImageInitialFitPolicy.magnification(
            imageSize: CGSize(width: 1_200, height: 800),
            viewportSize: CGSize(width: 8, height: 8)
        ))
    }

    func test_initialFitPolicyFitsLargeImageAndCapsSmallImageAtActualSize() throws {
        XCTAssertEqual(
            try XCTUnwrap(RasterImageInitialFitPolicy.magnification(
                imageSize: CGSize(width: 1_200, height: 800),
                viewportSize: CGSize(width: 600, height: 400)
            )),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(RasterImageInitialFitPolicy.magnification(
                imageSize: CGSize(width: 300, height: 200),
                viewportSize: CGSize(width: 600, height: 400)
            )),
            1,
            accuracy: 0.0001
        )
    }

    func test_initiallyInvalidViewportFitsOnceAfterLayoutAndLaterResizePreservesManualZoom() throws {
        let image = RasterImageTestFixtures.quadrantImage(width: 1_200, height: 800)
        let canvas = EditableRasterImageCanvasView(frame: .zero)
        canvas.session = RasterImageEditSession.inMemory(
            image,
            canvasSize: CGSize(width: 1_200, height: 800),
            renderer: RasterImageRenderer()
        )
        let container = NSView(frame: .zero)
        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.documentView = canvas
        container.addSubview(scrollView)
        let viewModel = RasterImageEditorViewModel(services: .makeDefault())
        let coordinator = RasterImageMemoryPreview.Coordinator()
        coordinator.viewModel = viewModel
        coordinator.prepare(canvas: canvas, scrollView: scrollView)
        coordinator.markInitialFitPending()

        coordinator.viewportDidLayout()
        XCTAssertTrue(coordinator.isInitialFitPending)
        XCTAssertEqual(scrollView.magnification, 1, accuracy: 0.0001)

        container.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        scrollView.frame = container.bounds
        coordinator.viewportDidLayout()
        XCTAssertFalse(coordinator.isInitialFitPending)
        XCTAssertEqual(scrollView.magnification, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.zoomPercent, 50, accuracy: 0.0001)

        scrollView.magnification = 0.75
        container.frame.size = CGSize(width: 500, height: 300)
        scrollView.frame = container.bounds
        coordinator.viewportDidLayout()
        XCTAssertEqual(scrollView.magnification, 0.75, accuracy: 0.0001)
        coordinator.shutdown()
    }
}
