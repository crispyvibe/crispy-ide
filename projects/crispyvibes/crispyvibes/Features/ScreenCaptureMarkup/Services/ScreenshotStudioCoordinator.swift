import Foundation

/// Installs each successful acquisition into the sole Screenshot Studio panel before delivery starts.
@MainActor
final class ScreenshotStudioCoordinator: ScreenCaptureStudioRouting {
    typealias ViewModelFactory = @MainActor (ScreenCapturePlacementContext) -> ScreenshotStudioViewModel

    private let windowController: ScreenshotStudioWindowController
    private let historyStore: ScreenCaptureHistoryStore
    private let viewModelFactory: ViewModelFactory

    init(
        windowController: ScreenshotStudioWindowController,
        historyStore: ScreenCaptureHistoryStore,
        viewModelFactory: @escaping ViewModelFactory
    ) {
        self.windowController = windowController
        self.historyStore = historyStore
        self.viewModelFactory = viewModelFactory
    }

    func present(_ capture: AcquiredScreenCapture) {
        let viewModel = windowController.viewModel ?? viewModelFactory(capture.image.placement)
        viewModel.installNewCapture(capture)
        windowController.presentOrFocus(viewModel: viewModel)
        viewModel.deliverCurrentCapture()
    }

    func clearHistory() {
        if let viewModel = windowController.viewModel {
            viewModel.clearHistory()
        } else {
            historyStore.clear()
        }
    }

    func shutdown() {
        windowController.dismiss()
    }
}
