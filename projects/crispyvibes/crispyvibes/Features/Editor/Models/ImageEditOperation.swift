import AppKit
import CoreGraphics

/// Platform-neutral RGBA color stored in edit operations.
struct RasterColor: Equatable, Hashable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? NSColor.black
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let defaultStroke = RasterColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.88)
    static let annotationText = RasterColor(red: 1, green: 1, blue: 1, alpha: 0.98)
    static let annotationBackground = RasterColor(red: 1, green: 0.58, blue: 0, alpha: 0.92)
}

/// A freehand stroke in canvas units (top-left origin).
struct RasterStroke: Equatable, Sendable {
    var points: [CGPoint]
    var color: RasterColor = .defaultStroke
    var lineWidth: CGFloat = 2.2
}

/// A text callout in canvas units (top-left origin).
struct RasterTextAnnotation: Equatable, Sendable {
    var text: String
    var location: CGPoint
    var fontName: String = "System"
    var fontSize: CGFloat = 14
    var textColor: RasterColor = .annotationText
    var backgroundColor: RasterColor = .annotationBackground
}

/// Effective color adjustments of an operation list (the last `.adjust`, or identity).
extension Collection where Element == ImageEditOperation {
    var effectiveAdjustments: RasterImageAdjustments {
        for operation in reversed() {
            if case .adjust(let adjustments) = operation { return adjustments }
        }
        return .identity
    }

    /// `true` when overlays include pixel effects that need the composited pixels beneath them.
    var containsPixelEffects: Bool {
        contains { $0.markupItem?.isPixelEffect == true }
    }
}

/// One reversible edit. Operations are replayed in order by `RasterImageRenderer`.
///
/// Coordinates are expressed in the canvas space that was current when the operation was
/// recorded. Geometric operations flatten preceding overlays into the base bitmap during replay,
/// so later operations live in the new canvas space.
enum ImageEditOperation: Equatable, Sendable {
    case stroke(RasterStroke)
    case annotation(RasterTextAnnotation)
    /// Crops to `rect` (canvas units, already snapped to export pixels).
    case crop(CGRect)
    /// Rotates clockwise by `quarterTurns` × 90° (normalized to 1...3).
    case rotate(quarterTurns: Int)
    /// Mirrors horizontally (left↔right) or vertically (top↔bottom).
    case flip(horizontal: Bool)
    /// Rotates by `radians` (clockwise positive) and crops to the largest same-aspect rectangle.
    /// `outputSize` is the canonical (export-pixel-snapped) result size; the session fills it in
    /// at commit so every replay produces identical dimensions.
    case straighten(radians: Double, outputSize: CGSize? = nil)
    /// Resamples to a new canvas size.
    case resize(CGSize)
    /// An editable markup object (shape, arrow, text, highlight, blur, pixelate, redact).
    case markup(RasterMarkupItem)
    /// Color adjustments. Only the last one counts; it applies to the source before every other edit.
    case adjust(RasterImageAdjustments)
    /// Makes everything outside the subject transparent, using a Vision foreground mask scaled to
    /// the current canvas. Flattens earlier overlays like other pixel-changing edits.
    case removeBackground(RasterImageMask)

    /// `true` for operations that change canvas geometry.
    var isGeometric: Bool {
        switch self {
        case .stroke, .annotation, .markup, .adjust: return false
        case .crop, .rotate, .flip, .straighten, .resize, .removeBackground: return true
        }
    }

    /// Markup item carried by this operation, if any.
    var markupItem: RasterMarkupItem? {
        if case .markup(let item) = self { return item }
        return nil
    }

    /// Canvas size after applying this operation to a canvas of `size`.
    func resultingCanvasSize(from size: CGSize) -> CGSize {
        geometry(for: size).size
    }

    /// Output canvas size plus the top-left-origin affine map from old to new canvas coordinates.
    func geometry(for size: CGSize) -> (size: CGSize, transform: CGAffineTransform) {
        let width = size.width
        let height = size.height
        switch self {
        case .stroke, .annotation, .markup, .adjust, .removeBackground:
            return (size, .identity)
        case .crop(let rect):
            return (rect.size, CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        case .rotate(let quarterTurns):
            switch ((quarterTurns % 4) + 4) % 4 {
            case 1: return (CGSize(width: height, height: width), CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0))
            case 2: return (size, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height))
            case 3: return (CGSize(width: height, height: width), CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width))
            default: return (size, .identity)
            }
        case .flip(let horizontal):
            return horizontal
                ? (size, CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0))
                : (size, CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height))
        case let .straighten(radians, outputSize):
            let output = outputSize ?? Self.straightenedSize(for: size, radians: radians)
            let transform = CGAffineTransform(translationX: output.width / 2, y: output.height / 2)
                .rotated(by: radians)
                .translatedBy(x: -width / 2, y: -height / 2)
            return (output, transform)
        case .resize(let target):
            guard width > 0, height > 0 else { return (target, .identity) }
            return (target, CGAffineTransform(scaleX: target.width / width, y: target.height / height))
        }
    }

    /// Largest rectangle with the source aspect ratio that fits inside the source rotated by `radians`.
    static func straightenedSize(for size: CGSize, radians: Double) -> CGSize {
        let c = abs(cos(radians))
        let s = abs(sin(radians))
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return size }
        let scale = min(width / (width * c + height * s), height / (width * s + height * c))
        return CGSize(width: width * scale, height: height * scale)
    }

    /// Returns the operation with any fractional output geometry snapped down to whole export
    /// pixels at `exportScale`, so canvas size always maps to an integral export bitmap.
    func canonicalized(for size: CGSize, exportScale: CGFloat) -> ImageEditOperation {
        guard case let .straighten(radians, nil) = self, exportScale > 0 else { return self }
        let exact = Self.straightenedSize(for: size, radians: radians)
        let snapped = CGSize(
            width: max(floor(exact.width * exportScale + 1e-6), 1) / exportScale,
            height: max(floor(exact.height * exportScale + 1e-6), 1) / exportScale
        )
        return .straighten(radians: radians, outputSize: snapped)
    }
}
