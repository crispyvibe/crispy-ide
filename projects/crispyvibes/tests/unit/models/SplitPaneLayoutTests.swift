import XCTest
@testable import CrispyVibes

final class SplitPaneLayoutTests: XCTestCase {
    func testSingleLeafHasLeafCountOne() {
        let node = SplitPaneNode.singleLeaf()
        XCTAssertEqual(node.leafCount, 1)
    }

    func testSplitNodeHasCorrectLeafCount() {
        let node = SplitPaneNode.split(id: UUID(), orientation: .horizontal,
                                       first: .leaf(id: UUID()), second: .leaf(id: UUID()), ratio: 0.5)
        XCTAssertEqual(node.leafCount, 2)
    }

    func testNestedSplitLeafCount() {
        let inner = SplitPaneNode.split(id: UUID(), orientation: .vertical,
                                        first: .leaf(id: UUID()), second: .leaf(id: UUID()), ratio: 0.5)
        let outer = SplitPaneNode.split(id: UUID(), orientation: .horizontal,
                                        first: inner, second: .leaf(id: UUID()), ratio: 0.5)
        XCTAssertEqual(outer.leafCount, 3)
    }

    func testAllLeafIDsReturnsAllLeaves() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = SplitPaneNode.split(id: UUID(), orientation: .vertical,
                                        first: .leaf(id: a), second: .leaf(id: b), ratio: 0.5)
        let outer = SplitPaneNode.split(id: UUID(), orientation: .horizontal,
                                        first: inner, second: .leaf(id: c), ratio: 0.5)
        XCTAssertEqual(Set(outer.allLeafIDs), Set([a, b, c]))
    }

    func testContainsLeaf() {
        let a = UUID(), b = UUID()
        let node = SplitPaneNode.split(id: UUID(), orientation: .horizontal,
                                       first: .leaf(id: a), second: .leaf(id: b), ratio: 0.5)
        XCTAssertTrue(node.containsLeaf(a))
        XCTAssertTrue(node.containsLeaf(b))
        XCTAssertFalse(node.containsLeaf(UUID()))
    }

    func testOrientationToggle() {
        XCTAssertEqual(SplitOrientation.horizontal.toggled, .vertical)
        XCTAssertEqual(SplitOrientation.vertical.toggled, .horizontal)
    }
}

final class SplitLayoutEngineTests: XCTestCase {
    func testAddSplitToSingleLeaf() {
        let root = SplitPaneNode.singleLeaf()
        let result = SplitLayoutEngine.addSplit(to: root, at: root.id, orientation: .horizontal)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.leafCount, 2)
    }

    func testAddSplitRespectsOrientation() {
        let root = SplitPaneNode.singleLeaf()
        let result = SplitLayoutEngine.addSplit(to: root, at: root.id, orientation: .vertical)!
        if case .split(_, let o, _, _, _) = result {
            XCTAssertEqual(o, .vertical)
        } else { XCTFail("Expected split") }
    }

    func testAddSplitEnforcesMaxPanes() {
        var root = SplitPaneNode.singleLeaf()
        for _ in 0..<(SplitPaneNode.maxPanes - 1) {
            let leafID = root.allLeafIDs.last!
            root = SplitLayoutEngine.addSplit(to: root, at: leafID, orientation: .horizontal)!
        }
        XCTAssertEqual(root.leafCount, SplitPaneNode.maxPanes)
        let extra = SplitLayoutEngine.addSplit(to: root, at: root.allLeafIDs.last!, orientation: .horizontal)
        XCTAssertNil(extra)
    }

    func testAddSplitToNonexistentPaneReturnsNil() {
        let root = SplitPaneNode.singleLeaf()
        XCTAssertNil(SplitLayoutEngine.addSplit(to: root, at: UUID(), orientation: .horizontal))
    }

    func testRemovePaneFromTwoLeafSplit() {
        let root = SplitPaneNode.singleLeaf()
        let split = SplitLayoutEngine.addSplit(to: root, at: root.id, orientation: .horizontal)!
        let leafToRemove = split.allLeafIDs.last!
        let result = SplitLayoutEngine.removePane(from: split, paneID: leafToRemove)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.leafCount, 1)
    }

    func testRemovePaneFromSingleLeafReturnsNil() {
        let root = SplitPaneNode.singleLeaf()
        XCTAssertNil(SplitLayoutEngine.removePane(from: root, paneID: root.id))
    }

    func testToggleOrientationOnDirectParent() {
        let root = SplitPaneNode.singleLeaf()
        let split = SplitLayoutEngine.addSplit(to: root, at: root.id, orientation: .horizontal)!
        let toggled = SplitLayoutEngine.toggleOrientation(of: split, containing: root.id)!
        if case .split(_, let o, _, _, _) = toggled {
            XCTAssertEqual(o, .vertical)
        } else { XCTFail("Expected split") }
    }

    func testUpdateRatioClampsToRange() {
        let root = SplitPaneNode.singleLeaf()
        let split = SplitLayoutEngine.addSplit(to: root, at: root.id, orientation: .horizontal)!
        let updated = SplitLayoutEngine.updateRatio(in: split, splitID: split.id, ratio: 1.5)!
        if case .split(_, _, _, _, let r) = updated {
            XCTAssertEqual(r, 0.9, accuracy: 0.01)
        } else { XCTFail("Expected split") }
    }

    func testMaxPanesReachableAndStable() {
        var root = SplitPaneNode.singleLeaf()
        while root.leafCount < SplitPaneNode.maxPanes {
            let leafID = root.allLeafIDs.last!
            root = SplitLayoutEngine.addSplit(to: root, at: leafID, orientation: .horizontal)!
        }
        XCTAssertEqual(root.leafCount, SplitPaneNode.maxPanes)
        // Remove one and re-add
        let removed = SplitLayoutEngine.removePane(from: root, paneID: root.allLeafIDs.first!)!
        XCTAssertEqual(removed.leafCount, SplitPaneNode.maxPanes - 1)
        let readded = SplitLayoutEngine.addSplit(to: removed, at: removed.allLeafIDs.first!, orientation: .vertical)!
        XCTAssertEqual(readded.leafCount, SplitPaneNode.maxPanes)
    }
}
