import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Interaction State

enum BoardInteractionState: Equatable {
    case idle
    case movingTile(MovingTileState)
    case movingMinimized(MovingMinimizedState)
    case resizingColumn(ResizingColumnState)
    case resizingRow(ResizingRowState)

    struct MovingTileState: Equatable {
        let tileID: UUID
        var pointer: CGPoint
        var dockingGuide: VibeSpaceTerminalBoardDockingGuide?
        var previewLayout: VibeSpaceTerminalBoardLayout?
    }

    struct MovingMinimizedState: Equatable {
        let tileID: UUID
        var pointer: CGPoint
        var dockingGuide: VibeSpaceTerminalBoardDockingGuide?
    }

    struct ResizingColumnState: Equatable {
        let leftColumnID: UUID
        let rightColumnID: UUID
        let initialLeftWeight: Double
        let initialRightWeight: Double
        let startX: CGFloat
    }

    struct ResizingRowState: Equatable {
        let columnID: UUID
        let upperTileID: UUID
        let lowerTileID: UUID
        let initialUpperWeight: Double
        let initialLowerWeight: Double
        let startY: CGFloat
    }
}

// MARK: - Cursor Style

enum BoardCursorStyle: Equatable {
    case `default`
    case resizeLeftRight
    case resizeUpDown
}

// MARK: - Hit-Test Result

enum BoardHitRegion: Equatable {
    case tileHeader(tileID: UUID)
    case tileBody(tileID: UUID)
    case columnDivider(leftColumnID: UUID, rightColumnID: UUID)
    case rowDivider(columnID: UUID, upperTileID: UUID, lowerTileID: UUID)
    case empty
}

// MARK: - Drag Proxy Info

struct BoardDragProxyInfo: Equatable {
    let title: String
    let subtitle: String
    let sourceFrame: CGRect
}

// MARK: - Delegate Protocol

@MainActor
protocol BoardInteractionDelegate: AnyObject {
    func interactionController(_ controller: BoardInteractionController, didMoveTile tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent)
    func interactionController(_ controller: BoardInteractionController, didRestoreMinimizedTile tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent)
    func interactionController(_ controller: BoardInteractionController, didDetachTile tileID: UUID, atScreenPoint screenPoint: CGPoint)
    func interactionController(_ controller: BoardInteractionController, didResizeColumns leftColumnID: UUID, rightColumnID: UUID, leftWeight: Double, rightWeight: Double, commit: Bool)
    func interactionController(_ controller: BoardInteractionController, didResizeRows columnID: UUID, upperTileID: UUID, lowerTileID: UUID, upperWeight: Double, lowerWeight: Double, commit: Bool)
    func interactionController(_ controller: BoardInteractionController, didActivateTile tileID: UUID)
    func interactionControllerDragProxyInfo(_ controller: BoardInteractionController, for tileID: UUID) -> BoardDragProxyInfo?
    func interactionControllerMinimizedDragProxyInfo(_ controller: BoardInteractionController, for tileID: UUID) -> BoardDragProxyInfo?
}

// MARK: - Metrics Provider Protocol

protocol BoardMetricsProviding {
    var boardSize: CGSize { get }
    func frame(for tileID: UUID) -> CGRect
    func hitTest(at point: CGPoint) -> BoardHitRegion
    func dockingGuide(at point: CGPoint, excluding tileID: UUID?) -> VibeSpaceTerminalBoardDockingGuide?
    func columnWeights(leftColumnID: UUID, rightColumnID: UUID) -> (left: Double, right: Double)?
    func rowWeights(columnID: UUID, upperTileID: UUID, lowerTileID: UUID) -> (upper: Double, lower: Double)?
    func horizontalWeightDelta(for pixelDelta: CGFloat) -> Double
    func verticalWeightDelta(for pixelDelta: CGFloat, columnID: UUID) -> Double
    func previewLayout(moving tileID: UUID, with intent: VibeSpaceTerminalBoardDropIntent) -> VibeSpaceTerminalBoardLayout?
}

// MARK: - Controller

@MainActor
final class BoardInteractionController: ObservableObject {
    @Published private(set) var state: BoardInteractionState = .idle
    @Published private(set) var hoveredRegion: BoardHitRegion = .empty
    @Published private(set) var cursorStyle: BoardCursorStyle = .default
    @Published private(set) var dragProxy: BoardDragProxyInfo?

    weak var delegate: BoardInteractionDelegate?
    var metricsProvider: BoardMetricsProviding?

    private static let minimumColumnWeight: Double = 0.12
    private static let minimumRowWeight: Double = 0.12
    private static let detachMargin: CGFloat = 48

    // MARK: - Hover Events

    func hoverMoved(to point: CGPoint) {
        guard case .idle = state else { return }
        guard let metrics = metricsProvider else {
            setHover(region: .empty, cursor: .default)
            return
        }
        let newRegion = metrics.hitTest(at: point)
        setHover(region: newRegion, cursor: cursorStyle(for: newRegion))
    }

    func hoverExited() {
        guard case .idle = state else { return }
        setHover(region: .empty, cursor: .default)
    }

    private func setHover(region: BoardHitRegion, cursor: BoardCursorStyle) {
        if hoveredRegion != region { hoveredRegion = region }
        if cursorStyle != cursor { cursorStyle = cursor }
    }

    // MARK: - Drag Events

    func dragStarted(at point: CGPoint) {
        guard case .idle = state, let metrics = metricsProvider else { return }
        let region = metrics.hitTest(at: point)

        switch region {
        case let .tileHeader(tileID):
            delegate?.interactionController(self, didActivateTile: tileID)
            dragProxy = delegate?.interactionControllerDragProxyInfo(self, for: tileID)
            state = .movingTile(.init(tileID: tileID, pointer: point))

        case let .columnDivider(leftColumnID, rightColumnID):
            guard let weights = metrics.columnWeights(leftColumnID: leftColumnID, rightColumnID: rightColumnID) else { return }
            state = .resizingColumn(.init(
                leftColumnID: leftColumnID,
                rightColumnID: rightColumnID,
                initialLeftWeight: weights.left,
                initialRightWeight: weights.right,
                startX: point.x
            ))
            cursorStyle = .resizeLeftRight

        case let .rowDivider(columnID, upperTileID, lowerTileID):
            guard let weights = metrics.rowWeights(columnID: columnID, upperTileID: upperTileID, lowerTileID: lowerTileID) else { return }
            state = .resizingRow(.init(
                columnID: columnID,
                upperTileID: upperTileID,
                lowerTileID: lowerTileID,
                initialUpperWeight: weights.upper,
                initialLowerWeight: weights.lower,
                startY: point.y
            ))
            cursorStyle = .resizeUpDown

        case .tileBody, .empty:
            break
        }
    }

    func dragStartedFromMinimized(tileID: UUID, at point: CGPoint) {
        guard case .idle = state else { return }
        dragProxy = delegate?.interactionControllerMinimizedDragProxyInfo(self, for: tileID)
        state = .movingMinimized(.init(tileID: tileID, pointer: point))
    }

    func dragMoved(to point: CGPoint) {
        guard let metrics = metricsProvider else { return }

        switch state {
        case var .movingTile(moving):
            moving.pointer = point
            moving.dockingGuide = isDetachPoint(point, boardSize: metrics.boardSize)
                ? nil
                : metrics.dockingGuide(at: point, excluding: moving.tileID)
            if let guide = moving.dockingGuide {
                moving.previewLayout = metrics.previewLayout(moving: moving.tileID, with: guide.intent)
            } else {
                moving.previewLayout = nil
            }
            state = .movingTile(moving)

        case var .movingMinimized(moving):
            moving.pointer = point
            moving.dockingGuide = metrics.dockingGuide(at: point, excluding: nil)
            state = .movingMinimized(moving)

        case let .resizingColumn(resizing):
            let pixelDelta = point.x - resizing.startX
            let weightDelta = metrics.horizontalWeightDelta(for: pixelDelta)
            let totalWeight = resizing.initialLeftWeight + resizing.initialRightWeight
            let targetLeft = resizing.initialLeftWeight + weightDelta
            let clampedLeft = min(max(targetLeft, Self.minimumColumnWeight), totalWeight - Self.minimumColumnWeight)
            let clampedRight = totalWeight - clampedLeft
            delegate?.interactionController(
                self,
                didResizeColumns: resizing.leftColumnID,
                rightColumnID: resizing.rightColumnID,
                leftWeight: clampedLeft,
                rightWeight: clampedRight,
                commit: false
            )

        case let .resizingRow(resizing):
            let pixelDelta = point.y - resizing.startY
            let weightDelta = metrics.verticalWeightDelta(for: pixelDelta, columnID: resizing.columnID)
            let totalWeight = resizing.initialUpperWeight + resizing.initialLowerWeight
            let targetUpper = resizing.initialUpperWeight + weightDelta
            let clampedUpper = min(max(targetUpper, Self.minimumRowWeight), totalWeight - Self.minimumRowWeight)
            let clampedLower = totalWeight - clampedUpper
            delegate?.interactionController(
                self,
                didResizeRows: resizing.columnID,
                upperTileID: resizing.upperTileID,
                lowerTileID: resizing.lowerTileID,
                upperWeight: clampedUpper,
                lowerWeight: clampedLower,
                commit: false
            )

        case .idle:
            break
        }
    }

    func dragEnded() {
        switch state {
        case let .movingTile(moving):
            if let metrics = metricsProvider,
               isDetachPoint(moving.pointer, boardSize: metrics.boardSize) {
                delegate?.interactionController(
                    self,
                    didDetachTile: moving.tileID,
                    atScreenPoint: currentScreenPoint()
                )
            } else if let intent = moving.dockingGuide?.intent {
                delegate?.interactionController(self, didMoveTile: moving.tileID, with: intent)
            }

        case let .movingMinimized(moving):
            if let intent = moving.dockingGuide?.intent {
                delegate?.interactionController(self, didRestoreMinimizedTile: moving.tileID, with: intent)
            }

        case let .resizingColumn(resizing):
            let pixelDelta = resizing.startX // no-op — commit current weights
            _ = pixelDelta
            // Re-derive final weights from last known state and commit
            delegate?.interactionController(
                self,
                didResizeColumns: resizing.leftColumnID,
                rightColumnID: resizing.rightColumnID,
                leftWeight: currentResizeColumnWeights().left,
                rightWeight: currentResizeColumnWeights().right,
                commit: true
            )

        case let .resizingRow(resizing):
            delegate?.interactionController(
                self,
                didResizeRows: resizing.columnID,
                upperTileID: resizing.upperTileID,
                lowerTileID: resizing.lowerTileID,
                upperWeight: currentResizeRowWeights().upper,
                lowerWeight: currentResizeRowWeights().lower,
                commit: true
            )

        case .idle:
            break
        }

        resetToIdle()
    }

    func dragCancelled() {
        if case let .resizingColumn(resizing) = state {
            delegate?.interactionController(
                self,
                didResizeColumns: resizing.leftColumnID,
                rightColumnID: resizing.rightColumnID,
                leftWeight: resizing.initialLeftWeight,
                rightWeight: resizing.initialRightWeight,
                commit: true
            )
        } else if case let .resizingRow(resizing) = state {
            delegate?.interactionController(
                self,
                didResizeRows: resizing.columnID,
                upperTileID: resizing.upperTileID,
                lowerTileID: resizing.lowerTileID,
                upperWeight: resizing.initialUpperWeight,
                lowerWeight: resizing.initialLowerWeight,
                commit: true
            )
        }
        resetToIdle()
    }

    // MARK: - Queries

    var isMoving: Bool {
        switch state {
        case .movingTile, .movingMinimized: return true
        default: return false
        }
    }

    var isResizing: Bool {
        switch state {
        case .resizingColumn, .resizingRow: return true
        default: return false
        }
    }

    var movingTileID: UUID? {
        if case let .movingTile(s) = state { return s.tileID }
        return nil
    }

    // MARK: - Private

    private func resetToIdle() {
        state = .idle
        dragProxy = nil
        cursorStyle = .default
        hoveredRegion = .empty
    }

    private func isDetachPoint(_ point: CGPoint, boardSize: CGSize) -> Bool {
        point.x < -Self.detachMargin ||
            point.y < -Self.detachMargin ||
            point.x > boardSize.width + Self.detachMargin ||
            point.y > boardSize.height + Self.detachMargin
    }

    private func currentScreenPoint() -> CGPoint {
        #if os(macOS)
        NSEvent.mouseLocation
        #else
        .zero
        #endif
    }

    private func cursorStyle(for region: BoardHitRegion) -> BoardCursorStyle {
        switch region {
        case .columnDivider: return .resizeLeftRight
        case .rowDivider: return .resizeUpDown
        default: return .default
        }
    }

    private func currentResizeColumnWeights() -> (left: Double, right: Double) {
        guard case let .resizingColumn(resizing) = state, let metrics = metricsProvider else {
            return (0.5, 0.5)
        }
        // Derive from current layout since delegate has been applying live updates
        return metrics.columnWeights(leftColumnID: resizing.leftColumnID, rightColumnID: resizing.rightColumnID)
            ?? (resizing.initialLeftWeight, resizing.initialRightWeight)
    }

    private func currentResizeRowWeights() -> (upper: Double, lower: Double) {
        guard case let .resizingRow(resizing) = state, let metrics = metricsProvider else {
            return (0.5, 0.5)
        }
        return metrics.rowWeights(columnID: resizing.columnID, upperTileID: resizing.upperTileID, lowerTileID: resizing.lowerTileID)
            ?? (resizing.initialUpperWeight, resizing.initialLowerWeight)
    }
}
