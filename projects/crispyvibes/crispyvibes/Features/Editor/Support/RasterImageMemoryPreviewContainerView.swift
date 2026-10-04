import AppKit

/// Reports actual AppKit layout instead of guessing when SwiftUI has assigned a viewport.
@MainActor
final class RasterImageMemoryPreviewContainerView: NSView {
  var onLayout: (() -> Void)?

  override func layout() {
    super.layout()
    onLayout?()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    needsLayout = true
  }
}
