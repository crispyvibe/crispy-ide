import Foundation

/// Export As: render full resolution in a chosen format to a user-picked file. Never modifies
/// the open document or its baseline.
extension RasterImageEditorViewModel {
    /// Suggested Export As file name, e.g. `photo-edited.png`.
    var suggestedExportFileName: String {
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? AppStrings.ImageEditor.exportDefaultName
        return "\(base)-edited.\(exportOptions.format.fileExtension)"
    }

    /// Asks for a destination, then exports with `exportOptions`.
    func exportAs() {
        guard canExport, canvas?.session != nil else { return }
        isExportSheetPresented = false
        let options = exportOptions
        services.destinationPicker.pickDestination(
            suggestedName: suggestedExportFileName,
            contentType: options.format.contentType
        ) { [weak self] url in
            guard let self, let url else { return }
            self.export(to: url, options: options)
        }
    }

    /// Renders and writes to `url`. Exporting onto the open file is refused (use Save).
    func export(to url: URL, options: RasterImageExportOptions) {
        guard canExport, let session = canvas?.session else { return }
        if let fileURL, Self.isSameFile(url, fileURL) {
            actionStatus = AppStrings.ImageEditor.statusExportOverOpenFile
            return
        }
        isExporting = true
        actionStatus = AppStrings.ImageEditor.statusExporting
        let generation = operationGeneration
        var job = session.makeExportJob(destinationURL: url)
        job.options = options
        exportHandle?.cancel()
        exportHandle = services.exporter.export(job) { [weak self] result in
            guard let self, generation == self.operationGeneration else { return }
            self.exportHandle = nil
            let data: Data
            do {
                guard let encoded = try result.get().data else { throw RasterImageSaveError.encodingFailure }
                data = encoded
            } catch {
                self.isExporting = false
                self.actionStatus = AppStrings.ImageEditor.statusExportFailed(error.localizedDescription)
                return
            }
            self.writeOffMain(data, to: url, generation: generation) { [weak self] writeResult in
                guard let self else { return }
                self.isExporting = false
                switch writeResult {
                case .success: self.actionStatus = AppStrings.ImageEditor.statusExported(url.lastPathComponent)
                case .failure(let error): self.actionStatus = AppStrings.ImageEditor.statusExportFailed(error.localizedDescription)
                }
            }
        }
    }

    /// `true` when both URLs resolve to the same file (symlinks, hard links, path aliases).
    static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.standardizedFileURL.resolvingSymlinksInPath()
        let right = rhs.standardizedFileURL.resolvingSymlinksInPath()
        if left.path == right.path { return true }
        var freshLeft = left
        var freshRight = right
        freshLeft.removeAllCachedResourceValues()
        freshRight.removeAllCachedResourceValues()
        guard let leftID = try? freshLeft.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject,
              let rightID = try? freshRight.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject else {
            return false
        }
        return leftID.isEqual(rightID)
    }

    /// Atomically writes `data` on the I/O queue, then completes on the main actor if this
    /// editor generation is still current.
    func writeOffMain(_ data: Data, to url: URL, generation: Int, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        services.ioQueue.async { [weak self] in
            let result = Result { try data.write(to: url, options: .atomic) }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, generation == self.operationGeneration else { return }
                    completion(result)
                }
            }
        }
    }
}
