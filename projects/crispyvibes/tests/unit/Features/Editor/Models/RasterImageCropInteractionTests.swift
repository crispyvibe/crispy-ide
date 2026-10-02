import CoreGraphics
import XCTest
@testable import CrispyVibes

/// F009 Phase 2: crop-box handles, aspect constraints, and bounds.
final class RasterImageCropInteractionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

    func test_handleHitTesting_prefersCorners() {
        let rect = CGRect(x: 20, y: 20, width: 100, height: 50)
        XCTAssertEqual(RasterImageCropInteraction.handle(at: CGPoint(x: 21, y: 19), in: rect, radius: 5), .topLeft)
        XCTAssertEqual(RasterImageCropInteraction.handle(at: CGPoint(x: 70, y: 70), in: rect, radius: 5), .bottom)
        XCTAssertEqual(RasterImageCropInteraction.handle(at: CGPoint(x: 120, y: 45), in: rect, radius: 5), .right)
        XCTAssertNil(RasterImageCropInteraction.handle(at: CGPoint(x: 70, y: 45), in: rect, radius: 5))
    }

    func test_cornerResize_keepsOppositeCornerFixed_andClampsToBounds() {
        let rect = CGRect(x: 20, y: 20, width: 100, height: 50)
        let resized = RasterImageCropInteraction.resize(rect, handle: .bottomRight, to: CGPoint(x: 500, y: 500),
                                                        aspect: nil, bounds: bounds, minimumSize: 2)
        XCTAssertEqual(resized, CGRect(x: 20, y: 20, width: 180, height: 80))
    }

    func test_cornerResize_withAspect_preservesRatio() {
        let rect = CGRect(x: 20, y: 20, width: 40, height: 40)
        let resized = RasterImageCropInteraction.resize(rect, handle: .bottomRight, to: CGPoint(x: 120, y: 60),
                                                        aspect: 1, bounds: bounds, minimumSize: 2)
        XCTAssertEqual(resized.width, resized.height, accuracy: 0.001)
        XCTAssertEqual(resized.origin, CGPoint(x: 20, y: 20))
        XCTAssertLessThanOrEqual(resized.maxY, bounds.maxY)
    }

    func test_cornerResize_canFlipAcrossAnchor() {
        let rect = CGRect(x: 50, y: 20, width: 50, height: 50)
        let resized = RasterImageCropInteraction.resize(rect, handle: .bottomRight, to: CGPoint(x: 10, y: 10),
                                                        aspect: nil, bounds: bounds, minimumSize: 2)
        XCTAssertEqual(resized, CGRect(x: 10, y: 10, width: 40, height: 10))
    }

    func test_edgeResize_withAspect_growsSymmetricallyWithinBounds() {
        let rect = CGRect(x: 50, y: 30, width: 40, height: 40)
        let resized = RasterImageCropInteraction.resize(rect, handle: .right, to: CGPoint(x: 190, y: 0),
                                                        aspect: 1, bounds: bounds, minimumSize: 2)
        XCTAssertEqual(resized.width, resized.height, accuracy: 0.001)
        XCTAssertEqual(resized.midY, 50, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(resized.minY, 0)
        XCTAssertLessThanOrEqual(resized.maxY, 100)
        XCTAssertEqual(resized.minX, 50)
    }

    func test_resize_enforcesMinimumSize() {
        let rect = CGRect(x: 50, y: 30, width: 40, height: 40)
        let resized = RasterImageCropInteraction.resize(rect, handle: .left, to: CGPoint(x: 90, y: 50),
                                                        aspect: nil, bounds: bounds, minimumSize: 4)
        XCTAssertGreaterThanOrEqual(resized.width, 4)
    }

    func test_move_staysInsideBounds() {
        let rect = CGRect(x: 150, y: 60, width: 40, height: 30)
        XCTAssertEqual(RasterImageCropInteraction.move(rect, by: CGVector(dx: 100, dy: 100), bounds: bounds),
                       CGRect(x: 160, y: 70, width: 40, height: 30))
        XCTAssertEqual(RasterImageCropInteraction.move(rect, by: CGVector(dx: -500, dy: -500), bounds: bounds),
                       CGRect(x: 0, y: 0, width: 40, height: 30))
    }

    func test_newSelection_withAspect_fitsBounds() {
        let rect = RasterImageCropInteraction.selection(from: CGPoint(x: 150, y: 50), to: CGPoint(x: 300, y: 300), aspect: 2, bounds: bounds)
        XCTAssertEqual(rect.width / rect.height, 2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rect.maxX, 200)
        XCTAssertLessThanOrEqual(rect.maxY, 100)
    }

    func test_centeredAspect_isLargestFittingBox() {
        let square = RasterImageCropInteraction.centered(aspect: 1, in: bounds)
        XCTAssertEqual(square, CGRect(x: 50, y: 0, width: 100, height: 100))
        let wide = RasterImageCropInteraction.centered(aspect: 4, in: bounds)
        XCTAssertEqual(wide, CGRect(x: 0, y: 25, width: 200, height: 50))
    }

    func test_aspectPresets() {
        let size = CGSize(width: 300, height: 200)
        XCTAssertNil(RasterImageCropAspectRatio.free.value(originalSize: size, portrait: false))
        XCTAssertEqual(RasterImageCropAspectRatio.square.value(originalSize: size, portrait: true), 1)
        XCTAssertEqual(RasterImageCropAspectRatio.original.value(originalSize: size, portrait: false)!, 1.5, accuracy: 0.0001)
        XCTAssertEqual(RasterImageCropAspectRatio.original.value(originalSize: size, portrait: true)!, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(RasterImageCropAspectRatio.ratio16x9.value(originalSize: size, portrait: true)!, 9.0 / 16.0, accuracy: 0.0001)
    }

    func test_minimumSize_keepsAnchorAndAspect_forEveryHandle() {
        let rect = CGRect(x: 50, y: 30, width: 40, height: 20)
        for handle in RasterImageCropHandle.allCases {
            for aspect: CGFloat? in [nil, 2, 0.5] {
                let target = CGPoint(x: rect.midX + 0.3, y: rect.midY + 0.3)
                let resized = RasterImageCropInteraction.resize(rect, handle: handle, to: target, aspect: aspect, bounds: bounds, minimumSize: 4)
                XCTAssertGreaterThanOrEqual(resized.width, 4, "\(handle) \(String(describing: aspect))")
                XCTAssertGreaterThanOrEqual(resized.height, 4, "\(handle) \(String(describing: aspect))")
                if let aspect, resized != rect {
                    XCTAssertEqual(resized.width / resized.height, aspect, accuracy: 0.001, "\(handle)")
                }
            }
        }
    }

    func test_cornerResize_belowMinimum_doesNotMoveOppositeAnchor() {
        let rect = CGRect(x: 50, y: 30, width: 40, height: 40)
        let resized = RasterImageCropInteraction.resize(rect, handle: .topLeft, to: CGPoint(x: 89, y: 69), aspect: nil, bounds: bounds, minimumSize: 4)
        XCTAssertEqual(resized.maxX, 90)
        XCTAssertEqual(resized.maxY, 70)
    }
}
