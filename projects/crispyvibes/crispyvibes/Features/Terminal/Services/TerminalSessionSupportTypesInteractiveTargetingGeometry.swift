import AppKit

extension NSView {
    func crispyvibesBackingScaleFactor() -> CGFloat {
        let backingUnit = convertToBacking(NSSize(width: 1, height: 1))
        let scale = max(backingUnit.width, backingUnit.height)
        return scale > 0 ? scale : 1
    }
}

extension MonitoredTerminalView {
    func interactiveTarget(for event: NSEvent) -> TerminalInteractiveTarget? {
        interactiveTarget(at: convert(event.locationInWindow, from: nil))
    }

    func interactiveTargetHit(at point: CGPoint) -> TerminalInteractiveTargetHit? {
        guard let hit = visibleGridPosition(at: point) else { return nil }
        return TerminalInteractiveTargetDetector.detectHit(
            in: SwiftTermTerminalInteractiveGrid(terminal: terminal),
            visibleColumn: hit.col,
            visibleRow: hit.row,
            currentDirectory: currentDirectoryProvider?()
        )
    }

    func updateInteractiveHoverHighlight(_ hit: TerminalInteractiveTargetHit?) {
        interactiveHoverOverlay.highlightRects = hit?.segments.compactMap {
            interactiveHighlightRect(for: $0)
        } ?? []
    }

    func visibleGridPosition(at point: CGPoint) -> (col: Int, row: Int)? {
        guard terminal.cols > 0, terminal.rows > 0 else { return nil }
        guard bounds.contains(point) else { return nil }

        guard let cellSize = resolvedTerminalCellSizeInPoints() else { return nil }
        let cellWidth = max(cellSize.width, 1)
        let cellHeight = max(cellSize.height, 1)
        let contentWidth = cellWidth * CGFloat(terminal.cols)
        let contentHeight = cellHeight * CGFloat(terminal.rows)
        let minimumY = max(0, bounds.height - contentHeight)
        guard point.x >= 0, point.x < contentWidth else { return nil }
        guard point.y >= minimumY, point.y <= bounds.height else { return nil }

        let column = min(max(Int(point.x / cellWidth), 0), terminal.cols - 1)
        let row = min(max(Int((bounds.height - point.y) / cellHeight), 0), terminal.rows - 1)
        return (col: column, row: row)
    }

    func resolvedTerminalCellSizeInPoints() -> CGSize? {
        guard let pixelSize = cellSizeInPixels(source: terminal) else { return nil }
        let scale = crispyvibesBackingScaleFactor()
        guard scale > 0 else { return nil }
        return CGSize(
            width: CGFloat(pixelSize.width) / scale,
            height: CGFloat(pixelSize.height) / scale
        )
    }

    func interactiveHighlightRect(for segment: TerminalInteractiveTargetSegment) -> CGRect? {
        guard let cellSize = resolvedTerminalCellSizeInPoints() else { return nil }
        let cellWidth = max(cellSize.width, 1)
        let cellHeight = max(cellSize.height, 1)

        let minX = CGFloat(segment.columns.lowerBound) * cellWidth
        let width = CGFloat(max(segment.columns.upperBound - segment.columns.lowerBound, 1)) * cellWidth
        let minY = bounds.height - (CGFloat(segment.row + 1) * cellHeight)

        let rect = CGRect(x: minX, y: minY, width: width, height: cellHeight)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
}
