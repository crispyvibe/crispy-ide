import Foundation

extension VibeSpaceTerminalBoardLayout {
    private static let minimumColumnWeight: Double = 0.12
    private static let minimumRowWeight: Double = 0.12

    @discardableResult
    mutating func insertNewTile(
        _ tile: VibeSpaceTerminalBoardTile,
        activeHintTileID: UUID?,
        activateInsertedTile: Bool = true
    ) -> Bool {
        guard tileCount < Self.maximumTileCount else { return false }

        if columns.isEmpty {
            columns = [VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [tile])]
            if activateInsertedTile {
                activeTileID = tile.id
            }
            return true
        }

        if tileCount == 1 {
            columns.append(VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [tile]))
            if activateInsertedTile {
                activeTileID = tile.id
            }
            return true
        }

        if columns.count == 1, columns[0].tiles.count >= 2 {
            columns.append(VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [tile]))
            if activateInsertedTile {
                activeTileID = tile.id
            }
            return true
        }

        let activeID = activeHintTileID ?? activeTileID
        if let activeID,
           let activePosition = position(of: activeID),
           columns[activePosition.columnIndex].tiles.count < Self.maxRowsPerColumn {
            let insertionIndex = min(
                activePosition.rowIndex + 1,
                columns[activePosition.columnIndex].tiles.count
            )
            columns[activePosition.columnIndex].tiles.insert(tile, at: insertionIndex)
            if activateInsertedTile {
                activeTileID = tile.id
            }
            return true
        }

        if columns.count < Self.maxColumns {
            let insertionIndex: Int
            if let activeID,
               let activePosition = position(of: activeID) {
                insertionIndex = min(activePosition.columnIndex + 1, columns.count)
            } else {
                insertionIndex = columns.count
            }

            columns.insert(
                VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [tile]),
                at: insertionIndex
            )
            if activateInsertedTile {
                activeTileID = tile.id
            }
            return true
        }

        if let fallbackColumnIndex = columns.firstIndex(where: { $0.tiles.count < Self.maxRowsPerColumn }) {
            columns[fallbackColumnIndex].tiles.append(tile)
            if activateInsertedTile {
                activeTileID = tile.id
            }
            return true
        }

        return false
    }

    @discardableResult
    mutating func moveTile(
        _ tileID: UUID,
        using intent: VibeSpaceTerminalBoardDropIntent
    ) -> Bool {
        switch intent {
        case let .swap(with: targetID):
            return swapTile(tileID, with: targetID)
        case let .insertLeft(of: targetID):
            return moveTile(tileID, relativeTo: targetID, edge: .left)
        case let .insertRight(of: targetID):
            return moveTile(tileID, relativeTo: targetID, edge: .right)
        case let .insertAbove(of: targetID):
            return moveTile(tileID, relativeTo: targetID, edge: .top)
        case let .insertBelow(of: targetID):
            return moveTile(tileID, relativeTo: targetID, edge: .bottom)
        }
    }

    func previewLayout(
        moving tileID: UUID,
        with intent: VibeSpaceTerminalBoardDropIntent
    ) -> VibeSpaceTerminalBoardLayout? {
        var draft = self
        guard draft.moveTile(tileID, using: intent) else { return nil }
        return draft
    }

    @discardableResult
    mutating func moveTileInLinearOrder(
        _ tileID: UUID,
        relativeTo targetID: UUID,
        placement: TerminalTabMovePlacement
    ) -> Bool {
        guard tileID != targetID else { return false }
        let columnCounts = columns.map(\.tiles.count)
        var flatTiles = columns.flatMap(\.tiles)
        guard let sourceIndex = flatTiles.firstIndex(where: { $0.id == tileID }),
              flatTiles.contains(where: { $0.id == targetID }) else {
            return false
        }

        let movingTile = flatTiles.remove(at: sourceIndex)
        guard let adjustedTargetIndex = flatTiles.firstIndex(where: { $0.id == targetID }) else {
            return false
        }
        let insertionIndex = switch placement {
        case .before:
            adjustedTargetIndex
        case .after:
            adjustedTargetIndex + 1
        }
        flatTiles.insert(movingTile, at: max(0, min(insertionIndex, flatTiles.count)))

        var cursor = 0
        for columnIndex in columns.indices {
            let count = columnCounts[columnIndex]
            columns[columnIndex].tiles = Array(flatTiles[cursor..<(cursor + count)])
            cursor += count
        }
        return true
    }

    private enum RelativeEdge {
        case left
        case right
        case top
        case bottom
    }

    @discardableResult
    private mutating func swapTile(_ tileID: UUID, with targetID: UUID) -> Bool {
        guard tileID != targetID else { return false }
        guard let source = position(of: tileID),
              let target = position(of: targetID) else {
            return false
        }

        let sourceTile = columns[source.columnIndex].tiles[source.rowIndex]
        columns[source.columnIndex].tiles[source.rowIndex] = columns[target.columnIndex].tiles[target.rowIndex]
        columns[target.columnIndex].tiles[target.rowIndex] = sourceTile
        activeTileID = tileID
        return true
    }

    @discardableResult
    private mutating func moveTile(
        _ tileID: UUID,
        relativeTo targetID: UUID,
        edge: RelativeEdge
    ) -> Bool {
        guard tileID != targetID else { return false }
        guard let sourcePosition = position(of: tileID),
              position(of: targetID) != nil else {
            return false
        }

        let sourceColumnCount = columns[sourcePosition.columnIndex].tiles.count
        let sourceColumnWillBeRemoved = sourceColumnCount == 1
        let canCreateAdjacentColumn = columns.count - (sourceColumnWillBeRemoved ? 1 : 0) + 1 <= Self.maxColumns

        let movingTile = columns[sourcePosition.columnIndex].tiles.remove(at: sourcePosition.rowIndex)
        if columns[sourcePosition.columnIndex].tiles.isEmpty {
            columns.remove(at: sourcePosition.columnIndex)
        }

        guard let targetPosition = position(of: targetID) else {
            return insertNewTile(movingTile, activeHintTileID: activeTileID)
        }

        switch edge {
        case .left:
            if canCreateAdjacentColumn {
                columns.insert(
                    VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [movingTile]),
                    at: targetPosition.columnIndex
                )
            } else {
                insertInColumnOrFallback(
                    movingTile,
                    columnIndex: targetPosition.columnIndex,
                    rowIndex: targetPosition.rowIndex
                )
            }
        case .right:
            if canCreateAdjacentColumn {
                let insertionColumn = min(targetPosition.columnIndex + 1, columns.count)
                columns.insert(
                    VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [movingTile]),
                    at: insertionColumn
                )
            } else {
                insertInColumnOrFallback(
                    movingTile,
                    columnIndex: targetPosition.columnIndex,
                    rowIndex: targetPosition.rowIndex + 1
                )
            }
        case .top:
            if columns[targetPosition.columnIndex].tiles.count < Self.maxRowsPerColumn {
                columns[targetPosition.columnIndex].tiles.insert(movingTile, at: targetPosition.rowIndex)
            } else if canCreateAdjacentColumn {
                columns.insert(
                    VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [movingTile]),
                    at: targetPosition.columnIndex
                )
            } else {
                insertIntoFirstAvailableRowColumn(movingTile)
            }
        case .bottom:
            if columns[targetPosition.columnIndex].tiles.count < Self.maxRowsPerColumn {
                let insertionRow = min(
                    targetPosition.rowIndex + 1,
                    columns[targetPosition.columnIndex].tiles.count
                )
                columns[targetPosition.columnIndex].tiles.insert(movingTile, at: insertionRow)
            } else if canCreateAdjacentColumn {
                let insertionColumn = min(targetPosition.columnIndex + 1, columns.count)
                columns.insert(
                    VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [movingTile]),
                    at: insertionColumn
                )
            } else {
                insertIntoFirstAvailableRowColumn(movingTile)
            }
        }

        activeTileID = tileID
        return true
    }

    private mutating func insertInColumnOrFallback(
        _ tile: VibeSpaceTerminalBoardTile,
        columnIndex: Int,
        rowIndex: Int
    ) {
        guard columns.indices.contains(columnIndex) else {
            insertIntoFirstAvailableRowColumn(tile)
            return
        }

        if columns[columnIndex].tiles.count < Self.maxRowsPerColumn {
            let insertionIndex = max(0, min(rowIndex, columns[columnIndex].tiles.count))
            columns[columnIndex].tiles.insert(tile, at: insertionIndex)
            return
        }

        insertIntoFirstAvailableRowColumn(tile)
    }

    private mutating func insertIntoFirstAvailableRowColumn(_ tile: VibeSpaceTerminalBoardTile) {
        if let fallbackColumnIndex = columns.firstIndex(where: { $0.tiles.count < Self.maxRowsPerColumn }) {
            columns[fallbackColumnIndex].tiles.append(tile)
            return
        }

        // Defensive fallback: replace active tile if every column is unexpectedly full.
        if let activeTileID,
           let activePosition = position(of: activeTileID) {
            columns[activePosition.columnIndex].tiles[activePosition.rowIndex] = tile
            return
        }

        columns = [VibeSpaceTerminalBoardColumn(widthWeight: 1, tiles: [tile])]
    }

    @discardableResult
    mutating func resizeColumns(
        leftColumnID: UUID,
        rightColumnID: UUID,
        deltaFraction: Double
    ) -> Bool {
        guard let leftIndex = columns.firstIndex(where: { $0.id == leftColumnID }),
              let rightIndex = columns.firstIndex(where: { $0.id == rightColumnID }),
              rightIndex == leftIndex + 1 else {
            return false
        }

        let leftWeight = VibeSpaceTerminalBoardColumn.normalizedWeight(columns[leftIndex].widthWeight)
        let rightWeight = VibeSpaceTerminalBoardColumn.normalizedWeight(columns[rightIndex].widthWeight)
        let totalWeight = leftWeight + rightWeight
        guard totalWeight > (Self.minimumColumnWeight * 2) else { return false }

        let targetLeftWeight = leftWeight + deltaFraction
        let clampedLeftWeight = min(
            max(targetLeftWeight, Self.minimumColumnWeight),
            totalWeight - Self.minimumColumnWeight
        )
        guard abs(clampedLeftWeight - leftWeight) > 0.0005 else { return false }

        columns[leftIndex].widthWeight = clampedLeftWeight
        columns[rightIndex].widthWeight = totalWeight - clampedLeftWeight
        return true
    }

    @discardableResult
    mutating func resizeRows(
        columnID: UUID,
        upperTileID: UUID,
        lowerTileID: UUID,
        deltaFraction: Double
    ) -> Bool {
        guard let columnIndex = columns.firstIndex(where: { $0.id == columnID }),
              let upperRowIndex = columns[columnIndex].tiles.firstIndex(where: { $0.id == upperTileID }),
              let lowerRowIndex = columns[columnIndex].tiles.firstIndex(where: { $0.id == lowerTileID }),
              lowerRowIndex == upperRowIndex + 1 else {
            return false
        }

        let upperWeight = VibeSpaceTerminalBoardColumn.normalizedWeight(
            columns[columnIndex].tiles[upperRowIndex].heightWeight
        )
        let lowerWeight = VibeSpaceTerminalBoardColumn.normalizedWeight(
            columns[columnIndex].tiles[lowerRowIndex].heightWeight
        )
        let totalWeight = upperWeight + lowerWeight
        guard totalWeight > (Self.minimumRowWeight * 2) else { return false }

        let targetUpperWeight = upperWeight + deltaFraction
        let clampedUpperWeight = min(
            max(targetUpperWeight, Self.minimumRowWeight),
            totalWeight - Self.minimumRowWeight
        )
        guard abs(clampedUpperWeight - upperWeight) > 0.0005 else { return false }

        columns[columnIndex].tiles[upperRowIndex].heightWeight = clampedUpperWeight
        columns[columnIndex].tiles[lowerRowIndex].heightWeight = totalWeight - clampedUpperWeight
        return true
    }
}
