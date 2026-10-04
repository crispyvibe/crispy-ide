import Foundation

/// Persisted metadata for one flattened screen capture history item.
///
/// This intentionally contains no capture target, origin, path, title, or annotation metadata.
struct ScreenCaptureHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let currentVersionID: UUID
    let flattenedFileIdentifier: String
    let thumbnailFileIdentifier: String
    let canvasWidth: Double
    let canvasHeight: Double
    let exportScale: Double
    let pixelWidth: Int
    let pixelHeight: Int
}
