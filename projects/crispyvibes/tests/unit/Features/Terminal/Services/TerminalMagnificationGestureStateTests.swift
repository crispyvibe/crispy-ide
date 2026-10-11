import AppKit
import XCTest
@testable import CrispyVibes

@MainActor
final class TerminalMagnificationGestureStateTests: XCTestCase {
    private let accuracy: CGFloat = 0.000_001

    @discardableResult
    private func apply(
        _ event: TerminalMagnificationGestureState.Event,
        state: inout TerminalMagnificationGestureState,
        scale: inout CGFloat
    ) -> CGFloat {
        scale = state.targetScale(for: event, currentScale: scale)
        return scale
    }

    /// F001-S61
    func testAboveNormalGestureRemainsContinuousInBothDirections() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 1.4

        apply(.began, state: &state, scale: &scale)
        XCTAssertEqual(apply(.changed(0.2), state: &state, scale: &scale), 1.68, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(-0.25), state: &state, scale: &scale), 1.26, accuracy: accuracy)
    }

    /// F001-S61
    func testCrossingNormalFromAboveLocksAtExactlyNormalUntilGestureEnds() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 1.2

        apply(.began, state: &state, scale: &scale)
        XCTAssertEqual(apply(.changed(-0.2), state: &state, scale: &scale), 1, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(-0.8), state: &state, scale: &scale), 1, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(0.8), state: &state, scale: &scale), 1, accuracy: accuracy)
        XCTAssertEqual(apply(.ended, state: &state, scale: &scale), 1, accuracy: accuracy)
    }

    /// F001-S61
    func testNewGestureAtNormalRequiresCumulativeInwardThresholdBeforeFirstShrinkStep() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 1.2

        apply(.began, state: &state, scale: &scale)
        apply(.changed(-0.2), state: &state, scale: &scale)
        apply(.ended, state: &state, scale: &scale)
        apply(.began, state: &state, scale: &scale)

        XCTAssertEqual(
            apply(.changed(-TerminalMagnificationGestureState.stepThreshold / 2), state: &state, scale: &scale),
            1,
            accuracy: accuracy
        )
        XCTAssertEqual(
            apply(.changed(-TerminalMagnificationGestureState.stepThreshold / 2), state: &state, scale: &scale),
            0.9,
            accuracy: accuracy
        )
    }

    /// F001-S61
    func testContinuedInwardDeltasProduceOrderedTenthStepsDownToMinimum() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 1
        apply(.began, state: &state, scale: &scale)

        var observed: [CGFloat] = []
        for _ in 0..<7 {
            observed.append(
                apply(
                    .changed(-TerminalMagnificationGestureState.stepThreshold),
                    state: &state,
                    scale: &scale
                )
            )
        }

        XCTAssertEqual(observed, [0.9, 0.8, 0.7, 0.6, 0.5, 0.5, 0.5])
        XCTAssertTrue(observed.allSatisfy { (0.5...1).contains($0) })
    }

    /// F001-S61
    func testBelowNormalOutwardStepsReachNormalLockAndRequireAnotherGestureToMagnify() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 0.7
        let threshold = TerminalMagnificationGestureState.stepThreshold

        apply(.began, state: &state, scale: &scale)
        XCTAssertEqual(apply(.changed(threshold), state: &state, scale: &scale), 0.8, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(threshold), state: &state, scale: &scale), 0.9, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(threshold), state: &state, scale: &scale), 1, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(0.5), state: &state, scale: &scale), 1, accuracy: accuracy)

        apply(.ended, state: &state, scale: &scale)
        apply(.began, state: &state, scale: &scale)
        XCTAssertEqual(apply(.changed(0.1), state: &state, scale: &scale), 1.1, accuracy: accuracy)
    }

    /// F001-S61
    func testBelowNormalReversalCancelsOpposingPartialAccumulation() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 0.8
        apply(.began, state: &state, scale: &scale)

        XCTAssertEqual(apply(.changed(-0.06), state: &state, scale: &scale), 0.8, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(0.04), state: &state, scale: &scale), 0.8, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(0.05), state: &state, scale: &scale), 0.8, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(0.05), state: &state, scale: &scale), 0.9, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(-0.04), state: &state, scale: &scale), 0.9, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(-0.04), state: &state, scale: &scale), 0.8, accuracy: accuracy)
    }

    /// F001-S61
    func testChangedWithoutBeganStartsDefensivelyAndEndOrCancelResetAccumulation() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 1

        XCTAssertEqual(apply(.changed(-0.04), state: &state, scale: &scale), 1, accuracy: accuracy)
        apply(.ended, state: &state, scale: &scale)
        XCTAssertEqual(apply(.changed(-0.04), state: &state, scale: &scale), 1, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(-0.04), state: &state, scale: &scale), 0.9, accuracy: accuracy)

        apply(.cancelled, state: &state, scale: &scale)
        XCTAssertEqual(apply(.changed(0.04), state: &state, scale: &scale), 0.9, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(0.04), state: &state, scale: &scale), 1, accuracy: accuracy)
    }

    /// F001-S61
    func testLargeDeltaStaysOnDiscreteLadderAndNeverPassesMinimum() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 1

        apply(.began, state: &state, scale: &scale)
        XCTAssertEqual(apply(.changed(-0.35), state: &state, scale: &scale), 0.6, accuracy: accuracy)
        XCTAssertEqual((scale * 10).rounded(), scale * 10, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(-100), state: &state, scale: &scale), 0.5, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(-100), state: &state, scale: &scale), 0.5, accuracy: accuracy)
    }

    /// F001-S61
    func testFiniteOutwardOverflowClampsToMaximumAndNonfiniteDeltaIsNoOp() {
        var state = TerminalMagnificationGestureState()
        var scale: CGFloat = 2

        apply(.began, state: &state, scale: &scale)
        XCTAssertEqual(
            apply(.changed(CGFloat.greatestFiniteMagnitude), state: &state, scale: &scale),
            TerminalSession.maximumDisplayMagnification,
            accuracy: accuracy
        )
        XCTAssertEqual(apply(.changed(.infinity), state: &state, scale: &scale), 3, accuracy: accuracy)
        XCTAssertEqual(apply(.changed(.nan), state: &state, scale: &scale), 3, accuracy: accuracy)
    }

    /// F001-S61
    func testThresholdBoundaryAccumulatesWithStableTolerance() {
        var inwardState = TerminalMagnificationGestureState()
        var inwardScale: CGFloat = 1
        let threshold = TerminalMagnificationGestureState.stepThreshold

        apply(.began, state: &inwardState, scale: &inwardScale)
        XCTAssertEqual(apply(.changed(-(threshold - 0.000_001)), state: &inwardState, scale: &inwardScale), 1)
        XCTAssertEqual(apply(.changed(-0.000_002), state: &inwardState, scale: &inwardScale), 0.9)

        var outwardState = TerminalMagnificationGestureState()
        var outwardScale: CGFloat = 0.500_000_001
        apply(.began, state: &outwardState, scale: &outwardScale)
        XCTAssertEqual(apply(.changed(threshold - 0.000_001), state: &outwardState, scale: &outwardScale), 0.5)
        XCTAssertEqual(apply(.changed(0.000_002), state: &outwardState, scale: &outwardScale), 0.6)
    }
}

@MainActor
final class TerminalOpticalTransformTests: XCTestCase {
    private let contentSize = CGSize(width: 320, height: 200)
    private let accuracy: CGFloat = 0.000_001

    /// F001-S59
    func testShrinkScalesCenterFixedContentIndependentOfAnchorAndPriorPan() {
        var transform = TerminalOpticalTransform(scale: 2, visibleOrigin: CGPoint(x: 40, y: 25))
        transform.pan(
            by: CGPoint(x: -70, y: 30),
            contentSize: contentSize,
            viewportSize: contentSize
        )

        transform.setScale(
            0.9,
            anchoredAt: CGPoint(x: 13, y: 179),
            contentSize: contentSize,
            viewportSize: contentSize
        )
        XCTAssertEqual(transform.scale, 0.9, accuracy: accuracy)
        XCTAssertEqual(transform.visibleOrigin.x, (320 - 320 / 0.9) / 2, accuracy: accuracy)
        XCTAssertEqual(transform.visibleOrigin.y, (200 - 200 / 0.9) / 2, accuracy: accuracy)

        transform.setScale(
            0.5,
            anchoredAt: CGPoint(x: 300, y: 3),
            contentSize: contentSize,
            viewportSize: contentSize
        )
        XCTAssertEqual(transform.scale, 0.5, accuracy: accuracy)
        XCTAssertEqual(transform.visibleOrigin.x, -160, accuracy: accuracy)
        XCTAssertEqual(transform.visibleOrigin.y, -100, accuracy: accuracy)
    }

    /// F001-S59
    func testPanIsNeutralizedAtOrBelowNormalAndNormalCanonicalizesCenter() {
        for scale: CGFloat in [0.5, 0.9, 1] {
            var transform = TerminalOpticalTransform(scale: scale, visibleOrigin: CGPoint(x: 99, y: -42))
            transform.pan(
                by: CGPoint(x: 10_000, y: -10_000),
                contentSize: contentSize,
                viewportSize: contentSize
            )
            XCTAssertEqual(transform.visibleOrigin.x, (320 - 320 / scale) / 2, accuracy: accuracy)
            XCTAssertEqual(transform.visibleOrigin.y, (200 - 200 / scale) / 2, accuracy: accuracy)
        }

        var transform = TerminalOpticalTransform(scale: 2, visibleOrigin: CGPoint(x: 40, y: 20))
        transform.setScale(1, anchoredAt: CGPoint(x: 10, y: 10), contentSize: contentSize, viewportSize: contentSize)
        XCTAssertEqual(transform.visibleOrigin, .zero)
    }

    /// F001-S59
    func testAboveNormalScalePreservesAnchorAndAllowsBoundedPan() {
        var transform = TerminalOpticalTransform()
        let anchor = CGPoint(x: 240, y: 50)
        let terminalAnchor = transform.terminalPoint(fromViewport: anchor)

        transform.setScale(2, anchoredAt: anchor, contentSize: contentSize, viewportSize: contentSize)
        let anchoredResult = transform.terminalPoint(fromViewport: anchor)
        XCTAssertEqual(anchoredResult.x, terminalAnchor.x, accuracy: accuracy)
        XCTAssertEqual(anchoredResult.y, terminalAnchor.y, accuracy: accuracy)

        let originBeforePan = transform.visibleOrigin
        transform.pan(by: CGPoint(x: 20, y: 10), contentSize: contentSize, viewportSize: contentSize)
        XCTAssertNotEqual(transform.visibleOrigin, originBeforePan)
        XCTAssertGreaterThanOrEqual(transform.visibleOrigin.x, 0)
        XCTAssertGreaterThanOrEqual(transform.visibleOrigin.y, 0)
    }

    /// F001-S59, F001-S60
    func testPointAndRectRoundTripsRemainExactUnderShrink() {
        var transform = TerminalOpticalTransform()
        transform.setScale(
            0.5,
            anchoredAt: CGPoint(x: 12, y: 18),
            contentSize: contentSize,
            viewportSize: contentSize
        )

        let terminalPoint = CGPoint(x: 245, y: 132)
        let roundTripPoint = transform.terminalPoint(
            fromViewport: transform.viewportPoint(fromTerminal: terminalPoint)
        )
        XCTAssertEqual(roundTripPoint.x, terminalPoint.x, accuracy: accuracy)
        XCTAssertEqual(roundTripPoint.y, terminalPoint.y, accuracy: accuracy)

        let terminalRect = CGRect(x: 80, y: 45, width: 60, height: 24)
        let roundTripRect = transform.terminalRect(
            fromViewport: transform.viewportRect(fromTerminal: terminalRect)
        )
        XCTAssertEqual(roundTripRect.origin.x, terminalRect.origin.x, accuracy: accuracy)
        XCTAssertEqual(roundTripRect.origin.y, terminalRect.origin.y, accuracy: accuracy)
        XCTAssertEqual(roundTripRect.width, terminalRect.width, accuracy: accuracy)
        XCTAssertEqual(roundTripRect.height, terminalRect.height, accuracy: accuracy)
    }
}
