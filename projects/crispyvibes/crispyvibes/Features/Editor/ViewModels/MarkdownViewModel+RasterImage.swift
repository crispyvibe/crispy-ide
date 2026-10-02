import Foundation

/// F009: raster image save routing and remote write-back.
extension MarkdownViewModel {
    /// Routes the Save command to the active document: raster images save through their
    /// editor (via `imageSaveRequestToken`), text documents through `save()`.
    func saveActiveDocument() {
        if documentType == .image {
            imageSaveRequestToken += 1
        } else {
            save()
        }
    }

    /// `true` while a ⌘S request is waiting for the raster editor.
    var isImageSaveRequestPending: Bool {
        imageSaveRequestToken != handledImageSaveRequestToken
    }

    /// Marks the pending raster save request as consumed.
    func acknowledgeImageSaveRequest() {
        handledImageSaveRequestToken = imageSaveRequestToken
    }

    /// Writes encoded image bytes for the open image. Remote images are written back through the
    /// provider only if the remote version still matches the staged baseline (fail closed when the
    /// version cannot be read). Disk writes run off the main actor.
    func saveImagePreviewData(
        _ data: Data,
        from presentedFileURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let sourceFileURL = fileURL else {
            completion(.failure(CocoaError(.fileNoSuchFile)))
            return
        }

        workerStatus = .busy(AppStrings.ImageEditor.workerSavingImage)

        Task { [weak self] in
            guard let self else { return }

            do {
                if let provider = self.fileContentProvider,
                   provider.requiresMaterializedLocalPreview,
                   presentedFileURL.standardizedFileURL != sourceFileURL.standardizedFileURL {
                    try await self.verifyRemoteImageUnchanged(at: sourceFileURL.path, provider: provider)
                    try await provider.writeFile(at: sourceFileURL.path, contents: data)
                    try await Self.writeOffMain(data, to: presentedFileURL)
                    self.remoteImageBaselineToken = try? await provider.modificationToken(at: sourceFileURL.path)
                } else {
                    try await Self.writeOffMain(data, to: presentedFileURL)
                }

                self.hasUnsavedImageEdits = false
                self.refreshUnsavedChangesFlag()
                self.workerStatus = .ready
                self.postVibeSpaceFileDidSaveNotification(for: sourceFileURL)
                completion(.success(()))
            } catch {
                self.hasUnsavedImageEdits = true
                self.refreshUnsavedChangesFlag()
                self.errorMessage = AppStrings.ImageEditor.statusSaveFailed(error.localizedDescription)
                self.workerStatus = .unavailable(AppStrings.ImageEditor.workerUnavailable)
                completion(.failure(error))
            }
        }
    }

    /// Mirrors the remote image into the staged preview file and records its version. The raster
    /// editor's file observer then reloads (no pending edits) or raises a Reload/Keep conflict.
    func refreshStagedRemoteImage() {
        guard documentType == .image,
              let provider = fileContentProvider,
              provider.requiresMaterializedLocalPreview,
              let sourceURL = fileURL,
              let stagedURL = imageFileURL,
              stagedURL.standardizedFileURL != sourceURL.standardizedFileURL else {
            return
        }
        let path = sourceURL.path
        Task { [weak self] in
            // Read the version first: if the file changes mid-read, the older token makes the next
            // save conservatively detect a conflict.
            let token = try? await provider.modificationToken(at: path)
            guard let data = try? await provider.readFile(at: path) else { return }
            guard let self, self.fileURL?.path == path, self.imageFileURL == stagedURL else { return }
            if (try? Data(contentsOf: stagedURL)) != data {
                try? await Self.writeOffMain(data, to: stagedURL)
            }
            self.remoteImageBaselineToken = token
        }
    }

    /// Throws `remoteChanged` when the remote version differs from the staged baseline, or when a
    /// version-capable provider cannot confirm it. Providers without versions (nil) are trusted.
    private func verifyRemoteImageUnchanged(at path: String, provider: any FileContentProviding) async throws {
        let current: String?
        do {
            current = try await provider.modificationToken(at: path)
        } catch {
            throw RasterImageSaveError.remoteChanged
        }
        guard let current else { return }
        guard let baseline = remoteImageBaselineToken, baseline == current else {
            refreshStagedRemoteImage()
            throw RasterImageSaveError.remoteChanged
        }
    }

    private static func writeOffMain(_ data: Data, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: url, options: .atomic)
        }.value
    }
}
