import AppKit
import Foundation
import ImageIO
import SwiftUI

struct RasterImageFilePreview: NSViewRepresentable {
    let fileURL: URL
    let editingMode: RasterImageEditingMode
    let cropToken: Int
    let clearToken: Int
    let saveToken: Int
    let annotationText: String
    let annotationFontFamily: String
    let annotationFontSize: Double
    let onSaveDataRequest: ((URL, Data, @escaping (Result<Void, Error>) -> Void) -> Void)?
    let onDirtyStateChange: (Bool) -> Void
    let onActionFeedback: (String) -> Void
    @Environment(\.appThemePalette) private var appThemePalette

    struct ViewportContext {
        let magnification: CGFloat
        let horizontalFraction: CGFloat
        let verticalFraction: CGFloat
    }

    final class ContainerView: NSView {
        var onBackingPropertiesChanged: (() -> Void)?

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            onBackingPropertiesChanged?()
        }
    }

    final class Coordinator {
        var currentFileURL: URL?
        var lastLoadedPath: String?
        var lastLoadedFileState: RasterImageFileState?
        weak var canvasView: EditableRasterImageCanvasView?
        weak var placeholderLabel: NSTextField?
        weak var scrollView: NSScrollView?
        var boundsObserver: NSObjectProtocol?
        var fileObservationSource: DispatchSourceFileSystemObject?
        var observedFileDescriptor: CInt = -1
        var observedPath: String?
        var onDirtyStateChange: ((Bool) -> Void)?
        var onActionFeedback: ((String) -> Void)?
        var lastCropToken = 0
        var lastClearToken = 0
        var lastSaveToken = 0
        private var hasInstalledDirtyObserver = false

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            tearDownFileObservation()
        }

        func installBoundsObserverIfNeeded() {
            guard boundsObserver == nil, let clipView = scrollView?.contentView else { return }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.refreshCenteringInsets()
            }
        }

        func bindCallbacks(
            onDirtyStateChange: @escaping (Bool) -> Void,
            onActionFeedback: @escaping (String) -> Void
        ) {
            self.onDirtyStateChange = onDirtyStateChange
            self.onActionFeedback = onActionFeedback
            guard !hasInstalledDirtyObserver else { return }
            hasInstalledDirtyObserver = true
            canvasView?.setDirtyStateObserver { [weak self] hasUnsavedEdits in
                self?.emitDirtyState(hasUnsavedEdits)
            }
        }

        func emitDirtyState(_ hasUnsavedEdits: Bool) {
            DispatchQueue.main.async { [weak self] in
                self?.onDirtyStateChange?(hasUnsavedEdits)
            }
        }

        func emitActionFeedback(_ message: String) {
            DispatchQueue.main.async { [weak self] in
                self?.onActionFeedback?(message)
            }
        }

        func configureFileObservation(for fileURL: URL) {
            guard observedPath != fileURL.path else { return }
            tearDownFileObservation()

            let descriptor = open(fileURL.path, O_EVTONLY)
            guard descriptor >= 0 else { return }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete, .revoke],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                _ = self.reloadImageIfNeeded(
                    from: fileURL,
                    force: false,
                    preserveViewportContext: true
                )

                let events = source.data
                if events.contains(.rename) || events.contains(.delete) || events.contains(.revoke) {
                    self.configureFileObservation(for: fileURL)
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }

            observedFileDescriptor = descriptor
            observedPath = fileURL.path
            fileObservationSource = source
            source.resume()
        }

        func tearDownFileObservation() {
            fileObservationSource?.cancel()
            fileObservationSource = nil
            observedPath = nil
            observedFileDescriptor = -1
        }

        func refreshCenteringInsets() {
            guard let scrollView, let canvasView, canvasView.hasRenderableImage else { return }
            let viewportSize = scrollView.contentSize
            let imageSize = canvasView.frame.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let targetInsets = RasterImagePreviewGeometry.centeredInsets(
                viewportSize: viewportSize,
                imageSize: imageSize,
                magnification: scrollView.magnification
            )
            if abs(scrollView.contentInsets.left - targetInsets.left) > 0.5 ||
                abs(scrollView.contentInsets.right - targetInsets.right) > 0.5 ||
                abs(scrollView.contentInsets.top - targetInsets.top) > 0.5 ||
                abs(scrollView.contentInsets.bottom - targetInsets.bottom) > 0.5 {
                scrollView.contentInsets = targetInsets
            }
        }

        func handleBackingPropertiesChanged() {
            guard let currentFileURL else { return }
            guard let canvasView else { return }
            if canvasView.hasPendingEdits {
                refreshCenteringInsets()
                return
            }
            _ = reloadImageIfNeeded(
                from: currentFileURL,
                force: true,
                preserveViewportContext: true
            )
            refreshCenteringInsets()
        }

        func markFileStateAsCurrent(_ fileURL: URL) {
            lastLoadedPath = fileURL.path
            lastLoadedFileState = RasterImageFileState.capture(for: fileURL)
        }

        @discardableResult
        func reloadImageIfNeeded(
            from fileURL: URL,
            force: Bool,
            preserveViewportContext: Bool
        ) -> Bool {
            guard let canvasView,
                  let scrollView else {
                return false
            }

            let fileState = RasterImageFileState.capture(for: fileURL)
            let isNewPath = lastLoadedPath != fileURL.path
            let hasSamePathContentChange = !isNewPath && fileState != lastLoadedFileState
            guard force || isNewPath || hasSamePathContentChange else {
                return false
            }

            let hadPendingEdits = canvasView.hasPendingEdits
            let viewportContext = preserveViewportContext ? captureViewportContext() : nil
            let previewImage = loadPreviewImage(
                from: fileURL,
                viewportSize: scrollView.contentSize,
                magnification: scrollView.magnification
            )
            canvasView.loadImage(previewImage)
            canvasView.setDirtyStateObserver(onDirtyStateChange ?? { _ in })

            lastLoadedPath = fileURL.path
            lastLoadedFileState = fileState

            if !canvasView.hasRenderableImage {
                emitActionFeedback("Unable to render the latest file contents.")
            } else if !isNewPath && hadPendingEdits {
                emitActionFeedback("Image was reloaded from disk and unsaved edits were cleared.")
            }

            if isNewPath {
                scrollView.magnification = 1.0
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else if let viewportContext, canvasView.hasRenderableImage {
                restoreViewportContext(viewportContext)
            }

            refreshCenteringInsets()
            return true
        }

        private func loadPreviewImage(
            from fileURL: URL,
            viewportSize: CGSize,
            magnification: CGFloat
        ) -> NSImage? {
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                return NSImage(contentsOf: fileURL)
            }

            let maxPixelSize = preferredThumbnailPixelSize(
                viewportSize: viewportSize,
                magnification: magnification
            )
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                thumbnailOptions as CFDictionary
            ) {
                let size = NSSize(width: thumbnail.width, height: thumbnail.height)
                return NSImage(cgImage: thumbnail, size: size)
            }

            if let fullResolution = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                let size = NSSize(width: fullResolution.width, height: fullResolution.height)
                return NSImage(cgImage: fullResolution, size: size)
            }

            return NSImage(contentsOf: fileURL)
        }

        private func preferredThumbnailPixelSize(
            viewportSize: CGSize,
            magnification: CGFloat
        ) -> Int {
            let minimumPixelSize = 1024
            let maximumPixelSize = 4096
            let longestViewportEdge = max(max(viewportSize.width, viewportSize.height), 1)
            let backingScaleFactor = resolvedBackingScaleFactor()
            let zoomMultiplier = max(1, magnification)
            let requestedSize = Int(
                ceil(longestViewportEdge * backingScaleFactor * zoomMultiplier * 1.8)
            )
            return min(max(requestedSize, minimumPixelSize), maximumPixelSize)
        }

        private func resolvedBackingScaleFactor() -> CGFloat {
            guard let scrollView else { return 1 }
            return scrollView.crispyvibesBackingScaleFactor()
        }

        private func captureViewportContext() -> ViewportContext? {
            guard let scrollView,
                  let canvasView,
                  canvasView.hasRenderableImage else {
                return nil
            }

            let visibleRect = scrollView.contentView.bounds
            let horizontalRange = max(0, canvasView.bounds.width - visibleRect.width)
            let verticalRange = max(0, canvasView.bounds.height - visibleRect.height)
            let horizontalFraction = horizontalRange > 0 ? visibleRect.origin.x / horizontalRange : 0
            let verticalFraction = verticalRange > 0 ? visibleRect.origin.y / verticalRange : 0

            return ViewportContext(
                magnification: scrollView.magnification,
                horizontalFraction: min(max(horizontalFraction, 0), 1),
                verticalFraction: min(max(verticalFraction, 0), 1)
            )
        }

        private func restoreViewportContext(_ context: ViewportContext) {
            guard let scrollView,
                  let canvasView,
                  canvasView.hasRenderableImage else {
                return
            }

            let targetMagnification = min(
                max(context.magnification, scrollView.minMagnification),
                scrollView.maxMagnification
            )
            scrollView.magnification = targetMagnification

            let visibleRect = scrollView.contentView.bounds
            let horizontalRange = max(0, canvasView.bounds.width - visibleRect.width)
            let verticalRange = max(0, canvasView.bounds.height - visibleRect.height)
            let targetOrigin = CGPoint(
                x: horizontalRange * context.horizontalFraction,
                y: verticalRange * context.verticalFraction
            )

            scrollView.contentView.scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
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

        let placeholderLabel = NSTextField(labelWithString: "Unable to render this image.")
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

        context.coordinator.canvasView = canvasView
        context.coordinator.placeholderLabel = placeholderLabel
        context.coordinator.scrollView = scrollView
        context.coordinator.currentFileURL = fileURL
        context.coordinator.installBoundsObserverIfNeeded()
        context.coordinator.bindCallbacks(
            onDirtyStateChange: onDirtyStateChange,
            onActionFeedback: onActionFeedback
        )
        container.onBackingPropertiesChanged = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.handleBackingPropertiesChanged()
        }
        updatePreview(in: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updatePreview(in: context.coordinator)
    }

    private func updatePreview(in coordinator: Coordinator) {
        guard let canvasView = coordinator.canvasView,
              let placeholderLabel = coordinator.placeholderLabel,
              let scrollView = coordinator.scrollView else {
            return
        }

        coordinator.bindCallbacks(
            onDirtyStateChange: onDirtyStateChange,
            onActionFeedback: onActionFeedback
        )

        let backgroundColor = appThemePalette.canvasBackground.nsColor
        scrollView.backgroundColor = backgroundColor
        scrollView.contentView.backgroundColor = backgroundColor
        placeholderLabel.textColor = appThemePalette.warning.nsColor

        coordinator.currentFileURL = fileURL
        coordinator.configureFileObservation(for: fileURL)
        _ = coordinator.reloadImageIfNeeded(
            from: fileURL,
            force: false,
            preserveViewportContext: true
        )

        let canRender = canvasView.hasRenderableImage
        scrollView.isHidden = !canRender
        placeholderLabel.isHidden = canRender
        guard canRender else { return }

        canvasView.editingMode = editingMode
        canvasView.annotationTextTemplate = annotationText
        canvasView.annotationFontFamily = annotationFontFamily
        canvasView.annotationFontSize = CGFloat(annotationFontSize)

        if clearToken != coordinator.lastClearToken {
            let hadEdits = canvasView.clearEdits()
            coordinator.emitActionFeedback(hadEdits ? "Edits cleared." : "Nothing to clear.")
            coordinator.lastClearToken = clearToken
        }
        if cropToken != coordinator.lastCropToken {
            let cropResult = canvasView.applyCropSelection()
            coordinator.emitActionFeedback(cropResult.feedbackMessage)
            coordinator.lastCropToken = cropToken
            if cropResult.didApply {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        if saveToken != coordinator.lastSaveToken {
            do {
                let encodedData = try canvasView.encodedCompositedImageData(for: fileURL)
                if let onSaveDataRequest {
                    coordinator.emitActionFeedback("Saving image…")
                    onSaveDataRequest(fileURL, encodedData) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                canvasView.finalizeSuccessfulSave(from: fileURL)
                                coordinator.markFileStateAsCurrent(fileURL)
                                coordinator.emitActionFeedback("Image saved.")
                            case .failure(let error):
                                coordinator.emitActionFeedback("Unable to save image: \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    try encodedData.write(to: fileURL, options: .atomic)
                    canvasView.finalizeSuccessfulSave(from: fileURL)
                    coordinator.markFileStateAsCurrent(fileURL)
                    coordinator.emitActionFeedback("Image saved to disk.")
                }
            } catch {
                coordinator.emitActionFeedback("Unable to save image: \(error.localizedDescription)")
            }
            coordinator.lastSaveToken = saveToken
        }

        coordinator.refreshCenteringInsets()
    }
}

struct RasterImageFileState: Equatable {
    let fileSize: Int64?
    let modificationDate: Date?

    static func capture(for fileURL: URL) -> RasterImageFileState? {
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
            return nil
        }
        return RasterImageFileState(
            fileSize: values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate
        )
    }
}

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
        case .success:
            return "Crop applied."
        case .noSelection:
            return "Draw a crop selection first."
        case .invalidSelection:
            return "Crop selection must stay within the image and be at least 2×2 pixels."
        case .decodeFailure:
            return "Unable to decode the image for cropping."
        case .cropFailure:
            return "Unable to crop the selected region."
        }
    }
}
