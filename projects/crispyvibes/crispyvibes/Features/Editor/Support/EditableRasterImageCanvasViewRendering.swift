import AppKit

/// On-screen drawing for the raster canvas. Overlays use the same painter as export.
extension EditableRasterImageCanvasView {
    func drawCanvasContent() {
        guard let session, let workingImage else { return }
        let canvasSize = session.canvasSize
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        NSGraphicsContext.current?.imageInterpolation = .high

        if previewStraightenRadians != 0 {
            drawStraightenPreview(workingImage, in: canvasRect)
            return
        }

        let editingID = markupDrag == nil ? nil : markupPreview?.id
        // The composite bakes in every committed item, so it can't be used while one is being
        // dragged (it would show the item twice). Revision and session must match; the adjustment
        // part of the key may lag during a slider drag so the preview stays smooth.
        if needsLiveComposite, editingID == nil, let liveComposite,
           liveComposite.key.revision == session.revision, liveComposite.key.sessionID == ObjectIdentifier(session) {
            // The composite already contains every committed overlay, including pixel effects.
            NSImage(cgImage: liveComposite.image, size: canvasSize).draw(in: canvasRect)
        } else {
            workingImage.draw(in: canvasRect)
            for operation in session.overlayOperations where operation.markupItem?.id != editingID {
                if let item = operation.markupItem, item.isPixelEffect {
                    drawPixelEffectPlaceholder(item)
                } else {
                    RasterImageOverlayPainter.draw(operation, canvasSize: canvasSize)
                }
            }
        }
        if let markupPreview, markupDrag != nil {
            if markupPreview.isPixelEffect {
                drawPixelEffectPlaceholder(markupPreview)
            } else {
                RasterImageOverlayPainter.draw(markupPreview)
            }
        }
        drawRecognizedText(canvasSize: canvasSize)
        drawCropSelection()
        drawMarkupSelection()
    }

    /// Outlines recognized text lines so users can see what OCR found.
    private func drawRecognizedText(canvasSize: CGSize) {
        guard !recognizedTextLines.isEmpty else { return }
        let lineWidth = canvasLength(forScreenPoints: 1)
        for line in recognizedTextLines {
            let box = line.box(in: canvasSize).insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
            NSColor.systemYellow.withAlphaComponent(0.18).setFill()
            NSBezierPath(rect: box).fill()
            let outline = NSBezierPath(rect: box)
            outline.lineWidth = lineWidth
            NSColor.systemYellow.withAlphaComponent(0.9).setStroke()
            outline.stroke()
        }
    }

    /// Previews a straighten: the rotated image scaled so its inscribed crop fills the canvas,
    /// matching what `.straighten` will produce (shown at the current canvas size).
    private func drawStraightenPreview(_ image: NSImage, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext, rect.width > 0 else { return }
        let output = ImageEditOperation.straightenedSize(for: rect.size, radians: Double(previewStraightenRadians))
        let zoom = rect.width / max(output.width, 0.0001)
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: previewStraightenRadians)
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        image.draw(in: rect)
        if let session {
            RasterImageOverlayPainter.draw(session.overlayOperations, canvasSize: session.canvasSize)
        }
        context.restoreGState()
        drawThirdsGrid(in: rect, lineWidth: canvasLength(forScreenPoints: 1))
    }
}
