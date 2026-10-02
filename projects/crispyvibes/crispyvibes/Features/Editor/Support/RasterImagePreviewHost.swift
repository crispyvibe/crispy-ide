import AppKit
import SwiftUI

/// Top-level editor modes.
enum RasterImageEditingMode: String, CaseIterable {
    case pan
    case crop
    /// Shapes, arrows, text, highlight, blur, pixelate, redact (see `RasterMarkupTool`).
    case markup
    /// Color adjustments.
    case adjust
}

enum RasterImagePreviewGeometry {
    static func centeredInsets(
        viewportSize: CGSize,
        imageSize: CGSize,
        magnification: CGFloat
    ) -> NSEdgeInsets {
        guard viewportSize.width > 0, viewportSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return NSEdgeInsetsZero
        }

        let clampedMagnification = max(0, magnification)
        let scaledWidth = imageSize.width * clampedMagnification
        let scaledHeight = imageSize.height * clampedMagnification
        let horizontalInset = max(0, (viewportSize.width - scaledWidth) / 2.0)
        let verticalInset = max(0, (viewportSize.height - scaledHeight) / 2.0)

        return NSEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}

/// An owner-issued save request (⌘S), delivered exactly once to the raster editor.
struct RasterImageSaveRequest {
    /// Changes whenever a new request is issued.
    let token: Int
    let isPending: () -> Bool
    let acknowledge: () -> Void

    static let none = RasterImageSaveRequest(token: 0, isPending: { false }, acknowledge: {})
}

/// Toolbar + canvas host for editable raster images (F009).
@MainActor
struct RasterImagePreviewHost: View {
    let fileURL: URL
    let onSaveDataRequest: RasterImageSaveDataHandler?
    let onDirtyStateChange: (Bool) -> Void
    let saveRequest: RasterImageSaveRequest

    @StateObject var viewModel: RasterImageEditorViewModel
    @Environment(\.appThemePalette) var appThemePalette

    init(
        fileURL: URL,
        onSaveDataRequest: RasterImageSaveDataHandler?,
        onDirtyStateChange: @escaping (Bool) -> Void,
        saveRequest: RasterImageSaveRequest = .none,
        services: RasterImageEditorServices = .makeDefault()
    ) {
        self.fileURL = fileURL
        self.onSaveDataRequest = onSaveDataRequest
        self.onDirtyStateChange = onDirtyStateChange
        self.saveRequest = saveRequest
        _viewModel = StateObject(wrappedValue: RasterImageEditorViewModel(services: services))
    }

    var body: some View {
        VStack(spacing: 0) {
            RasterImageEditorToolbar(viewModel: viewModel, onSave: save)
            Divider()
            RasterImageFilePreview(
                fileURL: fileURL,
                viewModel: viewModel,
                onDirtyStateChange: onDirtyStateChange
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            viewModel.saveDataHandler = onSaveDataRequest
            consumeSaveRequestIfPending()
        }
        .onDisappear { viewModel.shutdown() }
        .onChange(of: saveRequest.token) { _, _ in consumeSaveRequestIfPending() }
        .onChange(of: viewModel.hasRenderableImage) { _, _ in consumeSaveRequestIfPending() }
        .sheet(isPresented: $viewModel.isResizeSheetPresented) {
            RasterImageResizeSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isExportSheetPresented) {
            RasterImageExportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isRecognizedTextPresented) {
            RasterImageRecognizedTextSheet(viewModel: viewModel)
        }
    }

    private func save() {
        viewModel.saveDataHandler = onSaveDataRequest
        viewModel.save()
    }

    /// Delivers a pending ⌘S once the editor can act on it.
    private func consumeSaveRequestIfPending() {
        guard saveRequest.isPending(), viewModel.hasRenderableImage else { return }
        saveRequest.acknowledge()
        save()
    }
}
