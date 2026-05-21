import Foundation
import XCTest
@testable import CrispyVibes

final class ProjectTerminalCyclerTests: XCTestCase {
    private let tabA = UUID()
    private let tabB = UUID()
    private let tabC = UUID()

    // MARK: - Focus Project (different project)

    func testDifferentProjectReturnsFocusProject() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: false,
            tabIDs: [tabA, tabB],
            activeTabID: tabA
        )
        XCTAssertEqual(result, .focusProject)
    }

    func testDifferentProjectWithEmptyTabsReturnsFocusProject() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: false,
            tabIDs: [],
            activeTabID: nil
        )
        XCTAssertEqual(result, .focusProject)
    }

    // MARK: - Cycle Terminal (same project, multiple tabs)

    func testSameProjectCyclesToNextTerminal() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA, tabB, tabC],
            activeTabID: tabA
        )
        XCTAssertEqual(result, .cycleTerminal(nextTabID: tabB))
    }

    func testSameProjectCyclesFromMiddleToNext() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA, tabB, tabC],
            activeTabID: tabB
        )
        XCTAssertEqual(result, .cycleTerminal(nextTabID: tabC))
    }

    func testSameProjectWrapsAroundFromLastToFirst() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA, tabB, tabC],
            activeTabID: tabC
        )
        XCTAssertEqual(result, .cycleTerminal(nextTabID: tabA))
    }

    func testSameProjectTwoTabsCyclesBetweenThem() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA, tabB],
            activeTabID: tabA
        )
        XCTAssertEqual(result, .cycleTerminal(nextTabID: tabB))

        let result2 = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA, tabB],
            activeTabID: tabB
        )
        XCTAssertEqual(result2, .cycleTerminal(nextTabID: tabA))
    }

    // MARK: - No-Op (same project, single or no terminal)

    func testSameProjectSingleTerminalReturnsNoOp() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA],
            activeTabID: tabA
        )
        XCTAssertEqual(result, .noOp)
    }

    func testSameProjectEmptyTabsReturnsNoOp() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [],
            activeTabID: nil
        )
        XCTAssertEqual(result, .noOp)
    }

    // MARK: - Edge Cases

    func testNilActiveTabIDDefaultsToFirstAndCyclesToSecond() {
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA, tabB],
            activeTabID: nil
        )
        XCTAssertEqual(result, .cycleTerminal(nextTabID: tabB))
    }

    func testActiveTabIDNotInListDefaultsToFirstAndCyclesToSecond() {
        let unknownTab = UUID()
        let result = ProjectTerminalCycler.resolve(
            isAlreadyFocused: true,
            tabIDs: [tabA, tabB],
            activeTabID: unknownTab
        )
        XCTAssertEqual(result, .cycleTerminal(nextTabID: tabB))
    }
}
