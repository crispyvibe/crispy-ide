import Foundation

/// Save and Copy workflows: full-resolution render/encode off the main thread, revision-checked.
///
/// Every async completion is tagged with `operationGeneration`; `shutdown()` bumps it so late
/// results never mutate a torn-down editor.
extension RasterImageEditorViewModel {
    func save() {
        guard !isSaving, let canvas, let session = canvas.session, let fileURL else { return }
        let state = canvas.state
        canvasState = state
        if state.hasCropSelection {
            actionStatus = AppStrings.ImageEditor.statusPendingCropBeforeSave
            return
        }
        if let message = saveBlockReason?.message ?? transparencySaveBlockMessage {
            actionStatus = message
            return
        }
        guard state.hasPendingEdits else {
            actionStatus = AppStrings.ImageEditor.statusNothingToSave
            return
        }
        guard !reportConflictIfFileChanged() else { return }

        isSaving = true
        canvas.isInteractionLocked = true
        actionStatus = AppStrings.ImageEditor.statusSaving
        let generation = operationGeneration
        saveHandle?.cancel()
        saveHandle = services.exporter.export(session.makeExportJob(destinationURL: fileURL)) { [weak self, weak session] result in
            guard let self, let session, generation == self.operationGeneration else { return }
            self.didRenderForSave(result, session: session, fileURL: fileURL, generation: generation)
        }
    }

    func copy() {
        guard !isCopying, let session = canvas?.session else { return }
        isCopying = true
        let canvasSize = session.canvasSize
        let generation = operationGeneration
        copyHandle?.cancel()
        copyHandle = services.exporter.export(session.makeExportJob(destinationURL: nil)) { [weak self] result in
            guard let self, generation == self.operationGeneration else { return }
            self.isCopying = false
            self.copyHandle = nil
            if case .success(let output) = result, self.services.pasteboard.write(output.image, size: canvasSize) {
                self.actionStatus = AppStrings.ImageEditor.statusCopied
            } else {
                self.actionStatus = AppStrings.ImageEditor.statusCopyFailed
            }
        }
    }

    /// Flags a conflict when the file changed on disk since it was loaded or last saved.
    /// - Returns: `true` when a conflict was reported.
    private func reportConflictIfFileChanged() -> Bool {
        guard fileSession?.hasExternalChangeSinceLoad() == true else { return false }
        hasExternalChangeConflict = true
        actionStatus = AppStrings.ImageEditor.statusSaveConflict
        return true
    }

    private func didRenderForSave(
        _ result: Result<RasterImageExportResult, Error>,
        session: RasterImageEditSession,
        fileURL: URL,
        generation: Int
    ) {
        saveHandle = nil
        let output: RasterImageExportResult
        do {
            output = try result.get()
        } catch {
            finishSave(.failure(error), output: nil, session: session)
            return
        }
        guard output.revision == session.revision, canvas?.session === session, let data = output.data else {
            finishSave(.failure(RasterImageSaveError.staleRevision), output: nil, session: session)
            return
        }
        // Re-check right before writing: the file may have changed while rendering.
        if reportConflictIfFileChanged() {
            finishSave(.failure(RasterImageSaveError.fileChangedDuringSave), output: nil, session: session, keepStatus: true)
            return
        }
        let completion: (Result<Void, Error>) -> Void = { [weak self, weak session] writeResult in
            DispatchQueue.main.async { [weak self, weak session] in
                guard let self, let session, generation == self.operationGeneration else { return }
                self.finishSave(writeResult, output: output, session: session)
            }
        }
        if let saveDataHandler {
            saveDataHandler(fileURL, data, completion)
        } else {
            writeOffMain(data, to: fileURL, generation: generation) { [weak self, weak session] result in
                guard let self, let session else { return }
                self.finishSave(result, output: output, session: session)
            }
        }
    }

    private func finishSave(
        _ result: Result<Void, Error>,
        output: RasterImageExportResult?,
        session: RasterImageEditSession,
        keepStatus: Bool = false
    ) {
        switch result {
        case .success:
            fileSession?.markFileStateCurrent()
            actionStatus = AppStrings.ImageEditor.statusSaved
            if let output, canvas?.session === session {
                session.rebase(afterSaving: output)
                if case .file = session.document.source, let fileSession {
                    // Show the persisted (possibly lossy) pixels the next export will start from.
                    // Stay locked until the reload installs, so no edit lands on the old session.
                    isAwaitingPostSaveReload = true
                    fileSession.reloadFromDisk()
                    if let canvas { canvasState = canvas.state }
                    return
                }
            }
        case .failure(let error):
            if !keepStatus {
                actionStatus = AppStrings.ImageEditor.statusSaveFailed(error.localizedDescription)
            }
        }
        isSaving = false
        canvas?.isInteractionLocked = false
        if let canvas { canvasState = canvas.state }
    }
}
