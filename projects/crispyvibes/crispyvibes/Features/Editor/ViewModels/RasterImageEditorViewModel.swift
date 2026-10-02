import Foundation

/// View model for the raster image editor toolbar and canvas (F009).
///
/// Views call named methods only; the canvas and file session are reached through protocols and
/// heavy work runs through the injected `RasterImageEditorServices`.
@MainActor
final class RasterImageEditorViewModel: ObservableObject {
    @Published private(set) var editingMode: RasterImageEditingMode = .pan
    @Published var canvasState = RasterImageCanvasState()
    /// Transient feedback; announced to VoiceOver when set.
    @Published var actionStatus: String? {
        didSet {
            if let actionStatus, actionStatus != oldValue { services.announcer.announce(actionStatus) }
        }
    }
    @Published var isSaving = false
    @Published var isCopying = false
    @Published private(set) var hasRenderableImage = false
    @Published private(set) var saveBlockReason: RasterImageSaveBlockReason?
    @Published var hasExternalChangeConflict = false
    @Published var cropAspectRatio: RasterImageCropAspectRatio = .free
    @Published var isCropPortrait = false
    /// Live straighten angle in degrees (−45…45); committed on release.
    @Published var straightenDegrees = 0.0
    /// Zoom where 100% shows one image pixel per device pixel.
    @Published var zoomPercent = 100.0
    @Published var isExportSheetPresented = false
    @Published var isResizeSheetPresented = false
    @Published var exportOptions = RasterImageExportOptions.default
    /// Default text for new text items; mirrors the selected text item while one is selected.
    @Published var annotationText = AppStrings.ImageEditor.annotationDefaultText
    @Published var markupTool: RasterMarkupTool = .select
    /// Style for new items; mirrors the selected item's style while one is selected.
    @Published var markupStyle = RasterMarkupStyle.default
    /// Slider values (committed as one `.adjust` operation on release).
    @Published var adjustments = RasterImageAdjustments.identity
    /// A slider is being dragged; the canvas shows a live preview.
    @Published var isAdjusting = false
    /// Hold-to-compare: the canvas shows the image without adjustments.
    @Published var isComparing = false
    /// Incremented to ask the toolbar to focus the text field (double-click on a text item).
    @Published var textFocusRequest = 0
    @Published var isAnalyzing = false
    /// OCR result for `recognizedTextRevision`; cleared when the document changes.
    @Published var recognizedText: [RecognizedTextLine] = []
    @Published var isRecognizedTextPresented = false
    var recognizedTextRevision: Int?
    var recognizedTextSession: ObjectIdentifier?
    var analysisHandle: RasterImageWorkHandle?

    let services: RasterImageEditorServices
    /// File currently presented by the preview.
    var fileURL: URL?
    /// Receives encoded bytes; when `nil`, the view model writes atomically to `fileURL`.
    var saveDataHandler: RasterImageSaveDataHandler?

    weak var canvas: RasterImageCanvasControlling?
    weak var fileSession: RasterImageFileSessionControlling?
    weak var viewport: RasterImageViewportControlling?
    var exportHandle: RasterImageWorkHandle?
    @Published var isExporting = false
    var saveHandle: RasterImageWorkHandle?
    var copyHandle: RasterImageWorkHandle?
    /// Bumped by `shutdown()`; async completions from older generations are ignored.
    var operationGeneration = 0
    /// A save succeeded and the file is being re-decoded; editing stays locked until it installs.
    var isAwaitingPostSaveReload = false

    init(services: RasterImageEditorServices) {
        self.services = services
    }

    var canSave: Bool {
        hasRenderableImage && !isSaving && canvasState.hasPendingEdits &&
            !canvasState.hasCropSelection && saveBlockReason == nil && transparencySaveBlockMessage == nil
    }

    var canApplyCrop: Bool { !isSaving && canvasState.canApplyCrop }
    var canCancelCrop: Bool { !isSaving && canvasState.hasCropSelection }
    var canRevert: Bool { !isSaving && (canvasState.hasPendingEdits || canvasState.hasCropSelection) }
    var canUndo: Bool { !isSaving && canvasState.canUndo }
    var canRedo: Bool { !isSaving && canvasState.canRedo }
    var canCopy: Bool { hasRenderableImage && !isCopying }
    var canEditGeometry: Bool { hasRenderableImage && !isSaving }
    var canExport: Bool { hasRenderableImage && !isExporting }

    /// Status line text: transient feedback, then persistent warnings, then the mode hint.
    var statusLine: String {
        if let actionStatus { return actionStatus }
        if hasExternalChangeConflict { return AppStrings.ImageEditor.statusExternalChange }
        if let saveBlockReason { return saveBlockReason.message }
        if let transparencySaveBlockMessage { return transparencySaveBlockMessage }
        if editingMode == .crop, let size = canvasState.cropPixelSize, canvasState.hasCropSelection {
            return AppStrings.ImageEditor.statusCropSize(width: Int(size.width), height: Int(size.height))
        }
        if editingMode == .markup { return markupTool.hint }
        if editingMode == .adjust, isComparing { return AppStrings.ImageEditor.statusComparing }
        return editingMode.hint
    }

    /// Current crop constraint as width ÷ height, pushed to the canvas.
    var cropAspectValue: CGFloat? {
        cropAspectRatio.value(originalSize: canvasState.imagePixelSize ?? .zero, portrait: isCropPortrait)
    }

    /// Connects the AppKit adapters created by the preview representable.
    func attach(
        canvas: RasterImageCanvasControlling,
        fileSession: RasterImageFileSessionControlling,
        viewport: RasterImageViewportControlling? = nil
    ) {
        self.canvas = canvas
        self.fileSession = fileSession
        self.viewport = viewport
    }

    /// Cancels in-flight background work and returns to an idle, editable state.
    /// Safe to call repeatedly; the editor can be reused afterwards (e.g. on reappearance).
    func shutdown() {
        operationGeneration += 1
        saveHandle?.cancel()
        copyHandle?.cancel()
        exportHandle?.cancel()
        cancelAnalysis()
        saveHandle = nil
        copyHandle = nil
        exportHandle = nil
        isSaving = false
        isCopying = false
        isExporting = false
        isAwaitingPostSaveReload = false
        canvas?.isInteractionLocked = false
    }

    func selectMode(_ mode: RasterImageEditingMode) {
        editingMode = mode
        actionStatus = nil
    }

    // MARK: - Inputs from the canvas / file layer

    func canvasStateDidChange(_ state: RasterImageCanvasState) {
        let selectionChanged = state.selectedMarkup?.id != canvasState.selectedMarkup?.id
        canvasState = state
        if selectionChanged { syncInspectorWithSelection() }
        if !isAdjusting, let session = canvas?.session, session.effectiveAdjustments != adjustments {
            adjustments = session.effectiveAdjustments
        }
        if recognizedTextIsStale { clearRecognizedText() }
    }

    /// Called after every (re)load from disk.
    func didLoadImage(rendered: Bool, saveBlockReason: RasterImageSaveBlockReason?, isNewFile: Bool) {
        if isAwaitingPostSaveReload || isNewFile {
            // A post-save reload (or a different file) supersedes any in-flight save.
            if isNewFile { operationGeneration += 1; saveHandle?.cancel(); saveHandle = nil }
            isAwaitingPostSaveReload = false
            isSaving = false
            canvas?.isInteractionLocked = false
        }
        // Every (re)load installs a new session: in-flight analysis and OCR boxes no longer apply.
        cancelAnalysis()
        hasRenderableImage = rendered
        self.saveBlockReason = saveBlockReason
        hasExternalChangeConflict = false
        if let canvas { canvasState = canvas.state }
        if !rendered {
            actionStatus = AppStrings.ImageEditor.statusRenderFailed
        } else if isNewFile {
            actionStatus = nil
        }
    }

    /// Called when the file changes on disk while edits are pending; the reload is deferred.
    func didDetectExternalChangeWithPendingEdits() {
        hasExternalChangeConflict = true
        actionStatus = nil
    }

    func handleCanvasCommand(_ command: RasterImageCanvasCommand) {
        switch command {
        case .applyCrop: applyCrop()
        case .cancelCrop: cancelCrop()
        case .undo: undo()
        case .redo: redo()
        case .deleteSelection: deleteSelectedMarkup()
        case .editSelectedText: textFocusRequest += 1
        }
    }
}
