import AppKit

/// Pure Screenshot Studio utility placement policy.
struct ScreenshotStudioPresentation: Equatable {
  let frame: CGRect
  let minimumSize: CGSize
  let maximumSize: CGSize

  static func resolve(canvasSize image: CGSize, visibleFrame visible: CGRect) -> Self {
    let cap = CGSize(width: visible.width * 0.8, height: visible.height * 0.8)
    let scale = min(
      1, cap.width / max(image.width, 1), max((cap.height - 190) / max(image.height, 1), 0.1))
    let size = CGSize(
      width: min(cap.width, max(min(640, cap.width), image.width * scale)),
      height: min(cap.height, max(min(480, cap.height), image.height * scale + 190))
    )
    return Self(
      frame: CGRect(
        x: visible.midX - size.width / 2,
        y: visible.midY - size.height / 2,
        width: size.width,
        height: size.height
      ),
      minimumSize: CGSize(width: min(520, cap.width), height: min(400, cap.height)),
      maximumSize: cap
    )
  }
}

/// Minimal activation adapter for inspecting the exact AppKit option policy.
@MainActor
protocol ScreenCaptureApplicationActivationAdapting: AnyObject {
  @discardableResult
  func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: ScreenCaptureApplicationActivationAdapting {}

/// Activation policy intentionally leaves all-window activation disabled.
enum ScreenCaptureApplicationActivationPolicy {
  static let options: NSApplication.ActivationOptions = []
}

/// Activates Crispy without revealing or ordering unrelated app windows.
@MainActor
final class AppKitScreenCaptureApplicationActivator: ScreenCaptureApplicationActivating {
  private let application: any ScreenCaptureApplicationActivationAdapting

  init(application: any ScreenCaptureApplicationActivationAdapting) {
    self.application = application
  }

  func activateApplication() {
    application.activate(options: ScreenCaptureApplicationActivationPolicy.options)
  }
}

/// AppKit adapter for operations scoped to the owned Markup utility panel.
@MainActor
final class AppKitScreenCaptureWindowFocuser: ScreenCaptureWindowFocusing {
  func makeKeyAndOrderFront(_ window: NSWindow) { window.makeKeyAndOrderFront(nil) }
  func orderFrontRegardless(_ window: NSWindow) { window.orderFrontRegardless() }
  func makeFirstResponder(_ responder: NSResponder, in window: NSWindow) -> Bool {
    window.makeFirstResponder(responder)
  }
}
