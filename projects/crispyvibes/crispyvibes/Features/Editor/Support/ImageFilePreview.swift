import SwiftUI

struct ImageFilePreview: View {
    let fileURL: URL
    var onSaveDataRequest: ((URL, Data, @escaping (Result<Void, Error>) -> Void) -> Void)? = nil
    var onRasterDirtyStateChange: (Bool) -> Void = { _ in }

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
                onDirtyStateChange: onRasterDirtyStateChange
            )
            .accessibilityIdentifier("editor.preview.image")
        }
    }
}
