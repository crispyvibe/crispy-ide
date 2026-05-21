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

    var errorDescription: String? {
        switch self {
        case .noRenderableImage:
            return "No renderable image is available."
        case .unsupportedEncoding(let ext):
            return "Saving .\(ext) images is not supported."
        case .decodeFailure:
            return "Unable to read image pixels for saving."
        case .encodingFailure:
            return "Unable to encode image data."
        case .writeFailure(let error):
            return error.localizedDescription
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
        let ext = destinationURL.pathExtension.lowercased()
        guard !ext.isEmpty else {
            throw RasterImageSaveError.unsupportedEncoding("unknown")
        }

        let destinationType = resolvedDestinationType(forExtension: ext)
        guard let destinationType else {
            throw RasterImageSaveError.unsupportedEncoding(ext)
        }

        guard let cgImage = cgImage(from: image) else {
            throw RasterImageSaveError.decodeFailure
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            destinationType.identifier as CFString,
            1,
            nil
        ) else {
            throw RasterImageSaveError.unsupportedEncoding(ext)
        }

        let options = destinationProperties(for: destinationType)
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary?)
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

    private static func destinationProperties(for type: UTType) -> [CFString: Any] {
        if type == .jpeg {
            return [kCGImageDestinationLossyCompressionQuality: 0.92]
        }
        if type == .heic || type == .heif || type == .webP {
            return [kCGImageDestinationLossyCompressionQuality: 0.90]
        }
        return [:]
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
