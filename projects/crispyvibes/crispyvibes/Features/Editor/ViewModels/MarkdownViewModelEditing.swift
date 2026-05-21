import Foundation

extension MarkdownViewModel {
    private func postVibeSpaceFileDidSaveNotification(for fileURL: URL) {
        NotificationCenter.default.post(name: .vibespaceFileDidSave, object: fileURL.standardizedFileURL)
    }

    // MARK: - Buffer Forwarding

    /// The active buffer for the current document, if any.
    var activeBuffer: DocumentBuffer? {
        guard let id = currentDocumentID else { return nil }
        return bufferStore.buffer(for: id)
    }

    /// Content for view binding — delegates to the active buffer.
    var displayContent: String {
        activeBuffer?.displayContent ?? ""
    }

    /// Whether the active buffer is currently loading.
    var isBufferLoading: Bool {
        activeBuffer?.isLoading ?? false
    }

    /// Called by the editor surface when the user edits content.
    func userDidEdit(_ content: String) {
        guard let buffer = activeBuffer else { return }
        buffer.applyEdit(content)
        rawContent = buffer.displayContent
        hasUnsavedTextChanges = buffer.isDirty
        refreshUnsavedChangesFlag()
        if buffer.isDirty {
            autosave.scheduleSave(for: buffer)
        }
    }

    var supportsMarkupViewModeToggle: Bool {
        documentType == .markdown || documentType == .html
    }

    var currentMarkupViewMode: MarkupViewMode {
        guard supportsMarkupViewModeToggle,
              let documentID = activeMarkupDocumentID else {
            return .rich
        }
        return markupViewModeByDocumentID[documentID] ?? .rich
    }

    func setCurrentMarkupViewMode(_ mode: MarkupViewMode) {
        guard supportsMarkupViewModeToggle,
              let documentID = activeMarkupDocumentID else {
            return
        }

        if mode == .rich {
            markupViewModeByDocumentID.removeValue(forKey: documentID)
        } else {
            markupViewModeByDocumentID[documentID] = mode
        }
    }

    func clearMarkupViewMode(forDocumentID documentID: String) {
        markupViewModeByDocumentID.removeValue(forKey: documentID)
    }

    func updateEditableContentFromRenderer(_ content: String) {
        guard isEditableDocumentType(documentType) else { return }
        userDidEdit(content)
    }

    func updateText(_ text: String) {
        guard isEditableDocumentType(documentType) else { return }
        userDidEdit(text)
    }

    func setImageEditDirtyState(_ hasUnsavedEdits: Bool) {
        guard documentType == .image else {
            hasUnsavedImageEdits = false
            refreshUnsavedChangesFlag()
            return
        }
        if hasUnsavedImageEdits != hasUnsavedEdits {
            hasUnsavedImageEdits = hasUnsavedEdits
            refreshUnsavedChangesFlag()
        }
    }

    func save() {
        guard let fileURL, isEditableDocumentType(documentType) else { return }
        guard let buffer = activeBuffer, let token = buffer.beginSave() else { return }

        workerStatus = .busy("Saving")
        hasUnsavedTextChanges = buffer.isDirty
        refreshUnsavedChangesFlag()

        Task { [weak self] in
            guard let self else { return }

            do {
                if let provider = self.fileContentProvider {
                    try await provider.writeFile(at: fileURL.path, contents: Data(token.content.utf8))
                } else {
                    _ = try await self.worker.execute(
                        .writeFile,
                        arguments: [
                            "filePath": fileURL.path,
                            "content": token.content
                        ],
                        timeout: 10
                    )
                }

                buffer.didSave(token: token)
                self.hasUnsavedTextChanges = buffer.isDirty
                self.refreshUnsavedChangesFlag()
                self.lastSaveDate = Date()
                self.workerStatus = .ready
                self.postVibeSpaceFileDidSaveNotification(for: fileURL)
            } catch {
                buffer.didFailSave(token: token)
                self.errorMessage = "Unable to save file: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Editor worker unavailable")
            }
        }
    }

    func saveAndExitEditing() {
        save()
    }

    func saveImagePreviewData(
        _ data: Data,
        from presentedFileURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let sourceFileURL = fileURL else {
            completion(.failure(CocoaError(.fileNoSuchFile)))
            return
        }

        workerStatus = .busy("Saving image")

        Task { [weak self] in
            guard let self else { return }

            do {
                if let provider = self.fileContentProvider,
                   provider.requiresMaterializedLocalPreview,
                   presentedFileURL.standardizedFileURL != sourceFileURL.standardizedFileURL {
                    try await provider.writeFile(at: sourceFileURL.path, contents: data)
                    try data.write(to: presentedFileURL, options: .atomic)
                } else {
                    try data.write(to: presentedFileURL, options: .atomic)
                }

                self.hasUnsavedImageEdits = false
                self.refreshUnsavedChangesFlag()
                self.workerStatus = .ready
                self.postVibeSpaceFileDidSaveNotification(for: sourceFileURL)
                completion(.success(()))
            } catch {
                self.hasUnsavedImageEdits = true
                self.refreshUnsavedChangesFlag()
                self.errorMessage = "Unable to save image: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Editor worker unavailable")
                completion(.failure(error))
            }
        }
    }

    func scheduleAutosave() {
        guard let buffer = activeBuffer else { return }
        autosave.scheduleSave(for: buffer)
    }

    func isEditableDocumentType(_ type: DocumentType) -> Bool {
        type == .markdown || type == .html || type == .python || type == .json || type == .r || type == .plainText
    }

    func refreshUnsavedChangesFlag() {
        hasUnsavedChanges = hasUnsavedTextChanges || hasUnsavedImageEdits
    }

    private var activeMarkupDocumentID: String? {
        if let activeEditorTabID {
            return activeEditorTabID
        }
        return currentDocumentID
    }
}
