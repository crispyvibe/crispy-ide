import CoreGraphics
import Foundation

// MARK: - Board Hit Testing

struct BoardHitTesting {
    /// Approximate header height for hit-test purposes. Matches tile card header padding (6pt vertical) + content (~20pt).
    static let defaultHeaderHeight: CGFloat = 32

    struct Context {
        let tileFrames: [(id: UUID, frame: CGRect)]
        let columnDividers: [(leftColumnID: UUID, rightColumnID: UUID, centerX: CGFloat)]
        let rowDividers: [(columnID: UUID, upperTileID: UUID, lowerTileID: UUID, centerY: CGFloat, minX: CGFloat, maxX: CGFloat)]
        let dividerThickness: CGFloat
        let headerHeight: CGFloat
    }

    static func hitTest(at point: CGPoint, context: Context) -> BoardHitRegion {
        // Priority 1: column dividers (vertical strips)
        for divider in context.columnDividers {
            let halfThickness = context.dividerThickness * 0.5
            if point.x >= divider.centerX - halfThickness && point.x <= divider.centerX + halfThickness {
                return .columnDivider(leftColumnID: divider.leftColumnID, rightColumnID: divider.rightColumnID)
            }
        }

        // Priority 2: row dividers (horizontal strips within column bounds)
        for divider in context.rowDividers {
            let halfThickness = context.dividerThickness * 0.5
            if point.y >= divider.centerY - halfThickness && point.y <= divider.centerY + halfThickness
                && point.x >= divider.minX && point.x <= divider.maxX {
                return .rowDivider(columnID: divider.columnID, upperTileID: divider.upperTileID, lowerTileID: divider.lowerTileID)
            }
        }

        // Priority 3: tile header or body
        for tile in context.tileFrames {
            guard tile.frame.contains(point) else { continue }
            let headerRect = CGRect(
                x: tile.frame.minX,
                y: tile.frame.minY,
                width: tile.frame.width,
                height: min(context.headerHeight, tile.frame.height)
            )
            if headerRect.contains(point) {
                return .tileHeader(tileID: tile.id)
            }
            return .tileBody(tileID: tile.id)
        }

        return .empty
    }

    /// Build a hit-test context from a layout and board size, reusing metrics math.
    static func context(
        from layout: VibeSpaceTerminalBoardLayout,
        boardSize: CGSize,
        spacing: CGFloat = 8,
        padding: CGFloat = 6,
        headerHeight: CGFloat = defaultHeaderHeight,
        dividerThickness: CGFloat = 16
    ) -> Context {
        let metrics = VibeSpaceTerminalBoardMetrics(
            size: boardSize,
            layout: layout,
            spacing: spacing,
            padding: padding
        )

        let tileFrames = layout.tiles.map { tile in
            (id: tile.id, frame: metrics.frame(for: tile))
        }

        var columnDividers: [(leftColumnID: UUID, rightColumnID: UUID, centerX: CGFloat)] = []
        for handle in metrics.columnResizeHandles() {
            columnDividers.append((
                leftColumnID: handle.leftColumnID,
                rightColumnID: handle.rightColumnID,
                centerX: handle.frame.midX
            ))
        }

        var rowDividers: [(columnID: UUID, upperTileID: UUID, lowerTileID: UUID, centerY: CGFloat, minX: CGFloat, maxX: CGFloat)] = []
        for handle in metrics.rowResizeHandles() {
            rowDividers.append((
                columnID: handle.columnID,
                upperTileID: handle.upperTileID,
                lowerTileID: handle.lowerTileID,
                centerY: handle.frame.midY,
                minX: handle.frame.minX,
                maxX: handle.frame.maxX
            ))
        }

        return Context(
            tileFrames: tileFrames,
            columnDividers: columnDividers,
            rowDividers: rowDividers,
            dividerThickness: dividerThickness,
            headerHeight: headerHeight
        )
    }
}

// MARK: - Board Resize Calculator

struct BoardResizeCalculator {
    static let minimumWeight: Double = 0.12

    struct ResizeResult: Equatable {
        let firstWeight: Double
        let secondWeight: Double
    }

    /// Compute new weights from initial weights and a weight delta.
    /// Clamps both sides to `minimumWeight`.
    static func computeWeights(
        initialFirst: Double,
        initialSecond: Double,
        weightDelta: Double,
        minimumWeight: Double = minimumWeight
    ) -> ResizeResult {
        let total = initialFirst + initialSecond
        guard total > minimumWeight * 2 else {
            return ResizeResult(firstWeight: initialFirst, secondWeight: initialSecond)
        }
        let targetFirst = initialFirst + weightDelta
        let clampedFirst = min(max(targetFirst, minimumWeight), total - minimumWeight)
        return ResizeResult(firstWeight: clampedFirst, secondWeight: total - clampedFirst)
    }
}
