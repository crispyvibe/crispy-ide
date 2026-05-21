import CoreGraphics
import Foundation
import XCTest
@testable import CrispyVibes

// MARK: - BoardHitTesting Tests

final class BoardHitTestingTests: XCTestCase {
    private let tileA = UUID()
    private let tileB = UUID()
    private let tileC = UUID()
    private let colLeft = UUID()
    private let colRight = UUID()
    private let colID = UUID()

    private func twoColumnContext() -> BoardHitTesting.Context {
        // Two columns side by side, 400px each, 8px gap, 6px padding
        // Column divider center at x=410 (6 + 400 + 4)
        BoardHitTesting.Context(
            tileFrames: [
                (id: tileA, frame: CGRect(x: 6, y: 6, width: 390, height: 588)),
                (id: tileB, frame: CGRect(x: 404, y: 6, width: 390, height: 588)),
            ],
            columnDividers: [
                (leftColumnID: colLeft, rightColumnID: colRight, centerX: 400)
            ],
            rowDividers: [],
            dividerThickness: 16,
            headerHeight: 32
        )
    }

    private func columnWithTwoRowsContext() -> BoardHitTesting.Context {
        // One column, two tiles stacked, row divider at y=300
        BoardHitTesting.Context(
            tileFrames: [
                (id: tileA, frame: CGRect(x: 6, y: 6, width: 788, height: 290)),
                (id: tileB, frame: CGRect(x: 6, y: 304, width: 788, height: 290)),
            ],
            columnDividers: [],
            rowDividers: [
                (columnID: colID, upperTileID: tileA, lowerTileID: tileB, centerY: 300, minX: 6, maxX: 794)
            ],
            dividerThickness: 16,
            headerHeight: 32
        )
    }

    // MARK: Column Divider

    func testPointOnColumnDividerReturnsColumnDivider() {
        let ctx = twoColumnContext()
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 400, y: 300), context: ctx)
        XCTAssertEqual(result, .columnDivider(leftColumnID: colLeft, rightColumnID: colRight))
    }

    func testPointAtEdgeOfColumnDividerStillHits() {
        let ctx = twoColumnContext()
        // dividerThickness=16, center=400, so range is 392..408
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 392, y: 300), context: ctx)
        XCTAssertEqual(result, .columnDivider(leftColumnID: colLeft, rightColumnID: colRight))
    }

    func testPointOutsideColumnDividerDoesNotHit() {
        let ctx = twoColumnContext()
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 391, y: 300), context: ctx)
        XCTAssertNotEqual(result, .columnDivider(leftColumnID: colLeft, rightColumnID: colRight))
    }

    // MARK: Row Divider

    func testPointOnRowDividerReturnsRowDivider() {
        let ctx = columnWithTwoRowsContext()
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 400, y: 300), context: ctx)
        XCTAssertEqual(result, .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB))
    }

    func testPointOnRowDividerOutsideColumnBoundsDoesNotHit() {
        let ctx = columnWithTwoRowsContext()
        // minX=6, so x=5 is outside
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 5, y: 300), context: ctx)
        XCTAssertNotEqual(result, .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB))
    }

    // MARK: Tile Header

    func testPointOnTileHeaderReturnsTileHeader() {
        let ctx = twoColumnContext()
        // tileA starts at y=6, header is 32px tall → y=6..38
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 200, y: 20), context: ctx)
        XCTAssertEqual(result, .tileHeader(tileID: tileA))
    }

    func testPointAtBottomEdgeOfHeaderReturnsTileHeader() {
        let ctx = twoColumnContext()
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 200, y: 37), context: ctx)
        XCTAssertEqual(result, .tileHeader(tileID: tileA))
    }

    // MARK: Tile Body

    func testPointBelowHeaderReturnsTileBody() {
        let ctx = twoColumnContext()
        // Header ends at y=38, so y=39 is body
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 200, y: 39), context: ctx)
        XCTAssertEqual(result, .tileBody(tileID: tileA))
    }

    func testPointInSecondTileBodyReturnsTileBody() {
        let ctx = twoColumnContext()
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 600, y: 300), context: ctx)
        XCTAssertEqual(result, .tileBody(tileID: tileB))
    }

    // MARK: Empty

    func testPointOutsideAllTilesReturnsEmpty() {
        let ctx = twoColumnContext()
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 2, y: 2), context: ctx)
        XCTAssertEqual(result, .empty)
    }

    func testEmptyContextReturnsEmpty() {
        let ctx = BoardHitTesting.Context(
            tileFrames: [],
            columnDividers: [],
            rowDividers: [],
            dividerThickness: 16,
            headerHeight: 32
        )
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 400, y: 300), context: ctx)
        XCTAssertEqual(result, .empty)
    }

    // MARK: Priority: Divider > Tile

    func testColumnDividerTakesPriorityOverTileHeader() {
        // Divider overlaps with tile header area
        let ctx = BoardHitTesting.Context(
            tileFrames: [
                (id: tileA, frame: CGRect(x: 0, y: 0, width: 400, height: 600)),
            ],
            columnDividers: [
                (leftColumnID: colLeft, rightColumnID: colRight, centerX: 395)
            ],
            rowDividers: [],
            dividerThickness: 16,
            headerHeight: 32
        )
        let result = BoardHitTesting.hitTest(at: CGPoint(x: 395, y: 16), context: ctx)
        XCTAssertEqual(result, .columnDivider(leftColumnID: colLeft, rightColumnID: colRight))
    }

    // MARK: Context from Layout

    func testContextFromLayoutProducesCorrectTileCount() {
        var layout = VibeSpaceTerminalBoardLayout.empty
        let tile = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp")
        _ = layout.insertNewTile(tile, activeHintTileID: nil)
        let ctx = BoardHitTesting.context(from: layout, boardSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(ctx.tileFrames.count, 1)
        XCTAssertEqual(ctx.tileFrames.first?.id, tile.id)
    }

    func testContextFromTwoColumnLayoutHasOneDivider() {
        var layout = VibeSpaceTerminalBoardLayout.empty
        let t1 = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/a")
        let t2 = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/b")
        _ = layout.insertNewTile(t1, activeHintTileID: nil)
        _ = layout.insertNewTile(t2, activeHintTileID: nil)
        let ctx = BoardHitTesting.context(from: layout, boardSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(ctx.columnDividers.count, 1)
        XCTAssertEqual(ctx.tileFrames.count, 2)
    }
}

// MARK: - BoardResizeCalculator Tests

final class BoardResizeCalculatorTests: XCTestCase {
    func testPositiveDeltaIncreasesFirstWeight() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.5, initialSecond: 0.5, weightDelta: 0.1)
        XCTAssertEqual(result.firstWeight, 0.6, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.4, accuracy: 0.001)
    }

    func testNegativeDeltaDecreasesFirstWeight() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.5, initialSecond: 0.5, weightDelta: -0.2)
        XCTAssertEqual(result.firstWeight, 0.3, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.7, accuracy: 0.001)
    }

    func testClampsFirstToMinimum() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.5, initialSecond: 0.5, weightDelta: -0.5)
        XCTAssertEqual(result.firstWeight, 0.12, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.88, accuracy: 0.001)
    }

    func testClampsSecondToMinimum() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.5, initialSecond: 0.5, weightDelta: 0.5)
        XCTAssertEqual(result.firstWeight, 0.88, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.12, accuracy: 0.001)
    }

    func testZeroDeltaReturnsOriginal() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.3, initialSecond: 0.7, weightDelta: 0)
        XCTAssertEqual(result.firstWeight, 0.3, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.7, accuracy: 0.001)
    }

    func testUnequalInitialWeights() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.3, initialSecond: 0.7, weightDelta: 0.2)
        XCTAssertEqual(result.firstWeight, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.5, accuracy: 0.001)
    }

    func testTotalWeightPreserved() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.4, initialSecond: 0.6, weightDelta: 0.15)
        XCTAssertEqual(result.firstWeight + result.secondWeight, 1.0, accuracy: 0.001)
    }

    func testCustomMinimumWeight() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.5, initialSecond: 0.5, weightDelta: 0.5, minimumWeight: 0.2)
        XCTAssertEqual(result.firstWeight, 0.8, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.2, accuracy: 0.001)
    }

    func testTotalTooSmallForTwoMinimumsReturnsOriginal() {
        let result = BoardResizeCalculator.computeWeights(initialFirst: 0.1, initialSecond: 0.1, weightDelta: 0.05)
        XCTAssertEqual(result.firstWeight, 0.1, accuracy: 0.001)
        XCTAssertEqual(result.secondWeight, 0.1, accuracy: 0.001)
    }
}
