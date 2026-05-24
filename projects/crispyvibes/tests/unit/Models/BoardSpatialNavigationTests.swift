import CoreGraphics
import Foundation
import XCTest
@testable import CrispyVibes

final class BoardSpatialNavigationTests: XCTestCase {

    // Helper: build a layout and frames for a given column/row structure
    private func makeGrid(_ structure: [[String]]) -> (layout: VibeSpaceTerminalBoardLayout, frames: [UUID: CGRect], ids: [String: UUID]) {
        var ids: [String: UUID] = [:]
        var columns: [VibeSpaceTerminalBoardColumn] = []
        let colWidth: CGFloat = 200
        let rowHeight: CGFloat = 150
        let spacing: CGFloat = 8
        var frames: [UUID: CGRect] = [:]

        for (colIdx, rows) in structure.enumerated() {
            var tiles: [VibeSpaceTerminalBoardTile] = []
            for (rowIdx, name) in rows.enumerated() {
                let id = UUID()
                ids[name] = id
                tiles.append(VibeSpaceTerminalBoardTile(id: id, workingDirectoryPath: "/\(name)"))
                frames[id] = CGRect(
                    x: CGFloat(colIdx) * (colWidth + spacing),
                    y: CGFloat(rowIdx) * (rowHeight + spacing),
                    width: colWidth,
                    height: rowHeight
                )
            }
            columns.append(VibeSpaceTerminalBoardColumn(tiles: tiles))
        }

        let layout = VibeSpaceTerminalBoardLayout(columns: columns, activeTileID: nil)
        return (layout, frames, ids)
    }

    // MARK: - Up/Down within column

    func testDownMovesToNextTileInColumn() {
        let (layout, frames, ids) = makeGrid([["A", "B", "C"]])
        let result = BoardSpatialNavigation.resolve(direction: .down, activeTileID: ids["A"], layout: layout, tileFrames: frames)
        XCTAssertEqual(result, ids["B"])
    }

    func testUpMovesToPreviousTileInColumn() {
        let (layout, frames, ids) = makeGrid([["A", "B", "C"]])
        let result = BoardSpatialNavigation.resolve(direction: .up, activeTileID: ids["C"], layout: layout, tileFrames: frames)
        XCTAssertEqual(result, ids["B"])
    }

    func testDownFromBottomTileReturnsNil() {
        let (layout, frames, ids) = makeGrid([["A", "B"]])
        let result = BoardSpatialNavigation.resolve(direction: .down, activeTileID: ids["B"], layout: layout, tileFrames: frames)
        XCTAssertNil(result)
    }

    func testUpFromTopTileReturnsNil() {
        let (layout, frames, ids) = makeGrid([["A", "B"]])
        let result = BoardSpatialNavigation.resolve(direction: .up, activeTileID: ids["A"], layout: layout, tileFrames: frames)
        XCTAssertNil(result)
    }

    // MARK: - Left/Right across columns

    func testRightMovesToAdjacentColumn() {
        let (layout, frames, ids) = makeGrid([["A"], ["B"]])
        let result = BoardSpatialNavigation.resolve(direction: .right, activeTileID: ids["A"], layout: layout, tileFrames: frames)
        XCTAssertEqual(result, ids["B"])
    }

    func testLeftMovesToAdjacentColumn() {
        let (layout, frames, ids) = makeGrid([["A"], ["B"]])
        let result = BoardSpatialNavigation.resolve(direction: .left, activeTileID: ids["B"], layout: layout, tileFrames: frames)
        XCTAssertEqual(result, ids["A"])
    }

    func testRightFromRightmostColumnReturnsNil() {
        let (layout, frames, ids) = makeGrid([["A"], ["B"]])
        let result = BoardSpatialNavigation.resolve(direction: .right, activeTileID: ids["B"], layout: layout, tileFrames: frames)
        XCTAssertNil(result)
    }

    func testLeftFromLeftmostColumnReturnsNil() {
        let (layout, frames, ids) = makeGrid([["A"], ["B"]])
        let result = BoardSpatialNavigation.resolve(direction: .left, activeTileID: ids["A"], layout: layout, tileFrames: frames)
        XCTAssertNil(result)
    }

    // MARK: - Cross-column vertical center matching

    func testRightPicksClosestVerticalCenter() {
        // Column 1: one tall tile centered at y=150
        // Column 2: three tiles centered at y=75, y=225, y=375
        // Moving right from column 1 should pick the tile closest to y=150 → row 0 (y=75) or row 1 (y=225)
        // Distance to row 0: |150-75|=75, distance to row 1: |150-225|=75 — tie, picks first (row 0)
        let (layout, frames, ids) = makeGrid([["A"], ["B", "C", "D"]])
        // Override A's frame to be tall and centered
        var adjustedFrames = frames
        adjustedFrames[ids["A"]!] = CGRect(x: 0, y: 0, width: 200, height: 300) // center at y=150
        // B at y=0..150 center=75, C at y=158..308 center=233, D at y=316..466 center=391
        adjustedFrames[ids["B"]!] = CGRect(x: 208, y: 0, width: 200, height: 150)
        adjustedFrames[ids["C"]!] = CGRect(x: 208, y: 158, width: 200, height: 150)
        adjustedFrames[ids["D"]!] = CGRect(x: 208, y: 316, width: 200, height: 150)

        let result = BoardSpatialNavigation.resolve(direction: .right, activeTileID: ids["A"], layout: layout, tileFrames: adjustedFrames)
        // A center=150, B center=75 (dist 75), C center=233 (dist 83) → picks B
        XCTAssertEqual(result, ids["B"])
    }

    func testRightPicksMiddleTileWhenClosest() {
        let (layout, frames, ids) = makeGrid([["A"], ["B", "C", "D"]])
        var adjustedFrames = frames
        adjustedFrames[ids["A"]!] = CGRect(x: 0, y: 100, width: 200, height: 150) // center at y=175
        adjustedFrames[ids["B"]!] = CGRect(x: 208, y: 0, width: 200, height: 100)   // center=50
        adjustedFrames[ids["C"]!] = CGRect(x: 208, y: 108, width: 200, height: 100)  // center=158
        adjustedFrames[ids["D"]!] = CGRect(x: 208, y: 216, width: 200, height: 100)  // center=266

        let result = BoardSpatialNavigation.resolve(direction: .right, activeTileID: ids["A"], layout: layout, tileFrames: adjustedFrames)
        // A center=175, B center=50 (dist 125), C center=158 (dist 17), D center=266 (dist 91) → picks C
        XCTAssertEqual(result, ids["C"])
    }

    // MARK: - Single tile

    func testSingleTileAllDirectionsReturnNil() {
        let (layout, frames, ids) = makeGrid([["A"]])
        for direction in [BoardNavigationDirection.left, .right, .up, .down] {
            let result = BoardSpatialNavigation.resolve(direction: direction, activeTileID: ids["A"], layout: layout, tileFrames: frames)
            XCTAssertNil(result, "Expected nil for direction \(direction) on single tile")
        }
    }

    // MARK: - Empty board

    func testEmptyBoardReturnsNil() {
        let layout = VibeSpaceTerminalBoardLayout.empty
        let result = BoardSpatialNavigation.resolve(direction: .right, activeTileID: nil, layout: layout, tileFrames: [:])
        XCTAssertNil(result)
    }

    // MARK: - Nil active tile defaults to first

    func testNilActiveTileDefaultsToFirstTile() {
        let (layout, frames, ids) = makeGrid([["A", "B"], ["C"]])
        let result = BoardSpatialNavigation.resolve(direction: .right, activeTileID: nil, layout: layout, tileFrames: frames)
        XCTAssertEqual(result, ids["A"])
    }
}
