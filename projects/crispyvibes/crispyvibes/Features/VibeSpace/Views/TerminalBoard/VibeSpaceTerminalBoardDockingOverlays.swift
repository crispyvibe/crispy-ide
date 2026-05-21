import SwiftUI

struct VibeSpaceTerminalBoardDockingGuideOverlay: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let guide: VibeSpaceTerminalBoardDockingGuide
    let boardSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(appThemePalette.canvasBackgroundColor.opacity(0.48))
                .frame(width: boardSize.width, height: boardSize.height)

            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(9), style: .continuous)
                .stroke(appThemePalette.primaryTextColor.opacity(0.44), lineWidth: 1.9)
                .overlay(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(9), style: .continuous)
                        .stroke(appThemePalette.accentColor.opacity(0.98), lineWidth: 1.05)
                )
                .frame(width: guide.targetFrame.width, height: guide.targetFrame.height)
                .offset(x: guide.targetFrame.minX, y: guide.targetFrame.minY)

            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(guide.isSwap ? 9 : 4), style: .continuous)
                .fill(appThemePalette.accentColor.opacity(guide.isSwap ? 0.24 : 0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(guide.isSwap ? 9 : 4), style: .continuous)
                        .stroke(appThemePalette.accentColor.opacity(0.96), lineWidth: 1.2)
                )
                .frame(width: guide.indicatorFrame.width, height: guide.indicatorFrame.height)
                .offset(x: guide.indicatorFrame.minX, y: guide.indicatorFrame.minY)

            dockingCompass
                .frame(width: guide.compassFrame.width, height: guide.compassFrame.height)
                .offset(x: guide.compassFrame.minX, y: guide.compassFrame.minY)

            dropHintBadge
                .offset(
                    x: max(8, guide.compassFrame.midX - 72),
                    y: min(
                        max(8, boardSize.height - 34),
                        guide.compassFrame.maxY + 12
                    )
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var dockingCompass: some View {
        let cornerRadius = crispyvibesTheme.radius(14)
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(appThemePalette.accentColor.opacity(0.38), lineWidth: 1.2)
                )
                .shadow(color: appThemePalette.canvasBackgroundColor.opacity(0.7), radius: 14, x: 0, y: 8)

            compassSegment(.left, symbol: "arrow.left")
                .offset(x: -segmentOffset, y: 0)
            compassSegment(.right, symbol: "arrow.right")
                .offset(x: segmentOffset, y: 0)
            compassSegment(.top, symbol: "arrow.up")
                .offset(x: 0, y: -segmentOffset)
            compassSegment(.bottom, symbol: "arrow.down")
                .offset(x: 0, y: segmentOffset)
            compassSegment(.center, symbol: "arrow.left.arrow.right")
        }
    }

    private var segmentOffset: CGFloat {
        guide.compassFrame.width * 0.28
    }

    private func compassSegment(_ target: VibeSpaceTerminalBoardDockTarget, symbol: String) -> some View {
        let isSelected = guide.selectedTarget == target
        let size = guide.compassFrame.width * 0.24
        return RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
            .fill(isSelected ? appThemePalette.accentColor.opacity(0.95) : appThemePalette.canvasBackgroundColor.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                    .stroke(
                        isSelected
                            ? appThemePalette.accentColor.opacity(0.98)
                            : appThemePalette.borderColorValue.opacity(0.58),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            )
            .overlay(
                Image(systemName: symbol)
                    .font(AppTypographyTokens.scaledIcon(max(size * 0.28, 10), weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : appThemePalette.secondaryTextColor)
            )
            .frame(width: size, height: size)
    }

    private var dropHintBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: dropHintSymbol)
                .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
            Text(dropHintText)
                .font(AppTypographyTokens.caption2Semibold)
        }
        .foregroundStyle(appThemePalette.primaryTextColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.98))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(appThemePalette.accentColor.opacity(0.74), lineWidth: 1)
        )
        .shadow(color: appThemePalette.canvasBackgroundColor.opacity(0.7), radius: 10, x: 0, y: 5)
    }

    private var dropHintText: String {
        switch guide.selectedTarget {
        case .left:
            return "Insert Left"
        case .right:
            return "Insert Right"
        case .top:
            return "Insert Above"
        case .bottom:
            return "Insert Below"
        case .center:
            return "Swap"
        }
    }

    private var dropHintSymbol: String {
        switch guide.selectedTarget {
        case .left:
            return "arrow.left"
        case .right:
            return "arrow.right"
        case .top:
            return "arrow.up"
        case .bottom:
            return "arrow.down"
        case .center:
            return "arrow.left.arrow.right"
        }
    }
}

struct VibeSpaceTerminalBoardLayoutPreviewOverlay: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.appThemePalette) private var appThemePalette
    let layout: VibeSpaceTerminalBoardLayout
    let metrics: VibeSpaceTerminalBoardMetrics
    let movingTileID: UUID

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(appThemePalette.canvasBackgroundColor.opacity(0.18))
                .frame(width: metrics.size.width, height: metrics.size.height)
                .overlay(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                        .stroke(appThemePalette.borderColorValue.opacity(0.55), lineWidth: 1)
                )

            ForEach(layout.tiles) { tile in
                let frame = metrics.frame(for: tile.id)
                let isMovedTile = tile.id == movingTileID
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(9), style: .continuous)
                    .fill(appThemePalette.accentColor.opacity(isMovedTile ? 0.30 : 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: crispyvibesTheme.radius(9), style: .continuous)
                            .stroke(
                                appThemePalette.accentColor.opacity(isMovedTile ? 0.98 : 0.66),
                                style: StrokeStyle(lineWidth: isMovedTile ? 1.8 : 1.1)
                            )
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct VibeSpaceTerminalBoardDragProxyView: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.appThemePalette) private var appThemePalette
    let title: String
    let subtitle: String
    let pointerLocation: CGPoint
    let sourceFrame: CGRect

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(AppTypographyTokens.scaledSystem(11, weight: .semibold))
                    .foregroundStyle(appThemePalette.accentColor)

                Text(title)
                    .font(AppTypographyTokens.captionSemibold)
                    .lineLimit(1)
                    .foregroundStyle(appThemePalette.primaryTextColor)
            }

            Text(subtitle)
                .font(AppTypographyTokens.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(appThemePalette.secondaryTextColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: proxySize.width, height: proxySize.height, alignment: .leading)
        .background(appThemePalette.canvasSecondaryBackgroundColor.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                .stroke(appThemePalette.accentColor.opacity(0.9), lineWidth: 1.2)
        )
        .shadow(color: appThemePalette.canvasBackgroundColor.opacity(0.7), radius: 14, x: 0, y: 8)
        .offset(
            x: pointerLocation.x - (proxySize.width * 0.5),
            y: pointerLocation.y - (proxySize.height * 0.55)
        )
        .allowsHitTesting(false)
    }

    private var proxySize: CGSize {
        let width = min(max(sourceFrame.width * 0.56, 220), 430)
        let height = min(max(sourceFrame.height * 0.18, 72), 124)
        return CGSize(width: width, height: height)
    }
}
