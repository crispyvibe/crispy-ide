import AppKit
import UniformTypeIdentifiers

/// Writes images to `NSPasteboard.general`.
struct SystemRasterImagePasteboard: RasterImagePasteboardWriting {
    func write(_ image: CGImage, size: CGSize) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([NSImage(cgImage: image, size: size)])
    }

    func writeText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

/// Presents an `NSSavePanel` for Export As.
struct SystemRasterImageExportDestinationPicker: RasterImageExportDestinationPicking {
    func pickDestination(suggestedName: String, contentType: UTType, completion: @escaping (URL?) -> Void) {
        MainActor.assumeIsolated {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedName
            panel.allowedContentTypes = [contentType]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.begin { response in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }
}

/// Eyedropper backed by `NSColorSampler`.
struct SystemRasterImageColorSampler: RasterImageColorSampling {
    func sampleColor(completion: @escaping (RasterColor?) -> Void) {
        NSColorSampler().show { color in
            completion(color.map(RasterColor.init))
        }
    }
}

/// Posts announcements through `NSAccessibility` for VoiceOver users.
struct SystemRasterImageAnnouncer: RasterImageAccessibilityAnnouncing {
    func announce(_ message: String) {
        guard !message.isEmpty, let element = NSApp?.keyWindow ?? NSApp?.mainWindow else { return }
        NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}

/// Dependencies of the raster image editor, assembled by `AppContainer`.
struct RasterImageEditorServices {
    let decoder: any RasterImageDecoding
    let renderer: any RasterImageRendering
    let exporter: any RasterImageExporting
    let pasteboard: any RasterImagePasteboardWriting
    let destinationPicker: any RasterImageExportDestinationPicking
    /// Serial queue for atomic file writes, keeping large writes off the main thread.
    var ioQueue = DispatchQueue(label: "com.crispyvibe.raster-image.io", qos: .userInitiated)
    var colorSampler: any RasterImageColorSampling = SystemRasterImageColorSampler()
    var announcer: any RasterImageAccessibilityAnnouncing = SystemRasterImageAnnouncer()
    var analyzer: any RasterImageAnalyzing = RasterImageVisionService()

    /// Production wiring: ImageIO decoder, Core Graphics renderer, background export queue,
    /// and the system pasteboard.
    static func makeDefault() -> RasterImageEditorServices {
        let decoder = RasterImageDecoder()
        let renderer = RasterImageRenderer()
        return RasterImageEditorServices(
            decoder: decoder,
            renderer: renderer,
            exporter: RasterImageExportService(decoder: decoder, renderer: renderer, encoder: RasterImageEncoder()),
            pasteboard: SystemRasterImagePasteboard(),
            destinationPicker: SystemRasterImageExportDestinationPicker()
        )
    }
}
