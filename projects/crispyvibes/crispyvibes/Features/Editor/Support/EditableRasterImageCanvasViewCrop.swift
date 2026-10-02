import AppKit

/// In-progress crop-box gesture.
enum RasterImageCanvasCropDrag {
    /// Drawing a new box from `start`.
    case create(start: CGPoint)
    /// Dragging one of the eight handles.
    case resize(handle: RasterImageCropHandle, original: CGRect)
    /// Moving the whole box.
    case move(original: CGRect, start: CGPoint)
}

/// Crop-box interaction: handles, move, aspect constraints, keyboard nudge, and drawing.
extension EditableRasterImageCanvasView {
    /// On-screen handle size in points, independent of zoom.
    static let cropHandleScreenSize: CGFloat = 9

    var canvasBounds: CGRect {
        CGRect(origin: .zero, size: session?.canvasSize ?? .zero)
    }

    /// Converts a screen distance to canvas units at the current zoom.
    func canvasLength(forScreenPoints points: CGFloat) -> CGFloat {
        points / max(enclosingScrollView?.magnification ?? 1, 0.01)
    }

    /// Minimum crop edge in canvas units (two export pixels).
    var minimumCropCanvasSize: CGFloat {
        RasterImageCropGeometry.minimumPixelEdge / max(session?.document.exportScale ?? 1, 0.0001)
    }

    func editingModeDidChange(from oldMode: RasterImageEditingMode) {
        if oldMode == .crop, !hasPendingCropSelection {
            // An untouched full-image box is not a pending edit; drop it outside Crop mode.
            cropSelection = nil
        }
        cropDrag = nil
        if editingMode != .markup {
            selectedMarkupID = nil
            markupDrag = nil
            markupPreview = nil
        }
        resetCropBoxIfNeeded()
        needsDisplay = true
        publishStateIfNeeded()
    }

    /// In Crop mode, ensures a crop box exists (whole image, or the aspect-ratio box).
    func resetCropBoxIfNeeded() {
        guard editingMode == .crop, cropSelection == nil, session != nil else { return }
        let bounds = canvasBounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        cropSelection = cropAspectRatio == nil ? bounds : RasterImageCropInteraction.centered(aspect: cropAspectRatio, in: bounds)
    }

    func cropAspectRatioDidChange() {
        guard editingMode == .crop, let selection = cropSelection else { return }
        let bounds = canvasBounds
        cropSelection = hasPendingCropSelection
            ? RasterImageCropInteraction.constrain(selection, to: cropAspectRatio, bounds: bounds)
            : (cropAspectRatio == nil ? bounds : RasterImageCropInteraction.centered(aspect: cropAspectRatio, in: bounds))
        needsDisplay = true
        publishStateIfNeeded()
    }

    // MARK: - Pointer

    func beginCropDrag(at location: CGPoint) {
        let radius = canvasLength(forScreenPoints: Self.cropHandleScreenSize)
        if let selection = cropSelection {
            if let handle = RasterImageCropInteraction.handle(at: location, in: selection, radius: radius) {
                cropDrag = .resize(handle: handle, original: selection)
                return
            }
            if hasPendingCropSelection, selection.contains(location) {
                cropDrag = .move(original: selection, start: location)
                return
            }
        }
        cropDrag = .create(start: location)
        cropStartPoint = location
    }

    func continueCropDrag(to location: CGPoint) {
        guard let cropDrag else { return }
        let bounds = canvasBounds
        switch cropDrag {
        case .create(let start):
            cropSelection = RasterImageCropInteraction.selection(from: start, to: location, aspect: cropAspectRatio, bounds: bounds)
        case let .resize(handle, original):
            cropSelection = RasterImageCropInteraction.resize(
                original, handle: handle, to: location, aspect: cropAspectRatio,
                bounds: bounds, minimumSize: minimumCropCanvasSize
            )
        case let .move(original, start):
            cropSelection = RasterImageCropInteraction.move(
                original, by: CGVector(dx: location.x - start.x, dy: location.y - start.y), bounds: bounds
            )
        }
        needsDisplay = true
        publishStateIfNeeded()
    }

    func endCropDrag() {
        if case .create = cropDrag, let selection = cropSelection,
           selection.width < minimumCropCanvasSize || selection.height < minimumCropCanvasSize {
            // A click without a meaningful drag restores the default box.
            cropSelection = nil
            resetCropBoxIfNeeded()
        }
        cropDrag = nil
        cropStartPoint = nil
        needsDisplay = true
        publishStateIfNeeded()
    }

    /// Arrow keys move the crop box by one export pixel (ten with Shift).
    /// - Returns: `true` when the key was handled.
    func handleCropNudge(_ event: NSEvent) -> Bool {
        guard editingMode == .crop, let selection = cropSelection, hasPendingCropSelection else { return false }
        let step = (event.modifierFlags.contains(.shift) ? 10 : 1) / max(session?.document.exportScale ?? 1, 0.0001)
        let delta: CGVector
        switch event.specialKey {
        case .leftArrow?: delta = CGVector(dx: -step, dy: 0)
        case .rightArrow?: delta = CGVector(dx: step, dy: 0)
        case .upArrow?: delta = CGVector(dx: 0, dy: -step)
        case .downArrow?: delta = CGVector(dx: 0, dy: step)
        default: return false
        }
        cropSelection = RasterImageCropInteraction.move(selection, by: delta, bounds: canvasBounds)
        needsDisplay = true
        publishStateIfNeeded()
        return true
    }

    // MARK: - Drawing

    /// Draws the crop box in every mode so a pending crop can never be hidden.
    func drawCropSelection() {
        guard let cropSelection, cropSelection.width > 0, cropSelection.height > 0 else { return }
        let isCropMode = editingMode == .crop

        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(rect: cropSelection))
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(isCropMode ? 0.5 : 0.35).setFill()
        outside.fill()

        let lineWidth = canvasLength(forScreenPoints: 1.5)
        let border = NSBezierPath(rect: cropSelection)
        border.lineWidth = lineWidth
        if !isCropMode {
            let dash = canvasLength(forScreenPoints: 5)
            border.setLineDash([dash, dash * 0.6], count: 2, phase: 0)
        }
        NSColor.white.withAlphaComponent(0.95).setStroke()
        border.stroke()

        guard isCropMode else { return }
        drawThirdsGrid(in: cropSelection, lineWidth: lineWidth * 0.6)
        drawCropHandles(on: cropSelection)
        drawCropDimensions(for: cropSelection)
    }

    func drawThirdsGrid(in rect: CGRect, lineWidth: CGFloat) {
        let grid = NSBezierPath()
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            grid.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            grid.line(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            grid.line(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
        }
        grid.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.45).setStroke()
        grid.stroke()
    }

    private func drawCropHandles(on rect: CGRect) {
        let size = canvasLength(forScreenPoints: Self.cropHandleScreenSize)
        for handle in RasterImageCropHandle.allCases {
            let center = handle.point(in: rect)
            let handleRect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: handleRect).fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            let outline = NSBezierPath(rect: handleRect)
            outline.lineWidth = canvasLength(forScreenPoints: 0.75)
            outline.stroke()
        }
    }

    private func drawCropDimensions(for rect: CGRect) {
        guard let pixels = state.cropPixelSize else { return }
        let fontSize = canvasLength(forScreenPoints: 11)
        let label = NSAttributedString(string: "\(Int(pixels.width)) × \(Int(pixels.height))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        let padding = canvasLength(forScreenPoints: 4)
        let size = label.size()
        let origin = CGPoint(x: rect.minX + padding * 2, y: rect.minY + padding * 2)
        let background = CGRect(x: origin.x - padding, y: origin.y - padding / 2,
                                width: size.width + padding * 2, height: size.height + padding)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: background, xRadius: padding, yRadius: padding).fill()
        label.draw(at: origin)
    }
}
