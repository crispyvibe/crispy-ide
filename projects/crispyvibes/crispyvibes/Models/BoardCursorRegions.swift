import CoreGraphics
import Foundation

enum BoardCursorType: Equatable {
    case resizeLeftRight
    case resizeUpDown
}

struct BoardCursorRegion: Equatable {
    let rect: CGRect
    let cursorType: BoardCursorType
}

struct BoardCursorRegions {
    static func regions(
        from layout: VibeSpaceTerminalBoardLayout,
        boardSize: CGSize,
        spacing: CGFloat = 8,
        padding: CGFloat = 6,
        hitExpansion: CGFloat = 4
    ) -> [BoardCursorRegion] {
        let metrics = VibeSpaceTerminalBoardMetrics(
            size: boardSize,
            layout: layout,
            spacing: spacing,
            padding: padding
        )
        var result: [BoardCursorRegion] = []

        for handle in metrics.columnResizeHandles() {
            let expanded = handle.frame.insetBy(dx: -hitExpansion, dy: 0)
            result.append(BoardCursorRegion(rect: expanded, cursorType: .resizeLeftRight))
        }

        for handle in metrics.rowResizeHandles() {
            let expanded = handle.frame.insetBy(dx: 0, dy: -hitExpansion)
            result.append(BoardCursorRegion(rect: expanded, cursorType: .resizeUpDown))
        }

        return result
    }
}
