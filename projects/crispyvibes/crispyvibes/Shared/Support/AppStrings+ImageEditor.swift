import Foundation

extension AppStrings {
    /// User-facing strings for the raster image editor (F009).
    enum ImageEditor {
        static let modePan = String(localized: "imageEditor.mode.pan", defaultValue: "Pan")
        static let modeCrop = String(localized: "imageEditor.mode.crop", defaultValue: "Crop")
        static let modeMarkup = String(localized: "imageEditor.mode.markup", defaultValue: "Markup")
        static let modeAdjust = String(localized: "imageEditor.mode.adjust", defaultValue: "Adjust")
        static let applyCrop = String(localized: "imageEditor.action.applyCrop", defaultValue: "Apply Crop")
        static let cancelCrop = String(localized: "imageEditor.action.cancelCrop", defaultValue: "Cancel Crop")
        static let save = String(localized: "imageEditor.action.save", defaultValue: "Save")
        static let copy = String(localized: "imageEditor.action.copy", defaultValue: "Copy")
        static let revert = String(localized: "imageEditor.action.revert", defaultValue: "Revert")
        static let undo = String(localized: "imageEditor.action.undo", defaultValue: "Undo")
        static let redo = String(localized: "imageEditor.action.redo", defaultValue: "Redo")
        static let reloadFromDisk = String(localized: "imageEditor.action.reload", defaultValue: "Reload from Disk")
        static let keepMine = String(localized: "imageEditor.action.keepMine", defaultValue: "Keep My Edits")
        static let annotationTextPlaceholder = String(localized: "imageEditor.annotation.text", defaultValue: "Annotation text")
        static let annotationDefaultText = String(localized: "imageEditor.annotation.default", defaultValue: "Note")
        static let annotationFont = String(localized: "imageEditor.annotation.font", defaultValue: "Font")
        static let annotationSystemFont = String(localized: "imageEditor.annotation.systemFont", defaultValue: "System")
        static func annotationSize(_ size: Int) -> String {
            String(localized: "imageEditor.annotation.size", defaultValue: "Size \(size)")
        }

        static let hintPan = String(localized: "imageEditor.hint.pan", defaultValue: "Pan: drag to move, pinch or scroll to zoom.")
        static let hintCrop = String(
            localized: "imageEditor.hint.crop",
            defaultValue: "Crop: drag the handles or draw a new box. Arrow keys nudge. Return applies, Escape resets."
        )
        static let hintMarkup = String(localized: "imageEditor.hint.markup", defaultValue: "Markup: choose a tool, then drag on the image.")
        static let hintAdjust = String(localized: "imageEditor.hint.adjust", defaultValue: "Adjust: drag the sliders. Hold Compare to see the original.")
        static let hintSelect = String(
            localized: "imageEditor.hint.select",
            defaultValue: "Select: click an item to edit it. Drag to move, drag handles to resize. Delete removes it; Tab cycles."
        )
        static let hintText = String(localized: "imageEditor.hint.text", defaultValue: "Text: click to place text, then edit it in the toolbar.")
        static let hintShape = String(localized: "imageEditor.hint.shape", defaultValue: "Drag to draw. Hold Shift to constrain.")
        static let hintObscure = String(
            localized: "imageEditor.hint.obscure",
            defaultValue: "Drag over an area to obscure it. Blur and pixelate are not secure for sensitive text; use Redact."
        )
        static let hintRedact = String(localized: "imageEditor.hint.redact", defaultValue: "Drag to cover an area with an opaque block. The pixels underneath are removed on save.")

        static let statusCropApplied = String(localized: "imageEditor.status.cropApplied", defaultValue: "Crop applied.")
        static let statusCropCancelled = String(localized: "imageEditor.status.cropCancelled", defaultValue: "Crop selection cancelled.")
        static let statusNoCropSelection = String(localized: "imageEditor.status.noCropSelection", defaultValue: "Draw a crop selection first.")
        static let statusInvalidCropSelection = String(
            localized: "imageEditor.status.invalidCropSelection",
            defaultValue: "Crop selection must be at least 2×2 pixels inside the image."
        )
        static let statusCropDecodeFailure = String(localized: "imageEditor.status.cropDecodeFailure", defaultValue: "Unable to decode the image for cropping.")
        static let statusCropFailure = String(localized: "imageEditor.status.cropFailure", defaultValue: "Unable to crop the selected region.")
        static let statusPendingCropBeforeSave = String(
            localized: "imageEditor.status.pendingCropBeforeSave",
            defaultValue: "Apply or cancel the crop selection before saving."
        )
        static let statusNothingToSave = String(localized: "imageEditor.status.nothingToSave", defaultValue: "No changes to save.")
        static let statusSaving = String(localized: "imageEditor.status.saving", defaultValue: "Saving image…")
        static let statusSaved = String(localized: "imageEditor.status.saved", defaultValue: "Image saved.")
        static func statusSaveFailed(_ reason: String) -> String {
            String(localized: "imageEditor.status.saveFailed", defaultValue: "Unable to save image: \(reason)")
        }
        static let statusCopied = String(localized: "imageEditor.status.copied", defaultValue: "Image copied to the clipboard.")
        static let statusCopyFailed = String(localized: "imageEditor.status.copyFailed", defaultValue: "Unable to copy the image.")
        static let statusReverted = String(localized: "imageEditor.status.reverted", defaultValue: "Reverted to the last saved image.")
        static let statusNothingToRevert = String(localized: "imageEditor.status.nothingToRevert", defaultValue: "Nothing to revert.")
        static let statusRenderFailed = String(localized: "imageEditor.status.renderFailed", defaultValue: "Unable to render the latest file contents.")
        static let statusExternalChange = String(
            localized: "imageEditor.status.externalChange",
            defaultValue: "This image changed on disk while you have unsaved edits."
        )
        static let statusSaveConflict = String(
            localized: "imageEditor.status.saveConflict",
            defaultValue: "The file changed on disk. Choose Reload from Disk or Keep My Edits before saving."
        )
        static let statusLoading = String(localized: "imageEditor.status.loading", defaultValue: "Loading image…")
        static let statusKeptEdits = String(
            localized: "imageEditor.status.keptEdits",
            defaultValue: "Kept your edits. Saving will overwrite the version on disk."
        )
        static let renderFailedPlaceholder = String(localized: "imageEditor.placeholder.renderFailed", defaultValue: "Unable to render this image.")

        static func saveBlockedReducedResolution(source: String, working: String) -> String {
            String(
                localized: "imageEditor.saveBlocked.reducedResolution",
                defaultValue: "Saving is disabled: edits use a \(working) preview of this \(source) image and would reduce its resolution. Use Copy instead."
            )
        }
        static func saveBlockedMultipleFrames(_ count: Int) -> String {
            String(
                localized: "imageEditor.saveBlocked.multipleFrames",
                defaultValue: "Saving is disabled: this image has \(count) frames or pages and saving would keep only the first. Use Copy instead."
            )
        }
        static func saveBlockedHighBitDepth(_ bits: Int) -> String {
            String(
                localized: "imageEditor.saveBlocked.highBitDepth",
                defaultValue: "Saving is disabled: this \(bits)-bit image would be reduced to 8 bits. Use Copy instead."
            )
        }
        static let saveBlockedGainMap = String(
            localized: "imageEditor.saveBlocked.gainMap",
            defaultValue: "Saving is disabled: this HDR image's gain map would be lost. Use Copy instead."
        )

        static let errorNoRenderableImage = String(localized: "imageEditor.error.noRenderableImage", defaultValue: "No renderable image is available.")
        static func errorUnsupportedEncoding(_ ext: String) -> String {
            String(localized: "imageEditor.error.unsupportedEncoding", defaultValue: "Saving .\(ext) images is not supported.")
        }
        static let errorDecodeFailure = String(localized: "imageEditor.error.decodeFailure", defaultValue: "Unable to read image pixels for saving.")
        static let errorEncodingFailure = String(localized: "imageEditor.error.encodingFailure", defaultValue: "Unable to encode image data.")
        static let errorStaleRevision = String(localized: "imageEditor.error.staleRevision", defaultValue: "The image changed while saving. Save again.")
        static let errorRemoteChanged = String(
            localized: "imageEditor.error.remoteChanged",
            defaultValue: "The image changed on the remote host. Choose Reload from Disk or Keep My Edits, then save again."
        )
        static let workerSavingImage = String(localized: "imageEditor.worker.saving", defaultValue: "Saving image")
        static let workerUnavailable = String(localized: "imageEditor.worker.unavailable", defaultValue: "Editor worker unavailable")

        // Phase 2: geometry, navigation, export
        static let rotateLeft = String(localized: "imageEditor.action.rotateLeft", defaultValue: "Rotate Left")
        static let rotateRight = String(localized: "imageEditor.action.rotateRight", defaultValue: "Rotate Right")
        static let flipHorizontal = String(localized: "imageEditor.action.flipHorizontal", defaultValue: "Flip Horizontal")
        static let flipVertical = String(localized: "imageEditor.action.flipVertical", defaultValue: "Flip Vertical")
        static let straighten = String(localized: "imageEditor.action.straighten", defaultValue: "Straighten")
        static func straightenValue(_ degrees: Double) -> String {
            String(localized: "imageEditor.straighten.value", defaultValue: "\(degrees.formatted(.number.precision(.fractionLength(1))))°")
        }
        static let aspectRatio = String(localized: "imageEditor.crop.aspectRatio", defaultValue: "Aspect Ratio")
        static let aspectFree = String(localized: "imageEditor.crop.aspect.free", defaultValue: "Freeform")
        static let aspectOriginal = String(localized: "imageEditor.crop.aspect.original", defaultValue: "Original")
        static let aspectSquare = String(localized: "imageEditor.crop.aspect.square", defaultValue: "Square")
        static let cropOrientation = String(localized: "imageEditor.crop.orientation", defaultValue: "Swap Orientation")
        static let resize = String(localized: "imageEditor.action.resize", defaultValue: "Resize…")
        static let resizeTitle = String(localized: "imageEditor.resize.title", defaultValue: "Resize Image")
        static let resizeWidth = String(localized: "imageEditor.resize.width", defaultValue: "Width")
        static let resizeHeight = String(localized: "imageEditor.resize.height", defaultValue: "Height")
        static let resizePixels = String(localized: "imageEditor.resize.pixels", defaultValue: "px")
        static let resizeKeepProportions = String(localized: "imageEditor.resize.keepProportions", defaultValue: "Keep proportions")
        static let resizeApply = String(localized: "imageEditor.resize.apply", defaultValue: "Resize")
        static func resizeCurrent(width: Int, height: Int) -> String {
            String(localized: "imageEditor.resize.current", defaultValue: "Current size: \(width) × \(height) px")
        }
        static let cancel = String(localized: "imageEditor.action.cancel", defaultValue: "Cancel")
        static let exportAs = String(localized: "imageEditor.action.exportAs", defaultValue: "Export As…")
        static let exportTitle = String(localized: "imageEditor.export.title", defaultValue: "Export Image")
        static let exportFormat = String(localized: "imageEditor.export.format", defaultValue: "Format")
        static let exportQuality = String(localized: "imageEditor.export.quality", defaultValue: "Quality")
        static let exportChooseLocation = String(localized: "imageEditor.export.chooseLocation", defaultValue: "Choose Location…")
        static let exportDropsTransparency = String(
            localized: "imageEditor.export.dropsTransparency",
            defaultValue: "JPEG does not support transparency; transparent areas become solid."
        )
        static let exportDefaultName = String(localized: "imageEditor.export.defaultName", defaultValue: "Image")
        static let zoomIn = String(localized: "imageEditor.zoom.in", defaultValue: "Zoom In")
        static let zoomOut = String(localized: "imageEditor.zoom.out", defaultValue: "Zoom Out")
        static let zoomToFit = String(localized: "imageEditor.zoom.fit", defaultValue: "Zoom to Fit")
        static let zoomActualSize = String(localized: "imageEditor.zoom.actualSize", defaultValue: "Actual Size")
        static func zoomPercent(_ percent: Int) -> String {
            (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
        }
        static func statusCropSize(width: Int, height: Int) -> String {
            String(localized: "imageEditor.status.cropSize", defaultValue: "Crop: \(width) × \(height) px. Press Return to apply, Escape to reset.")
        }
        static let statusTransformFailed = String(localized: "imageEditor.status.transformFailed", defaultValue: "Unable to transform the image.")
        static func statusResizeTooLarge(_ limit: Int) -> String {
            String(localized: "imageEditor.status.resizeTooLarge", defaultValue: "Width and height must be at most \(limit) px.")
        }
        static let statusExporting = String(localized: "imageEditor.status.exporting", defaultValue: "Exporting image…")
        static func statusExported(_ name: String) -> String {
            String(localized: "imageEditor.status.exported", defaultValue: "Exported \(name).")
        }
        static func statusExportFailed(_ reason: String) -> String {
            String(localized: "imageEditor.status.exportFailed", defaultValue: "Unable to export image: \(reason)")
        }
        static let statusExportOverOpenFile = String(
            localized: "imageEditor.status.exportOverOpenFile",
            defaultValue: "Choose a different file. Use Save to overwrite the open image."
        )
        static let hintPanSpace = String(localized: "imageEditor.hint.spacePan", defaultValue: "Hold Space and drag to pan in any mode.")

        static func aspectRatio(width: Int, height: Int) -> String {
            String(localized: "imageEditor.crop.aspect.ratio", defaultValue: "\(width):\(height)")
        }
        static func percent(_ value: Double) -> String {
            value.formatted(.percent.precision(.fractionLength(0)))
        }
        static let formatPNG = String(localized: "imageEditor.format.png", defaultValue: "PNG")
        static let formatJPEG = String(localized: "imageEditor.format.jpeg", defaultValue: "JPEG")
        static let formatHEIC = String(localized: "imageEditor.format.heic", defaultValue: "HEIC")
        static let formatTIFF = String(localized: "imageEditor.format.tiff", defaultValue: "TIFF")

        // Phase 3: markup, adjustments, accessibility
        static let toolSelect = String(localized: "imageEditor.tool.select", defaultValue: "Select")
        static let toolPen = String(localized: "imageEditor.tool.pen", defaultValue: "Pen")
        static let toolLine = String(localized: "imageEditor.tool.line", defaultValue: "Line")
        static let toolArrow = String(localized: "imageEditor.tool.arrow", defaultValue: "Arrow")
        static let toolRectangle = String(localized: "imageEditor.tool.rectangle", defaultValue: "Rectangle")
        static let toolEllipse = String(localized: "imageEditor.tool.ellipse", defaultValue: "Ellipse")
        static let toolHighlight = String(localized: "imageEditor.tool.highlight", defaultValue: "Highlight")
        static let toolText = String(localized: "imageEditor.tool.text", defaultValue: "Text")
        static let toolBlur = String(localized: "imageEditor.tool.blur", defaultValue: "Blur")
        static let toolPixelate = String(localized: "imageEditor.tool.pixelate", defaultValue: "Pixelate")
        static let toolRedact = String(localized: "imageEditor.tool.redact", defaultValue: "Redact")
        static let markupTools = String(localized: "imageEditor.markup.tools", defaultValue: "Markup Tools")
        static let strokeColor = String(localized: "imageEditor.markup.strokeColor", defaultValue: "Color")
        static let fillColor = String(localized: "imageEditor.markup.fillColor", defaultValue: "Fill")
        static let noFill = String(localized: "imageEditor.markup.noFill", defaultValue: "No Fill")
        static let lineWidth = String(localized: "imageEditor.markup.lineWidth", defaultValue: "Width")
        static let sampleColor = String(localized: "imageEditor.markup.sampleColor", defaultValue: "Pick Color from Screen")
        static let deleteItem = String(localized: "imageEditor.markup.delete", defaultValue: "Delete")
        static let statusItemDeleted = String(localized: "imageEditor.status.itemDeleted", defaultValue: "Item deleted.")
        static func accessibilityTextItem(_ text: String) -> String {
            String(localized: "imageEditor.accessibility.textItem", defaultValue: "Text: \(text)")
        }
        static func accessibilityMarkupCount(_ count: Int) -> String {
            String(localized: "imageEditor.accessibility.markupCount", defaultValue: "\(count) markup items")
        }
        static let adjustExposure = String(localized: "imageEditor.adjust.exposure", defaultValue: "Exposure")
        static let adjustContrast = String(localized: "imageEditor.adjust.contrast", defaultValue: "Contrast")
        static let adjustSaturation = String(localized: "imageEditor.adjust.saturation", defaultValue: "Saturation")
        static let adjustVibrance = String(localized: "imageEditor.adjust.vibrance", defaultValue: "Vibrance")
        static let adjustTemperature = String(localized: "imageEditor.adjust.temperature", defaultValue: "Temperature")
        static let adjustHighlights = String(localized: "imageEditor.adjust.highlights", defaultValue: "Highlights")
        static let adjustShadows = String(localized: "imageEditor.adjust.shadows", defaultValue: "Shadows")
        static let adjustSharpness = String(localized: "imageEditor.adjust.sharpness", defaultValue: "Sharpness")
        static let adjustReset = String(localized: "imageEditor.adjust.reset", defaultValue: "Reset Adjustments")
        static let adjustCompare = String(localized: "imageEditor.adjust.compare", defaultValue: "Compare")
        static let statusComparing = String(localized: "imageEditor.status.comparing", defaultValue: "Showing the image without adjustments.")
        static func adjustValue(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))
        }

        // Phase 4: Vision
        static let smartTools = String(localized: "imageEditor.vision.menu", defaultValue: "Smart Tools")
        static let recognizeText = String(localized: "imageEditor.vision.recognizeText", defaultValue: "Recognize Text")
        static let removeBackground = String(localized: "imageEditor.vision.removeBackground", defaultValue: "Remove Background")
        static let showRecognizedText = String(localized: "imageEditor.vision.showText", defaultValue: "Show Recognized Text…")
        static let copyAllText = String(localized: "imageEditor.vision.copyAll", defaultValue: "Copy All Text")
        static let copySelectedText = String(localized: "imageEditor.vision.copySelected", defaultValue: "Copy Selected")
        static let recognizedTextTitle = String(localized: "imageEditor.vision.title", defaultValue: "Recognized Text")
        static let done = String(localized: "imageEditor.action.done", defaultValue: "Done")
        static let statusRecognizingText = String(localized: "imageEditor.status.recognizingText", defaultValue: "Recognizing text…")
        static func statusTextFound(_ count: Int) -> String {
            String(localized: "imageEditor.status.textFound", defaultValue: "Found \(count) lines of text.")
        }
        static let statusNoTextFound = String(localized: "imageEditor.status.noTextFound", defaultValue: "No text was found in this image.")
        static let statusTextCopied = String(localized: "imageEditor.status.textCopied", defaultValue: "Text copied to the clipboard.")
        static let statusRemovingBackground = String(localized: "imageEditor.status.removingBackground", defaultValue: "Removing background…")
        static let statusBackgroundRemoved = String(localized: "imageEditor.status.backgroundRemoved", defaultValue: "Background removed.")
        static let statusNoSubjectFound = String(localized: "imageEditor.status.noSubjectFound", defaultValue: "No subject was found to separate from the background.")
        static let statusAnalysisStale = String(localized: "imageEditor.status.analysisStale", defaultValue: "The image changed during analysis. Try again.")
        static let saveBlockedTransparency = String(
            localized: "imageEditor.saveBlocked.transparency",
            defaultValue: "This file format can't store transparency. Use Export As… and choose PNG, HEIC, or TIFF."
        )

        static let accessibilityMoveLeft = String(localized: "imageEditor.accessibility.moveLeft", defaultValue: "Move Left")
        static let accessibilityMoveRight = String(localized: "imageEditor.accessibility.moveRight", defaultValue: "Move Right")
        static let accessibilityMoveUp = String(localized: "imageEditor.accessibility.moveUp", defaultValue: "Move Up")
        static let accessibilityMoveDown = String(localized: "imageEditor.accessibility.moveDown", defaultValue: "Move Down")
        static let accessibilityShrinkCrop = String(localized: "imageEditor.accessibility.shrinkCrop", defaultValue: "Shrink Crop")
        static let accessibilityExpandCrop = String(localized: "imageEditor.accessibility.expandCrop", defaultValue: "Expand Crop")

        static let canvasAccessibilityLabel = String(localized: "imageEditor.canvas.accessibilityLabel", defaultValue: "Editable image")
    }
}
