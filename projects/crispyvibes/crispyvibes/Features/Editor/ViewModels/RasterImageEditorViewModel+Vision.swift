import CoreGraphics
import Foundation

/// On-device Vision features: recognize/copy text and remove the background.
///
/// Both analyze a full-resolution render of the current document. Results are tagged with the
/// document revision and editor generation; stale results are discarded.
extension RasterImageEditorViewModel {
    var canAnalyze: Bool { hasRenderableImage && !isAnalyzing && !isSaving }

    /// All recognized text in reading order.
    var recognizedFullText: String {
        recognizedText.map(\.text).joined(separator: "\n")
    }

    /// Formats that can't store an 8-bit alpha channel faithfully (GIF has only 1-bit transparency).
    static let formatsWithoutAlpha: Set<String> = ["jpg", "jpeg", "bmp", "gif"]

    /// Save is blocked when background removal added transparency the file format can't store.
    var transparencySaveBlockMessage: String? {
        guard let operations = canvas?.session?.document.operations,
              operations.contains(where: { if case .removeBackground = $0 { return true } else { return false } }),
              let ext = fileURL?.pathExtension.lowercased(),
              Self.formatsWithoutAlpha.contains(ext) else {
            return nil
        }
        return AppStrings.ImageEditor.saveBlockedTransparency
    }

    func recognizeText() {
        analyzeFullResolution(status: AppStrings.ImageEditor.statusRecognizingText) { [weak self] image, token in
            self?.analysisHandle = self?.services.analyzer.recognizeText(in: image) { [weak self] result in
                guard let self, self.isCurrent(token) else { return }
                self.isAnalyzing = false
                switch result {
                case .success(let lines):
                    self.recognizedText = lines
                    self.recognizedTextRevision = token.revision
                    self.recognizedTextSession = token.session
                    self.isRecognizedTextPresented = true
                    self.actionStatus = AppStrings.ImageEditor.statusTextFound(lines.count)
                case .failure(let error):
                    self.actionStatus = error.localizedDescription
                }
            }
        }
    }

    func removeBackground() {
        analyzeFullResolution(status: AppStrings.ImageEditor.statusRemovingBackground) { [weak self] image, token in
            self?.analysisHandle = self?.services.analyzer.foregroundMask(for: image) { [weak self] result in
                guard let self, self.isCurrent(token) else { return }
                self.isAnalyzing = false
                switch result {
                case .success(let mask):
                    guard let session = self.canvas?.session, session.commit(.removeBackground(mask)) else {
                        self.actionStatus = AppStrings.ImageEditor.statusTransformFailed
                        return
                    }
                    self.refreshCanvasState()
                    self.actionStatus = self.transparencySaveBlockMessage ?? AppStrings.ImageEditor.statusBackgroundRemoved
                case .failure(let error):
                    self.actionStatus = error.localizedDescription
                }
            }
        }
    }

    /// Copies `lines` (default: all recognized text) as plain text.
    func copyRecognizedText(_ lines: [RecognizedTextLine]? = nil) {
        let text = (lines ?? recognizedText).map(\.text).joined(separator: "\n")
        guard !text.isEmpty else { return }
        actionStatus = services.pasteboard.writeText(text)
            ? AppStrings.ImageEditor.statusTextCopied
            : AppStrings.ImageEditor.statusCopyFailed
    }

    func clearRecognizedText() {
        recognizedText = []
        recognizedTextRevision = nil
        recognizedTextSession = nil
        isRecognizedTextPresented = false
    }

    /// Cancels in-flight analysis and drops OCR results (document replaced or editor torn down).
    func cancelAnalysis() {
        analysisHandle?.cancel()
        analysisHandle = nil
        isAnalyzing = false
        clearRecognizedText()
    }

    /// `true` when OCR results belong to a different document state than the one displayed.
    var recognizedTextIsStale: Bool {
        guard let revision = recognizedTextRevision else { return false }
        return canvas?.session?.revision != revision || canvas?.session.map(ObjectIdentifier.init) != recognizedTextSession
    }

    // MARK: - Private

    /// Identifies the document state an analysis started from.
    struct AnalysisToken {
        let generation: Int
        let revision: Int
        let session: ObjectIdentifier
    }

    /// Renders the document at full resolution off-main, then hands the image to `analyze`.
    private func analyzeFullResolution(
        status: String,
        analyze: @escaping @MainActor (CGImage, AnalysisToken) -> Void
    ) {
        guard canAnalyze, let session = canvas?.session else { return }
        isAnalyzing = true
        actionStatus = status
        let token = AnalysisToken(generation: operationGeneration, revision: session.revision, session: ObjectIdentifier(session))
        analysisHandle?.cancel()
        analysisHandle = services.exporter.export(session.makeExportJob(destinationURL: nil)) { [weak self] result in
            guard let self, token.generation == self.operationGeneration else { return }
            self.analysisHandle = nil
            switch result {
            case .success(let output):
                analyze(output.image, token)
            case .failure(let error):
                self.isAnalyzing = false
                self.actionStatus = error.localizedDescription
            }
        }
    }

    /// `true` when an analysis result still applies to the displayed document (same editor
    /// generation, same session object, same revision); otherwise ends the analysis quietly.
    private func isCurrent(_ token: AnalysisToken) -> Bool {
        guard token.generation == operationGeneration else { return false }
        analysisHandle = nil
        guard let session = canvas?.session, ObjectIdentifier(session) == token.session, session.revision == token.revision else {
            isAnalyzing = false
            actionStatus = AppStrings.ImageEditor.statusAnalysisStale
            return false
        }
        return true
    }
}
