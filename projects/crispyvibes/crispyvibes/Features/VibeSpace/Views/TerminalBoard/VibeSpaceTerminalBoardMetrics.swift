import CoreGraphics
import Foundation

enum VibeSpaceTerminalBoardDockTarget: CaseIterable, Equatable {
    case left
    case right
    case top
    case bottom
    case center
}

struct VibeSpaceTerminalBoardDockingGuide: Equatable {
    let targetTileID: UUID
    let targetFrame: CGRect
    let compassFrame: CGRect
    let selectedTarget: VibeSpaceTerminalBoardDockTarget

    var intent: VibeSpaceTerminalBoardDropIntent {
        switch selectedTarget {
        case .left:
            return .insertLeft(of: targetTileID)
        case .right:
            return .insertRight(of: targetTileID)
        case .top:
            return .insertAbove(of: targetTileID)
        case .bottom:
            return .insertBelow(of: targetTileID)
        case .center:
            return .swap(with: targetTileID)
        }
    }

    var isSwap: Bool {
        selectedTarget == .center
    }

    var indicatorFrame: CGRect {
        let edgeThickness = max(10, min(min(targetFrame.width, targetFrame.height) * 0.2, 26))
        switch selectedTarget {
        case .left:
            return CGRect(
                x: targetFrame.minX,
                y: targetFrame.minY,
                width: edgeThickness,
                height: targetFrame.height
            )
        case .right:
            return CGRect(
                x: targetFrame.maxX - edgeThickness,
                y: targetFrame.minY,
                width: edgeThickness,
                height: targetFrame.height
            )
        case .top:
            return CGRect(
                x: targetFrame.minX,
                y: targetFrame.minY,
                width: targetFrame.width,
                height: edgeThickness
            )
        case .bottom:
            return CGRect(
                x: targetFrame.minX,
                y: targetFrame.maxY - edgeThickness,
                width: targetFrame.width,
                height: edgeThickness
            )
        case .center:
            return targetFrame
        }
    }
}

struct VibeSpaceTerminalBoardColumnResizeHandle: Identifiable, Equatable {
    let leftColumnID: UUID
    let rightColumnID: UUID
    let frame: CGRect

    var id: String {
        "\(leftColumnID.uuidString)-\(rightColumnID.uuidString)"
    }
}

struct VibeSpaceTerminalBoardRowResizeHandle: Identifiable, Equatable {
    let columnID: UUID
    let upperTileID: UUID
    let lowerTileID: UUID
    let frame: CGRect

    var id: String {
        "\(columnID.uuidString)-\(upperTileID.uuidString)-\(lowerTileID.uuidString)"
    }
}

struct VibeSpaceTerminalBoardMetrics {
    let size: CGSize
    let layout: VibeSpaceTerminalBoardLayout
    let spacing: CGFloat
    let padding: CGFloat

    private let framesByTileID: [UUID: CGRect]
    private let framesByColumnID: [UUID: CGRect]

    init(
        size: CGSize,
        layout: VibeSpaceTerminalBoardLayout,
        spacing: CGFloat = 8,
        padding: CGFloat = 6
    ) {
        self.size = size
        self.layout = layout.normalized()
        self.spacing = spacing
        self.padding = padding
        let frames = Self.computeFrames(
            for: self.layout,
            size: size,
            spacing: spacing,
            padding: padding
        )
        framesByTileID = frames.tileFramesByID
        framesByColumnID = frames.columnFramesByID
    }

    func frame(for tile: VibeSpaceTerminalBoardTile) -> CGRect {
        frame(for: tile.id)
    }

    func frame(for tileID: UUID) -> CGRect {
        framesByTileID[tileID] ?? .zero
    }

    func dockingGuide(at point: CGPoint, excluding draggedTileID: UUID?) -> VibeSpaceTerminalBoardDockingGuide? {
        let candidates = framesByTileID.filter { candidate in
            candidate.key != draggedTileID
        }
        guard !candidates.isEmpty else { return nil }

        let chosenTarget: (id: UUID, frame: CGRect)
        if let containing = candidates.first(where: { $0.value.contains(point) }) {
            chosenTarget = (containing.key, containing.value)
        } else if let nearest = candidates.min(by: {
            distance(from: point, to: $0.value) < distance(from: point, to: $1.value)
        }) {
            chosenTarget = (nearest.key, nearest.value)
        } else {
            return nil
        }

        let selectedTarget = dockTarget(for: point, in: chosenTarget.frame)
        let compassFrame = compassFrame(for: chosenTarget.frame)
        return VibeSpaceTerminalBoardDockingGuide(
            targetTileID: chosenTarget.id,
            targetFrame: chosenTarget.frame,
            compassFrame: compassFrame,
            selectedTarget: selectedTarget
        )
    }

    func columnResizeHandles() -> [VibeSpaceTerminalBoardColumnResizeHandle] {
        guard layout.columns.count >= 2 else { return [] }
        let hitWidth: CGFloat = max(spacing + 8, 14)
        var handles: [VibeSpaceTerminalBoardColumnResizeHandle] = []
        handles.reserveCapacity(layout.columns.count - 1)

        for index in 0..<(layout.columns.count - 1) {
            let leftColumn = layout.columns[index]
            let rightColumn = layout.columns[index + 1]
            guard let leftFrame = framesByColumnID[leftColumn.id] else { continue }
            let centerX = leftFrame.maxX + (spacing * 0.5)
            let frame = CGRect(
                x: centerX - (hitWidth * 0.5),
                y: padding,
                width: hitWidth,
                height: max(size.height - (padding * 2), 1)
            )
            handles.append(
                VibeSpaceTerminalBoardColumnResizeHandle(
                    leftColumnID: leftColumn.id,
                    rightColumnID: rightColumn.id,
                    frame: frame
                )
            )
        }

        return handles
    }

    func rowResizeHandles() -> [VibeSpaceTerminalBoardRowResizeHandle] {
        let hitHeight: CGFloat = max(spacing + 8, 14)
        var handles: [VibeSpaceTerminalBoardRowResizeHandle] = []

        for column in layout.columns where column.tiles.count >= 2 {
            guard let columnFrame = framesByColumnID[column.id] else { continue }

            for index in 0..<(column.tiles.count - 1) {
                let upperTile = column.tiles[index]
                let lowerTile = column.tiles[index + 1]
                guard let upperFrame = framesByTileID[upperTile.id] else { continue }
                let centerY = upperFrame.maxY + (spacing * 0.5)
                let frame = CGRect(
                    x: columnFrame.minX,
                    y: centerY - (hitHeight * 0.5),
                    width: max(columnFrame.width, 1),
                    height: hitHeight
                )
                handles.append(
                    VibeSpaceTerminalBoardRowResizeHandle(
                        columnID: column.id,
                        upperTileID: upperTile.id,
                        lowerTileID: lowerTile.id,
                        frame: frame
                    )
                )
            }
        }

        return handles
    }

    func horizontalWeightDelta(for pixelDelta: CGFloat) -> Double {
        let availableWidth = max(Self.availableBoardWidth(for: size, spacing: spacing, padding: padding, columnCount: layout.columns.count), 1)
        return Double(pixelDelta / availableWidth)
    }

    func verticalWeightDelta(for pixelDelta: CGFloat, columnID: UUID) -> Double {
        guard let column = layout.columns.first(where: { $0.id == columnID }) else { return 0 }
        let availableHeight = max(Self.availableColumnHeight(for: size, spacing: spacing, padding: padding, rowCount: column.tiles.count), 1)
        return Double(pixelDelta / availableHeight)
    }

    private func compassFrame(for targetFrame: CGRect) -> CGRect {
        let size = min(max(min(targetFrame.width, targetFrame.height) * 0.42, 92), 146)
        return CGRect(
            x: targetFrame.midX - (size * 0.5),
            y: targetFrame.midY - (size * 0.5),
            width: size,
            height: size
        )
    }

    private func dockTarget(for point: CGPoint, in frame: CGRect) -> VibeSpaceTerminalBoardDockTarget {
        if frame.contains(point) {
            let centerInsetX = min(max(frame.width * 0.24, 20), frame.width * 0.40)
            let centerInsetY = min(max(frame.height * 0.24, 20), frame.height * 0.40)
            let centerFrame = frame.insetBy(dx: centerInsetX, dy: centerInsetY)
            if centerFrame.contains(point) {
                return .center
            }

            let leftDistance = abs(point.x - frame.minX)
            let rightDistance = abs(point.x - frame.maxX)
            let topDistance = abs(point.y - frame.minY)
            let bottomDistance = abs(point.y - frame.maxY)

            let minimum = min(leftDistance, rightDistance, topDistance, bottomDistance)
            if minimum == leftDistance { return .left }
            if minimum == rightDistance { return .right }
            if minimum == topDistance { return .top }
            return .bottom
        }

        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        if abs(dx) > abs(dy) {
            return dx < 0 ? .left : .right
        }
        return dy < 0 ? .top : .bottom
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return hypot(dx, dy)
    }

    private static func computeFrames(
        for layout: VibeSpaceTerminalBoardLayout,
        size: CGSize,
        spacing: CGFloat,
        padding: CGFloat
    ) -> (tileFramesByID: [UUID: CGRect], columnFramesByID: [UUID: CGRect]) {
        guard !layout.columns.isEmpty else { return ([:], [:]) }

        var tileFrames: [UUID: CGRect] = [:]
        tileFrames.reserveCapacity(layout.tileCount)
        var columnFrames: [UUID: CGRect] = [:]
        columnFrames.reserveCapacity(layout.columns.count)

        let availableWidth = Self.availableBoardWidth(
            for: size,
            spacing: spacing,
            padding: padding,
            columnCount: layout.columns.count
        )

        var currentX = padding
        for column in layout.columns {
            let columnWidth = availableWidth * CGFloat(column.widthWeight)
            let availableHeight = Self.availableColumnHeight(
                for: size,
                spacing: spacing,
                padding: padding,
                rowCount: column.tiles.count
            )

            columnFrames[column.id] = CGRect(
                x: currentX,
                y: padding,
                width: max(columnWidth, 1),
                height: max(size.height - (padding * 2), 1)
            )

            var currentY = padding
            for tile in column.tiles {
                let tileHeight = availableHeight * CGFloat(tile.heightWeight)
                tileFrames[tile.id] = CGRect(
                    x: currentX,
                    y: currentY,
                    width: max(columnWidth, 1),
                    height: max(tileHeight, 1)
                )
                currentY += tileHeight + spacing
            }

            currentX += columnWidth + spacing
        }

        return (tileFrames, columnFrames)
    }

    private static func availableBoardWidth(
        for size: CGSize,
        spacing: CGFloat,
        padding: CGFloat,
        columnCount: Int
    ) -> CGFloat {
        let totalHorizontalSpacing = spacing * CGFloat(max(columnCount - 1, 0))
        return max(size.width - (padding * 2) - totalHorizontalSpacing, 1)
    }

    private static func availableColumnHeight(
        for size: CGSize,
        spacing: CGFloat,
        padding: CGFloat,
        rowCount: Int
    ) -> CGFloat {
        let totalVerticalSpacing = spacing * CGFloat(max(rowCount - 1, 0))
        return max(size.height - (padding * 2) - totalVerticalSpacing, 1)
    }
}
