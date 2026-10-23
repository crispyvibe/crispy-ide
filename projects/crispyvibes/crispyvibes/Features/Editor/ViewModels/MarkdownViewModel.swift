import Combine
import Foundation

/// Preferred destination for HTTP(S) links activated from rendered Markdown.
enum MarkdownWebLinkPreference: String, CaseIterable, Identifiable, Sendable {
    case ask
    case crispy
    case defaultBrowser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask:
            return AppStrings.Editor.webLinkPreferenceAsk
        case .crispy:
            return AppStrings.Editor.webLinkPreferenceCrispy
        case .defaultBrowser:
            return AppStrings.Editor.webLinkPreferenceDefaultBrowser
        }
    }
}

/// Target category produced by the rendered Markdown runtime.
enum MarkdownLinkTargetKind: String, Equatable, Sendable {
    case localFile
    case web
    case external
}

/// User action selected for a rendered Markdown link.
enum MarkdownLinkOpenAction: String, Equatable, Sendable {
    case openInCrispy
    case openInDefaultBrowser
}

/// Typed action emitted by the rendered Markdown runtime.
struct MarkdownLinkActionRequest: Equatable, Sendable {
    let action: MarkdownLinkOpenAction
    let targetKind: MarkdownLinkTargetKind
    let href: String
    let resolvedURL: String
    let fragment: String?
}

/// One-shot request to scroll a newly opened rich Markdown document to a heading.
struct MarkdownRichNavigationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let documentID: String
    let fragment: String
    let recordsHistory: Bool

    init(
        id: UUID = UUID(),
        documentID: String,
        fragment: String,
        recordsHistory: Bool = false
    ) {
        self.id = id
        self.documentID = documentID
        self.fragment = fragment
        self.recordsHistory = recordsHistory
    }
}

/// Direction for rendered Markdown history navigation.
enum MarkdownNavigationDirection: String, Equatable, Sendable {
    case back
    case forward
}

/// A rendered Markdown scroll offset persisted across presentation remounts.
struct MarkdownScrollPosition: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
    }
}

/// Current same-document navigation state reported by the Markdown runtime.
struct MarkdownNavigationState: Codable, Equatable, Sendable {
    static let maximumHistoryCount = 100

    let documentID: String
    let canNavigateBack: Bool
    let canNavigateForward: Bool
    let backScrollPositions: [MarkdownScrollPosition]
    let forwardScrollPositions: [MarkdownScrollPosition]

    init(
        documentID: String,
        canNavigateBack: Bool,
        canNavigateForward: Bool,
        backScrollPositions: [MarkdownScrollPosition] = [],
        forwardScrollPositions: [MarkdownScrollPosition] = []
    ) {
        self.documentID = documentID
        self.backScrollPositions = Array(backScrollPositions.suffix(Self.maximumHistoryCount))
        self.forwardScrollPositions = Array(forwardScrollPositions.suffix(Self.maximumHistoryCount))
        self.canNavigateBack = canNavigateBack
        self.canNavigateForward = canNavigateForward
    }

    var hasSavedHistory: Bool {
        !backScrollPositions.isEmpty || !forwardScrollPositions.isEmpty
    }

    static func decodeBridgePayload(documentID: String, body: Any) -> MarkdownNavigationState? {
        guard let payload = body as? [String: Any],
              let canBack = payload["canBack"] as? Bool,
              let canForward = payload["canForward"] as? Bool else { return nil }
        return MarkdownNavigationState(
            documentID: documentID,
            canNavigateBack: canBack,
            canNavigateForward: canForward,
            backScrollPositions: decodePositions(payload["backPositions"]),
            forwardScrollPositions: decodePositions(payload["forwardPositions"])
        )
    }

    private static func decodePositions(_ value: Any?) -> [MarkdownScrollPosition] {
        guard let values = value as? [[String: Any]] else { return [] }
        return values.suffix(maximumHistoryCount).compactMap { value in
            guard let x = (value["x"] as? NSNumber)?.doubleValue,
                  let y = (value["y"] as? NSNumber)?.doubleValue,
                  x.isFinite,
                  y.isFinite else { return nil }
            return MarkdownScrollPosition(x: x, y: y)
        }
    }
}

/// One-shot native request to navigate rendered Markdown history.
struct MarkdownNavigationCommandRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let documentID: String
    let direction: MarkdownNavigationDirection

    init(
        id: UUID = UUID(),
        documentID: String,
        direction: MarkdownNavigationDirection
    ) {
        self.id = id
        self.documentID = documentID
        self.direction = direction
    }
}

/// Injected native destinations for rendered Markdown link actions.
struct MarkdownLinkRouter {
    let openInCrispyBrowser: @MainActor (URL, String?) -> Void
    let openInDefaultBrowser: @MainActor (URL) -> Void

    static let disabled = MarkdownLinkRouter(
        openInCrispyBrowser: { _, _ in },
        openInDefaultBrowser: { _ in }
    )
}

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
    /// Incremented to ask the active raster image editor to save (⌘S).
    @Published var imageSaveRequestToken = 0
    /// Last request consumed by a raster editor; requests are delivered exactly once, even if
    /// the editor mounts after the request was made.
    var handledImageSaveRequestToken = 0
    @Published var pdfFileURL: URL?
    @Published var officeFileURL: URL?
    @Published var unsupportedFileMessage: String?
    @Published var errorMessage: String?
    @Published var workerStatus: PaneWorkerStatus = .ready
    @Published var isOpeningInSystem = false
    @Published var codeLanguageKind: CodeLanguageKind?
    @Published var markupViewModeByDocumentID: [String: MarkupViewMode] = [:]
    @Published var pendingSourceSelection: PendingSourceSelection?
    @Published private(set) var pendingRichNavigationRequest: MarkdownRichNavigationRequest?
    @Published private(set) var renderedNavigationStatesByDocumentID: [String: MarkdownNavigationState] = [:]
    @Published private(set) var renderedNavigationCommandRequest: MarkdownNavigationCommandRequest?
    /// Pending LaTeX snippet to insert at the source editor's cursor (math palette).
    @Published var latexInsertionRequest: EditorInsertionRequest?

    var lastSavedContent = ""
    var lastSaveDate = Date.distantPast
    var openRequestID = UUID()
    var openFileTask: Task<Void, Never>?
    var gitDiffTask: Task<Void, Never>?
    var externalOpenTask: Task<Void, Never>?
    var externalOpenBufferID: String?
    var displayTitleOverride: String?
    var materializedPreviewURL: URL?
    let worker: any PaneWorkerExecuting
    let bufferStore: DocumentBufferStore
    let markdownLinkRouter: MarkdownLinkRouter
    let externalFileOpener: (any ExternalFileOpening)?
    private(set) var autosave: AutosaveScheduler
    /// Optional remote file content provider. When set, file reads/writes use this instead of the local worker.
    var fileContentProvider: (any FileContentProviding)?
    /// Decoder/renderer/export services handed to raster image editors (F009).
    let rasterImageEditorServices: RasterImageEditorServices
    /// Installed by the owning editor group so linked files participate in its
    /// visible tab list, provider registry, comments context, and persistence.
    var linkedFileOpenHandler: ((URL, FileDocumentReference) -> Void)?
    /// Installed by the owning group so rendered keyboard navigation can fall
    /// back to cross-file history when same-document history is exhausted.
    var renderedNavigationFallbackHandler: ((MarkdownNavigationDirection) -> Void)?

    var canNavigateBackInRenderedDocument: Bool {
        renderedNavigationState(for: currentDocumentID)?.canNavigateBack == true
    }

    var canNavigateForwardInRenderedDocument: Bool {
        renderedNavigationState(for: currentDocumentID)?.canNavigateForward == true
    }

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
    /// F009: remote version the staged image preview was read at; image saves require it to match.
    var remoteImageBaselineToken: String?
    private var fileURLPollingCancellable: AnyCancellable?
    private let remoteReloadPollInterval: UInt64 = 4_000_000_000

    init(
        worker: any PaneWorkerExecuting,
        bufferStore: DocumentBufferStore,
        markdownLinkRouter: MarkdownLinkRouter = .disabled,
        externalFileOpener: (any ExternalFileOpening)? = nil,
        rasterImageEditorServices: RasterImageEditorServices = .makeDefault()
    ) {
        self.rasterImageEditorServices = rasterImageEditorServices
        self.worker = worker
        self.bufferStore = bufferStore
        self.markdownLinkRouter = markdownLinkRouter
        self.externalFileOpener = externalFileOpener
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
        externalOpenTask?.cancel()
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
        if documentType == .image {
            refreshStagedRemoteImage()
            return
        }
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

    func setPendingRichNavigationRequest(_ request: MarkdownRichNavigationRequest?) {
        pendingRichNavigationRequest = request
    }

    func updateRenderedNavigationState(_ state: MarkdownNavigationState) {
        guard state.documentID == currentDocumentID else { return }
        renderedNavigationStatesByDocumentID[state.documentID] = state
    }

    func renderedNavigationState(for documentID: String?) -> MarkdownNavigationState? {
        guard let documentID else { return nil }
        return renderedNavigationStatesByDocumentID[documentID]
    }

    func requestRenderedNavigation(_ direction: MarkdownNavigationDirection) {
        guard let currentDocumentID else { return }
        renderedNavigationCommandRequest = MarkdownNavigationCommandRequest(
            documentID: currentDocumentID,
            direction: direction
        )
    }

    func renderedNavigationCommand(for documentID: String?) -> MarkdownNavigationCommandRequest? {
        guard renderedNavigationCommandRequest?.documentID == documentID else { return nil }
        return renderedNavigationCommandRequest
    }

    @discardableResult
    func claimRenderedNavigationCommand(id: UUID) -> Bool {
        guard renderedNavigationCommandRequest?.id == id else { return false }
        renderedNavigationCommandRequest = nil
        return true
    }

    func clearRenderedNavigation(for documentID: String) {
        renderedNavigationStatesByDocumentID.removeValue(forKey: documentID)
        if renderedNavigationCommandRequest?.documentID == documentID {
            renderedNavigationCommandRequest = nil
        }
        if pendingRichNavigationRequest?.documentID == documentID {
            pendingRichNavigationRequest = nil
        }
    }

    func handleRenderedNavigationFallback(_ direction: MarkdownNavigationDirection) {
        renderedNavigationFallbackHandler?(direction)
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
        guard (fileContentProvider == nil || fileContentProvider is LocalFileContentProvider),
              fileURL?.standardizedFileURL == url.standardizedFileURL,
              let buffer = activeBuffer, buffer.isDirty else { return }
        try? Data(buffer.displayContent.utf8).write(to: url, options: .atomic)
    }

    func retargetOpenDocuments(from oldURL: URL, to newURL: URL) {
        let normalizedOldURL = oldURL.standardizedFileURL
        let normalizedNewURL = newURL.standardizedFileURL
        let knownDocumentIDs = Set(
            editorTabs.map(\.id)
                + Array(markupViewModeByDocumentID.keys)
                + Array(renderedNavigationStatesByDocumentID.keys)
                + [
                    currentDocumentID,
                    activeEditorTabID,
                    pendingRichNavigationRequest?.documentID,
                    renderedNavigationCommandRequest?.documentID,
                    pendingSourceSelection?.documentID
                ].compactMap { $0 }
        )
        let identityMappings = knownDocumentIDs.reduce(into: [String: FileDocumentReference]()) { result, documentID in
            let sourceURL = URL(fileURLWithPath: Self.filePath(fromDocumentID: documentID))
            guard let mappedURL = Self.mapFileSystemLocation(
                sourceURL,
                from: normalizedOldURL,
                to: normalizedNewURL
            ) else { return }
            result[documentID] = FileDocumentReference(
                url: mappedURL,
                projectIdentifier: Self.projectIdentifier(fromDocumentID: documentID)
            )
        }
        let migratedTabs = editorTabs.map { tab in
            EditorTab(documentReference: identityMappings[tab.id] ?? tab.documentReference)
        }
        let migratedFileURL = fileURL.flatMap {
            Self.mapFileSystemLocation($0, from: normalizedOldURL, to: normalizedNewURL)
        } ?? fileURL
        let migratedImageFileURL = imageFileURL.flatMap {
            Self.mapFileSystemLocation($0, from: normalizedOldURL, to: normalizedNewURL)
        } ?? imageFileURL
        let migratedPDFFileURL = pdfFileURL.flatMap {
            Self.mapFileSystemLocation($0, from: normalizedOldURL, to: normalizedNewURL)
        } ?? pdfFileURL
        let migratedOfficeFileURL = officeFileURL.flatMap {
            Self.mapFileSystemLocation($0, from: normalizedOldURL, to: normalizedNewURL)
        } ?? officeFileURL

        migrateOpenDocumentIdentities(
            identityMappings,
            editorTabs: migratedTabs,
            fileURL: migratedFileURL,
            imageFileURL: migratedImageFileURL,
            pdfFileURL: migratedPDFFileURL,
            officeFileURL: migratedOfficeFileURL
        )
    }

    func migrateOpenDocumentIdentities(
        _ identityMappings: [String: FileDocumentReference],
        editorTabs migratedTabs: [EditorTab],
        fileURL migratedFileURL: URL?,
        imageFileURL migratedImageFileURL: URL?,
        pdfFileURL migratedPDFFileURL: URL?,
        officeFileURL migratedOfficeFileURL: URL?
    ) {
        guard !identityMappings.isEmpty else {
            editorTabs = migratedTabs
            fileURL = migratedFileURL
            imageFileURL = migratedImageFileURL
            pdfFileURL = migratedPDFFileURL
            officeFileURL = migratedOfficeFileURL
            return
        }

        for oldID in identityMappings.keys {
            autosave.cancel(for: oldID)
        }
        for (oldID, reference) in identityMappings {
            _ = bufferStore.migrateBuffer(from: oldID, to: reference)
        }

        editorTabs = migratedTabs
        currentDocumentID = currentDocumentID.flatMap {
            identityMappings[$0]?.documentIdentity ?? $0
        }
        activeEditorTabID = activeEditorTabID.flatMap {
            identityMappings[$0]?.documentIdentity ?? $0
        }
        fileURL = migratedFileURL
        imageFileURL = migratedImageFileURL
        pdfFileURL = migratedPDFFileURL
        officeFileURL = migratedOfficeFileURL

        markupViewModeByDocumentID = markupViewModeByDocumentID.reduce(into: [:]) { result, entry in
            result[identityMappings[entry.key]?.documentIdentity ?? entry.key] = entry.value
        }
        renderedNavigationStatesByDocumentID = renderedNavigationStatesByDocumentID.reduce(into: [:]) { result, entry in
            let migratedID = identityMappings[entry.key]?.documentIdentity ?? entry.key
            let state = entry.value
            result[migratedID] = MarkdownNavigationState(
                documentID: migratedID,
                canNavigateBack: state.canNavigateBack,
                canNavigateForward: state.canNavigateForward,
                backScrollPositions: state.backScrollPositions,
                forwardScrollPositions: state.forwardScrollPositions
            )
        }
        if let request = pendingRichNavigationRequest,
           let migratedID = identityMappings[request.documentID]?.documentIdentity {
            pendingRichNavigationRequest = MarkdownRichNavigationRequest(
                id: request.id,
                documentID: migratedID,
                fragment: request.fragment,
                recordsHistory: request.recordsHistory
            )
        }
        if let request = renderedNavigationCommandRequest,
           let migratedID = identityMappings[request.documentID]?.documentIdentity {
            renderedNavigationCommandRequest = MarkdownNavigationCommandRequest(
                id: request.id,
                documentID: migratedID,
                direction: request.direction
            )
        }
        if let selection = pendingSourceSelection,
           let migratedID = identityMappings[selection.documentID]?.documentIdentity {
            pendingSourceSelection = PendingSourceSelection(
                documentID: migratedID,
                selection: selection.selection
            )
        }

        let migratedBuffers = identityMappings.values.compactMap {
            bufferStore.buffer(for: $0.documentIdentity)
        }
        if let currentDocumentID {
            observeActiveBuffer(bufferStore.buffer(for: currentDocumentID))
        }
        for buffer in migratedBuffers where buffer.isDirty {
            autosave.scheduleSave(for: buffer)
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
