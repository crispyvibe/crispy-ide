import AppKit
import SwiftUI

private final class ScreenCaptureOverlayPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// Owns exactly one capture overlay panel per active NSScreen.
@MainActor
final class ScreenCaptureOverlayController: ScreenCaptureSelectionControlling {
  typealias SelectionViewModelFactory =
    @MainActor (
      _ catalog: ScreenCaptureCatalog,
      _ initialMode: CaptureMode,
      _ options: CaptureOptions
    ) -> CaptureSelectionViewModel

  private let surfaceRegistry: ScreenCaptureSurfaceRegistry
  private let selectionViewModelFactory: SelectionViewModelFactory
  private let screenResolver: (CGDirectDisplayID) -> NSScreen?
  private var panels: [CGDirectDisplayID: NSPanel] = [:]
  private var viewModel: CaptureSelectionViewModel?
  private var continuation: CheckedContinuation<CaptureSelectionDescriptor?, Error>?
  private var keyMonitor: Any?

  init(
    surfaceRegistry: ScreenCaptureSurfaceRegistry,
    screenResolver: ((CGDirectDisplayID) -> NSScreen?)? = nil,
    selectionViewModelFactory: @escaping SelectionViewModelFactory
  ) {
    self.surfaceRegistry = surfaceRegistry
    self.screenResolver = screenResolver ?? { displayID in
      NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == displayID
      }
    }
    self.selectionViewModelFactory = selectionViewModelFactory
  }

  func selectTarget(
    from catalog: ScreenCaptureCatalog,
    initialMode: CaptureMode,
    options: CaptureOptions,
    sessionGeneration: UInt64
  ) async throws -> CaptureSelectionDescriptor? {
    dismissSelection()
    let model = selectionViewModelFactory(catalog, initialMode, options)
    viewModel = model
    let panelCount = installPanels(for: catalog, viewModel: model)
    guard panelCount > 0 else {
      dismissSelection()
      throw catalog.displays.isEmpty
        ? ScreenCaptureError.catalogUnavailable
        : ScreenCaptureError.targetUnavailable
    }
    installKeyMonitor(for: model)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        model.onCommit = { [weak self] selection in
          guard let self, let continuation = self.continuation else { return }
          self.continuation = nil
          continuation.resume(returning: selection)
        }
        model.onCancel = { [weak self] in self?.cancelAndResume() }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelAndResume() }
    }
  }

  func dismissSelection() {
    removeKeyMonitor()
    panels.values.forEach {
      surfaceRegistry.unregister($0)
      $0.orderOut(nil)
      $0.close()
    }
    panels.removeAll()
    viewModel?.shutdown()
    viewModel = nil
    if let continuation {
      self.continuation = nil
      continuation.resume(returning: nil)
    }
  }

  func shutdown() { dismissSelection() }

  @discardableResult
  private func installPanels(
    for catalog: ScreenCaptureCatalog, viewModel: CaptureSelectionViewModel
  ) -> Int {
    for display in catalog.displays {
      guard let screen = screenResolver(display.id) else { continue }
      let panel = makePanel(frame: screen.frame, screen: screen)
      panel.contentView = NSHostingView(
        rootView: CaptureSelectionOverlay(display: display, viewModel: viewModel))
      panels[display.id] = panel
      surfaceRegistry.register(panel)
      panel.orderFrontRegardless()
    }
    panels.values.first?.makeKey()
    return panels.count
  }

  private func makePanel(frame: CGRect, screen: NSScreen) -> NSPanel {
    let panel = ScreenCaptureOverlayPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false,
      screen: screen
    )
    panel.setFrame(frame, display: true)
    panel.level = .screenSaver
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    panel.isReleasedWhenClosed = false
    panel.acceptsMouseMovedEvents = true
    return panel
  }

  private func installKeyMonitor(for model: CaptureSelectionViewModel) {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
      guard let model else { return event }
      let shift = event.modifierFlags.contains(.shift)
      switch event.keyCode {
      case 53:
        model.cancel()
        return nil
      case 36, 76:
        model.commitCurrentTarget()
        return nil
      case 48:
        model.traverseTarget(forward: !shift)
        return nil
      case 123:
        model.adjustRegion(horizontal: -1, vertical: 0, largeStep: shift)
        return nil
      case 124:
        model.adjustRegion(horizontal: 1, vertical: 0, largeStep: shift)
        return nil
      case 125:
        model.adjustRegion(horizontal: 0, vertical: -1, largeStep: shift)
        return nil
      case 126:
        model.adjustRegion(horizontal: 0, vertical: 1, largeStep: shift)
        return nil
      default:
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r":
          model.selectMode(.region)
          return nil
        case "w":
          model.selectMode(.window)
          return nil
        case "d":
          model.selectMode(.display)
          return nil
        default: return event
        }
      }
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }

  private func cancelAndResume() {
    removeKeyMonitor()
    panels.values.forEach {
      surfaceRegistry.unregister($0)
      $0.close()
    }
    panels.removeAll()
    viewModel?.shutdown()
    viewModel = nil
    if let continuation {
      self.continuation = nil
      continuation.resume(returning: nil)
    }
  }
}
