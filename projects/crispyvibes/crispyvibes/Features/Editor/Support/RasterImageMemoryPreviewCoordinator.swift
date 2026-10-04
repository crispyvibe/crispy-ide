import AppKit

extension RasterImageMemoryPreview {
  @MainActor
  final class Coordinator: NSObject, RasterImageFileSessionControlling,
    RasterImageViewportControlling
  {
    weak var canvas: EditableRasterImageCanvasView?
    weak var scrollView: NSScrollView?
    weak var viewModel: RasterImageEditorViewModel?
    var onRevisionChange: ((RasterImageEditSession, Int, Bool) -> Void)?
    var onCanvasReady: ((NSResponder) -> Void)?
    private weak var installedImage: CGImage?
    private weak var installedViewModel: RasterImageEditorViewModel?
    private var boundsObserver: NSObjectProtocol?
    private var installationGeneration: UInt64 = 0
    private var installationTask: Task<Void, Never>?
    var hasReceivedLayout = false
    var isApplyingInitialFit = false
    var isInitialFitPending = false

    deinit {
      installationTask?.cancel()
      if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    func prepare(canvas: EditableRasterImageCanvasView, scrollView: NSScrollView) {
      self.canvas = canvas
      self.scrollView = scrollView
      if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
      boundsObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: scrollView.contentView,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.viewportDidLayout() }
      }
      scrollView.contentView.postsBoundsChangedNotifications = true
    }

    func scheduleInstallation(
      image: CGImage,
      canvasSize: CGSize,
      viewModel: RasterImageEditorViewModel,
      onRevisionChange: @escaping (RasterImageEditSession, Int, Bool) -> Void,
      onCanvasReady: @escaping (NSResponder) -> Void
    ) {
      self.onRevisionChange = onRevisionChange
      self.onCanvasReady = onCanvasReady
      guard installedImage !== image || installedViewModel !== viewModel || canvas?.session == nil
      else {
        return
      }
      installationGeneration &+= 1
      let generation = installationGeneration
      installationTask?.cancel()
      installationTask = Task { @MainActor [weak self, weak viewModel] in
        await Task.yield()
        guard let self, let viewModel, !Task.isCancelled,
          generation == self.installationGeneration,
          let canvas = self.canvas
        else { return }
        self.viewModel = viewModel
        self.installedViewModel = viewModel
        viewModel.attach(canvas: canvas, fileSession: self, viewport: self)
        canvas.onCommand = { [weak viewModel] command in
          viewModel?.handleCanvasCommand(command)
        }
        canvas.setStateObserver { [weak self, weak viewModel] state in
          guard let self else { return }
          viewModel?.canvasStateDidChange(state)
          self.publishRevision()
        }
        self.installImageIfNeeded(image, canvasSize: canvasSize)
        guard !Task.isCancelled, generation == self.installationGeneration else { return }
        self.onCanvasReady?(canvas)
        self.installationTask = nil
      }
    }

    func shutdown() {
      installationGeneration &+= 1
      installationTask?.cancel()
      installationTask = nil
      if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
      boundsObserver = nil
      canvas?.onCommand = nil
      canvas?.setStateObserver(nil)
      viewModel = nil
      installedViewModel = nil
      installedImage = nil
      hasReceivedLayout = false
      isApplyingInitialFit = false
      isInitialFitPending = false
      onRevisionChange = nil
      onCanvasReady = nil
    }

    private func installImageIfNeeded(_ image: CGImage, canvasSize: CGSize) {
      guard installedImage !== image || canvas?.session == nil else { return }
      installedImage = image
      let session = RasterImageEditSession.inMemory(
        image,
        canvasSize: canvasSize,
        renderer: viewModel?.services.renderer ?? RasterImageRenderer()
      )
      canvas?.session = session
      markInitialFitPending()
      viewModel?.didLoadImage(rendered: true, saveBlockReason: nil, isNewFile: true)
      _ = applyPendingInitialFitIfPossible()
      publishRevision()
    }

    func reloadFromDisk() {}
    func markFileStateCurrent() {}
    func hasExternalChangeSinceLoad() -> Bool { false }
    private func publishRevision() {
      guard let session = canvas?.session else { return }
      onRevisionChange?(session, session.revision, session.isDirty)
    }
  }
}
