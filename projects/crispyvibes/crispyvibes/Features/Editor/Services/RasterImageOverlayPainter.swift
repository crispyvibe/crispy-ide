import AppKit

/// Draws vector overlays into the current, flipped `NSGraphicsContext` in canvas units. Shared by
/// the live canvas and the off-main renderer so on-screen and exported output match exactly.
/// Pixel effects (blur, pixelate) are applied by `RasterImageRenderer`, not here.
enum RasterImageOverlayPainter {
    static func draw<Operations: Sequence>(_ operations: Operations, canvasSize: CGSize)
    where Operations.Element == ImageEditOperation {
        for operation in operations {
            draw(operation, canvasSize: canvasSize)
        }
    }

    static func draw(_ operation: ImageEditOperation, canvasSize: CGSize) {
        switch operation {
        case .stroke(let stroke):
            draw(stroke)
        case .annotation(let annotation):
            draw(annotation, canvasSize: canvasSize)
        case .markup(let item):
            draw(item)
        case .crop, .rotate, .flip, .straighten, .resize, .adjust, .removeBackground:
            break
        }
    }

    static func draw(_ stroke: RasterStroke) {
        guard let path = path(for: stroke.points, lineWidth: stroke.lineWidth) else { return }
        stroke.color.nsColor.setStroke()
        path.stroke()
    }

    static func path(for points: [CGPoint], lineWidth: CGFloat) -> NSBezierPath? {
        guard points.count > 1 else { return nil }
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        return path
    }

    static func font(named name: String, size: CGFloat) -> NSFont {
        if name == "System" {
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func draw(_ annotation: RasterTextAnnotation, canvasSize: CGSize) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(named: annotation.fontName, size: annotation.fontSize),
            .foregroundColor: annotation.textColor.nsColor
        ]
        let attributed = NSAttributedString(string: annotation.text, attributes: attributes)
        let textSize = attributed.size()
        let padding = NSSize(width: 8, height: 4)
        let bubbleSize = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        let origin = CGPoint(
            x: min(max(annotation.location.x + 6, 0), max(0, canvasSize.width - bubbleSize.width)),
            y: min(max(annotation.location.y + 6, 0), max(0, canvasSize.height - bubbleSize.height))
        )
        let bubbleRect = CGRect(origin: origin, size: bubbleSize)

        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 5, yRadius: 5)
        annotation.backgroundColor.nsColor.setFill()
        bubblePath.fill()
        NSColor.black.withAlphaComponent(0.7).setStroke()
        bubblePath.lineWidth = 1
        bubblePath.stroke()

        attributed.draw(at: CGPoint(x: bubbleRect.minX + padding.width, y: bubbleRect.minY + padding.height))
    }
}
