import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Cursor Rects (AppKit NSViewRepresentable)

#if os(macOS)
struct BoardCursorRectsView: NSViewRepresentable {
    let cursorRegions: [BoardCursorRegion]
    let controller: BoardInteractionController?

    func makeNSView(context: Context) -> BoardCursorRectsNSView {
        let view = BoardCursorRectsNSView()
        view.controller = controller
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: view,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        return view
    }

    func updateNSView(_ nsView: BoardCursorRectsNSView, context: Context) {
        let regionsChanged = nsView.cursorRegions != cursorRegions
        nsView.cursorRegions = cursorRegions
        nsView.controller = controller
        if regionsChanged {
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }

    final class BoardCursorRectsNSView: NSView {
        var cursorRegions: [BoardCursorRegion] = []
        var controller: BoardInteractionController?

        override func resetCursorRects() {
            discardCursorRects()
            for region in cursorRegions {
                let cursor: NSCursor = region.cursorType == .resizeLeftRight
                    ? .resizeLeftRight
                    : .resizeUpDown
                addCursorRect(region.rect, cursor: cursor)
            }
        }

        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: point.x, y: bounds.height - point.y)
            controller?.hoverMoved(to: flipped)
        }

        override func mouseExited(with event: NSEvent) {
            controller?.hoverExited()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
#endif

// MARK: - Divider Visuals Overlay

struct BoardDividerVisualsOverlay: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let layout: VibeSpaceTerminalBoardLayout
    let metrics: VibeSpaceTerminalBoardMetrics
    let hoveredRegion: BoardHitRegion
    let isInteracting: Bool

    var body: some View {
        Canvas { context, size in
            guard !isInteracting else { return }
            drawColumnDividers(context: context)
            drawRowDividers(context: context)
        }
        .allowsHitTesting(false)
    }

    private func drawColumnDividers(context: GraphicsContext) {
        for handle in metrics.columnResizeHandles() {
            let isHovered = hoveredRegion == .columnDivider(leftColumnID: handle.leftColumnID, rightColumnID: handle.rightColumnID)
            drawGrip(context: context, frame: handle.frame, isVertical: true, isHovered: isHovered)
        }
    }

    private func drawRowDividers(context: GraphicsContext) {
        for handle in metrics.rowResizeHandles() {
            let isHovered = hoveredRegion == .rowDivider(columnID: handle.columnID, upperTileID: handle.upperTileID, lowerTileID: handle.lowerTileID)
            drawGrip(context: context, frame: handle.frame, isVertical: false, isHovered: isHovered)
        }
    }

    private func drawGrip(context: GraphicsContext, frame: CGRect, isVertical: Bool, isHovered: Bool) {
        let gripColor = isHovered
            ? appThemePalette.borderColorValue.opacity(0.92)
            : appThemePalette.borderColorValue.opacity(0.72)
        let bgColor = isHovered
            ? appThemePalette.canvasSecondaryBackgroundColor.opacity(0.96)
            : appThemePalette.canvasSecondaryBackgroundColor.opacity(0.84)

        let gripSize: CGSize
        let bgSize: CGSize
        if isVertical {
            let gripHeight = min(max(frame.height * 0.32, 36), 78)
            gripSize = CGSize(width: 4, height: gripHeight)
            bgSize = CGSize(width: 10, height: gripHeight + 8)
        } else {
            let gripWidth = min(max(frame.width * 0.32, 36), 78)
            gripSize = CGSize(width: gripWidth, height: 4)
            bgSize = CGSize(width: gripWidth + 8, height: 10)
        }

        let bgRect = CGRect(
            x: frame.midX - bgSize.width * 0.5,
            y: frame.midY - bgSize.height * 0.5,
            width: bgSize.width,
            height: bgSize.height
        )
        let gripRect = CGRect(
            x: frame.midX - gripSize.width * 0.5,
            y: frame.midY - gripSize.height * 0.5,
            width: gripSize.width,
            height: gripSize.height
        )

        context.fill(
            Path(roundedRect: bgRect, cornerRadius: crispyvibesTheme.radius(8), style: .continuous),
            with: .color(bgColor)
        )
        context.fill(
            Path(roundedRect: gripRect, cornerRadius: crispyvibesTheme.radius(2), style: .continuous),
            with: .color(gripColor)
        )
    }
}

// MARK: - Interaction Gesture Overlay

// Gesture is attached directly to the board ZStack — no separate overlay view needed.
// This avoids blocking input to terminal sessions and tile cards below.

// MARK: - Hit Shape (only dividers + tile headers are hit-testable)

struct BoardInteractionHitShape: Shape {
    let hitTestContext: BoardHitTesting.Context

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for divider in hitTestContext.columnDividers {
            let halfThickness = hitTestContext.dividerThickness * 0.5
            path.addRect(CGRect(
                x: divider.centerX - halfThickness,
                y: 0,
                width: hitTestContext.dividerThickness,
                height: rect.height
            ))
        }

        for divider in hitTestContext.rowDividers {
            let halfThickness = hitTestContext.dividerThickness * 0.5
            path.addRect(CGRect(
                x: divider.minX,
                y: divider.centerY - halfThickness,
                width: divider.maxX - divider.minX,
                height: hitTestContext.dividerThickness
            ))
        }

        for tile in hitTestContext.tileFrames {
            path.addRect(CGRect(
                x: tile.frame.minX,
                y: tile.frame.minY,
                width: tile.frame.width,
                height: min(hitTestContext.headerHeight, tile.frame.height)
            ))
        }

        return path
    }
}
