import CoreGraphics

/// Crop aspect-ratio presets offered in the crop toolbar.
enum RasterImageCropAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case free
    case original
    case square
    case ratio4x3
    case ratio3x2
    case ratio16x9

    var id: String { rawValue }

    /// Width ÷ height, or `nil` for free-form. Non-square presets are landscape unless `portrait`.
    func value(originalSize: CGSize, portrait: Bool) -> CGFloat? {
        let landscape: CGFloat?
        switch self {
        case .free: return nil
        case .square: return 1
        case .original:
            guard originalSize.width > 0, originalSize.height > 0 else { return nil }
            let ratio = originalSize.width / originalSize.height
            return portrait == (ratio >= 1) ? 1 / ratio : ratio
        case .ratio4x3: landscape = 4.0 / 3.0
        case .ratio3x2: landscape = 3.0 / 2.0
        case .ratio16x9: landscape = 16.0 / 9.0
        }
        return landscape.map { portrait ? 1 / $0 : $0 }
    }

    /// `true` when the portrait/landscape toggle changes the ratio.
    var isOrientable: Bool {
        self != .free && self != .square
    }
}

/// Part of a crop rectangle grabbed by the pointer.
enum RasterImageCropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinY: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesMaxY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { (movesMinX || movesMaxX) && (movesMinY || movesMaxY) }

    /// Handle position on `rect` (top-left origin).
    func point(in rect: CGRect) -> CGPoint {
        let x = movesMinX ? rect.minX : (movesMaxX ? rect.maxX : rect.midX)
        let y = movesMinY ? rect.minY : (movesMaxY ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }
}

/// Pure geometry for interactive crop editing, in canvas units (top-left origin).
enum RasterImageCropInteraction {
    /// Handle within `radius` of `point`, preferring corners.
    static func handle(at point: CGPoint, in rect: CGRect, radius: CGFloat) -> RasterImageCropHandle? {
        let ordered = RasterImageCropHandle.allCases.sorted { $0.isCorner && !$1.isCorner }
        return ordered.first { handle in
            let p = handle.point(in: rect)
            return abs(p.x - point.x) <= radius && abs(p.y - point.y) <= radius
        }
    }

    /// A new selection dragged from `start` to `current`, honoring `aspect` and `bounds`.
    static func selection(from start: CGPoint, to current: CGPoint, aspect: CGFloat?, bounds: CGRect) -> CGRect {
        sized(anchor: start, toward: current, aspect: aspect, bounds: bounds)
    }

    /// Resizes `rect` by dragging `handle` to `point`; the opposite side stays fixed. Steps that
    /// would go below `minimumSize` leave `rect` unchanged.
    static func resize(
        _ rect: CGRect,
        handle: RasterImageCropHandle,
        to point: CGPoint,
        aspect: CGFloat?,
        bounds: CGRect,
        minimumSize: CGFloat
    ) -> CGRect {
        let clampedPoint = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        if handle.isCorner {
            let anchor = CGPoint(x: handle.movesMinX ? rect.maxX : rect.minX, y: handle.movesMinY ? rect.maxY : rect.minY)
            return enforceMinimum(sized(anchor: anchor, toward: clampedPoint, aspect: aspect, bounds: bounds), previous: rect, minimumSize: minimumSize)
        }
        var result = rect
        if handle.movesMinX || handle.movesMaxX {
            let anchorX = handle.movesMinX ? rect.maxX : rect.minX
            result.origin.x = min(anchorX, clampedPoint.x)
            result.size.width = abs(anchorX - clampedPoint.x)
            if let aspect {
                let maxHeight = 2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY)
                var height = result.width / aspect
                if height > maxHeight {
                    height = maxHeight
                    let width = height * aspect
                    result.origin.x = clampedPoint.x < anchorX ? anchorX - width : anchorX
                    result.size.width = width
                }
                result.origin.y = rect.midY - height / 2
                result.size.height = height
            }
        } else {
            let anchorY = handle.movesMinY ? rect.maxY : rect.minY
            result.origin.y = min(anchorY, clampedPoint.y)
            result.size.height = abs(anchorY - clampedPoint.y)
            if let aspect {
                let maxWidth = 2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX)
                var width = result.height * aspect
                if width > maxWidth {
                    width = maxWidth
                    let height = width / aspect
                    result.origin.y = clampedPoint.y < anchorY ? anchorY - height : anchorY
                    result.size.height = height
                }
                result.origin.x = rect.midX - width / 2
                result.size.width = width
            }
        }
        return enforceMinimum(result, previous: rect, minimumSize: minimumSize)
    }

    /// Moves `rect` by `delta`, keeping it inside `bounds`.
    static func move(_ rect: CGRect, by delta: CGVector, bounds: CGRect) -> CGRect {
        var result = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    /// Largest rectangle with `aspect` centered on `rect`, fitted inside `bounds`.
    static func constrain(_ rect: CGRect, to aspect: CGFloat?, bounds: CGRect) -> CGRect {
        guard let aspect, aspect > 0 else { return rect }
        var width = rect.width
        var height = width / aspect
        if height > rect.height {
            height = rect.height
            width = height * aspect
        }
        let fitted = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        let scale = min(1, bounds.width / max(fitted.width, 0.0001), bounds.height / max(fitted.height, 0.0001))
        let scaled = CGRect(x: fitted.midX - fitted.width * scale / 2, y: fitted.midY - fitted.height * scale / 2,
                            width: fitted.width * scale, height: fitted.height * scale)
        return move(scaled, by: .zero, bounds: bounds)
    }

    /// Largest centered rectangle with `aspect` inside `bounds` (initial crop box for a ratio).
    static func centered(aspect: CGFloat?, in bounds: CGRect) -> CGRect {
        constrain(bounds, to: aspect, bounds: bounds)
    }

    // MARK: - Private

    private static func sized(anchor: CGPoint, toward point: CGPoint, aspect: CGFloat?, bounds: CGRect) -> CGRect {
        let directionX: CGFloat = point.x >= anchor.x ? 1 : -1
        let directionY: CGFloat = point.y >= anchor.y ? 1 : -1
        let maxWidth = directionX > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let maxHeight = directionY > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        var width = min(abs(point.x - anchor.x), maxWidth)
        var height = min(abs(point.y - anchor.y), maxHeight)
        if let aspect, aspect > 0 {
            if width / max(height, 0.0001) > aspect { width = height * aspect } else { height = width / aspect }
            if width > maxWidth { width = maxWidth; height = width / aspect }
            if height > maxHeight { height = maxHeight; width = height * aspect }
        }
        return CGRect(
            x: directionX > 0 ? anchor.x : anchor.x - width,
            y: directionY > 0 ? anchor.y : anchor.y - height,
            width: width,
            height: height
        )
    }

    /// Rejects a resize step that would shrink below `minimumSize`, keeping the previous box so
    /// the fixed anchor and aspect ratio are never distorted.
    private static func enforceMinimum(_ rect: CGRect, previous: CGRect, minimumSize: CGFloat) -> CGRect {
        rect.width < minimumSize || rect.height < minimumSize ? previous : rect
    }
}
