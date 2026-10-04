import Foundation

/// Persistence boundary for bounded, device-local flattened screenshot history.
protocol ScreenCaptureHistoryRepository: Sendable {
    func loadEntries() async throws -> [ScreenCaptureHistoryEntry]
    func add(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry
    func update(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry
    func thumbnail(for id: UUID) async throws -> ScreenCaptureHistoryImage
    func flattenedSource(for id: UUID) async throws -> ScreenCaptureHistoryImage
    func delete(id: UUID) async throws
    func clear() async throws
}
