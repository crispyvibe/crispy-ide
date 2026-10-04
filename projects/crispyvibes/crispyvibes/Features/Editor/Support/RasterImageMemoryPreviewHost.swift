import AppKit
import SwiftUI

/// F009 toolbar and editable canvas backed only by immutable in-memory pixels.
@MainActor
struct RasterImageMemoryPreviewHost: View {
  let image: CGImage
  let canvasSize: CGSize
  let onRevisionChange: (RasterImageEditSession, Int, Bool) -> Void
  let onCanvasReady: (NSResponder) -> Void
  @ObservedObject var viewModel: RasterImageEditorViewModel

  var body: some View {
    VStack(spacing: 0) {
      RasterImageEditorToolbar(
        viewModel: viewModel,
        onSave: {},
        configuration: .screenCapture
      )
      Divider()
      RasterImageMemoryPreview(
        image: image,
        canvasSize: canvasSize,
        viewModel: viewModel,
        onRevisionChange: onRevisionChange,
        onCanvasReady: onCanvasReady
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onDisappear { viewModel.shutdown() }
  }
}

/// AppKit bridge that installs an F009 edit session without a file URL or file observer.
@MainActor
struct RasterImageMemoryPreview: NSViewRepresentable {
  let image: CGImage
  let canvasSize: CGSize
  @ObservedObject var viewModel: RasterImageEditorViewModel
  let onRevisionChange: (RasterImageEditSession, Int, Bool) -> Void
  let onCanvasReady: (NSResponder) -> Void
  @Environment(\.appThemePalette) private var appThemePalette

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let container = RasterImageMemoryPreviewContainerView()
    let scrollView = NSScrollView()
    let canvas = EditableRasterImageCanvasView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.1
    scrollView.maxMagnification = 10
    scrollView.documentView = canvas
    scrollView.setAccessibilityIdentifier("screenCapture.markup.canvas.scroll")
    canvas.setAccessibilityIdentifier("screenCapture.markup.canvas")
    container.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    context.coordinator.prepare(canvas: canvas, scrollView: scrollView)
    container.onLayout = { [weak coordinator = context.coordinator] in
      coordinator?.viewportDidLayout()
    }
    context.coordinator.scheduleInstallation(
      image: image,
      canvasSize: canvasSize,
      viewModel: viewModel,
      onRevisionChange: onRevisionChange,
      onCanvasReady: onCanvasReady
    )
    update(context.coordinator)
    return container
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.scheduleInstallation(
      image: image,
      canvasSize: canvasSize,
      viewModel: viewModel,
      onRevisionChange: onRevisionChange,
      onCanvasReady: onCanvasReady
    )
    update(context.coordinator)
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.shutdown()
  }

  private func update(_ coordinator: Coordinator) {
    guard let canvas = coordinator.canvas, let scrollView = coordinator.scrollView else { return }
    let color = appThemePalette.canvasBackground.nsColor
    scrollView.backgroundColor = color
    scrollView.contentView.backgroundColor = color
    canvas.cropAspectRatio = viewModel.cropAspectValue
    canvas.editingMode = viewModel.editingMode
    canvas.previewStraightenRadians = CGFloat(viewModel.straightenDegrees * .pi / 180)
    canvas.annotationTextTemplate = viewModel.annotationText
    canvas.markupTool = viewModel.markupTool
    canvas.markupStyle = viewModel.markupStyle
    canvas.previewAdjustments = nil
  }

}
