import CoreGraphics
import Foundation

/// Visual style of a markup item.
struct RasterMarkupStyle: Equatable, Hashable, Sendable {
    var strokeColor: RasterColor = RasterColor(red: 1, green: 0.23, blue: 0.19)
    /// Interior fill for rectangles/ellipses and the text background; `nil` = no fill.
    var fillColor: RasterColor?
    var lineWidth: CGFloat = 4
    var fontName: String = "System"
    var fontSize: CGFloat = 18

    static let `default` = RasterMarkupStyle()
}

/// Editable markup tools in Markup mode.
enum RasterMarkupTool: String, CaseIterable, Identifiable, Sendable {
    case select, pen, line, arrow, rectangle, ellipse, highlight, text, blur, pixelate, redact

    var id: String { rawValue }

    /// `true` for tools that create an item by dragging a rectangle.
    var createsRect: Bool {
        switch self {
        case .rectangle, .ellipse, .highlight, .blur, .pixelate, .redact: return true
        default: return false
        }
    }
}

/// One editable markup object, in canvas units (top-left origin).
struct RasterMarkupItem: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case pen([CGPoint])
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        /// Translucent marker over a rectangle.
        case highlight(CGRect)
        /// Text whose top-left corner is `origin`.
        case text(String, origin: CGPoint)
        /// Gaussian blur of the pixels underneath. Not secure: blurred text may be recoverable.
        case blur(CGRect)
        /// Mosaic of the pixels underneath. Not secure for small text.
        case pixelate(CGRect)
        /// Opaque fill that destroys the pixels underneath on export.
        case redact(CGRect)
    }

    var id = UUID()
    var kind: Kind
    var style: RasterMarkupStyle

    /// `true` for items computed from the pixels beneath them (blur, pixelate). Redact is an
    /// opaque fill and needs no source pixels.
    var isPixelEffect: Bool {
        switch kind {
        case .blur, .pixelate: return true
        default: return false
        }
    }

    /// Rectangle for rect-shaped kinds.
    var rect: CGRect? {
        switch kind {
        case .rectangle(let r), .ellipse(let r), .highlight(let r), .blur(let r), .pixelate(let r), .redact(let r): return r
        default: return nil
        }
    }

    /// Endpoints for line-shaped kinds.
    var endpoints: (from: CGPoint, to: CGPoint)? {
        switch kind {
        case let .line(from, to), let .arrow(from, to): return (from, to)
        default: return nil
        }
    }

    /// Returns a copy with the rectangle of a rect-shaped kind replaced.
    func withRect(_ newRect: CGRect) -> RasterMarkupItem {
        var copy = self
        switch kind {
        case .rectangle: copy.kind = .rectangle(newRect)
        case .ellipse: copy.kind = .ellipse(newRect)
        case .highlight: copy.kind = .highlight(newRect)
        case .blur: copy.kind = .blur(newRect)
        case .pixelate: copy.kind = .pixelate(newRect)
        case .redact: copy.kind = .redact(newRect)
        default: break
        }
        return copy
    }

    /// Returns a copy with the endpoints of a line-shaped kind replaced.
    func withEndpoints(from: CGPoint, to: CGPoint) -> RasterMarkupItem {
        var copy = self
        switch kind {
        case .line: copy.kind = .line(from: from, to: to)
        case .arrow: copy.kind = .arrow(from: from, to: to)
        default: break
        }
        return copy
    }

    /// Returns a copy moved by `delta`.
    func translated(by delta: CGVector) -> RasterMarkupItem {
        let move: (CGPoint) -> CGPoint = { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
        var copy = self
        switch kind {
        case .pen(let points): copy.kind = .pen(points.map(move))
        case let .line(from, to): copy.kind = .line(from: move(from), to: move(to))
        case let .arrow(from, to): copy.kind = .arrow(from: move(from), to: move(to))
        case let .text(text, origin): copy.kind = .text(text, origin: move(origin))
        default:
            if let rect { return withRect(rect.offsetBy(dx: delta.dx, dy: delta.dy)) }
        }
        return copy
    }

    /// Returns a copy whose text is replaced (text items only).
    func withText(_ newText: String) -> RasterMarkupItem {
        guard case let .text(_, origin) = kind else { return self }
        var copy = self
        copy.kind = .text(newText, origin: origin)
        return copy
    }
}

/// Non-destructive color adjustments applied to the source before any other edit.
struct RasterImageAdjustments: Equatable, Hashable, Sendable {
    /// Exposure in EV stops (−2…2).
    var exposure: Double = 0
    /// Contrast multiplier offset (−1…1, 0 = unchanged).
    var contrast: Double = 0
    /// Saturation offset (−1…1, −1 = grayscale).
    var saturation: Double = 0
    /// Vibrance (−1…1).
    var vibrance: Double = 0
    /// White-balance shift (−1 cooler … 1 warmer).
    var temperature: Double = 0
    /// Highlight recovery (−1…1, negative darkens highlights).
    var highlights: Double = 0
    /// Shadow lift (−1…1, positive brightens shadows).
    var shadows: Double = 0
    /// Sharpening amount (0…1).
    var sharpness: Double = 0

    static let identity = RasterImageAdjustments()

    var isIdentity: Bool { self == .identity }
}
