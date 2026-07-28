import SwiftUI

@MainActor
struct AutomationConceptArtwork: View {
    enum Kind {
        case skill
        case vibe
        case lane
        case loop
    }

    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: Kind
    let color: Color
    let isActive: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 24.0,
                paused: !isActive || reduceMotion
            )
        ) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Group {
                switch kind {
                case .skill:
                    skillArtwork(time: time)
                case .vibe:
                    vibeArtwork(time: time)
                case .lane:
                    laneArtwork(time: time)
                case .loop:
                    loopArtwork(time: time)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func skillArtwork(time: TimeInterval) -> some View {
        let pulse = automationWave(time, speed: 1.8)
        ZStack {
            RoundedRectangle(cornerRadius: uiScale.chromeSize(7), style: .continuous)
                .fill(color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: uiScale.chromeSize(7), style: .continuous)
                        .strokeBorder(color.opacity(0.48), lineWidth: uiScale.chromeSize(1.5))
                )
                .frame(width: uiScale.chromeSize(54), height: uiScale.chromeSize(42))
                .offset(x: -uiScale.spacing(8), y: uiScale.spacing(3))

            Image(systemName: "text.book.closed.fill")
                .font(.system(size: uiScale.iconSize(24), weight: .semibold))
                .foregroundStyle(color)
                .offset(x: -uiScale.spacing(8))

            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: uiScale.iconSize(10), weight: .bold))
                .foregroundStyle(palette.canvasBackgroundColor)
                .frame(width: uiScale.chromeSize(23), height: uiScale.chromeSize(23))
                .background(Circle().fill(color))
                .overlay(Circle().strokeBorder(palette.canvasSecondaryBackgroundColor))
                .offset(x: uiScale.spacing(22), y: uiScale.spacing(18))
                .scaleEffect(0.94 + pulse * 0.1)
                .rotationEffect(.degrees(-4 + Double(pulse) * 8))
        }
    }

    @ViewBuilder
    private func vibeArtwork(time: TimeInterval) -> some View {
        let pulse = automationWave(time, speed: 2.1)
        ZStack {
            AutomationTargetShape()
                .stroke(
                    color.opacity(0.52),
                    style: StrokeStyle(
                        lineWidth: uiScale.chromeSize(1.5),
                        lineCap: .round
                    )
                )
                .scaleEffect(0.96 + pulse * 0.05)
                .opacity(0.72 + pulse * 0.28)

            Circle()
                .fill(color.opacity(0.16))
                .frame(width: uiScale.chromeSize(28), height: uiScale.chromeSize(28))

            Circle()
                .fill(color)
                .frame(width: uiScale.chromeSize(8), height: uiScale.chromeSize(8))
                .scaleEffect(0.85 + pulse * 0.3)

            Image(systemName: "checkmark")
                .font(.system(size: uiScale.iconSize(8), weight: .bold))
                .foregroundStyle(palette.canvasBackgroundColor)
                .offset(x: uiScale.spacing(24), y: -uiScale.spacing(20))
                .frame(width: uiScale.chromeSize(18), height: uiScale.chromeSize(18))
                .background(Circle().fill(color))
        }
    }

    @ViewBuilder
    private func laneArtwork(time: TimeInterval) -> some View {
        let travel = automationTravel(time, speed: 0.32)
        let travelOpacity = automationTravelOpacity(travel)
        GeometryReader { proxy in
            ZStack {
                AutomationLanePath()
                    .stroke(
                        color.opacity(0.58),
                        style: StrokeStyle(
                            lineWidth: uiScale.chromeSize(2),
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [uiScale.chromeSize(5), uiScale.chromeSize(4)]
                        )
                    )

                laneNode(filled: true)
                    .position(x: proxy.size.width * 0.10, y: proxy.size.height * 0.72)
                laneNode(filled: false)
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.46)
                laneNode(filled: true)
                    .position(x: proxy.size.width * 0.90, y: proxy.size.height * 0.26)

                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: uiScale.iconSize(7), weight: .bold))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(-18))
                    .opacity(travelOpacity)
                    .position(
                        x: proxy.size.width * (0.54 + travel * 0.28),
                        y: proxy.size.height * (0.43 - travel * 0.14)
                    )
            }
        }
    }

    private func laneNode(filled: Bool) -> some View {
        Circle()
            .fill(filled ? color : palette.canvasSecondaryBackgroundColor)
            .overlay(
                Circle()
                    .strokeBorder(color, lineWidth: uiScale.chromeSize(2))
            )
            .frame(width: uiScale.chromeSize(15), height: uiScale.chromeSize(15))
            .shadow(color: color.opacity(filled ? 0.25 : 0), radius: uiScale.chromeSize(3))
    }

    @ViewBuilder
    private func loopArtwork(time: TimeInterval) -> some View {
        let pulse = automationWave(time, speed: 2)
        let rotation = time.truncatingRemainder(dividingBy: 12) * 30
        ZStack {
            ZStack {
                Circle()
                    .trim(from: 0.08, to: 0.86)
                    .stroke(
                        color.opacity(0.64),
                        style: StrokeStyle(
                            lineWidth: uiScale.chromeSize(3),
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-36))
                    .padding(uiScale.spacing(8))

                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: uiScale.iconSize(8), weight: .bold))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(42))
                    .offset(x: uiScale.spacing(27), y: -uiScale.spacing(16))
            }
            .rotationEffect(.degrees(rotation))

            Image(systemName: "folder.fill")
                .font(.system(size: uiScale.iconSize(22), weight: .semibold))
                .foregroundStyle(color)

            Image(systemName: "clock.fill")
                .font(.system(size: uiScale.iconSize(10), weight: .semibold))
                .foregroundStyle(palette.canvasBackgroundColor)
                .frame(width: uiScale.chromeSize(20), height: uiScale.chromeSize(20))
                .background(Circle().fill(color))
                .offset(x: uiScale.spacing(22), y: uiScale.spacing(20))
                .scaleEffect(0.92 + pulse * 0.16)
        }
    }
}

enum AutomationFlowDirection: Equatable {
    case right
    case down

    var symbolName: String {
        switch self {
        case .right: "arrow.right"
        case .down: "arrow.down"
        }
    }

    func offset(for travel: CGFloat, distance: CGFloat) -> CGSize {
        switch self {
        case .right: CGSize(width: travel * distance, height: 0)
        case .down: CGSize(width: 0, height: travel * distance)
        }
    }
}

@MainActor
struct AutomationFlowConnector: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let direction: AutomationFlowDirection
    let isActive: Bool
    let iconSize: CGFloat

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 20.0,
                paused: !isActive || reduceMotion
            )
        ) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let travel = automationTravel(time, speed: 0.48)
            Image(systemName: direction.symbolName)
                .font(.system(size: uiScale.iconSize(iconSize), weight: .semibold))
                .opacity(reduceMotion ? 0.7 : automationTravelOpacity(travel))
                .offset(direction.offset(for: travel, distance: uiScale.spacing(5)))
        }
    }
}

extension View {
    func automationOverviewReveal(
        isRevealed: Bool,
        order: Double,
        reduceMotion: Bool,
        offset: CGFloat
    ) -> some View {
        modifier(
            AutomationOverviewRevealModifier(
                isRevealed: isRevealed,
                order: order,
                reduceMotion: reduceMotion,
                offset: offset
            )
        )
    }
}

private struct AutomationOverviewRevealModifier: ViewModifier {
    let isRevealed: Bool
    let order: Double
    let reduceMotion: Bool
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: reduceMotion || isRevealed ? 0 : offset)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.38).delay(order * 0.07),
                value: isRevealed
            )
    }
}

private func automationWave(_ time: TimeInterval, speed: Double) -> CGFloat {
    CGFloat((sin(time * speed) + 1) / 2)
}

private func automationTravel(_ time: TimeInterval, speed: Double) -> CGFloat {
    CGFloat((time * speed).truncatingRemainder(dividingBy: 1))
}

private func automationTravelOpacity(_ travel: CGFloat) -> Double {
    let edgeFade = min(min(travel / 0.16, (1 - travel) / 0.16), 1)
    return 0.28 + Double(max(0, edgeFade)) * 0.62
}

private struct AutomationTargetShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.68
        let middle = outer * 0.62

        path.addEllipse(
            in: CGRect(
                x: center.x - outer / 2,
                y: center.y - outer / 2,
                width: outer,
                height: outer
            )
        )
        path.addEllipse(
            in: CGRect(
                x: center.x - middle / 2,
                y: center.y - middle / 2,
                width: middle,
                height: middle
            )
        )
        path.move(to: CGPoint(x: center.x, y: rect.minY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: center.x, y: rect.maxY - rect.height * 0.06))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: center.y))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: center.y))
        return path
    }
}

private struct AutomationLanePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.10, y: rect.height * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.90, y: rect.height * 0.26),
            control1: CGPoint(x: rect.width * 0.32, y: rect.height * 0.82),
            control2: CGPoint(x: rect.width * 0.62, y: rect.height * 0.28)
        )
        return path
    }
}
