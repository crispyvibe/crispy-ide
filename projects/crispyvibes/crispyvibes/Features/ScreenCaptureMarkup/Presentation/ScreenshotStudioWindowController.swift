import AppKit
import SwiftUI

/// Owns one Screenshot Studio panel and focuses it on repeated presentation requests.
@MainActor
final class ScreenshotStudioWindowController: NSObject, NSWindowDelegate {
    private let registry: ScreenCaptureSurfaceRegistry
    private let announcer: any RasterImageAccessibilityAnnouncing
    private let applicationActivator: any ScreenCaptureApplicationActivating
    private let windowFocuser: any ScreenCaptureWindowFocusing
    private(set) var panel: NSPanel?
    private(set) var viewModel: ScreenshotStudioViewModel?
    private var presentedItemID: UUID?

    init(
        registry: ScreenCaptureSurfaceRegistry,
        announcer: any RasterImageAccessibilityAnnouncing,
        applicationActivator: any ScreenCaptureApplicationActivating,
        windowFocuser: any ScreenCaptureWindowFocusing
    ) {
        self.registry = registry
        self.announcer = announcer
        self.applicationActivator = applicationActivator
        self.windowFocuser = windowFocuser
        super.init()
    }

    /// Creates the sole panel, or focuses the existing panel without revealing IDE windows.
    func presentOrFocus(viewModel: ScreenshotStudioViewModel) {
        if let panel {
            if presentedItemID != viewModel.currentItem?.id {
                applyPresentation(to: panel, viewModel: self.viewModel ?? viewModel)
            }
            presentedItemID = self.viewModel?.currentItem?.id
            focus()
            return
        }
        self.viewModel = viewModel
        presentedItemID = viewModel.currentItem?.id
        viewModel.onClose = { [weak self] in self?.dismiss() }
        let presentation = ScreenshotStudioPresentation.resolve(
            canvasSize: viewModel.currentItem?.canvasSize ?? CGSize(width: 800, height: 500),
            visibleFrame: viewModel.placement.visibleFrame
        )
        let panel = NSPanel(
            contentRect: presentation.frame,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = AppStrings.ScreenCapture.studioTitle
        panel.minSize = presentation.minimumSize
        panel.maxSize = presentation.maximumSize
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: ScreenshotStudioView(viewModel: viewModel) { [weak self, weak panel] responder in
                guard let self, let panel, self.panel === panel else { return }
                self.windowFocuser.makeFirstResponder(responder, in: panel)
                self.announcer.announce(AppStrings.ScreenCapture.studioTitle)
            }
        )
        self.panel = panel
        panel.delegate = self
        registry.register(panel)
        focus()
    }

    /// Focuses only the owned utility panel after app activation.
    func focus() {
        guard let panel else { return }
        applicationActivator.activateApplication()
        windowFocuser.makeKeyAndOrderFront(panel)
        windowFocuser.orderFrontRegardless(panel)
    }

    /// Shuts down Studio and closes its sole panel.
    func dismiss() {
        guard let panel else {
            releaseViewModel()
            return
        }
        self.panel = nil
        panel.delegate = nil
        registry.unregister(panel)
        releaseViewModel()
        panel.close()
    }

    /// Native titlebar close performs the same cleanup as an explicit Close action.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === panel else { return }
        panel = nil
        registry.unregister(closing)
        releaseViewModel()
    }

    private func applyPresentation(to panel: NSPanel, viewModel: ScreenshotStudioViewModel) {
        let presentation = ScreenshotStudioPresentation.resolve(
            canvasSize: viewModel.currentItem?.canvasSize ?? CGSize(width: 800, height: 500),
            visibleFrame: viewModel.placement.visibleFrame
        )
        panel.minSize = presentation.minimumSize
        panel.maxSize = presentation.maximumSize
        panel.setFrame(presentation.frame, display: true)
    }

    private func releaseViewModel() {
        presentedItemID = nil
        viewModel?.shutdown()
        viewModel = nil
    }
}
