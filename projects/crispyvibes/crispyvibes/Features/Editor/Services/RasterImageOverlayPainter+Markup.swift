import AppKit

/// Markup drawing, bounds, and hit testing.
extension RasterImageOverlayPainter {
    static func draw(_ item: RasterMarkupItem) {
        let style = item.style
        switch item.kind {
        case .pen(let points):
            guard let path = path(for: points, lineWidth: style.lineWidth) else { return }
            style.strokeColor.nsColor.setStroke()
            path.stroke()
        case let .line(from, to):
            strokeLine(from: from, to: to, style: style)
        case let .arrow(from, to):
            strokeLine(from: from, to: arrowShaftEnd(from: from, to: to, lineWidth: style.lineWidth), style: style)
            arrowHead(from: from, to: to, lineWidth: style.lineWidth).map { head in
                style.strokeColor.nsColor.setFill()
                head.fill()
            }
        case .rectangle(let rect):
            shape(NSBezierPath(rect: rect.standardized), style: style)
        case .ellipse(let rect):
            shape(NSBezierPath(ovalIn: rect.standardized), style: style)
        case .highlight(let rect):
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setBlendMode(.multiply)
            style.strokeColor.nsColor.withAlphaComponent(0.4).setFill()
            NSBezierPath(rect: rect.standardized).fill()
            NSGraphicsContext.current?.cgContext.restoreGState()
        case let .text(text, origin):
            let attributed = attributedText(text, style: style)
            let size = attributed.size()
            if let fill = style.fillColor {
                fill.nsColor.setFill()
                NSBezierPath(roundedRect: CGRect(origin: origin, size: size).insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4).fill()
            }
            attributed.draw(at: origin)
        case .redact(let rect):
            (style.fillColor ?? RasterColor(red: 0, green: 0, blue: 0)).nsColor.withAlphaComponent(1).setFill()
            NSBezierPath(rect: rect.standardized).fill()
        case .blur, .pixelate:
            break
        }
    }

    static func attributedText(_ text: String, style: RasterMarkupStyle) -> NSAttributedString {
        NSAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: font(named: style.fontName, size: style.fontSize),
            .foregroundColor: style.strokeColor.nsColor
        ])
    }

    /// Bounding box of an item in canvas units (including stroke width).
    static func bounds(of item: RasterMarkupItem) -> CGRect {
        let pad = item.style.lineWidth / 2 + 1
        switch item.kind {
        case .pen(let points):
            return boundingRect(of: points).insetBy(dx: -pad, dy: -pad)
        case let .line(from, to), let .arrow(from, to):
            return boundingRect(of: [from, to]).insetBy(dx: -pad * 3, dy: -pad * 3)
        case let .text(text, origin):
            return CGRect(origin: origin, size: attributedText(text, style: item.style).size()).insetBy(dx: -4, dy: -2)
        default:
            return (item.rect ?? .zero).standardized.insetBy(dx: -pad, dy: -pad)
        }
    }

    /// `true` when `point` (canvas units) touches the item within `tolerance`.
    static func hitTest(_ item: RasterMarkupItem, at point: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = tolerance + item.style.lineWidth / 2
        switch item.kind {
        case .pen(let points):
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= reach }
        case let .line(from, to), let .arrow(from, to):
            return distance(from: point, toSegment: from, to) <= reach
        default:
            return bounds(of: item).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    // MARK: - Private

    private static func strokeLine(from: CGPoint, to: CGPoint, style: RasterMarkupStyle) {
        let path = NSBezierPath()
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        path.move(to: from)
        path.line(to: to)
        style.strokeColor.nsColor.setStroke()
        path.stroke()
    }

    private static func shape(_ path: NSBezierPath, style: RasterMarkupStyle) {
        if let fill = style.fillColor {
            fill.nsColor.setFill()
            path.fill()
        }
        path.lineWidth = style.lineWidth
        style.strokeColor.nsColor.setStroke()
        path.stroke()
    }

    private static func arrowHeadLength(_ lineWidth: CGFloat) -> CGFloat { max(10, lineWidth * 4) }

    private static func arrowShaftEnd(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> CGPoint {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return to }
        let back = min(arrowHeadLength(lineWidth) * 0.8, length)
        return CGPoint(x: to.x - (to.x - from.x) / length * back, y: to.y - (to.y - from.y) / length * back)
    }

    private static func arrowHead(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> NSBezierPath? {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return nil }
        let head = min(arrowHeadLength(lineWidth), length)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let spread = CGFloat.pi / 7
        let path = NSBezierPath()
        path.move(to: to)
        path.line(to: CGPoint(x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread)))
        path.line(to: CGPoint(x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread)))
        path.close()
        return path
    }

    private static func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
