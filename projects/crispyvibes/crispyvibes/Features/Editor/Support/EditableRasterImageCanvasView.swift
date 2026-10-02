import AppKit

/// Snapshot of canvas editing state published to the editor view model.
struct RasterImageCanvasState: Equatable {
    /// Committed but unsaved edits.
    var hasPendingEdits = false
    /// A crop marquee exists and has not been applied or cancelled.
    var hasCropSelection = false
    /// The marquee maps to a valid pixel rectangle.
    var canApplyCrop = false
    var canUndo = false
    var canRedo = false
    /// Export-pixel size of the pending crop, when one is drawn.
    var cropPixelSize: CGSize?
    /// Export-pixel size of the whole image.
    var imagePixelSize: CGSize?
    /// Selected markup item, if any.
    var selectedMarkup: RasterMarkupItem?
    /// Number of editable markup items.
    var markupCount = 0
}

/// Keyboard / menu commands the canvas forwards to its controller.
enum RasterImageCanvasCommand {
    case applyCrop
    case cancelCrop
    case undo
    case redo
    case deleteSelection
    case editSelectedText
}

/// AppKit input/render adapter for an editable raster image.
///
/// Document state (operations, history, display bitmap) lives in `RasterImageEditSession`;
/// the canvas only holds transient gesture state (crop marquee, in-progress stroke, pan).
/// The crop marquee never counts as a persistable edit and stays visible in every mode.
@MainActor
final class EditableRasterImageCanvasView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { hasRenderableImage }

    /// Document being displayed; assigning it resets transient gesture state.
    var session: RasterImageEditSession? {
        didSet {
            oldValue?.onChange = nil
            session?.onChange = { [weak self] in self?.sessionDidChange() }
            cropStartPoint = nil
            cropSelection = nil
            markupDrag = nil
            markupPreview = nil
            selectedMarkupID = nil
            liveComposite = nil
            compositor.cancel()
            sessionDidChange(force: true)
        }
    }

    var editingMode: RasterImageEditingMode = .pan {
        didSet {
            guard oldValue != editingMode else { return }
            editingModeDidChange(from: oldValue)
            window?.invalidateCursorRects(for: self)
        }
    }
    /// Width ÷ height constraint for crop selections; `nil` is free-form.
    var cropAspectRatio: CGFloat? {
        didSet {
            guard oldValue != cropAspectRatio else { return }
            cropAspectRatioDidChange()
        }
    }
    /// Active markup tool in Markup mode.
    var markupTool: RasterMarkupTool = .select {
        didSet {
            guard oldValue != markupTool else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    /// Style for new markup items.
    var markupStyle = RasterMarkupStyle.default
    /// Adjustment override for live slider preview / before-after compare; `nil` shows the document.
    var previewAdjustments: RasterImageAdjustments? {
        didSet {
            guard oldValue != previewAdjustments else { return }
            refreshLiveComposite()
        }
    }
    /// OCR results to outline on the canvas (normalized, top-left origin).
    var recognizedTextLines: [RecognizedTextLine] = [] {
        didSet {
            guard oldValue != recognizedTextLines else { return }
            needsDisplay = true
        }
    }
    /// Live straighten preview angle (radians, clockwise); committed separately.
    var previewStraightenRadians: CGFloat = 0 {
        didSet {
            guard oldValue != previewStraightenRadians else { return }
            needsDisplay = true
        }
    }
    var annotationTextTemplate: String = AppStrings.ImageEditor.annotationDefaultText
    /// Ignores edits while a save is in flight so the submitted revision cannot change.
    var isInteractionLocked = false
    /// Receives Return / Escape / Undo / Redo commands.
    var onCommand: ((RasterImageCanvasCommand) -> Void)?

    var cropStartPoint: CGPoint?
    var cropSelection: CGRect?
    var selectedMarkupID: UUID?
    var markupDrag: RasterImageCanvasMarkupDrag?
    /// Live geometry of the markup item being created or edited.
    var markupPreview: RasterMarkupItem?
    /// Off-main composite used when vectors can't be drawn directly (pixel effects, preview adjustments).
    var liveComposite: (key: RasterImageLiveCompositor.Key, image: CGImage)?
    let compositor = RasterImageLiveCompositor()
    var panAnchor: (window: CGPoint, origin: CGPoint)?
    /// Active crop-box gesture.
    var cropDrag: RasterImageCanvasCropDrag?
    /// Space is held: temporary pan in any mode.
    var isSpacePanning = false
    private var lastReportedState: RasterImageCanvasState?
    private weak var lastFlattenedImage: CGImage?
    private var onDirtyStateChange: ((Bool) -> Void)?
    private var onStateChange: ((RasterImageCanvasState) -> Void)?
    private var cachedDisplayImage: (source: CGImage, image: NSImage)?
    private var lastCanvasSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        frame = NSRect(origin: .zero, size: NSSize(width: 1, height: 1))
        wantsLayer = true
        setAccessibilityRole(.image)
        setAccessibilityLabel(AppStrings.ImageEditor.canvasAccessibilityLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    var hasRenderableImage: Bool { session != nil }

    var hasPendingEdits: Bool {
        (session?.isDirty ?? false) || markupDrag.map { if case .create = $0 { return true } else { return false } } ?? false
    }

    /// The marquee differs from the whole image (a full-image crop box is not a pending edit).
    var hasPendingCropSelection: Bool {
        guard let cropSelection, let session else { return false }
        return !session.isFullCanvasSelection(cropSelection)
    }

    var state: RasterImageCanvasState {
        let snapped = cropSelection.flatMap { session?.snappedCropRect(forSelection: $0) }
        let scale = session?.document.exportScale ?? 1
        let pixels = session?.exportTransform.pixelSize
        return RasterImageCanvasState(
            hasPendingEdits: hasPendingEdits,
            hasCropSelection: hasPendingCropSelection,
            canApplyCrop: hasPendingCropSelection && snapped != nil,
            canUndo: session?.canUndo ?? false,
            canRedo: session?.canRedo ?? false,
            cropPixelSize: snapped.map { CGSize(width: ($0.width * scale).rounded(), height: ($0.height * scale).rounded()) },
            imagePixelSize: pixels.map { CGSize(width: $0.width, height: $0.height) },
            selectedMarkup: selectedMarkupID.flatMap { session?.markupItem(id: $0) },
            markupCount: session?.markupEntries.count ?? 0
        )
    }

    /// Display bitmap with every geometric edit applied, sized in canvas units.
    var workingImage: NSImage? {
        guard let session else { return nil }
        let source = session.flattenedDisplayImage
        if let cachedDisplayImage, cachedDisplayImage.source === source, cachedDisplayImage.image.size == session.canvasSize {
            return cachedDisplayImage.image
        }
        let image = NSImage(cgImage: source, size: session.canvasSize)
        cachedDisplayImage = (source, image)
        return image
    }

    // MARK: - Observation

    /// Observes only the dirty flag (lightweight hosts and tests).
    func setDirtyStateObserver(_ observer: @escaping (Bool) -> Void) {
        onDirtyStateChange = observer
        publishStateIfNeeded(force: true)
    }

    /// Observes the full canvas state.
    func setStateObserver(_ observer: @escaping (RasterImageCanvasState) -> Void) {
        onStateChange = observer
        publishStateIfNeeded(force: true)
    }

    func publishStateIfNeeded(force: Bool = false) {
        let current = state
        guard force || current != lastReportedState else { return }
        let dirtyChanged = current.hasPendingEdits != lastReportedState?.hasPendingEdits
        lastReportedState = current
        if force || dirtyChanged {
            onDirtyStateChange?(current.hasPendingEdits)
        }
        onStateChange?(current)
    }

    private func sessionDidChange(force: Bool = false) {
        let size = session?.canvasSize ?? NSSize(width: 1, height: 1)
        let flattened = session?.flattenedDisplayImage
        if size != lastCanvasSize || flattened !== lastFlattenedImage {
            // A geometric change invalidates any marquee drawn in the old canvas space.
            cropStartPoint = nil
            cropDrag = nil
            cropSelection = nil
            lastCanvasSize = size
            lastFlattenedImage = flattened
            resetCropBoxIfNeeded()
        }
        validateMarkupSelection()
        refreshLiveComposite()
        frame = NSRect(origin: .zero, size: size.width > 0 && size.height > 0 ? size : NSSize(width: 1, height: 1))
        NSAccessibility.post(element: self, notification: .valueChanged)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        publishStateIfNeeded(force: force)
    }

    // MARK: - Commands

    /// Replaces the document with in-memory pixels (standalone use and tests).
    func loadImage(_ image: NSImage?) {
        var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
        guard let image, image.size.width > 0, image.size.height > 0,
              let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            session = nil
            return
        }
        session = .inMemory(cgImage, canvasSize: image.size)
    }

    /// Commits a finished overlay operation.
    func commit(_ operation: ImageEditOperation) {
        guard !isInteractionLocked else { return }
        session?.commit(operation)
    }

    /// Discards the crop marquee and every unsaved edit (undoable).
    /// - Returns: `true` when anything was discarded.
    @discardableResult
    func clearEdits() -> Bool {
        let hadSelection = cancelCropSelection()
        let hadDrag = markupDrag != nil
        markupDrag = nil
        markupPreview = nil
        let reverted = session?.revert() ?? false
        needsDisplay = true
        publishStateIfNeeded()
        return hadSelection || hadDrag || reverted
    }

    /// Discards the pending crop without touching pixels. In Crop mode the box resets to the
    /// whole image (or the aspect-ratio box) instead of disappearing.
    /// - Returns: `true` when a pending crop was discarded.
    @discardableResult
    func cancelCropSelection() -> Bool {
        guard cropSelection != nil else { return false }
        let wasPending = hasPendingCropSelection
        cropStartPoint = nil
        cropDrag = nil
        cropSelection = nil
        resetCropBoxIfNeeded()
        needsDisplay = true
        publishStateIfNeeded()
        return wasPending
    }

    /// Applies the current marquee as a crop operation.
    func applyCropSelection() -> RasterImageCropResult {
        guard let session else { return .decodeFailure }
        guard !isInteractionLocked else { return .cropFailure }
        let result = session.applyCrop(selection: cropSelection)
        if result.didApply {
            cropStartPoint = nil
            cropSelection = nil
            publishStateIfNeeded(force: true)
        }
        return result
    }

    /// Display-scale composite of every edit.
    func compositedImage() -> NSImage? {
        guard let session, let composite = session.compositeDisplayImage() else { return nil }
        return NSImage(cgImage: composite, size: session.canvasSize)
    }

    @discardableResult
    func copyCompositedImageToPasteboard() -> Bool {
        guard let composited = compositedImage() else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([composited])
    }

    /// Synchronously renders at export resolution, writes `destinationURL`, and rebases.
    func saveCompositedImage(to destinationURL: URL) -> Result<Void, Error> {
        guard let session else { return .failure(RasterImageSaveError.noRenderableImage) }
        let result = RasterImageExportService.run(
            session.makeExportJob(destinationURL: destinationURL),
            handle: nil,
            decoder: RasterImageDecoder(),
            renderer: RasterImageRenderer(),
            encoder: RasterImageEncoder()
        )
        do {
            let output = try result.get()
            try output.data?.write(to: destinationURL, options: .atomic)
            session.rebase(afterSaving: output)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Undo / Redo responders (⌘Z, ⇧⌘Z)

    @objc func undo(_ sender: Any?) {
        onCommand?(.undo)
    }

    @objc func redo(_ sender: Any?) {
        onCommand?(.redo)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCanvasContent()
    }
}

extension EditableRasterImageCanvasView {
    /// `true` when the canvas must show an off-main composite instead of drawing vectors directly.
    var needsLiveComposite: Bool {
        guard let session else { return false }
        return previewAdjustments != nil || session.overlayOperations.containsPixelEffects
    }

    /// Requests a fresh off-main composite when the document or preview override changed.
    func refreshLiveComposite() {
        guard let session, needsLiveComposite else {
            liveComposite = nil
            compositor.cancel()
            needsDisplay = true
            return
        }
        let key = RasterImageLiveCompositor.Key(
            revision: session.revision, adjustments: previewAdjustments, sessionID: ObjectIdentifier(session)
        )
        guard liveComposite?.key != key else { return }
        compositor.render(session.displayCompositeJob(adjustments: previewAdjustments), renderer: session.displayRenderer) { [weak self] image in
            guard let self, self.session.map(ObjectIdentifier.init) == key.sessionID else { return }
            // A failed render must not leave an older composite on screen.
            self.liveComposite = image.map { (key, $0) }
            self.needsDisplay = true
        }
    }
}

extension EditableRasterImageCanvasView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return !isInteractionLocked && (session?.canUndo ?? false)
        case #selector(redo(_:)): return !isInteractionLocked && (session?.canRedo ?? false)
        default: return true
        }
    }
}
