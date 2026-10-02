import AppKit
import SwiftUI

/// Hosts the editable raster canvas inside a magnifiable scroll view.
///
/// All editing commands flow through `RasterImageEditorViewModel`; this representable only
/// builds the AppKit hierarchy and forwards view-model settings to the canvas.
@MainActor
struct RasterImageFilePreview: NSViewRepresentable {
    let fileURL: URL
    @ObservedObject var viewModel: RasterImageEditorViewModel
    let onDirtyStateChange: (Bool) -> Void
    @Environment(\.appThemePalette) private var appThemePalette

    final class ContainerView: NSView {
        var onBackingPropertiesChanged: (() -> Void)?

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            onBackingPropertiesChanged?()
        }
    }

    func makeCoordinator() -> RasterImageFilePreviewCoordinator {
        RasterImageFilePreviewCoordinator(services: viewModel.services)
    }

    func makeNSView(context: Context) -> NSView {
        let container = ContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setAccessibilityElement(true)
        container.setAccessibilityIdentifier("editor.preview.image.container")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 10.0
        scrollView.drawsBackground = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.setAccessibilityElement(true)
        scrollView.setAccessibilityIdentifier("editor.preview.image.scroll")

        let canvasView = EditableRasterImageCanvasView()
        canvasView.setAccessibilityElement(true)
        canvasView.setAccessibilityIdentifier("editor.preview.image")
        scrollView.documentView = canvasView

        let placeholderLabel = NSTextField(labelWithString: AppStrings.ImageEditor.renderFailedPlaceholder)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alignment = .center
        placeholderLabel.isHidden = true
        placeholderLabel.setAccessibilityIdentifier("editor.preview.image.failed")

        container.addSubview(scrollView)
        container.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            placeholderLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let coordinator = context.coordinator
        coordinator.install(
            canvasView: canvasView,
            scrollView: scrollView,
            placeholderLabel: placeholderLabel,
            viewModel: viewModel,
            onDirtyStateChange: onDirtyStateChange
        )
        container.onBackingPropertiesChanged = { [weak coordinator] in
            coordinator?.handleBackingPropertiesChanged()
        }
        updatePreview(in: coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDirtyStateChange = onDirtyStateChange
        updatePreview(in: context.coordinator)
    }

    private func updatePreview(in coordinator: RasterImageFilePreviewCoordinator) {
        guard let canvasView = coordinator.canvasView,
              let placeholderLabel = coordinator.placeholderLabel,
              let scrollView = coordinator.scrollView else {
            return
        }

        let backgroundColor = appThemePalette.canvasBackground.nsColor
        scrollView.backgroundColor = backgroundColor
        scrollView.contentView.backgroundColor = backgroundColor
        placeholderLabel.textColor = appThemePalette.warning.nsColor

        viewModel.fileURL = fileURL
        coordinator.present(fileURL)

        canvasView.cropAspectRatio = viewModel.cropAspectValue
        if canvasView.editingMode != viewModel.editingMode {
            canvasView.editingMode = viewModel.editingMode
            canvasView.focusIfPossible()
        }
        canvasView.previewStraightenRadians = CGFloat(viewModel.straightenDegrees * .pi / 180)
        canvasView.annotationTextTemplate = viewModel.annotationText
        canvasView.markupTool = viewModel.markupTool
        canvasView.markupStyle = viewModel.markupStyle
        canvasView.previewAdjustments = viewModel.previewAdjustmentsOverride
        canvasView.recognizedTextLines = viewModel.recognizedText
        coordinator.refreshCenteringInsets()
    }
}

/// Outcome of applying a crop selection.
enum RasterImageCropResult {
    case success
    case noSelection
    case invalidSelection
    case decodeFailure
    case cropFailure

    var didApply: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var feedbackMessage: String {
        switch self {
        case .success: return AppStrings.ImageEditor.statusCropApplied
        case .noSelection: return AppStrings.ImageEditor.statusNoCropSelection
        case .invalidSelection: return AppStrings.ImageEditor.statusInvalidCropSelection
        case .decodeFailure: return AppStrings.ImageEditor.statusCropDecodeFailure
        case .cropFailure: return AppStrings.ImageEditor.statusCropFailure
        }
    }
}
