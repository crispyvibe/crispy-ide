import Foundation
import UniformTypeIdentifiers

/// Formats offered by Export As.
enum RasterImageExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic
    case tiff

    var id: String { rawValue }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .png: return AppStrings.ImageEditor.formatPNG
        case .jpeg: return AppStrings.ImageEditor.formatJPEG
        case .heic: return AppStrings.ImageEditor.formatHEIC
        case .tiff: return AppStrings.ImageEditor.formatTIFF
        }
    }

    var isLossy: Bool { self == .jpeg || self == .heic }

    /// `false` for formats that drop transparency.
    var supportsAlpha: Bool { self != .jpeg }

    /// Format matching a file extension, if offered.
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        case "heic", "heif": self = .heic
        case "tif", "tiff": self = .tiff
        default: return nil
        }
    }
}

/// Encoder settings for Export As.
struct RasterImageExportOptions: Equatable, Sendable {
    var format: RasterImageExportFormat
    /// Lossy compression quality in 0...1 (ignored for lossless formats).
    var quality: Double

    static let `default` = RasterImageExportOptions(format: .png, quality: 0.9)
}
