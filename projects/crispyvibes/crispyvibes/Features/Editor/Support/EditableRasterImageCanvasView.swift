import AppKit

final class EditableRasterImageCanvasView: NSView {
    struct AnnotationStyle {
        var fontName: String
        var fontSize: CGFloat
        var textColor: NSColor
        var backgroundColor: NSColor
    }

    struct TextAnnotation {
        var text: String
        var location: CGPoint
        var style: AnnotationStyle
    }

    override var isFlipped: Bool { true }

    var editingMode: RasterImageEditingMode = .pan
    var annotationTextTemplate: String = "Note"
    var annotationFontFamily: String = "System"
    var annotationFontSize: CGFloat = 14

    var hasRenderableImage: Bool {
        workingImage != nil
    }

    var hasPendingEdits: Bool {
        hasUnsavedBitmapMutations ||
            cropSelection != nil ||
            !activeStroke.isEmpty ||
            !drawnStrokes.isEmpty ||
            !annotations.isEmpty
    }

    var workingImage: NSImage?
    var cropStartPoint: CGPoint?
    var cropSelection: CGRect?
    var activeStroke: [CGPoint] = []
    var drawnStrokes: [[CGPoint]] = []
    var annotations: [TextAnnotation] = []
    var hasUnsavedBitmapMutations = false
    var lastReportedDirtyState = false
    var onDirtyStateChange: ((Bool) -> Void)?
    private var drawnStrokePaths: [NSBezierPath] = []
    private var needsStrokePathRefresh = true
    private var compositingRevision = 0
    private var cachedCompositedRevision = -1
    private var cachedCompositedImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        frame = NSRect(origin: .zero, size: NSSize(width: 1, height: 1))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setDirtyStateObserver(_ observer: @escaping (Bool) -> Void) {
        onDirtyStateChange = observer
        publishDirtyStateIfNeeded(force: true)
    }

    func loadImage(_ image: NSImage?) {
        workingImage = image
        hasUnsavedBitmapMutations = false
        clearTransientEdits()
        invalidateStrokePathCache()
        invalidateCompositedImageCache()
        if let size = image?.size, size.width > 0, size.height > 0 {
            frame = NSRect(origin: .zero, size: size)
        } else {
            frame = NSRect(origin: .zero, size: NSSize(width: 1, height: 1))
        }
        needsDisplay = true
        publishDirtyStateIfNeeded(force: true)
    }

    @discardableResult
    func clearEdits() -> Bool {
        let hadEdits = cropSelection != nil || !activeStroke.isEmpty || !drawnStrokes.isEmpty || !annotations.isEmpty
        clearTransientEdits()
        invalidateStrokePathCache()
        invalidateCompositedImageCache()
        needsDisplay = true
        publishDirtyStateIfNeeded()
        return hadEdits
    }

    @discardableResult
    func copyCompositedImageToPasteboard() -> Bool {
        guard let composited = compositedImage() else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([composited])
    }

    func saveCompositedImage(to destinationURL: URL) -> Result<Void, Error> {
        do {
            try encodedCompositedImageData(for: destinationURL).write(to: destinationURL, options: .atomic)
            finalizeSuccessfulSave(from: destinationURL)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func encodedCompositedImageData(for destinationURL: URL) throws -> Data {
        guard let composited = compositedImage() else {
            throw RasterImageSaveError.noRenderableImage
        }
        return try RasterImagePersistence.encodedData(for: composited, destinationURL: destinationURL)
    }

    func finalizeSuccessfulSave(from destinationURL: URL) {
        let refreshedImage = NSImage(contentsOf: destinationURL) ?? compositedImage()
        workingImage = refreshedImage
        hasUnsavedBitmapMutations = false
        clearTransientEdits()
        invalidateStrokePathCache()
        invalidateCompositedImageCache()
        if let refreshedImage, refreshedImage.size.width > 0, refreshedImage.size.height > 0 {
            frame = NSRect(origin: .zero, size: refreshedImage.size)
        }
        needsDisplay = true
        publishDirtyStateIfNeeded(force: true)
    }

    func applyCropSelection() -> RasterImageCropResult {
        guard let sourceImage = workingImage else {
            return .decodeFailure
        }
        guard let selectionRect = cropSelection else {
            return .noSelection
        }

        let imageRect = CGRect(origin: .zero, size: sourceImage.size)
        let normalizedSelection = selectionRect.intersection(imageRect).integral
        guard normalizedSelection.width >= 2, normalizedSelection.height >= 2 else {
            return .invalidSelection
        }

        var proposedRect = CGRect(origin: .zero, size: sourceImage.size)
        guard let sourceCGImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return .decodeFailure
        }

        let scaleX = CGFloat(sourceCGImage.width) / imageRect.width
        let scaleY = CGFloat(sourceCGImage.height) / imageRect.height
        let cropRect = CGRect(
            x: normalizedSelection.origin.x * scaleX,
            y: (imageRect.height - normalizedSelection.maxY) * scaleY,
            width: normalizedSelection.width * scaleX,
            height: normalizedSelection.height * scaleY
        )
        .integral
        .intersection(
            CGRect(x: 0, y: 0, width: sourceCGImage.width, height: sourceCGImage.height)
        )

        guard cropRect.width >= 2, cropRect.height >= 2 else {
            return .invalidSelection
        }
        guard let croppedCGImage = sourceCGImage.cropping(to: cropRect) else {
            return .cropFailure
        }

        let preservedStrokes = croppedStrokes(within: normalizedSelection)
        let preservedAnnotations = croppedAnnotations(within: normalizedSelection)
        let croppedImage = NSImage(
            cgImage: croppedCGImage,
            size: NSSize(width: normalizedSelection.width, height: normalizedSelection.height)
        )
        workingImage = croppedImage
        hasUnsavedBitmapMutations = true
        cropStartPoint = nil
        cropSelection = nil
        activeStroke.removeAll()
        drawnStrokes = preservedStrokes
        annotations = preservedAnnotations
        invalidateStrokePathCache()
        invalidateCompositedImageCache()
        frame = NSRect(origin: .zero, size: croppedImage.size)
        needsDisplay = true
        publishDirtyStateIfNeeded(force: true)
        return .success
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let workingImage else { return }

        let imageRect = CGRect(origin: .zero, size: workingImage.size)
        drawCompositeContent(in: imageRect, includeActiveStroke: true)
        drawCropSelection()
    }

    override func mouseDown(with event: NSEvent) {
        guard hasRenderableImage else { return }
        let location = clampedLocation(from: event)
        switch editingMode {
        case .pan:
            super.mouseDown(with: event)
        case .crop:
            cropStartPoint = location
            cropSelection = CGRect(origin: location, size: .zero)
            needsDisplay = true
            publishDirtyStateIfNeeded()
        case .draw:
            activeStroke = [location]
            needsDisplay = true
            publishDirtyStateIfNeeded()
        case .annotate:
            let trimmed = annotationTextTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = trimmed.isEmpty ? "Note" : trimmed
            let style = AnnotationStyle(
                fontName: annotationFontFamily,
                fontSize: max(8, min(annotationFontSize, 96)),
                textColor: NSColor.white.withAlphaComponent(0.98),
                backgroundColor: NSColor.systemOrange.withAlphaComponent(0.92)
            )
            annotations.append(TextAnnotation(text: label, location: location, style: style))
            invalidateCompositedImageCache()
            needsDisplay = true
            publishDirtyStateIfNeeded()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard hasRenderableImage else { return }
        let location = clampedLocation(from: event)
        switch editingMode {
        case .crop:
            guard let start = cropStartPoint else { return }
            cropSelection = CGRect(
                x: min(start.x, location.x),
                y: min(start.y, location.y),
                width: abs(location.x - start.x),
                height: abs(location.y - start.y)
            )
            needsDisplay = true
        case .draw:
            activeStroke.append(location)
            needsDisplay = true
        case .pan, .annotate:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard hasRenderableImage else { return }
        switch editingMode {
        case .draw:
            if activeStroke.count > 1 {
                drawnStrokes.append(activeStroke)
                invalidateStrokePathCache()
                invalidateCompositedImageCache()
            }
            activeStroke.removeAll()
            needsDisplay = true
            publishDirtyStateIfNeeded()
        case .crop:
            cropStartPoint = nil
            needsDisplay = true
            publishDirtyStateIfNeeded()
        case .pan, .annotate:
            break
        }
    }

    func clearTransientEdits() {
        cropStartPoint = nil
        cropSelection = nil
        activeStroke.removeAll()
        drawnStrokes.removeAll()
        annotations.removeAll()
    }

    func cachedPathsForDrawnStrokes() -> [NSBezierPath] {
        if needsStrokePathRefresh {
            drawnStrokePaths = drawnStrokes.compactMap(pathForStroke(_:))
            needsStrokePathRefresh = false
        }
        return drawnStrokePaths
    }

    func pathForActiveStroke() -> NSBezierPath? {
        pathForStroke(activeStroke)
    }

    func cachedCompositedImageIfAvailable() -> NSImage? {
        guard cachedCompositedRevision == compositingRevision else { return nil }
        return cachedCompositedImage
    }

    func cacheCompositedImage(_ image: NSImage) {
        cachedCompositedImage = image
        cachedCompositedRevision = compositingRevision
    }

    func invalidateCompositedImageCache() {
        compositingRevision += 1
        cachedCompositedRevision = -1
        cachedCompositedImage = nil
    }

    func invalidateStrokePathCache() {
        needsStrokePathRefresh = true
        drawnStrokePaths.removeAll(keepingCapacity: true)
    }

    private func pathForStroke(_ stroke: [CGPoint]) -> NSBezierPath? {
        guard stroke.count > 1 else { return nil }
        let path = NSBezierPath()
        path.lineWidth = 2.2
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: stroke[0])
        for point in stroke.dropFirst() {
            path.line(to: point)
        }
        return path
    }

    func publishDirtyStateIfNeeded(force: Bool = false) {
        let dirtyState = hasPendingEdits
        guard force || dirtyState != lastReportedDirtyState else { return }
        lastReportedDirtyState = dirtyState
        onDirtyStateChange?(dirtyState)
    }
}
