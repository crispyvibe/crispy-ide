import AppKit

/// In-progress markup gesture.
enum RasterImageCanvasMarkupDrag {
    /// Creating a new item with the active tool from `start`.
    case create(start: CGPoint)
    /// Moving an existing item.
    case move(original: RasterMarkupItem, start: CGPoint)
    /// Resizing a rect-shaped item by a handle.
    case resize(original: RasterMarkupItem, handle: RasterImageCropHandle)
    /// Dragging one endpoint of a line/arrow.
    case endpoint(original: RasterMarkupItem, isStart: Bool)
}

/// Markup creation, selection, and editing.
extension EditableRasterImageCanvasView {
    /// Pointer tolerance for hit testing, in canvas units at the current zoom.
    var markupHitTolerance: CGFloat { canvasLength(forScreenPoints: 6) }

    /// The selected item as currently displayed (live preview while dragging).
    var displayedSelectedMarkup: RasterMarkupItem? {
        guard let selectedMarkupID else { return nil }
        if let markupPreview, markupPreview.id == selectedMarkupID { return markupPreview }
        return session?.markupItem(id: selectedMarkupID)
    }

    // MARK: - Pointer

    func beginMarkupDrag(at location: CGPoint, clickCount: Int) {
        if markupTool == .select || markupTool == .text {
            if let selected = displayedSelectedMarkup, let drag = handleDrag(on: selected, at: location) {
                markupDrag = drag
                return
            }
            if let hit = topmostMarkup(at: location) {
                selectMarkup(hit.id)
                if markupTool == .text, clickCount > 1, case .text = hit.kind {
                    onCommand?(.editSelectedText)
                }
                markupDrag = .move(original: hit, start: location)
                return
            }
            if markupTool == .select {
                selectMarkup(nil)
                return
            }
        }
        selectMarkup(nil)
        markupDrag = .create(start: location)
        if markupTool == .text {
            let text = annotationTextTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            markupPreview = RasterMarkupItem(
                kind: .text(text.isEmpty ? AppStrings.ImageEditor.annotationDefaultText : text, origin: location),
                style: markupStyle
            )
        } else {
            markupPreview = newItem(from: location, to: location)
        }
        needsDisplay = true
    }

    func continueMarkupDrag(to location: CGPoint, constrained: Bool) {
        guard let markupDrag else { return }
        switch markupDrag {
        case .create(let start):
            if markupTool == .pen, case .pen(var points)? = markupPreview?.kind {
                points.append(location)
                markupPreview?.kind = .pen(points)
            } else if markupTool != .text {
                let end = constrained ? constrainedEnd(from: start, to: location) : location
                markupPreview = newItem(from: start, to: end, id: markupPreview?.id)
            }
        case let .move(original, start):
            markupPreview = original.translated(by: CGVector(dx: location.x - start.x, dy: location.y - start.y))
        case let .resize(original, handle):
            guard let rect = original.rect?.standardized else { return }
            let resized = RasterImageCropInteraction.resize(
                rect, handle: handle, to: location, aspect: constrained ? max(rect.width, 1) / max(rect.height, 1) : nil,
                bounds: CGRect(x: -.greatestFiniteMagnitude / 4, y: -.greatestFiniteMagnitude / 4,
                               width: .greatestFiniteMagnitude / 2, height: .greatestFiniteMagnitude / 2),
                minimumSize: canvasLength(forScreenPoints: 4)
            )
            markupPreview = original.withRect(resized)
        case let .endpoint(original, isStart):
            guard let ends = original.endpoints else { return }
            markupPreview = isStart ? original.withEndpoints(from: location, to: ends.to) : original.withEndpoints(from: ends.from, to: location)
        }
        needsDisplay = true
    }

    func endMarkupDrag() {
        defer {
            markupDrag = nil
            markupPreview = nil
            needsDisplay = true
            publishStateIfNeeded()
        }
        guard let markupDrag, let preview = markupPreview, !isInteractionLocked else { return }
        switch markupDrag {
        case .create:
            guard isMeaningful(preview) else { return }
            commit(.markup(preview))
            if markupTool != .pen { selectMarkup(preview.id) }
        case .move, .resize, .endpoint:
            session?.updateMarkup(id: preview.id, to: preview)
        }
    }

    // MARK: - Selection and keyboard

    func selectMarkup(_ id: UUID?) {
        guard selectedMarkupID != id else { return }
        selectedMarkupID = id
        needsDisplay = true
        publishStateIfNeeded()
        if id != nil { NSAccessibility.post(element: self, notification: .selectedChildrenChanged) }
    }

    /// Clears a selection whose item no longer exists (after undo, crop, revert).
    func validateMarkupSelection() {
        if let selectedMarkupID, session?.markupItem(id: selectedMarkupID) == nil {
            self.selectedMarkupID = nil
        }
    }

    /// Delete, arrows, Tab, Escape for the selected item. Returns `true` when handled.
    func handleMarkupKey(_ event: NSEvent) -> Bool {
        guard editingMode == .markup else { return false }
        if event.keyCode == 48 {
            cycleMarkupSelection(backwards: event.modifierFlags.contains(.shift))
            return true
        }
        guard let selected = displayedSelectedMarkup, !isInteractionLocked else { return false }
        if event.keyCode == 51 || event.keyCode == 117 {
            onCommand?(.deleteSelection)
            return true
        }
        let step = (event.modifierFlags.contains(.shift) ? 10 : 1) / max(session?.document.exportScale ?? 1, 0.0001)
        let delta: CGVector
        switch event.specialKey {
        case .leftArrow?: delta = CGVector(dx: -step, dy: 0)
        case .rightArrow?: delta = CGVector(dx: step, dy: 0)
        case .upArrow?: delta = CGVector(dx: 0, dy: -step)
        case .downArrow?: delta = CGVector(dx: 0, dy: step)
        default: return false
        }
        session?.updateMarkup(id: selected.id, to: selected.translated(by: delta), coalescingKey: "nudge")
        return true
    }

    func cycleMarkupSelection(backwards: Bool) {
        guard let items = session?.markupEntries.map(\.item), !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedMarkupID }
        let next: Int
        if let current {
            next = (current + (backwards ? -1 : 1) + items.count) % items.count
        } else {
            next = backwards ? items.count - 1 : 0
        }
        selectMarkup(items[next].id)
    }

    /// Applies `change` to the selected item. Returns `false` when nothing is selected.
    @discardableResult
    func updateSelectedMarkup(coalescingKey: String?, _ change: (RasterMarkupItem) -> RasterMarkupItem) -> Bool {
        guard !isInteractionLocked, let selectedMarkupID, let item = session?.markupItem(id: selectedMarkupID) else { return false }
        return session?.updateMarkup(id: selectedMarkupID, to: change(item), coalescingKey: coalescingKey) ?? false
    }

    func deleteSelectedMarkup() -> Bool {
        guard !isInteractionLocked, let selectedMarkupID, session?.deleteMarkup(id: selectedMarkupID) == true else { return false }
        self.selectedMarkupID = nil
        publishStateIfNeeded()
        return true
    }

    // MARK: - Drawing

    /// Draws selection chrome: dashed bounds plus resize/endpoint handles.
    func drawMarkupSelection() {
        guard editingMode == .markup, let item = displayedSelectedMarkup else { return }
        let lineWidth = canvasLength(forScreenPoints: 1)
        let bounds = RasterImageOverlayPainter.bounds(of: item)
        let outline = NSBezierPath(rect: bounds)
        outline.lineWidth = lineWidth
        let dash = canvasLength(forScreenPoints: 4)
        outline.setLineDash([dash, dash], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        let size = canvasLength(forScreenPoints: 8)
        let handlePoints: [CGPoint]
        if let rect = item.rect?.standardized {
            handlePoints = RasterImageCropHandle.allCases.map { $0.point(in: rect) }
        } else if let ends = item.endpoints {
            handlePoints = [ends.from, ends.to]
        } else {
            handlePoints = []
        }
        for point in handlePoints {
            let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: rect)
            ring.lineWidth = lineWidth
            ring.stroke()
        }
    }

    /// Placeholder for pixel effects while their real composite is rendering or being dragged.
    func drawPixelEffectPlaceholder(_ item: RasterMarkupItem) {
        guard item.isPixelEffect, let rect = item.rect?.standardized else { return }
        NSColor.gray.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: rect).fill()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = canvasLength(forScreenPoints: 1)
        NSColor.white.withAlphaComponent(0.8).setStroke()
        outline.stroke()
    }

    // MARK: - Private

    private func topmostMarkup(at point: CGPoint) -> RasterMarkupItem? {
        session?.markupEntries.reversed().first {
            RasterImageOverlayPainter.hitTest($0.item, at: point, tolerance: markupHitTolerance)
        }?.item
    }

    private func handleDrag(on item: RasterMarkupItem, at point: CGPoint) -> RasterImageCanvasMarkupDrag? {
        let radius = canvasLength(forScreenPoints: 7)
        if let rect = item.rect?.standardized,
           let handle = RasterImageCropInteraction.handle(at: point, in: rect, radius: radius) {
            return .resize(original: item.withRect(rect), handle: handle)
        }
        if let ends = item.endpoints {
            if hypot(point.x - ends.from.x, point.y - ends.from.y) <= radius { return .endpoint(original: item, isStart: true) }
            if hypot(point.x - ends.to.x, point.y - ends.to.y) <= radius { return .endpoint(original: item, isStart: false) }
        }
        return nil
    }

    private func newItem(from start: CGPoint, to end: CGPoint, id: UUID? = nil) -> RasterMarkupItem {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let kind: RasterMarkupItem.Kind
        switch markupTool {
        case .pen: kind = .pen([start])
        case .line: kind = .line(from: start, to: end)
        case .arrow: kind = .arrow(from: start, to: end)
        case .ellipse: kind = .ellipse(rect)
        case .highlight: kind = .highlight(rect)
        case .blur: kind = .blur(rect)
        case .pixelate: kind = .pixelate(rect)
        case .redact: kind = .redact(rect)
        case .rectangle, .select, .text: kind = .rectangle(rect)
        }
        var item = RasterMarkupItem(kind: kind, style: markupStyle)
        if let id { item.id = id }
        return item
    }

    /// Shift: 45° steps for lines, squares for rectangles.
    private func constrainedEnd(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        if markupTool == .line || markupTool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    private func isMeaningful(_ item: RasterMarkupItem) -> Bool {
        let minimum = canvasLength(forScreenPoints: 3)
        switch item.kind {
        case .pen(let points): return points.count > 1
        case let .line(from, to), let .arrow(from, to): return hypot(to.x - from.x, to.y - from.y) >= minimum
        case .text(let text, _): return !text.isEmpty
        default:
            guard let rect = item.rect else { return false }
            return rect.width >= minimum && rect.height >= minimum
        }
    }
}
