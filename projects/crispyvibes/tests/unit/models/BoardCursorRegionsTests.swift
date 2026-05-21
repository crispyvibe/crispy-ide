import CoreGraphics
import Foundation
import XCTest
@testable import CrispyVibes

final class BoardCursorRegionsTests: XCTestCase {
    func testSingleColumnNoCursorRegions() {
        var layout = VibeSpaceTerminalBoardLayout.empty
        _ = layout.insertNewTile(VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp"), activeHintTileID: nil)
        let regions = BoardCursorRegions.regions(from: layout, boardSize: CGSize(width: 800, height: 600))
        XCTAssertTrue(regions.isEmpty)
    }

    func testTwoColumnsOneHorizontalRegion() {
        var layout = VibeSpaceTerminalBoardLayout.empty
        _ = layout.insertNewTile(VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/a"), activeHintTileID: nil)
        _ = layout.insertNewTile(VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/b"), activeHintTileID: nil)
        let regions = BoardCursorRegions.regions(from: layout, boardSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions.first?.cursorType, .resizeLeftRight)
    }

    func testColumnWithTwoTilesOneVerticalRegion() {
        var layout = VibeSpaceTerminalBoardLayout.empty
        let t1 = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/a")
        let t2 = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/b")
        let t3 = VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/c")
        _ = layout.insertNewTile(t1, activeHintTileID: nil)
        _ = layout.insertNewTile(t2, activeHintTileID: nil)
        // Third tile goes into active column as a row
        _ = layout.insertNewTile(t3, activeHintTileID: t2.id)
        let regions = BoardCursorRegions.regions(from: layout, boardSize: CGSize(width: 800, height: 600))
        let horizontal = regions.filter { $0.cursorType == .resizeLeftRight }
        let vertical = regions.filter { $0.cursorType == .resizeUpDown }
        XCTAssertEqual(horizontal.count, 1)
        XCTAssertEqual(vertical.count, 1)
    }

    func testRegionRectsHavePositiveSize() {
        var layout = VibeSpaceTerminalBoardLayout.empty
        _ = layout.insertNewTile(VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/a"), activeHintTileID: nil)
        _ = layout.insertNewTile(VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/b"), activeHintTileID: nil)
        let regions = BoardCursorRegions.regions(from: layout, boardSize: CGSize(width: 800, height: 600))
        for region in regions {
            XCTAssertGreaterThan(region.rect.width, 0)
            XCTAssertGreaterThan(region.rect.height, 0)
        }
    }

    func testHitExpansionExpandsRects() {
        var layout = VibeSpaceTerminalBoardLayout.empty
        _ = layout.insertNewTile(VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/a"), activeHintTileID: nil)
        _ = layout.insertNewTile(VibeSpaceTerminalBoardTile(workingDirectoryPath: "/tmp/b"), activeHintTileID: nil)
        let narrow = BoardCursorRegions.regions(from: layout, boardSize: CGSize(width: 800, height: 600), hitExpansion: 0)
        let wide = BoardCursorRegions.regions(from: layout, boardSize: CGSize(width: 800, height: 600), hitExpansion: 8)
        XCTAssertGreaterThan(wide.first!.rect.width, narrow.first!.rect.width)
    }
}
