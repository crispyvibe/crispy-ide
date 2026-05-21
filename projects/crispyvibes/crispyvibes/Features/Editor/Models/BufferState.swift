import Foundation

/// Opaque token minted when a save begins, used to correlate completion callbacks.
struct SaveToken: Equatable {
    let id: UUID
    let content: String
}

/// Represents the lifecycle state of a document buffer.
@MainActor
enum BufferState: Equatable {
    case loading
    case clean(content: String)
    case dirty(content: String, baseline: String)
    case saving(content: String, baseline: String, token: SaveToken)
    case failed(message: String)
}
