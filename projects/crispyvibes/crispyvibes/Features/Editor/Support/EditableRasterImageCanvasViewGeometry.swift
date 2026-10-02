import AppKit

extension EditableRasterImageCanvasView {
    /// Event location in canvas units, clamped to the canvas bounds.
    func clampedLocation(from event: NSEvent) -> CGPoint {
        let raw = convert(event.locationInWindow, from: nil)
        let x = min(max(raw.x, 0), bounds.width)
        let y = min(max(raw.y, 0), bounds.height)
        return CGPoint(x: x, y: y)
    }
}
