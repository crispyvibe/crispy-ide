import AppKit

extension EditableRasterImageCanvasView {
    func clampedLocation(from event: NSEvent) -> CGPoint {
        let raw = convert(event.locationInWindow, from: nil)
        let x = min(max(raw.x, 0), bounds.width)
        let y = min(max(raw.y, 0), bounds.height)
        return CGPoint(x: x, y: y)
    }

    func croppedStrokes(within selection: CGRect) -> [[CGPoint]] {
        var preserved: [[CGPoint]] = []
        for stroke in drawnStrokes where stroke.count > 1 {
            preserved.append(contentsOf: clippedSegments(for: stroke, within: selection))
        }
        return preserved
    }

    func clippedSegments(for stroke: [CGPoint], within selection: CGRect) -> [[CGPoint]] {
        var segments: [[CGPoint]] = []
        var currentSegment: [CGPoint] = []

        for point in stroke {
            if contains(point, inInclusiveRect: selection) {
                currentSegment.append(translate(point, bySubtracting: selection.origin))
            } else if currentSegment.count > 1 {
                segments.append(currentSegment)
                currentSegment.removeAll()
            } else {
                currentSegment.removeAll()
            }
        }

        if currentSegment.count > 1 {
            segments.append(currentSegment)
        }
        return segments
    }

    func croppedAnnotations(within selection: CGRect) -> [TextAnnotation] {
        annotations.compactMap { annotation in
            guard contains(annotation.location, inInclusiveRect: selection) else {
                return nil
            }

            var shifted = annotation
            shifted.location = translate(annotation.location, bySubtracting: selection.origin)
            return shifted
        }
    }

    func contains(_ point: CGPoint, inInclusiveRect rect: CGRect) -> Bool {
        point.x >= rect.minX &&
            point.x <= rect.maxX &&
            point.y >= rect.minY &&
            point.y <= rect.maxY
    }

    func translate(_ point: CGPoint, bySubtracting origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}
