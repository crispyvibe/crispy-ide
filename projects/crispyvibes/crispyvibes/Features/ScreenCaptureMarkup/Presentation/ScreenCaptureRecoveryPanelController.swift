import AppKit
import SwiftUI

private final class ScreenCaptureRecoveryPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// Presents permission and structured recovery commands without navigating the main IDE.
@MainActor
final class ScreenCaptureRecoveryPanelController: NSObject, NSWindowDelegate,
  ScreenCaptureRecoveryPresenting
{
  typealias ViewModelFactory =
    @MainActor (
      _ title: String,
      _ message: String,
      _ commands: [ScreenCaptureRecoveryCommand]
    ) -> ScreenCaptureRecoveryViewModel

  private let registry: ScreenCaptureSurfaceRegistry
  private let authorizer: any ScreenCaptureAuthorizing
  private let applicationActivator: any ScreenCaptureApplicationActivating
  private let windowFocuser: any ScreenCaptureWindowFocusing
  private let viewModelFactory: ViewModelFactory
  private(set) var panel: NSPanel?

  init(
    registry: ScreenCaptureSurfaceRegistry,
    authorizer: any ScreenCaptureAuthorizing,
    applicationActivator: any ScreenCaptureApplicationActivating,
    windowFocuser: any ScreenCaptureWindowFocusing,
    viewModelFactory: @escaping ViewModelFactory
  ) {
    self.registry = registry
    self.authorizer = authorizer
    self.applicationActivator = applicationActivator
    self.windowFocuser = windowFocuser
    self.viewModelFactory = viewModelFactory
    super.init()
  }

  func presentPermission(
    _ state: ScreenCaptureAuthorizationState,
    recheck: @escaping () -> Void,
    relaunch: @escaping () -> Void,
    cancel: @escaping () -> Void
  ) {
    var commands = [ScreenCaptureRecoveryCommand]()
    if state == .deniedOrRestricted || state == .revoked {
      commands.append(
        .init(action: .openSystemSettings) { [weak self] in
          self?.authorizer.openScreenRecordingSettings()
        })
    }
    if state == .grantedRelaunchRequired {
      commands.append(.init(action: .relaunchApplication, perform: relaunch))
    }
    commands.append(.init(action: .recheckPermission, perform: recheck))
    commands.append(.init(action: .cancel, perform: cancel))
    present(
      viewModelFactory(
        AppStrings.ScreenCapture.permissionTitle,
        AppStrings.ScreenCapture.permissionMessage(state),
        commands
      ))
  }

  func presentError(
    _ error: ScreenCaptureError, perform: @escaping (ScreenCaptureRecoveryAction) -> Void
  ) {
    present(
      viewModelFactory(
        AppStrings.ScreenCapture.captureFailedTitle,
        AppStrings.ScreenCapture.errorMessage(error),
        error.recoveryActions.map { action in
          ScreenCaptureRecoveryCommand(action: action) { perform(action) }
        }
      ))
  }

  func dismiss() {
    if let panel {
      self.panel = nil
      panel.delegate = nil
      registry.unregister(panel)
      panel.close()
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard sender === panel else { return true }
    dismiss()
    return false
  }

  private func present(_ viewModel: ScreenCaptureRecoveryViewModel) {
    dismiss()
    let panel = ScreenCaptureRecoveryPanel(
      contentRect: CGRect(x: 0, y: 0, width: 420, height: 180),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = viewModel.title
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.contentView = NSHostingView(rootView: ScreenCaptureRecoveryView(viewModel: viewModel))
    panel.center()
    self.panel = panel
    panel.delegate = self
    registry.register(panel)
    applicationActivator.activateApplication()
    windowFocuser.makeKeyAndOrderFront(panel)
    windowFocuser.orderFrontRegardless(panel)
  }
}
