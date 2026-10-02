import SwiftUI

@MainActor
struct ImageFilePreview: View {
    let fileURL: URL
    var onSaveDataRequest: RasterImageSaveDataHandler? = nil
    var onRasterDirtyStateChange: (Bool) -> Void = { _ in }
    /// Owner-issued ⌘S request for the raster editor.
    var saveRequest: RasterImageSaveRequest = .none
    var services: RasterImageEditorServices = .makeDefault()

    private var isSVG: Bool {
        fileURL.pathExtension.lowercased() == "svg"
    }

    var body: some View {
        if isSVG {
            SVGFilePreview(fileURL: fileURL)
                .accessibilityIdentifier("editor.preview.image.svg")
        } else {
            RasterImagePreviewHost(
                fileURL: fileURL,
                onSaveDataRequest: onSaveDataRequest,
                onDirtyStateChange: onRasterDirtyStateChange,
                saveRequest: saveRequest,
                services: services
            )
            .accessibilityIdentifier("editor.preview.image")
        }
    }
}
