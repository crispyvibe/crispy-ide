import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class ProjectPaneLayoutStateTests: XCTestCase {
    func testProjectPaneLayoutNormalizationClampsValues() {
        let state = ProjectPaneLayoutState(
            explorerFraction: -0.5,
            terminalFraction: 2.0,
            explorerPoints: 120,
            terminalPoints: 80
        ).normalized()

        XCTAssertEqual(state.explorerFraction, 0.18, accuracy: 0.0001)
        XCTAssertEqual(state.terminalFraction, 0.72, accuracy: 0.0001)
        XCTAssertEqual(state.explorerPoints, 190)
        XCTAssertEqual(state.terminalPoints, 160)
    }

    func testProjectPaneLayoutNormalizationPreservesNilPointValues() {
        let state = ProjectPaneLayoutState(
            explorerFraction: 0.5,
            terminalFraction: 0.4,
            explorerPoints: nil,
            terminalPoints: nil
        ).normalized()

        XCTAssertNil(state.explorerPoints)
        XCTAssertNil(state.terminalPoints)
    }
}

