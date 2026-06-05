import Foundation

extension MarkdownViewModel {
    func restartWorker() {
        Task { [weak self] in
            guard let self else { return }
            await self.worker.restart()
            self.workerStatus = .ready
            if let documentReference = currentOpenDocumentReference() {
                self.openFile(at: documentReference.url, documentReference: documentReference)
            } else if let fileURL = self.fileURL {
                self.openFile(at: fileURL)
            }
        }
    }

    func previewFile(at url: URL, documentReference: FileDocumentReference? = nil) {
        let resolvedReference = documentReference ?? FileDocumentReference(url: url)
        let normalizedURL = resolvedReference.url
        if let existingTab = editorTabs.first(where: { $0.id == resolvedReference.documentIdentity }) {
            activateEditorTab(withID: existingTab.id)
            return
        }

        activeEditorTabID = nil
        openFileIfNeeded(at: normalizedURL, documentReference: resolvedReference)
    }

    func openFileInTab(
        at url: URL,
        line: Int? = nil,
        column: Int? = nil,
        documentReference: FileDocumentReference? = nil,
        suppressConnectionReadinessErrors: Bool = false
    ) {
        let resolvedReference = documentReference ?? FileDocumentReference(url: url)
        let normalizedURL = resolvedReference.url
        registerPendingSourceSelection(for: resolvedReference.documentIdentity, line: line, column: column)
        if let existingTab = editorTabs.first(where: { $0.id == resolvedReference.documentIdentity }) {
            activateEditorTab(
                withID: existingTab.id,
                suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
            )
            return
        }

        editorTabs.append(EditorTab(documentReference: resolvedReference))
        activeEditorTabID = resolvedReference.documentIdentity
        openFileIfNeeded(
            at: normalizedURL,
            documentReference: resolvedReference,
            suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
        )
    }

    func activateEditorTab(withID tabID: String, suppressConnectionReadinessErrors: Bool = false) {
        guard let tab = editorTabs.first(where: { $0.id == tabID }) else { return }
        activeEditorTabID = tab.id
        openFileIfNeeded(
            at: tab.fileURL,
            documentReference: tab.documentReference,
            suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
        )
    }

    func closeEditorTab(withID tabID: String) {
        guard let closingIndex = editorTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let closingWasActive = activeEditorTabID == tabID
        clearMarkupViewMode(forDocumentID: tabID)

        // Close the buffer for this tab
        autosave.cancel(for: tabID)
        bufferStore.closeBuffer(id: tabID, writer: makeBufferWriter())

        editorTabs.remove(at: closingIndex)

        guard closingWasActive else { return }

        if editorTabs.isEmpty {
            activeEditorTabID = nil
            clearCurrentDocument()
            return
        }

        let fallbackIndex = min(closingIndex, editorTabs.count - 1)
        let fallbackTab = editorTabs[fallbackIndex]
        activeEditorTabID = fallbackTab.id
        openFileIfNeeded(at: fallbackTab.fileURL, documentReference: fallbackTab.documentReference)
    }

    func previewGitDiff(
        rootURL: URL,
        fileURL: URL,
        relativePath: String,
        statusCode: String,
        documentReference: FileDocumentReference? = nil
    ) {
        autosave.cancel(for: currentDocumentID ?? "")
        cancelInFlightOpenTasks()
        activeEditorTabID = nil
        let resolvedReference = documentReference ?? FileDocumentReference(url: fileURL)
        self.fileURL = resolvedReference.url
        currentDocumentID = resolvedReference.documentIdentity
        observeActiveBuffer(nil)
        displayTitleOverride = "\(relativePath) (Changes)"
        unsupportedFileMessage = nil
        errorMessage = nil
        imageFileURL = nil
        pdfFileURL = nil
        officeFileURL = nil
        codeLanguageKind = nil
        rawContent = ""
        lastSavedContent = ""
        hasUnsavedChanges = false
        hasUnsavedTextChanges = false
        hasUnsavedImageEdits = false
        documentType = .gitDiff

        let requestID = UUID()
        openRequestID = requestID
        workerStatus = .busy("Loading changes")

        gitDiffTask = Task { [weak self] in
            guard let self else { return }
            do {
                let diffContent = try await self.worker.execute(
                    .gitDiff,
                    arguments: [
                        "rootPath": rootURL.standardizedFileURL.path,
                        "relativePath": relativePath
                    ],
                    timeout: 12
                ) ?? ""
                guard !Task.isCancelled else { return }

                guard self.openRequestID == requestID else { return }

                if diffContent.contains(where: { !$0.isWhitespace }) {
                    self.rawContent = diffContent
                } else {
                    self.rawContent = """
                    ### Git Status
                    \(statusCode) \(relativePath)

                    No textual diff is available for this file revision.
                    """
                }
                self.lastSavedContent = self.rawContent
                self.workerStatus = .ready
            } catch {
                guard !Task.isCancelled else { return }
                guard self.openRequestID == requestID else { return }
                self.errorMessage = "Unable to load git changes: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Editor worker unavailable")
            }
        }
    }

    func previewGitFileContent(
        rootURL: URL,
        fileURL: URL,
        relativePath: String,
        titleSuffix: String,
        documentReference: FileDocumentReference? = nil
    ) {
        autosave.cancel(for: currentDocumentID ?? "")
        cancelInFlightOpenTasks()
        activeEditorTabID = nil
        let resolvedReference = documentReference ?? FileDocumentReference(url: fileURL)
        self.fileURL = resolvedReference.url
        currentDocumentID = resolvedReference.documentIdentity
        observeActiveBuffer(nil)
        displayTitleOverride = "\(relativePath) (\(titleSuffix))"
        unsupportedFileMessage = nil
        errorMessage = nil
        imageFileURL = nil
        pdfFileURL = nil
        officeFileURL = nil
        codeLanguageKind = nil
        rawContent = ""
        lastSavedContent = ""
        hasUnsavedChanges = false
        hasUnsavedTextChanges = false
        hasUnsavedImageEdits = false
        documentType = .gitDiff

        let requestID = UUID()
        openRequestID = requestID
        workerStatus = .busy("Loading file")

        gitDiffTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await self.worker.execute(
                    .gitFileContent,
                    arguments: [
                        "rootPath": rootURL.standardizedFileURL.path,
                        "relativePath": relativePath
                    ],
                    timeout: 12
                ) ?? ""
                guard !Task.isCancelled else { return }
                guard self.openRequestID == requestID else { return }

                self.rawContent = content
                self.lastSavedContent = content
                self.workerStatus = .ready
            } catch {
                guard !Task.isCancelled else { return }
                guard self.openRequestID == requestID else { return }
                self.errorMessage = "Unable to load previous file content: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Editor worker unavailable")
            }
        }
    }

    func openFile(
        at url: URL,
        documentReference: FileDocumentReference? = nil,
        suppressConnectionReadinessErrors: Bool = false
    ) {
        autosave.cancel(for: currentDocumentID ?? "")
        cancelInFlightOpenTasks()
        cleanupMaterializedPreview()
        let resolvedReference = documentReference ?? FileDocumentReference(url: url)
        let normalizedURL = resolvedReference.url
        fileURL = normalizedURL
        currentDocumentID = resolvedReference.documentIdentity
        displayTitleOverride = nil
        unsupportedFileMessage = nil
        errorMessage = nil
        hasUnsavedChanges = false
        hasUnsavedTextChanges = false
        hasUnsavedImageEdits = false
        imageFileURL = nil
        pdfFileURL = nil
        officeFileURL = nil
        codeLanguageKind = Self.detectCodeLanguage(for: normalizedURL.pathExtension.lowercased())

        let detectedType = Self.detectDocumentType(for: normalizedURL)
        documentType = detectedType
        let requestID = UUID()
        openRequestID = requestID

        switch detectedType {
        case .image:
            observeActiveBuffer(nil)
            if let provider = fileContentProvider, provider.requiresMaterializedLocalPreview {
                materializeRemotePreview(
                    from: normalizedURL,
                    using: provider,
                    requestID: requestID,
                    message: "Fetching remote image",
                    suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
                ) { [weak self] stagedURL in
                    self?.imageFileURL = stagedURL
                }
            } else {
                imageFileURL = normalizedURL
                workerStatus = .ready
            }

        case .pdf:
            observeActiveBuffer(nil)
            if let provider = fileContentProvider, provider.requiresMaterializedLocalPreview {
                materializeRemotePreview(
                    from: normalizedURL,
                    using: provider,
                    requestID: requestID,
                    message: "Fetching remote document",
                    suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
                ) { [weak self] stagedURL in
                    self?.pdfFileURL = stagedURL
                }
            } else {
                pdfFileURL = normalizedURL
                workerStatus = .ready
            }

        case .office:
            observeActiveBuffer(nil)
            if let provider = fileContentProvider, provider.requiresMaterializedLocalPreview {
                materializeRemotePreview(
                    from: normalizedURL,
                    using: provider,
                    requestID: requestID,
                    message: "Fetching remote document",
                    suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
                ) { [weak self] stagedURL in
                    self?.officeFileURL = stagedURL
                }
            } else {
                officeFileURL = normalizedURL
                workerStatus = .ready
            }

        case .none, .gitDiff, .notebook:
            // F050: the notebook surface is rendered by the Jupyter server in a
            // WKWebView; the text buffer is intentionally not loaded so autosave
            // never overwrites the server-managed `.ipynb`.
            observeActiveBuffer(nil)
            workerStatus = .ready

        case .markdown, .plainText, .python, .json, .r, .html, .whiteboard, .unsupported:
            workerStatus = .busy("Opening file")
            let buffer = bufferStore.openBuffer(for: resolvedReference)
            observeActiveBuffer(buffer)
            let capturedProvider = fileContentProvider
            buffer.beginLoadIfNeeded { [weak self] in
                guard let self else { throw CancellationError() }
                if let provider = capturedProvider {
                    let data = try await provider.readFile(at: normalizedURL.path)
                    return String(data: data, encoding: .utf8) ?? ""
                } else {
                    return try await self.worker.execute(
                        .readFile,
                        arguments: ["filePath": normalizedURL.path],
                        timeout: 10
                    ) ?? ""
                }
            }
            if !buffer.isLoading {
                if detectedType == .unsupported {
                    self.documentType = .plainText
                }
                self.workerStatus = .ready
                return
            }
            // Observe buffer load completion to update workerStatus
            openFileTask = Task { [weak self, weak buffer] in
                guard let self, let buffer else { return }
                for await state in buffer.$state.values {
                    guard !Task.isCancelled else { return }
                    guard self.currentDocumentID == buffer.id else { return }
                    switch state {
                    case .clean:
                        if detectedType == .unsupported {
                            self.documentType = .plainText
                        }
                        self.workerStatus = .ready
                        return
                    case .failed(let message):
                        if suppressConnectionReadinessErrors,
                           capturedProvider != nil {
                            self.workerStatus = .unavailable("SSH connection unavailable")
                        } else if detectedType == .unsupported {
                            self.unsupportedFileMessage = "Preview is not available for this file type."
                            self.workerStatus = .unavailable("Editor worker unavailable")
                        } else {
                            self.errorMessage = "Unable to open file: \(message)"
                            self.workerStatus = .unavailable("Editor worker unavailable")
                        }
                        return
                    default:
                        continue
                    }
                }
            }
        }
    }

    func reloadExternalEditableFile(suppressConnectionReadinessErrors: Bool = false) {
        guard let fileURL, isEditableDocumentType(documentType) else { return }
        guard let buffer = activeBuffer, !buffer.isDirty, !buffer.isSaving, !buffer.isLoading else { return }

        cancelInFlightOpenTasks()

        let normalizedURL = fileURL.standardizedFileURL
        let detectedType = documentType
        workerStatus = .busy("Reloading file")

        let capturedProvider = fileContentProvider
        openFileTask = Task { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            do {
                let content: String
                if let provider = capturedProvider {
                    let data = try await provider.readFile(at: normalizedURL.path)
                    content = String(data: data, encoding: .utf8) ?? ""
                } else {
                    content = try await self.worker.execute(
                        .readFile,
                        arguments: ["filePath": normalizedURL.path],
                        timeout: 10
                    ) ?? ""
                }

                guard !Task.isCancelled else { return }
                guard self.currentDocumentID == buffer.id else { return }
                buffer.externalContentChanged(content)
                if detectedType == .unsupported {
                    self.documentType = .plainText
                }
                self.errorMessage = nil
                self.unsupportedFileMessage = nil
                self.workerStatus = .ready
            } catch {
                guard !Task.isCancelled else { return }
                guard self.currentDocumentID == buffer.id else { return }
                if suppressConnectionReadinessErrors,
                   capturedProvider != nil {
                    self.workerStatus = .unavailable("SSH connection unavailable")
                } else if detectedType == .unsupported {
                    self.unsupportedFileMessage = "Preview is not available for this file type."
                    self.workerStatus = .unavailable("Editor worker unavailable")
                } else {
                    self.errorMessage = "Unable to reload file: \(error.localizedDescription)"
                    self.workerStatus = .unavailable("Editor worker unavailable")
                }
            }
        }
    }

    func reloadCurrentEditableFile(suppressConnectionReadinessErrors: Bool = false) {
        guard let fileURL, isEditableDocumentType(documentType) else { return }
        guard let buffer = activeBuffer else { return }

        autosave.cancel(for: buffer.id)
        cancelInFlightOpenTasks()
        observeActiveBuffer(buffer)

        let normalizedURL = fileURL.standardizedFileURL
        let detectedType = documentType
        workerStatus = .busy("Reloading file")

        let capturedProvider = fileContentProvider
        buffer.beginReload { [weak self] in
            guard let self else { throw CancellationError() }
            if let provider = capturedProvider {
                let data = try await provider.readFile(at: normalizedURL.path)
                return String(data: data, encoding: .utf8) ?? ""
            } else {
                return try await self.worker.execute(
                    .readFile,
                    arguments: ["filePath": normalizedURL.path],
                    timeout: 10
                ) ?? ""
            }
        }

        openFileTask = Task { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            for await state in buffer.$state.values {
                guard !Task.isCancelled else { return }
                guard self.currentDocumentID == buffer.id else { return }
                switch state {
                case .clean:
                    if detectedType == .unsupported {
                        self.documentType = .plainText
                    }
                    self.hasUnsavedChanges = false
                    self.hasUnsavedTextChanges = false
                    self.hasUnsavedImageEdits = false
                    self.errorMessage = nil
                    self.unsupportedFileMessage = nil
                    self.workerStatus = .ready
                    return
                case .failed(let message):
                    if suppressConnectionReadinessErrors,
                       capturedProvider != nil {
                        self.workerStatus = .unavailable("SSH connection unavailable")
                    } else if detectedType == .unsupported {
                        self.unsupportedFileMessage = "Preview is not available for this file type."
                    } else {
                        self.errorMessage = "Unable to open file: \(message)"
                    }
                    self.workerStatus = .unavailable("Editor worker unavailable")
                    return
                default:
                    continue
                }
            }
        }
    }

    func openFileIfNeeded(
        at url: URL,
        documentReference: FileDocumentReference? = nil,
        suppressConnectionReadinessErrors: Bool = false
    ) {
        let resolvedReference = documentReference ?? FileDocumentReference(url: url)
        let normalizedURL = resolvedReference.url
        // If we already have this document active (and it's not a git diff or override), skip
        if currentDocumentID == resolvedReference.documentIdentity,
           displayTitleOverride == nil,
           documentType != .gitDiff {
            return
        }
        openFile(
            at: normalizedURL,
            documentReference: resolvedReference,
            suppressConnectionReadinessErrors: suppressConnectionReadinessErrors
        )
    }

    func clearCurrentDocument() {
        if let id = currentDocumentID {
            autosave.cancel(for: id)
            bufferStore.closeBuffer(id: id, writer: makeBufferWriter())
        }
        cancelInFlightOpenTasks()
        openRequestID = UUID()
        cleanupMaterializedPreview()
        fileContentProvider = nil
        fileURL = nil
        currentDocumentID = nil
        observeActiveBuffer(nil)
        rawContent = ""
        hasUnsavedChanges = false
        hasUnsavedTextChanges = false
        hasUnsavedImageEdits = false
        documentType = .none
        imageFileURL = nil
        pdfFileURL = nil
        unsupportedFileMessage = nil
        errorMessage = nil
        codeLanguageKind = nil
        displayTitleOverride = nil
        pendingSourceSelection = nil
        workerStatus = .ready
    }

    private func cancelInFlightOpenTasks() {
        openFileTask?.cancel()
        gitDiffTask?.cancel()
        openFileTask = nil
        gitDiffTask = nil
        openRequestID = UUID()
    }

    /// Creates a writer closure for buffer flush-on-close.
    func makeBufferWriter() -> (URL, SaveToken) async throws -> Void {
        { [weak self] url, token in
            guard let self else { return }
            if let provider = self.fileContentProvider {
                try await provider.writeFile(at: url.path, contents: Data(token.content.utf8))
            } else {
                _ = try await self.worker.execute(
                    .writeFile,
                    arguments: ["filePath": url.path, "content": token.content],
                    timeout: 10
                )
            }
            self.lastSaveDate = Date()
            NotificationCenter.default.post(name: .vibespaceFileDidSave, object: url.standardizedFileURL)
        }
    }

    private func materializeRemotePreview(
        from sourceURL: URL,
        using provider: any FileContentProviding,
        requestID: UUID,
        message: String,
        suppressConnectionReadinessErrors: Bool,
        applyPreviewURL: @escaping @MainActor (URL) -> Void
    ) {
        workerStatus = .busy(message)
        openFileTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await provider.readFile(at: sourceURL.path)
                guard !Task.isCancelled else { return }
                guard self.openRequestID == requestID else { return }

                let stagedURL = try self.stagePreviewData(data, for: sourceURL)
                guard self.openRequestID == requestID else {
                    try? FileManager.default.removeItem(at: stagedURL)
                    return
                }

                applyPreviewURL(stagedURL)
                self.workerStatus = .ready
            } catch {
                guard !Task.isCancelled else { return }
                guard self.openRequestID == requestID else { return }
                if suppressConnectionReadinessErrors,
                   Self.isConnectionReadinessError(error) {
                    self.workerStatus = .unavailable("SSH connection unavailable")
                    return
                }
                self.errorMessage = "Unable to open file: \(error.localizedDescription)"
                self.workerStatus = .unavailable("Editor worker unavailable")
            }
        }
    }

    private func stagePreviewData(_ data: Data, for sourceURL: URL) throws -> URL {
        cleanupMaterializedPreview()

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crispyvibes-remote-preview", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        let extensionSuffix = sourceURL.pathExtension.isEmpty ? "" : ".\(sourceURL.pathExtension)"
        let baseName = currentDocumentID?
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            ?? UUID().uuidString
        let stagedURL = cacheDirectory.appendingPathComponent("\(baseName)-\(UUID().uuidString)\(extensionSuffix)")
        try data.write(to: stagedURL, options: .atomic)
        materializedPreviewURL = stagedURL
        return stagedURL
    }

    private func cleanupMaterializedPreview() {
        if let materializedPreviewURL {
            try? FileManager.default.removeItem(at: materializedPreviewURL)
            self.materializedPreviewURL = nil
        }
    }

    private func currentOpenDocumentReference() -> FileDocumentReference? {
        if let activeEditorTabID,
           let tab = editorTabs.first(where: { $0.id == activeEditorTabID }) {
            return tab.documentReference
        }
        if let currentDocumentID,
           let tab = editorTabs.first(where: { $0.id == currentDocumentID }) {
            return tab.documentReference
        }
        guard let fileURL else { return nil }
        return FileDocumentReference(
            url: fileURL,
            projectIdentifier: projectIdentifier(from: currentDocumentID)
        )
    }

    private func projectIdentifier(from documentID: String?) -> String? {
        guard let documentID else { return nil }
        let components = documentID.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }
        return components[0]
    }

    private func registerPendingSourceSelection(for documentID: String, line: Int?, column: Int?) {
        guard let line else {
            pendingSourceSelection = nil
            return
        }
        pendingSourceSelection = PendingSourceSelection(
            documentID: documentID,
            selection: SourceSelection(line: line, column: column)
        )
    }

    private static func isConnectionReadinessError(_ error: Error) -> Bool {
        if let sshError = error as? SSHRemoteError {
            if case .timeout = sshError {
                return true
            }
        }

        if let sftpError = error as? SFTPError {
            switch sftpError {
            case .notConnected, .timeout:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case Int(ENOTCONN), Int(ECONNRESET), Int(EHOSTUNREACH), Int(ENETDOWN), Int(ENETUNREACH):
                return true
            default:
                break
            }
        }

        return false
    }
}
