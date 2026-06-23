import Combine
import Foundation

@MainActor
final class MarkdownViewModel: ObservableObject {
    struct EditorTab: Identifiable, Equatable {
        let documentReference: FileDocumentReference

        var id: String { documentReference.documentIdentity }
        var fileURL: URL { documentReference.url }
        var title: String {
            let name = fileURL.lastPathComponent
            return name.isEmpty ? fileURL.path : name
        }
    }

    struct SourceSelection: Equatable {
        let line: Int
        let column: Int?

        init(line: Int, column: Int?) {
            self.line = max(1, line)
            if let column {
                self.column = max(1, column)
            } else {
                self.column = nil
            }
        }
    }

    struct PendingSourceSelection: Equatable {
        let documentID: String
        let selection: SourceSelection
    }

    enum MarkupViewMode: String, CaseIterable, Hashable {
        case rich
        case source
        /// Full-TeX compiled PDF preview (LaTeX only).
        case compiled
    }

    @Published var fileURL: URL?
    @Published var currentDocumentID: String?
    @Published var rawContent = ""
    @Published var hasUnsavedChanges = false
    @Published var hasUnsavedTextChanges = false
    @Published var hasUnsavedImageEdits = false
    @Published var editorTabs: [EditorTab] = []
    @Published var activeEditorTabID: String?
    @Published var documentType: DocumentType = .none
    @Published var imageFileURL: URL?
    @Published var pdfFileURL: URL?
    @Published var officeFileURL: URL?
    @Published var unsupportedFileMessage: String?
    @Published var errorMessage: String?
    @Published var workerStatus: PaneWorkerStatus = .ready
    @Published var codeLanguageKind: CodeLanguageKind?
    @Published var markupViewModeByDocumentID: [String: MarkupViewMode] = [:]
    @Published var pendingSourceSelection: PendingSourceSelection?
    /// Pending LaTeX snippet to insert at the source editor's cursor (math palette).
    @Published var latexInsertionRequest: EditorInsertionRequest?

    var lastSavedContent = ""
    var lastSaveDate = Date.distantPast
    var openRequestID = UUID()
    var openFileTask: Task<Void, Never>?
    var gitDiffTask: Task<Void, Never>?
    var displayTitleOverride: String?
    var materializedPreviewURL: URL?
    let worker: any PaneWorkerExecuting
    let bufferStore: DocumentBufferStore
    private(set) var autosave: AutosaveScheduler
    /// Optional remote file content provider. When set, file reads/writes use this instead of the local worker.
    var fileContentProvider: (any FileContentProviding)?

    enum DocumentType: Hashable {
        case none
        case markdown
        case plainText
        case python
        case json
        case r
        case html
        /// F050: Jupyter notebook (`.ipynb`) — rendered by a dedicated editor
        /// surface backed by a locally-spawned Jupyter server, not the text buffer.
        case notebook
        /// F052: Excalidraw whiteboard (`.excalidraw`) — a text-backed JSON
        /// document edited through an offline Excalidraw canvas in a WKWebView.
        /// The buffer holds the scene JSON, so it autosaves like any text file.
        case whiteboard
        /// LaTeX document (`.tex`/`.latex`/`.ltx`) — a text-backed source file
        /// edited in a split source + live KaTeX-rendered math preview. The
        /// buffer holds the raw LaTeX, so it autosaves like any text file.
        case latex
        /// Typst document (`.typ`) — text-backed; edited in source with a
        /// rendered PDF preview (`typst compile`).
        case typst
        /// AsciiDoc document (`.adoc`/`.asciidoc`) — text-backed; edited in
        /// source with a rendered HTML preview (`asciidoctor`).
        case asciidoc
        /// Graphviz diagram (`.dot`/`.gv`) — text-backed; edited in source with
        /// a rendered PDF preview (`dot -Tpdf`).
        case diagram
        case image
        case pdf
        case office
        case gitDiff
        case unsupported
    }

    var title: String {
        displayTitleOverride ?? fileURL?.lastPathComponent ?? "No File Selected"
    }

    var canEditCurrentDocument: Bool {
        fileURL != nil && isEditableDocumentType(documentType)
    }

    var plainTextEditorLanguage: (any LanguageDefinition)? {
        guard documentType == .plainText,
              let codeLanguageKind else {
            return nil
        }
        return codeLanguageKind.editorLanguage
    }

    private var fileChangeObserver: Any?
    private var activeBufferStateCancellable: AnyCancellable?
    private var observedBufferID: String?

    /// F051: polls the open *remote* file for external content changes (the
    /// remote FS can't push FSEvents and `inotifywait` isn't assumed present).
    private var remoteReloadPollTask: Task<Void, Never>?
    private var lastRemoteModificationToken: String?
    private var fileURLPollingCancellable: AnyCancellable?
    private let remoteReloadPollInterval: UInt64 = 4_000_000_000

    init(worker: any PaneWorkerExecuting, bufferStore: DocumentBufferStore) {
        self.worker = worker
        self.bufferStore = bufferStore
        self.autosave = AutosaveScheduler { _, _ in }
        self.autosave = AutosaveScheduler { [weak self] url, token in
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
        fileChangeObserver = NotificationCenter.default.addObserver(
            forName: .fileSystemContentsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let paths = notification.userInfo?["changedPaths"] as? Set<String> else { return }
            MainActor.assumeIsolated {
                self?.reloadIfFileChanged(changedPaths: paths)
            }
        }
        fileURLPollingCancellable = $fileURL
            .removeDuplicates()
            .sink { [weak self] url in
                MainActor.assumeIsolated { self?.restartRemoteReloadPolling(for: url) }
            }
    }

    deinit {
        if let fileChangeObserver { NotificationCenter.default.removeObserver(fileChangeObserver) }
        MainActor.assumeIsolated {
            autosave.cancelAll()
        }
        openFileTask?.cancel()
        gitDiffTask?.cancel()
        remoteReloadPollTask?.cancel()
        if let materializedPreviewURL {
            try? FileManager.default.removeItem(at: materializedPreviewURL)
        }
    }

    /// Reload the current file if it was changed externally.
    func reloadIfFileChanged(changedPaths: Set<String>) {
        guard let fileURL, isEditableDocumentType(documentType) else { return }
        let filePath = fileURL.standardizedFileURL.path
        let parentPath = fileURL.deletingLastPathComponent().standardizedFileURL.path
        guard changedPaths.contains(filePath) || changedPaths.contains(parentPath) else { return }
        guard Date().timeIntervalSince(lastSaveDate) > 1.0 else { return }
        // If buffer is clean, reload from disk. If dirty/saving, preserve user edits (F039-R07).
        if let buffer = activeBuffer, !buffer.isDirty, !buffer.isSaving, !buffer.isLoading {
            reloadExternalEditableFile()
        }
    }

    /// F051: (re)starts polling the open file's remote modification token. Only
    /// runs for remote (SFTP) providers; local files rely on FSEvents. The first
    /// sample establishes a baseline, then a changed token triggers a reload
    /// (when the buffer is clean), reusing the same path as external-change reload.
    private func restartRemoteReloadPolling(for url: URL?) {
        remoteReloadPollTask?.cancel()
        remoteReloadPollTask = nil
        lastRemoteModificationToken = nil
        guard let url,
              let provider = fileContentProvider,
              provider.requiresMaterializedLocalPreview else { return }
        let path = url.path
        let interval = remoteReloadPollInterval
        remoteReloadPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                guard let token = try? await provider.modificationToken(at: path) else { continue }
                await MainActor.run { [weak self] in
                    guard let self, self.fileURL?.path == path else { return }
                    let previous = self.lastRemoteModificationToken
                    self.lastRemoteModificationToken = token
                    if let previous, previous != token {
                        self.reloadOpenRemoteFileIfClean()
                    }
                }
            }
        }
    }

    private func reloadOpenRemoteFileIfClean() {
        guard isEditableDocumentType(documentType) else { return }
        guard Date().timeIntervalSince(lastSaveDate) > 1.0 else { return }
        if let buffer = activeBuffer, !buffer.isDirty, !buffer.isSaving, !buffer.isLoading {
            reloadExternalEditableFile()
        }
    }

    func observeActiveBuffer(_ buffer: DocumentBuffer?) {
        guard observedBufferID != buffer?.id else { return }
        activeBufferStateCancellable?.cancel()
        activeBufferStateCancellable = nil
        observedBufferID = buffer?.id

        guard let buffer else { return }
        syncPublishedState(from: buffer.state, for: buffer.id)
        activeBufferStateCancellable = buffer.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    self?.syncPublishedState(from: state, for: buffer.id)
                }
            }
    }

    private func syncPublishedState(from state: BufferState, for bufferID: String) {
        guard currentDocumentID == bufferID else { return }
        switch state {
        case .clean(let content):
            rawContent = content
            lastSavedContent = content
            hasUnsavedTextChanges = false
        case .dirty(let content, _):
            rawContent = content
            hasUnsavedTextChanges = true
        case .saving(let content, _, _):
            rawContent = content
            hasUnsavedTextChanges = true
        case .loading:
            break
        case .failed:
            hasUnsavedTextChanges = false
        }
        refreshUnsavedChangesFlag()
        objectWillChange.send()
    }

    /// F052: best-effort synchronous flush of the active dirty buffer to `url`,
    /// used before a file move so the last buffered edits aren't lost. Local
    /// files only; remote files autosave through their content provider.
    func flushUnsavedEdits(forFileURL url: URL) {
        guard fileContentProvider == nil,
              fileURL?.standardizedFileURL == url.standardizedFileURL,
              let buffer = activeBuffer, buffer.isDirty else { return }
        try? Data(buffer.displayContent.utf8).write(to: url, options: .atomic)
    }

    func retargetOpenDocuments(from oldURL: URL, to newURL: URL) {
        func map(_ candidate: URL?) -> URL? {
            guard let candidate else { return nil }
            return Self.mapFileSystemLocation(candidate, from: oldURL, to: newURL)
        }

        fileURL = map(fileURL) ?? fileURL
        imageFileURL = map(imageFileURL) ?? imageFileURL
        pdfFileURL = map(pdfFileURL) ?? pdfFileURL
        officeFileURL = map(officeFileURL) ?? officeFileURL

        editorTabs = editorTabs.map { tab in
            guard let mappedURL = map(tab.fileURL) else { return tab }
            return EditorTab(documentReference: tab.documentReference.replacingURL(mappedURL))
        }

        if let currentDocumentID,
           let activeTab = editorTabs.first(where: { $0.id == currentDocumentID }) {
            self.currentDocumentID = activeTab.id
        } else if let fileURL {
            let existingProjectIdentifier = self.currentDocumentID.flatMap(Self.projectIdentifier(fromDocumentID:))
            self.currentDocumentID = map(fileURL).map {
                FileDocumentReference(url: $0, projectIdentifier: existingProjectIdentifier).documentIdentity
            } ?? currentDocumentID
        }

        if let currentActiveEditorTabID = activeEditorTabID,
           let mappedTab = editorTabs.first(where: { $0.id == currentActiveEditorTabID }) {
            activeEditorTabID = mappedTab.id
        }

        markupViewModeByDocumentID = Dictionary(
            uniqueKeysWithValues: markupViewModeByDocumentID.map { key, value in
                if let tab = editorTabs.first(where: { $0.id == key }) {
                    return (tab.id, value)
                }
                let projectIdentifier = Self.projectIdentifier(fromDocumentID: key)
                let filePath = Self.filePath(fromDocumentID: key)
                let mappedURL = map(URL(fileURLWithPath: filePath))
                let mappedID = mappedURL.map {
                    FileDocumentReference(url: $0, projectIdentifier: projectIdentifier).documentIdentity
                } ?? key
                return (mappedID, value)
            }
        )

        if let pendingSourceSelection,
           let tab = editorTabs.first(where: { $0.id == pendingSourceSelection.documentID }) {
            self.pendingSourceSelection = PendingSourceSelection(
                documentID: tab.id,
                selection: pendingSourceSelection.selection
            )
        }
    }

    private static func mapFileSystemLocation(_ candidate: URL, from oldURL: URL, to newURL: URL) -> URL? {
        let normalizedCandidate = candidate.standardizedFileURL
        let normalizedOldURL = oldURL.standardizedFileURL
        let normalizedNewURL = newURL.standardizedFileURL

        if normalizedCandidate == normalizedOldURL {
            return normalizedNewURL
        }

        let oldPath = normalizedOldURL.path.hasSuffix("/") ? normalizedOldURL.path : normalizedOldURL.path + "/"
        let candidatePath = normalizedCandidate.path
        guard candidatePath.hasPrefix(oldPath) else { return nil }

        let relativeSuffix = String(candidatePath.dropFirst(oldPath.count))
        return normalizedNewURL.appendingPathComponent(relativeSuffix)
    }

    private static func projectIdentifier(fromDocumentID documentID: String) -> String? {
        let components = documentID.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }
        return components[0]
    }

    private static func filePath(fromDocumentID documentID: String) -> String {
        let components = documentID.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return documentID }
        return components[1]
    }

    func consumePendingSourceSelection(for documentID: String?) {
        guard pendingSourceSelection?.documentID == documentID else { return }
        pendingSourceSelection = nil
    }
}

enum DocumentError: LocalizedError {
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "File encoding is not supported."
        }
    }
}
