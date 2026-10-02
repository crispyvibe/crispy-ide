import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RasterImageSaveError: LocalizedError {
    case noRenderableImage
    case unsupportedEncoding(String)
    case decodeFailure
    case encodingFailure
    case writeFailure(Error)
    /// The document changed while a save was rendering.
    case staleRevision
    /// The file on disk changed between starting the save and writing it.
    case fileChangedDuringSave
    /// The remote source changed since it was staged.
    case remoteChanged

    var errorDescription: String? {
        switch self {
        case .noRenderableImage:
            return AppStrings.ImageEditor.errorNoRenderableImage
        case .unsupportedEncoding(let ext):
            return AppStrings.ImageEditor.errorUnsupportedEncoding(ext)
        case .decodeFailure:
            return AppStrings.ImageEditor.errorDecodeFailure
        case .encodingFailure:
            return AppStrings.ImageEditor.errorEncodingFailure
        case .writeFailure(let error):
            return error.localizedDescription
        case .staleRevision:
            return AppStrings.ImageEditor.errorStaleRevision
        case .fileChangedDuringSave:
            return AppStrings.ImageEditor.statusSaveConflict
        case .remoteChanged:
            return AppStrings.ImageEditor.errorRemoteChanged
        }
    }
}

enum RasterImagePersistence {
    static func writeImage(_ image: NSImage, to destinationURL: URL) throws {
        let outputData = try encodedData(for: image, destinationURL: destinationURL)

        do {
            try outputData.write(to: destinationURL, options: .atomic)
        } catch {
            throw RasterImageSaveError.writeFailure(error)
        }
    }

    static func encodedData(for image: NSImage, destinationURL: URL) throws -> Data {
        guard let cgImage = cgImage(from: image) else {
            throw RasterImageSaveError.decodeFailure
        }
        return try encodedData(for: cgImage, destinationURL: destinationURL)
    }

    /// Encodes upright pixels for the destination's extension, writing orientation 1.
    static func encodedData(for cgImage: CGImage, destinationURL: URL) throws -> Data {
        let ext = destinationURL.pathExtension.lowercased()
        guard !ext.isEmpty else {
            throw RasterImageSaveError.unsupportedEncoding("unknown")
        }

        let destinationType = resolvedDestinationType(forExtension: ext)
        guard let destinationType else {
            throw RasterImageSaveError.unsupportedEncoding(ext)
        }
        return try encodedData(for: cgImage, type: destinationType, quality: nil)
    }

    /// Encodes upright pixels as `type`, writing orientation 1. `quality` overrides the default
    /// lossy compression quality.
    static func encodedData(for cgImage: CGImage, type destinationType: UTType, quality: Double?) throws -> Data {
        let ext = destinationType.preferredFilenameExtension ?? destinationType.identifier

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            destinationType.identifier as CFString,
            1,
            nil
        ) else {
            throw RasterImageSaveError.unsupportedEncoding(ext)
        }

        var options = destinationProperties(for: destinationType)
        if let quality, options[kCGImageDestinationLossyCompressionQuality] != nil {
            options[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1)
        }
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw RasterImageSaveError.encodingFailure
        }

        return outputData as Data
    }

    private static func resolvedDestinationType(forExtension ext: String) -> UTType? {
        if ext == "jpg" || ext == "jpeg" {
            return .jpeg
        }
        if ext == "tif" || ext == "tiff" {
            return .tiff
        }
        if ext == "png" {
            return .png
        }
        if ext == "gif" {
            return .gif
        }
        if ext == "bmp" {
            return .bmp
        }
        if ext == "heic" {
            return .heic
        }
        if ext == "heif" {
            return .heif
        }
        if ext == "webp" {
            return .webP
        }
        guard let detected = UTType(filenameExtension: ext), detected.conforms(to: .image) else {
            return nil
        }
        return detected
    }

    /// Encoder options. Pixels are always exported upright, so orientation is written as 1
    /// to stop viewers from re-applying the source's EXIF rotation.
    private static func destinationProperties(for type: UTType) -> [CFString: Any] {
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        } else if type == .heic || type == .heif || type == .webP {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.90
        }
        return properties
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage else {
            return nil
        }
        return cgImage
    }
}
