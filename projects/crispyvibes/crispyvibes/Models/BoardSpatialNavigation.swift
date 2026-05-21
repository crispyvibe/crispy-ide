import CoreGraphics
import Foundation

enum BoardNavigationDirection {
    case left, right, up, down
}

enum BoardSpatialNavigation {
    /// Resolve the next tile to focus based on spatial position.
    /// Returns the target tile ID, or nil if navigation is not possible.
    static func resolve(
        direction: BoardNavigationDirection,
        activeTileID: UUID?,
        layout: VibeSpaceTerminalBoardLayout,
        tileFrames: [UUID: CGRect]
    ) -> UUID? {
        guard !layout.columns.isEmpty else { return nil }

        guard let activeID = activeTileID,
              let activePosition = layout.position(of: activeID),
              let activeFrame = tileFrames[activeID] else {
            return layout.columns.first?.tiles.first?.id
        }

        switch direction {
        case .up:
            let column = layout.columns[activePosition.columnIndex]
            guard activePosition.rowIndex > 0 else { return nil }
            return column.tiles[activePosition.rowIndex - 1].id

        case .down:
            let column = layout.columns[activePosition.columnIndex]
            guard activePosition.rowIndex < column.tiles.count - 1 else { return nil }
            return column.tiles[activePosition.rowIndex + 1].id

        case .left:
            guard activePosition.columnIndex > 0 else { return nil }
            let targetColumn = layout.columns[activePosition.columnIndex - 1]
            return closestTileByVerticalCenter(in: targetColumn, to: activeFrame, tileFrames: tileFrames)

        case .right:
            guard activePosition.columnIndex < layout.columns.count - 1 else { return nil }
            let targetColumn = layout.columns[activePosition.columnIndex + 1]
            return closestTileByVerticalCenter(in: targetColumn, to: activeFrame, tileFrames: tileFrames)
        }
    }

    private static func closestTileByVerticalCenter(
        in column: VibeSpaceTerminalBoardColumn,
        to referenceFrame: CGRect,
        tileFrames: [UUID: CGRect]
    ) -> UUID? {
        let refCenterY = referenceFrame.midY
        return column.tiles.min(by: { a, b in
            let aDist = abs((tileFrames[a.id]?.midY ?? 0) - refCenterY)
            let bDist = abs((tileFrames[b.id]?.midY ?? 0) - refCenterY)
            return aDist < bDist
        })?.id
    }
}
