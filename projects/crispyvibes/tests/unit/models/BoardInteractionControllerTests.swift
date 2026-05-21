import CoreGraphics
import Foundation
import XCTest
@testable import CrispyVibes

// MARK: - Mock Metrics Provider

final class MockBoardMetricsProvider: BoardMetricsProviding {
    var boardSize: CGSize = CGSize(width: 800, height: 600)
    var hitTestResult: BoardHitRegion = .empty
    var dockingGuideResult: VibeSpaceTerminalBoardDockingGuide?
    var columnWeightsResult: (left: Double, right: Double)?
    var rowWeightsResult: (upper: Double, lower: Double)?
    var horizontalWeightDeltaResult: Double = 0
    var verticalWeightDeltaResult: Double = 0
    var previewLayoutResult: VibeSpaceTerminalBoardLayout?

    private(set) var hitTestCallCount = 0
    private(set) var lastHitTestPoint: CGPoint?

    func frame(for tileID: UUID) -> CGRect { CGRect(x: 0, y: 0, width: 400, height: 300) }

    func hitTest(at point: CGPoint) -> BoardHitRegion {
        hitTestCallCount += 1
        lastHitTestPoint = point
        return hitTestResult
    }

    func dockingGuide(at point: CGPoint, excluding tileID: UUID?) -> VibeSpaceTerminalBoardDockingGuide? {
        dockingGuideResult
    }

    func columnWeights(leftColumnID: UUID, rightColumnID: UUID) -> (left: Double, right: Double)? {
        columnWeightsResult
    }

    func rowWeights(columnID: UUID, upperTileID: UUID, lowerTileID: UUID) -> (upper: Double, lower: Double)? {
        rowWeightsResult
    }

    func horizontalWeightDelta(for pixelDelta: CGFloat) -> Double {
        horizontalWeightDeltaResult
    }

    func verticalWeightDelta(for pixelDelta: CGFloat, columnID: UUID) -> Double {
        verticalWeightDeltaResult
    }

    func previewLayout(moving tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent) -> VibeSpaceTerminalBoardLayout? {
        previewLayoutResult
    }
}

// MARK: - Mock Delegate

final class MockBoardInteractionDelegate: BoardInteractionDelegate {
    private(set) var movedTiles: [(tileID: UUID, intent: VibeSpaceTerminalBoardDropIntent)] = []
    private(set) var restoredMinimized: [(tileID: UUID, intent: VibeSpaceTerminalBoardDropIntent)] = []
    private(set) var detachedTiles: [(tileID: UUID, screenPoint: CGPoint)] = []
    private(set) var columnResizes: [(leftID: UUID, rightID: UUID, leftWeight: Double, rightWeight: Double, commit: Bool)] = []
    private(set) var rowResizes: [(columnID: UUID, upperID: UUID, lowerID: UUID, upperWeight: Double, lowerWeight: Double, commit: Bool)] = []
    private(set) var activatedTiles: [UUID] = []
    var dragProxyResult: BoardDragProxyInfo?
    var minimizedDragProxyResult: BoardDragProxyInfo?

    func interactionController(_ controller: BoardInteractionController, didMoveTile tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent) {
        movedTiles.append((tileID, intent))
    }

    func interactionController(_ controller: BoardInteractionController, didRestoreMinimizedTile tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent) {
        restoredMinimized.append((tileID, intent))
    }

    func interactionController(_ controller: BoardInteractionController, didDetachTile tileID: UUID, atScreenPoint screenPoint: CGPoint) {
        detachedTiles.append((tileID, screenPoint))
    }

    func interactionController(_ controller: BoardInteractionController, didResizeColumns leftColumnID: UUID, rightColumnID: UUID, leftWeight: Double, rightWeight: Double, commit: Bool) {
        columnResizes.append((leftColumnID, rightColumnID, leftWeight, rightWeight, commit))
    }

    func interactionController(_ controller: BoardInteractionController, didResizeRows columnID: UUID, upperTileID: UUID, lowerTileID: UUID, upperWeight: Double, lowerWeight: Double, commit: Bool) {
        rowResizes.append((columnID, upperTileID, lowerTileID, upperWeight, lowerWeight, commit))
    }

    func interactionController(_ controller: BoardInteractionController, didActivateTile tileID: UUID) {
        activatedTiles.append(tileID)
    }

    func interactionControllerDragProxyInfo(_ controller: BoardInteractionController, for tileID: UUID) -> BoardDragProxyInfo? {
        dragProxyResult
    }

    func interactionControllerMinimizedDragProxyInfo(_ controller: BoardInteractionController, for tileID: UUID) -> BoardDragProxyInfo? {
        minimizedDragProxyResult
    }
}

// MARK: - State Transition Tests

@MainActor
final class BoardInteractionControllerTests: XCTestCase {
    private var controller: BoardInteractionController!
    private var metrics: MockBoardMetricsProvider!
    private var delegate: MockBoardInteractionDelegate!

    private let tileA = UUID()
    private let tileB = UUID()
    private let colLeft = UUID()
    private let colRight = UUID()
    private let colID = UUID()

    override func setUp() {
        super.setUp()
        controller = BoardInteractionController()
        metrics = MockBoardMetricsProvider()
        delegate = MockBoardInteractionDelegate()
        controller.metricsProvider = metrics
        controller.delegate = delegate
    }

    // MARK: Idle State

    func testInitialStateIsIdle() {
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.cursorStyle, .default)
        XCTAssertFalse(controller.isMoving)
        XCTAssertFalse(controller.isResizing)
    }

    // MARK: Hover

    func testHoverOnColumnDividerSetsCursor() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        controller.hoverMoved(to: CGPoint(x: 400, y: 300))
        XCTAssertEqual(controller.cursorStyle, .resizeLeftRight)
        XCTAssertEqual(controller.hoveredRegion, .columnDivider(leftColumnID: colLeft, rightColumnID: colRight))
    }

    func testHoverOnRowDividerSetsCursor() {
        metrics.hitTestResult = .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB)
        controller.hoverMoved(to: CGPoint(x: 200, y: 300))
        XCTAssertEqual(controller.cursorStyle, .resizeUpDown)
    }

    func testHoverOnTileBodySetsDefaultCursor() {
        metrics.hitTestResult = .tileBody(tileID: tileA)
        controller.hoverMoved(to: CGPoint(x: 200, y: 200))
        XCTAssertEqual(controller.cursorStyle, .default)
    }

    func testHoverExitedResetsCursor() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        controller.hoverMoved(to: CGPoint(x: 400, y: 300))
        XCTAssertEqual(controller.cursorStyle, .resizeLeftRight)

        controller.hoverExited()
        XCTAssertEqual(controller.cursorStyle, .default)
        XCTAssertEqual(controller.hoveredRegion, .empty)
    }

    func testHoverIgnoredDuringMove() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))
        XCTAssertTrue(controller.isMoving)

        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        controller.hoverMoved(to: CGPoint(x: 400, y: 300))
        XCTAssertEqual(controller.cursorStyle, .default) // not resizeLeftRight
    }

    // MARK: Drag Start → Move

    func testDragOnTileHeaderTransitionsToMoving() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        delegate.dragProxyResult = BoardDragProxyInfo(title: "T", subtitle: "S", sourceFrame: .zero)

        controller.dragStarted(at: CGPoint(x: 100, y: 20))

        XCTAssertTrue(controller.isMoving)
        XCTAssertEqual(controller.movingTileID, tileA)
        XCTAssertEqual(delegate.activatedTiles, [tileA])
        XCTAssertNotNil(controller.dragProxy)
    }

    func testDragOnTileBodyStaysIdle() {
        metrics.hitTestResult = .tileBody(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 200, y: 200))
        XCTAssertEqual(controller.state, .idle)
    }

    func testDragOnEmptyStaysIdle() {
        metrics.hitTestResult = .empty
        controller.dragStarted(at: CGPoint(x: 700, y: 500))
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Move → Docking Guide

    func testMovingDragMovedUpdatesDockingGuide() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))

        let guide = VibeSpaceTerminalBoardDockingGuide(
            targetTileID: tileB,
            targetFrame: CGRect(x: 400, y: 0, width: 400, height: 600),
            compassFrame: CGRect(x: 500, y: 200, width: 100, height: 100),
            selectedTarget: .left
        )
        metrics.dockingGuideResult = guide
        controller.dragMoved(to: CGPoint(x: 450, y: 300))

        if case let .movingTile(state) = controller.state {
            XCTAssertEqual(state.dockingGuide, guide)
            XCTAssertEqual(state.pointer, CGPoint(x: 450, y: 300))
        } else {
            XCTFail("Expected movingTile state")
        }
    }

    func testMovingDragMovedClearsDockingGuideWhenNil() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))

        metrics.dockingGuideResult = nil
        controller.dragMoved(to: CGPoint(x: 50, y: 50))

        if case let .movingTile(state) = controller.state {
            XCTAssertNil(state.dockingGuide)
            XCTAssertNil(state.previewLayout)
        } else {
            XCTFail("Expected movingTile state")
        }
    }

    // MARK: Move → End

    func testMovingDragEndedWithIntentCallsDelegate() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))

        let guide = VibeSpaceTerminalBoardDockingGuide(
            targetTileID: tileB,
            targetFrame: CGRect(x: 400, y: 0, width: 400, height: 600),
            compassFrame: CGRect(x: 500, y: 200, width: 100, height: 100),
            selectedTarget: .right
        )
        metrics.dockingGuideResult = guide
        controller.dragMoved(to: CGPoint(x: 500, y: 300))
        controller.dragEnded()

        XCTAssertEqual(delegate.movedTiles.count, 1)
        XCTAssertEqual(delegate.movedTiles.first?.tileID, tileA)
        XCTAssertEqual(delegate.movedTiles.first?.intent, .insertRight(of: tileB))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.dragProxy)
    }

    func testMovingDragEndedOutsideBoardCallsDetachDelegate() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))

        metrics.dockingGuideResult = VibeSpaceTerminalBoardDockingGuide(
            targetTileID: tileB,
            targetFrame: CGRect(x: 400, y: 0, width: 400, height: 600),
            compassFrame: CGRect(x: 500, y: 200, width: 100, height: 100),
            selectedTarget: .right
        )
        controller.dragMoved(to: CGPoint(x: 900, y: 300))
        controller.dragEnded()

        XCTAssertEqual(delegate.detachedTiles.map(\.tileID), [tileA])
        XCTAssertTrue(delegate.movedTiles.isEmpty)
        XCTAssertEqual(controller.state, .idle)
    }

    func testMovingDragEndedWithoutIntentDoesNotCallDelegate() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))

        metrics.dockingGuideResult = nil
        controller.dragMoved(to: CGPoint(x: 50, y: 50))
        controller.dragEnded()

        XCTAssertTrue(delegate.movedTiles.isEmpty)
        XCTAssertEqual(controller.state, .idle)
    }

    func testMovingDragCancelledReturnsToIdle() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))
        controller.dragCancelled()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(delegate.movedTiles.isEmpty)
    }

    // MARK: Minimized Move

    func testDragStartedFromMinimizedTransitionsToMovingMinimized() {
        controller.dragStartedFromMinimized(tileID: tileA, at: CGPoint(x: 50, y: 580))
        if case let .movingMinimized(state) = controller.state {
            XCTAssertEqual(state.tileID, tileA)
        } else {
            XCTFail("Expected movingMinimized state")
        }
    }

    func testMinimizedDragEndedWithIntentCallsRestore() {
        controller.dragStartedFromMinimized(tileID: tileA, at: CGPoint(x: 50, y: 580))

        let guide = VibeSpaceTerminalBoardDockingGuide(
            targetTileID: tileB,
            targetFrame: CGRect(x: 0, y: 0, width: 400, height: 600),
            compassFrame: CGRect(x: 100, y: 200, width: 100, height: 100),
            selectedTarget: .center
        )
        metrics.dockingGuideResult = guide
        controller.dragMoved(to: CGPoint(x: 200, y: 300))
        controller.dragEnded()

        XCTAssertEqual(delegate.restoredMinimized.count, 1)
        XCTAssertEqual(delegate.restoredMinimized.first?.tileID, tileA)
        XCTAssertEqual(delegate.restoredMinimized.first?.intent, .swap(with: tileB))
    }

    // MARK: Drag Start → Resize Column

    func testDragOnColumnDividerTransitionsToResizingColumn() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)

        controller.dragStarted(at: CGPoint(x: 400, y: 300))

        XCTAssertTrue(controller.isResizing)
        XCTAssertEqual(controller.cursorStyle, .resizeLeftRight)
        if case let .resizingColumn(state) = controller.state {
            XCTAssertEqual(state.leftColumnID, colLeft)
            XCTAssertEqual(state.rightColumnID, colRight)
            XCTAssertEqual(state.initialLeftWeight, 0.5)
            XCTAssertEqual(state.initialRightWeight, 0.5)
            XCTAssertEqual(state.startX, 400)
        } else {
            XCTFail("Expected resizingColumn state")
        }
    }

    // MARK: Resize Column → Move

    func testResizingColumnDragMovedCallsDelegate() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)
        metrics.horizontalWeightDeltaResult = 0.1

        controller.dragStarted(at: CGPoint(x: 400, y: 300))
        controller.dragMoved(to: CGPoint(x: 480, y: 300))

        XCTAssertEqual(delegate.columnResizes.count, 1)
        let resize = delegate.columnResizes[0]
        XCTAssertEqual(resize.leftID, colLeft)
        XCTAssertEqual(resize.rightID, colRight)
        XCTAssertEqual(resize.leftWeight, 0.6, accuracy: 0.001)
        XCTAssertEqual(resize.rightWeight, 0.4, accuracy: 0.001)
        XCTAssertFalse(resize.commit)
    }

    func testResizingColumnClampsToMinimumWeight() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)
        metrics.horizontalWeightDeltaResult = 0.5 // would push left to 1.0

        controller.dragStarted(at: CGPoint(x: 400, y: 300))
        controller.dragMoved(to: CGPoint(x: 800, y: 300))

        let resize = delegate.columnResizes[0]
        XCTAssertEqual(resize.leftWeight, 0.88, accuracy: 0.001) // 1.0 - 0.12
        XCTAssertEqual(resize.rightWeight, 0.12, accuracy: 0.001)
    }

    func testResizingColumnClampsNegativeDelta() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)
        metrics.horizontalWeightDeltaResult = -0.5

        controller.dragStarted(at: CGPoint(x: 400, y: 300))
        controller.dragMoved(to: CGPoint(x: 0, y: 300))

        let resize = delegate.columnResizes[0]
        XCTAssertEqual(resize.leftWeight, 0.12, accuracy: 0.001)
        XCTAssertEqual(resize.rightWeight, 0.88, accuracy: 0.001)
    }

    // MARK: Resize Column → End / Cancel

    func testResizingColumnDragEndedCommits() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.6, right: 0.4)

        controller.dragStarted(at: CGPoint(x: 400, y: 300))
        controller.dragEnded()

        let commits = delegate.columnResizes.filter(\.commit)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.cursorStyle, .default)
    }

    func testResizingColumnCancelledRestoresInitialWeights() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)
        metrics.horizontalWeightDeltaResult = 0.2

        controller.dragStarted(at: CGPoint(x: 400, y: 300))
        controller.dragMoved(to: CGPoint(x: 560, y: 300))
        controller.dragCancelled()

        let commits = delegate.columnResizes.filter(\.commit)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].leftWeight, 0.5, accuracy: 0.001)
        XCTAssertEqual(commits[0].rightWeight, 0.5, accuracy: 0.001)
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: Drag Start → Resize Row

    func testDragOnRowDividerTransitionsToResizingRow() {
        metrics.hitTestResult = .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB)
        metrics.rowWeightsResult = (upper: 0.6, lower: 0.4)

        controller.dragStarted(at: CGPoint(x: 200, y: 300))

        XCTAssertTrue(controller.isResizing)
        XCTAssertEqual(controller.cursorStyle, .resizeUpDown)
        if case let .resizingRow(state) = controller.state {
            XCTAssertEqual(state.columnID, colID)
            XCTAssertEqual(state.upperTileID, tileA)
            XCTAssertEqual(state.lowerTileID, tileB)
            XCTAssertEqual(state.initialUpperWeight, 0.6)
            XCTAssertEqual(state.initialLowerWeight, 0.4)
        } else {
            XCTFail("Expected resizingRow state")
        }
    }

    func testResizingRowDragMovedCallsDelegate() {
        metrics.hitTestResult = .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB)
        metrics.rowWeightsResult = (upper: 0.5, lower: 0.5)
        metrics.verticalWeightDeltaResult = -0.15

        controller.dragStarted(at: CGPoint(x: 200, y: 300))
        controller.dragMoved(to: CGPoint(x: 200, y: 200))

        XCTAssertEqual(delegate.rowResizes.count, 1)
        let resize = delegate.rowResizes[0]
        XCTAssertEqual(resize.upperWeight, 0.35, accuracy: 0.001)
        XCTAssertEqual(resize.lowerWeight, 0.65, accuracy: 0.001)
        XCTAssertFalse(resize.commit)
    }

    func testResizingRowClampsToMinimumWeight() {
        metrics.hitTestResult = .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB)
        metrics.rowWeightsResult = (upper: 0.5, lower: 0.5)
        metrics.verticalWeightDeltaResult = 0.5

        controller.dragStarted(at: CGPoint(x: 200, y: 300))
        controller.dragMoved(to: CGPoint(x: 200, y: 600))

        let resize = delegate.rowResizes[0]
        XCTAssertEqual(resize.upperWeight, 0.88, accuracy: 0.001)
        XCTAssertEqual(resize.lowerWeight, 0.12, accuracy: 0.001)
    }

    func testResizingRowCancelledRestoresInitialWeights() {
        metrics.hitTestResult = .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB)
        metrics.rowWeightsResult = (upper: 0.5, lower: 0.5)
        metrics.verticalWeightDeltaResult = 0.2

        controller.dragStarted(at: CGPoint(x: 200, y: 300))
        controller.dragMoved(to: CGPoint(x: 200, y: 420))
        controller.dragCancelled()

        let commits = delegate.rowResizes.filter(\.commit)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].upperWeight, 0.5, accuracy: 0.001)
        XCTAssertEqual(commits[0].lowerWeight, 0.5, accuracy: 0.001)
    }

    // MARK: Mutual Exclusion (Structural)

    func testCannotStartResizeWhileMoving() {
        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))
        XCTAssertTrue(controller.isMoving)

        // Attempt another drag start — should be ignored because state != .idle
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)
        controller.dragStarted(at: CGPoint(x: 400, y: 300))

        XCTAssertTrue(controller.isMoving) // still moving, not resizing
        XCTAssertFalse(controller.isResizing)
    }

    func testCannotStartMoveWhileResizing() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)
        controller.dragStarted(at: CGPoint(x: 400, y: 300))
        XCTAssertTrue(controller.isResizing)

        metrics.hitTestResult = .tileHeader(tileID: tileA)
        controller.dragStarted(at: CGPoint(x: 100, y: 20))

        XCTAssertTrue(controller.isResizing) // still resizing
        XCTAssertFalse(controller.isMoving)
    }

    func testCannotStartMinimizedMoveWhileResizing() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = (left: 0.5, right: 0.5)
        controller.dragStarted(at: CGPoint(x: 400, y: 300))

        controller.dragStartedFromMinimized(tileID: tileA, at: CGPoint(x: 50, y: 580))
        XCTAssertTrue(controller.isResizing) // unchanged
    }

    // MARK: No Metrics Provider

    func testDragStartWithoutMetricsStaysIdle() {
        controller.metricsProvider = nil
        controller.dragStarted(at: CGPoint(x: 100, y: 20))
        XCTAssertEqual(controller.state, .idle)
    }

    func testHoverWithoutMetricsResetsToDefault() {
        controller.metricsProvider = nil
        controller.hoverMoved(to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(controller.cursorStyle, .default)
        XCTAssertEqual(controller.hoveredRegion, .empty)
    }

    // MARK: Column Divider Without Weights

    func testDragOnColumnDividerWithoutWeightsStaysIdle() {
        metrics.hitTestResult = .columnDivider(leftColumnID: colLeft, rightColumnID: colRight)
        metrics.columnWeightsResult = nil
        controller.dragStarted(at: CGPoint(x: 400, y: 300))
        XCTAssertEqual(controller.state, .idle)
    }

    func testDragOnRowDividerWithoutWeightsStaysIdle() {
        metrics.hitTestResult = .rowDivider(columnID: colID, upperTileID: tileA, lowerTileID: tileB)
        metrics.rowWeightsResult = nil
        controller.dragStarted(at: CGPoint(x: 200, y: 300))
        XCTAssertEqual(controller.state, .idle)
    }
}
