import Foundation

/// F049 — typed error surface for the comment store.
///
/// Replaces raw `String` errors per coding-guidelines: "User-facing errors
/// should be structured types, not raw strings." The Rust persistence
/// helper returns string error messages; `classify(_:)` maps known error
/// shapes back into typed cases so the UI can present targeted feedback.
enum CommentStoreError: Error, Equatable, Sendable {
    case noActiveVibeSpace
    case helperUnavailable
    case decodeFailed
    case limitExceeded(String)
    case rpcError(String)

    /// Human-readable message suitable for an error banner.
    var userFacingMessage: String {
        switch self {
        case .noActiveVibeSpace: return "No active vibespace"
        case .helperUnavailable: return "Persistence helper unavailable"
        case .decodeFailed: return "Could not decode comment from helper"
        case .limitExceeded(let msg): return msg
        case .rpcError(let msg): return msg
        }
    }

    /// Map a raw helper error message into the most specific typed case.
    static func classify(_ raw: String) -> CommentStoreError {
        let lower = raw.lowercased()
        if lower.contains("limit_exceeded") {
            return .limitExceeded(raw)
        }
        return .rpcError(raw)
    }
}

extension VibeSpaceCommentStore {

    /// Group flat comments into threads (root + replies) using a single
    /// dictionary lookup pass. Replaces the previous O(n²) implementation
    /// that walked parent chains via `.first(where:)` for every reply.
    ///
    /// Complexity: O(n) where n is the comment count. Critical for large
    /// files / chatty threads.
    static func buildThreads(from comments: [Comment]) -> [CommentThread] {
        // Build an id → comment lookup once.
        var byID: [String: Comment] = [:]
        byID.reserveCapacity(comments.count)
        for c in comments { byID[c.id] = c }

        // Walk each reply's parent chain via O(1) dictionary lookups to
        // find its root id. Cache results so siblings amortize the cost.
        var rootCache: [String: String] = [:]
        rootCache.reserveCapacity(comments.count)

        func rootID(of comment: Comment) -> String {
            if comment.parentID == nil { return comment.id }
            if let cached = rootCache[comment.id] { return cached }
            var current = comment
            while let pid = current.parentID, let parent = byID[pid] {
                if let cached = rootCache[parent.id] {
                    rootCache[comment.id] = cached
                    return cached
                }
                current = parent
            }
            rootCache[comment.id] = current.id
            return current.id
        }

        // Group replies by root id; collect roots separately.
        var roots: [Comment] = []
        var repliesByRoot: [String: [Comment]] = [:]
        for c in comments {
            if c.parentID == nil {
                roots.append(c)
            } else {
                let rid = rootID(of: c)
                repliesByRoot[rid, default: []].append(c)
            }
        }

        return roots
            .sorted { $0.createdAt < $1.createdAt }
            .map { root in
                let replies = (repliesByRoot[root.id] ?? []).sorted { $0.createdAt < $1.createdAt }
                return CommentThread(root: root, replies: replies)
            }
    }
}
