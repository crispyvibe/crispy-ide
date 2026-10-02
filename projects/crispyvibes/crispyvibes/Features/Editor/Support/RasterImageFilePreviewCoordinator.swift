import AppKit
import Foundation

/// Identity of an on-disk image (size, modification date, and file-system resource identifier),
/// used to detect external modification or replacement.
struct RasterImageFileState: Equatable {
    let fileSize: Int64?
    let modificationDate: Date?
    let resourceIdentifier: NSObject?

    static func capture(for fileURL: URL) -> RasterImageFileState? {
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        // URL caches resource values per instance; always read fresh identity from disk.
        var freshURL = fileURL
        freshURL.removeAllCachedResourceValues()
        guard let values = try? freshURL.resourceValues(forKeys: resourceKeys) else {
            return nil
        }
        return RasterImageFileState(
            fileSize: values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate,
            resourceIdentifier: values.fileResourceIdentifier as? NSObject
        )
    }

    static func == (lhs: RasterImageFileState, rhs: RasterImageFileState) -> Bool {
        lhs.fileSize == rhs.fileSize &&
            lhs.modificationDate == rhs.modificationDate &&
            lhs.resourceIdentifier?.isEqual(rhs.resourceIdentifier) ?? (rhs.resourceIdentifier == nil)
    }
}

/// Loads (off the main thread), observes, and frames the raster preview; bridges AppKit state
/// to the editor view model.
///
/// External changes are never applied over pending edits: the view model is told about the
/// conflict and the user chooses Reload from Disk or Keep My Edits.
@MainActor
final class RasterImageFilePreviewCoordinator: RasterImageFileSessionControlling {
    struct ViewportContext {
        let magnification: CGFloat
        let horizontalFraction: CGFloat
        let verticalFraction: CGFloat
    }

    private(set) weak var canvasView: EditableRasterImageCanvasView?
    private(set) weak var scrollView: NSScrollView?
    private(set) weak var placeholderLabel: NSTextField?
    weak var viewModel: RasterImageEditorViewModel?
    var viewModelForViewport: RasterImageEditorViewModel? { viewModel }
    var onDirtyStateChange: ((Bool) -> Void)?

    let services: RasterImageEditorServices
    private let decodeQueue = DispatchQueue(label: "com.crispyvibe.raster-image.decode", qos: .userInitiated)
    private var currentFileURL: URL?
    private var lastLoadedPath: String?
    private var lastLoadedFileState: RasterImageFileState?
    private var deferredConflictFileState: RasterImageFileState?
    var lastDecodeWasFullResolution = false
    var loadGeneration = 0
    var isLoading = false
    nonisolated(unsafe) var boundsObserver: NSObjectProtocol?
    nonisolated(unsafe) var fileObservationSource: DispatchSourceFileSystemObject?
    var observedPath: String?

    init(services: RasterImageEditorServices) {
        self.services = services
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        fileObservationSource?.cancel()
    }

    func install(
        canvasView: EditableRasterImageCanvasView,
        scrollView: NSScrollView,
        placeholderLabel: NSTextField,
        viewModel: RasterImageEditorViewModel,
        onDirtyStateChange: @escaping (Bool) -> Void
    ) {
        self.canvasView = canvasView
        self.scrollView = scrollView
        self.placeholderLabel = placeholderLabel
        self.viewModel = viewModel
        self.onDirtyStateChange = onDirtyStateChange
        viewModel.attach(canvas: canvasView, fileSession: self, viewport: self)

        canvasView.setDirtyStateObserver { [weak self] hasUnsavedEdits in
            DispatchQueue.main.async { [weak self] in
                self?.onDirtyStateChange?(hasUnsavedEdits)
            }
        }
        canvasView.setStateObserver { [weak viewModel] state in
            DispatchQueue.main.async { [weak viewModel] in
                viewModel?.canvasStateDidChange(state)
            }
        }
        canvasView.onCommand = { [weak viewModel] command in
            viewModel?.handleCanvasCommand(command)
        }
        installBoundsObserverIfNeeded()
        applyVisibility()
    }

    /// Ensures `fileURL` is loaded and observed; safe to call on every SwiftUI update.
    func present(_ fileURL: URL) {
        currentFileURL = fileURL
        configureFileObservation(for: fileURL)
        reloadImageIfNeeded(from: fileURL, force: false)
    }

    // MARK: - RasterImageFileSessionControlling

    func reloadFromDisk() {
        guard let currentFileURL else { return }
        reloadImageIfNeeded(from: currentFileURL, force: true)
    }

    func markFileStateCurrent() {
        guard let currentFileURL else { return }
        lastLoadedPath = currentFileURL.path
        lastLoadedFileState = RasterImageFileState.capture(for: currentFileURL)
        deferredConflictFileState = nil
    }

    func hasExternalChangeSinceLoad() -> Bool {
        guard let currentFileURL else { return false }
        return RasterImageFileState.capture(for: currentFileURL) != lastLoadedFileState
    }

    func resetScrollPosition() {
        guard let scrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refreshCenteringInsets()
    }

    // MARK: - Loading

    func handleBackingPropertiesChanged() {
        guard let currentFileURL, let canvasView else { return }
        let hasWork = canvasView.hasPendingEdits || canvasView.cropSelection != nil
        if !hasWork, !lastDecodeWasFullResolution {
            reloadImageIfNeeded(from: currentFileURL, force: true)
        }
        refreshCenteringInsets()
    }

    func reloadImageIfNeeded(from fileURL: URL, force: Bool) {
        guard let canvasView, let scrollView else { return }

        let fileState = RasterImageFileState.capture(for: fileURL)
        let isNewPath = lastLoadedPath != fileURL.path
        let hasSamePathContentChange = !isNewPath && fileState != lastLoadedFileState
        guard force || isNewPath || hasSamePathContentChange else { return }
        // Our own in-flight save writes the file; its completion records the new state.
        if !force, !isNewPath, viewModel?.isSaving == true { return }

        let hasWork = canvasView.hasPendingEdits || canvasView.cropSelection != nil
        if !force, !isNewPath, hasWork {
            guard fileState != deferredConflictFileState else { return }
            deferredConflictFileState = fileState
            notifyViewModel { $0.didDetectExternalChangeWithPendingEdits() }
            return
        }

        lastLoadedPath = fileURL.path
        lastLoadedFileState = fileState
        deferredConflictFileState = nil
        loadGeneration += 1
        let generation = loadGeneration
        let viewportContext = isNewPath ? nil : captureViewportContext()
        let maxPixelSize = preferredProxyPixelSize(viewportSize: scrollView.contentSize, magnification: scrollView.magnification)
        let decoder = services.decoder
        if isNewPath {
            canvasView.session = nil
        }
        isLoading = true
        applyVisibility()

        decodeQueue.async { [weak self] in
            let decoded = decoder.decode(contentsOf: fileURL, maxPixelSize: maxPixelSize)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.install(decoded, fileURL: fileURL, generation: generation, isNewPath: isNewPath, viewportContext: viewportContext)
                }
            }
        }
    }

    /// Defers view-model publishes out of the SwiftUI update pass.
    private func notifyViewModel(_ body: @escaping (RasterImageEditorViewModel) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let viewModel = self?.viewModel else { return }
            body(viewModel)
        }
    }

    private func preferredProxyPixelSize(viewportSize: CGSize, magnification: CGFloat) -> Int {
        let longestViewportEdge = max(max(viewportSize.width, viewportSize.height), 1)
        let backingScaleFactor = scrollView?.crispyvibesBackingScaleFactor() ?? 1
        let requestedSize = Int(ceil(longestViewportEdge * backingScaleFactor * max(1, magnification) * 1.8))
        return min(max(requestedSize, 1024), 4096)
    }

    func applyVisibility() {
        guard let canvasView, let scrollView, let placeholderLabel else { return }
        let canRender = canvasView.hasRenderableImage
        scrollView.isHidden = !canRender
        placeholderLabel.isHidden = canRender
        placeholderLabel.stringValue = isLoading ? AppStrings.ImageEditor.statusLoading : AppStrings.ImageEditor.renderFailedPlaceholder
        placeholderLabel.setAccessibilityIdentifier(isLoading ? "editor.preview.image.loading" : "editor.preview.image.failed")
    }
}
