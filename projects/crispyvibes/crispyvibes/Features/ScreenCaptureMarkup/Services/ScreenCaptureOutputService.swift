import AppKit
import Foundation

/// Serial eager encoder that reuses F009's raster encoding boundary.
actor ScreenCaptureOutputService: ScreenCaptureOutputEncoding {
    private let encoder: any RasterImageEncoding
    private let resourcePolicy: ScreenCaptureResourcePolicy
    private var operationGeneration: UInt64 = 0
    private var currentTask: Task<EncodedScreenCapture, Error>?

    init(encoder: any RasterImageEncoding, resourcePolicy: ScreenCaptureResourcePolicy = .init()) {
        self.encoder = encoder
        self.resourcePolicy = resourcePolicy
    }

    func encode(_ image: CapturedScreenImage) async throws -> EncodedScreenCapture {
        operationGeneration &+= 1
        let generation = operationGeneration
        currentTask?.cancel()
        let encoder = encoder
        let resourcePolicy = resourcePolicy
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            _ = try resourcePolicy.validate(
                pixelWidth: image.cgImage.width,
                pixelHeight: image.cgImage.height,
                simultaneousBuffers: 3
            )
            return try autoreleasepool {
                do {
                    let pngURL = URL(fileURLWithPath: "/capture.png")
                    let tiffURL = URL(fileURLWithPath: "/capture.tiff")
                    let png = try encoder.encodedData(for: image.cgImage, destinationURL: pngURL, options: nil)
                    try Task.checkCancellation()
                    let tiff = try encoder.encodedData(for: image.cgImage, destinationURL: tiffURL, options: nil)
                    try Task.checkCancellation()
                    guard !png.isEmpty, !tiff.isEmpty else { throw ScreenCaptureError.encodingFailed }
                    return EncodedScreenCapture(png: png, tiff: tiff)
                } catch let error as ScreenCaptureError {
                    throw error
                } catch is CancellationError {
                    throw ScreenCaptureError.cancelled
                } catch {
                    throw ScreenCaptureError.encodingFailed
                }
            }
        }
        currentTask = task
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard generation == operationGeneration else { throw ScreenCaptureError.staleOperation }
            currentTask = nil
            return result
        } catch {
            if generation == operationGeneration { currentTask = nil }
            throw error
        }
    }
}

/// AppKit pasteboard adapter that commits a pre-populated item in one write operation.
@MainActor
final class AppKitScreenCaptureClipboard: ScreenCaptureClipboardDelivering {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func writeCompleteRepresentations(_ representations: EncodedScreenCapture) throws {
        guard !representations.png.isEmpty, !representations.tiff.isEmpty else {
            throw ScreenCaptureError.clipboardFailed
        }
        let item = NSPasteboardItem()
        guard item.setData(representations.png, forType: .png),
              item.setData(representations.tiff, forType: .tiff) else {
            throw ScreenCaptureError.clipboardFailed
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ScreenCaptureError.clipboardFailed
        }
    }
}
