import AppKit

extension EditableRasterImageCanvasView {
    func drawCompositeContent(in imageRect: CGRect, includeActiveStroke: Bool) {
        workingImage?.draw(in: imageRect)
        drawStrokes(in: imageRect, includeActiveStroke: includeActiveStroke)
        drawAnnotations(in: imageRect)
    }

    func drawStrokes(in imageRect: CGRect, includeActiveStroke: Bool) {
        let strokeColor = NSColor.systemGreen.withAlphaComponent(0.88)
        strokeColor.setStroke()

        for path in cachedPathsForDrawnStrokes() {
            path.stroke()
        }

        if includeActiveStroke,
           let path = pathForActiveStroke() {
            path.stroke()
        }
    }

    func drawAnnotations(in imageRect: CGRect) {
        guard !annotations.isEmpty else { return }
        for annotation in annotations {
            let resolvedFont: NSFont
            if annotation.style.fontName == "System" {
                resolvedFont = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .semibold)
            } else {
                resolvedFont = NSFont(
                    name: annotation.style.fontName,
                    size: annotation.style.fontSize
                ) ?? NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .semibold)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: resolvedFont,
                .foregroundColor: annotation.style.textColor
            ]
            let attributed = NSAttributedString(string: annotation.text, attributes: attributes)
            let textSize = attributed.size()
            let padding = NSSize(width: 8, height: 4)
            let origin = CGPoint(
                x: min(max(annotation.location.x + 6, 0), max(0, imageRect.width - (textSize.width + padding.width * 2))),
                y: min(max(annotation.location.y + 6, 0), max(0, imageRect.height - (textSize.height + padding.height * 2)))
            )
            let bubbleRect = CGRect(
                x: origin.x,
                y: origin.y,
                width: textSize.width + padding.width * 2,
                height: textSize.height + padding.height * 2
            )

            let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 5, yRadius: 5)
            annotation.style.backgroundColor.setFill()
            bubblePath.fill()
            NSColor.black.withAlphaComponent(0.7).setStroke()
            bubblePath.lineWidth = 1
            bubblePath.stroke()

            let textPoint = CGPoint(x: bubbleRect.origin.x + padding.width, y: bubbleRect.origin.y + padding.height)
            attributed.draw(at: textPoint)
        }
    }

    func drawCropSelection() {
        guard editingMode == .crop,
              let cropSelection,
              cropSelection.width > 0,
              cropSelection.height > 0 else {
            return
        }

        NSColor.systemBlue.withAlphaComponent(0.20).setFill()
        cropSelection.fill()

        let border = NSBezierPath(rect: cropSelection)
        border.lineWidth = 1.5
        border.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.90).setStroke()
        border.stroke()
    }

    func compositedImage() -> NSImage? {
        guard let workingImage else { return nil }
        let size = workingImage.size
        guard size.width > 0, size.height > 0 else { return nil }
        if let cachedImage = cachedCompositedImageIfAvailable() {
            return cachedImage
        }

        let imageRect = CGRect(origin: .zero, size: size)
        var proposedRect = imageRect
        let sourceCGImage = workingImage.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        )
        let pixelWidth = max(sourceCGImage?.width ?? Int(ceil(size.width)), 1)
        let pixelHeight = max(sourceCGImage?.height ?? Int(ceil(size.height)), 1)

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmapRep.size = size

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high
        graphicsContext.shouldAntialias = true
        graphicsContext.cgContext.translateBy(x: 0, y: size.height)
        graphicsContext.cgContext.scaleBy(x: 1, y: -1)
        drawCompositeContent(in: imageRect, includeActiveStroke: false)
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let outputImage = NSImage(size: size)
        outputImage.addRepresentation(bitmapRep)
        cacheCompositedImage(outputImage)
        return outputImage
    }
}
