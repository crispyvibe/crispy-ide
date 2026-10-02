import Foundation

/// Crop, undo/redo, revert, and conflict-resolution commands.
extension RasterImageEditorViewModel {
    func applyCrop() {
        guard !isSaving, let canvas else { return }
        let result = canvas.applyCropSelection()
        canvasState = canvas.state
        actionStatus = result.feedbackMessage
        if result.didApply {
            fileSession?.resetScrollPosition()
        }
    }

    func cancelCrop() {
        guard let canvas, canvas.cancelCropSelection() else { return }
        canvasState = canvas.state
        actionStatus = AppStrings.ImageEditor.statusCropCancelled
    }

    func undo() {
        guard !isSaving, let canvas, canvas.session?.undo() == true else { return }
        canvasState = canvas.state
        actionStatus = nil
    }

    func redo() {
        guard !isSaving, let canvas, canvas.session?.redo() == true else { return }
        canvasState = canvas.state
        actionStatus = nil
    }

    func revert() {
        guard !isSaving, let canvas else { return }
        let didRevert = canvas.clearEdits()
        canvasState = canvas.state
        actionStatus = didRevert ? AppStrings.ImageEditor.statusReverted : AppStrings.ImageEditor.statusNothingToRevert
    }

    func reloadFromDisk() {
        guard !isSaving else { return }
        hasExternalChangeConflict = false
        fileSession?.reloadFromDisk()
    }

    func keepMyEdits() {
        hasExternalChangeConflict = false
        fileSession?.markFileStateCurrent()
        actionStatus = AppStrings.ImageEditor.statusKeptEdits
    }
}
