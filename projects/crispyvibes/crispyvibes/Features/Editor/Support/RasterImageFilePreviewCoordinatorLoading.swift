import AppKit
import Foundation

/// Installs decoded images as edit sessions.
extension RasterImageFilePreviewCoordinator {
    func install(
        _ decoded: RasterImageDecodeResult?,
        fileURL: URL,
        generation: Int,
        isNewPath: Bool,
        viewportContext: ViewportContext?
    ) {
        guard generation == loadGeneration, let canvasView, let viewModel else { return }
        isLoading = false
        lastDecodeWasFullResolution = decoded?.isFullResolution ?? false

        canvasView.session = decoded.map { decoded in
            let info = decoded.sourceInfo
            let canvasSize = CGSize(width: info.pixelWidth, height: info.pixelHeight)
            return RasterImageEditSession(
                document: RasterImageDocument(source: .file(fileURL), baseCanvasSize: canvasSize, exportScale: 1),
                displayImage: decoded.image,
                sourceInfo: info,
                renderer: services.renderer
            )
        }
        // Export always re-decodes full resolution, so only fidelity limits block overwrite.
        let blockReason = decoded.flatMap {
            RasterImageSavePolicy.blockReason(
                for: $0.sourceInfo,
                baselinePixelWidth: $0.sourceInfo.pixelWidth,
                baselinePixelHeight: $0.sourceInfo.pixelHeight
            )
        }
        let rendered = canvasView.hasRenderableImage
        viewModel.didLoadImage(rendered: rendered, saveBlockReason: blockReason, isNewFile: isNewPath)

        if isNewPath {
            fitToWindow()
            canvasView.focusIfPossible()
        } else if let viewportContext, rendered {
            restoreViewportContext(viewportContext)
        }
        applyVisibility()
        refreshCenteringInsets()
    }
}
