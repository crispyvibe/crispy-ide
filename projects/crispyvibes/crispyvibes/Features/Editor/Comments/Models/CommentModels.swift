import CryptoKit
import Foundation

// MARK: - Author Kind

/// F049-R07: distinguishes user-authored from agent-authored comments. Agent
/// identity is captured in the `authorLabel` (e.g., the channel-client tag).
enum CommentAuthorKind: String, Codable, Sendable, Equatable {
    case user
    case agent
}

// MARK: - Surface Kind

/// F049-v2: which kind of surface the comment is anchored to. Today: a file
/// in the workspace, or a browser-window URL. New surfaces (e.g., terminal
/// transcripts) would extend this enum.
enum CommentSurfaceKind: String, Codable, Sendable, Equatable {
    case file
    case browser
}

// MARK: - Anchor

/// F049-R05 anchor: a character range plus a content snapshot that lets the
/// fuzzy relocator find the comment's anchor after the file changes.
///
/// F049-v2: optional DOM-selector fields (populated for HTML preview and
/// browser surfaces) provide direct re-anchoring via `querySelector(...)`,
/// with the line-based fields kept for cross-surface display.
struct CommentAnchor: Codable, Sendable, Equatable, Hashable {
    /// 1-based start line.
    var startLine: Int
    /// 1-based start column.
    var startColumn: Int
    /// 1-based end line (inclusive).
    var endLine: Int
    /// 1-based end column (exclusive — the column after the last anchored char).
    var endColumn: Int
    /// SHA-256 hex of `anchorText`.
    var anchorHash: String
    /// The literal text within the anchored range, capped at 4 KB.
    var anchorText: String
    /// Up to 64 chars of text immediately before the anchored range.
    var leadingContext: String
    /// Up to 64 chars of text immediately after the anchored range.
    var trailingContext: String

    /// F049-v2: CSS selector path identifying the containing block element
    /// (HTML preview / browser surfaces only). e.g.
    /// `"#hero > article > h2:nth-of-type(3)"`. Bounded depth ≤6.
    var domSelector: String?
    /// Char offset of the selection start within the containing block's
    /// `textContent`.
    var domTextOffset: Int?
    /// Length of the selection in characters within the containing block.
    var domTextLength: Int?
    /// SHA-256 of the containing block's `textContent` at capture time —
    /// used to validate that the selector still points at the same content
    /// before applying decorations.
    var domFingerprint: String?

    /// Convenience: a line-only anchor (full-line comment) at `line`.
    static func wholeLine(_ line: Int, lineText: String) -> CommentAnchor {
        CommentAnchor(
            startLine: line,
            startColumn: 1,
            endLine: line,
            endColumn: max(1, lineText.count + 1),
            anchorHash: Self.hash(lineText),
            anchorText: lineText,
            leadingContext: "",
            trailingContext: "",
            domSelector: nil,
            domTextOffset: nil,
            domTextLength: nil,
            domFingerprint: nil
        )
    }

    /// SHA-256 hex of a string. Used to validate anchor stability.
    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Build a `CommentAnchor` from a `.commentsRequestAddForSelection`
    /// notification's `userInfo` dictionary. Missing keys fall back to
    /// safe defaults so callers always get a usable anchor; this mirrors
    /// the Rust handler's defensive `unwrap_or` logic.
    static func fromNotificationPayload(_ info: [String: Any]) -> CommentAnchor {
        let startLine = (info["startLine"] as? Int) ?? 1
        let startCol = (info["startColumn"] as? Int) ?? 1
        let endLine = (info["endLine"] as? Int) ?? startLine
        let endCol = (info["endColumn"] as? Int) ?? (startCol + 1)
        let anchorText = (info["anchorText"] as? String) ?? ""
        let leading = (info["leadingContext"] as? String) ?? ""
        let trailing = (info["trailingContext"] as? String) ?? ""
        return CommentAnchor(
            startLine: startLine,
            startColumn: startCol,
            endLine: endLine,
            endColumn: endCol,
            anchorHash: Self.hash(anchorText),
            anchorText: anchorText,
            leadingContext: leading,
            trailingContext: trailing,
            domSelector: info["domSelector"] as? String,
            domTextOffset: info["domTextOffset"] as? Int,
            domTextLength: info["domTextLength"] as? Int,
            domFingerprint: info["domFingerprint"] as? String
        )
    }

    /// Build the dictionary payload for a `.commentsRequestAddForSelection`
    /// notification. Used by both code-mode and rich-mode editors so the
    /// payload schema stays in one place.
    func notificationPayload(filePath: String?) -> [String: Any] {
        var info: [String: Any] = [
            "startLine": startLine,
            "startColumn": startColumn,
            "endLine": endLine,
            "endColumn": endColumn,
            "anchorText": anchorText,
            "leadingContext": leadingContext,
            "trailingContext": trailingContext,
        ]
        if let filePath { info["filePath"] = filePath }
        if let domSelector { info["domSelector"] = domSelector }
        if let domTextOffset { info["domTextOffset"] = domTextOffset }
        if let domTextLength { info["domTextLength"] = domTextLength }
        if let domFingerprint { info["domFingerprint"] = domFingerprint }
        return info
    }
}

// MARK: - Status filter

/// F049-R16 status filter shared by the side panel, cross-file view, and CLI.
enum CommentStatusFilter: String, CaseIterable, Codable, Sendable {
    case active
    case resolved
    case stale
    case all
}

// MARK: - Comment

/// One comment row. Replies have a non-nil `parentID`. Resolution is tracked
/// on the root only (R03 / R10) — clients should treat any resolved root as
/// resolving the entire thread.
struct Comment: Codable, Sendable, Equatable, Identifiable, Hashable {
    let id: String
    let vibespaceID: String
    let filePath: String
    let parentID: String?
    var body: String
    let authorKind: CommentAuthorKind
    let authorLabel: String?
    let createdAt: Date
    var updatedAt: Date
    var resolvedAt: Date?
    var isStale: Bool
    var anchor: CommentAnchor
    /// F049-v2: which surface this comment is anchored to. Defaults to
    /// `.file` for backwards-compat with rows persisted before the v3
    /// schema migration.
    var surfaceKind: CommentSurfaceKind = .file

    var isEdited: Bool { updatedAt > createdAt.addingTimeInterval(1) }
    var isResolved: Bool { resolvedAt != nil }
    var isReply: Bool { parentID != nil }
}

// MARK: - Thread

/// A top-level comment plus its full reply subtree, materialized for the UI.
struct CommentThread: Identifiable, Equatable, Sendable {
    let root: Comment
    /// Replies in chronological order, flat (UI nests via parentID).
    let replies: [Comment]

    var id: String { root.id }
    var allComments: [Comment] { [root] + replies }
    var status: CommentStatusFilter {
        if root.resolvedAt != nil { return .resolved }
        if root.isStale { return .stale }
        return .active
    }
}

// MARK: - File key

/// Stable identity for a file in a vibespace. Path is canonicalized
/// (`URL.standardizedFileURL.path`) so renames detected by the file watcher
/// can update the key in the store map.
struct CommentFileKey: Hashable, Codable, Sendable {
    let vibespaceID: String
    let filePath: String
}

// MARK: - JSON-RPC encoder helpers

/// Encodes Swift comment models into the shape the Rust persistence helper
/// expects on `comment.*` RPC methods.
enum CommentRPCEncoder {

    static func encodeAdd(
        id: String,
        vibespaceID: String,
        filePath: String,
        parentID: String?,
        body: String,
        authorKind: CommentAuthorKind,
        authorLabel: String?,
        anchor: CommentAnchor,
        surfaceKind: CommentSurfaceKind = .file
    ) -> [String: Any] {
        var anchorPayload: [String: Any] = [
            "startLine": anchor.startLine,
            "startColumn": anchor.startColumn,
            "endLine": anchor.endLine,
            "endColumn": anchor.endColumn,
            "anchorHash": anchor.anchorHash,
            "anchorText": anchor.anchorText,
            "leadingContext": anchor.leadingContext,
            "trailingContext": anchor.trailingContext,
        ]
        if let s = anchor.domSelector { anchorPayload["domSelector"] = s }
        if let o = anchor.domTextOffset { anchorPayload["domTextOffset"] = o }
        if let l = anchor.domTextLength { anchorPayload["domTextLength"] = l }
        if let f = anchor.domFingerprint { anchorPayload["domFingerprint"] = f }

        var p: [String: Any] = [
            "id": id,
            "vibespaceId": vibespaceID,
            "filePath": filePath,
            "body": body,
            "authorKind": authorKind.rawValue,
            "surfaceKind": surfaceKind.rawValue,
            "anchor": anchorPayload,
        ]
        if let parentID { p["parentId"] = parentID }
        if let authorLabel { p["authorLabel"] = authorLabel }
        return p
    }

    static func encodeList(
        vibespaceID: String,
        filePath: String?,
        status: CommentStatusFilter,
        surfaceKind: CommentSurfaceKind? = nil
    ) -> [String: Any] {
        var p: [String: Any] = [
            "vibespaceId": vibespaceID,
            "status": status.rawValue,
        ]
        if let filePath { p["filePath"] = filePath }
        if let surfaceKind { p["surfaceKind"] = surfaceKind.rawValue }
        return p
    }

    static func encodeRelocate(id: String, anchor: CommentAnchor, isStale: Bool) -> [String: Any] {
        [
            "id": id,
            "startLine": anchor.startLine,
            "startColumn": anchor.startColumn,
            "endLine": anchor.endLine,
            "endColumn": anchor.endColumn,
            "isStale": isStale,
        ]
    }

    static func encodeMovePath(
        vibespaceID: String,
        oldPath: String,
        newPath: String,
        surfaceKind: CommentSurfaceKind
    ) -> [String: Any] {
        [
            "vibespaceId": vibespaceID,
            "oldPath": oldPath,
            "newPath": newPath,
            "surfaceKind": surfaceKind.rawValue,
        ]
    }
}

// MARK: - Decoding from RPC

enum CommentRPCDecoder {

    static func decodeComment(_ dict: [String: Any]) -> Comment? {
        guard let id = dict["id"] as? String,
              let vsID = dict["vibespaceId"] as? String,
              let filePath = dict["filePath"] as? String,
              let body = dict["body"] as? String,
              let authorKindRaw = dict["authorKind"] as? String,
              let authorKind = CommentAuthorKind(rawValue: authorKindRaw),
              let createdISO = dict["createdAt"] as? String,
              let updatedISO = dict["updatedAt"] as? String
        else { return nil }
        let createdAt = parseISO(createdISO) ?? Date()
        let updatedAt = parseISO(updatedISO) ?? createdAt
        let resolvedAt: Date? = (dict["resolvedAt"] as? String).flatMap(parseISO)
        let isStale = (dict["isStale"] as? Bool) ?? false
        let anchorDict = dict["anchor"] as? [String: Any] ?? [:]
        let surfaceKind = CommentSurfaceKind(rawValue: (dict["surfaceKind"] as? String) ?? "file") ?? .file

        let anchor = CommentAnchor(
            startLine: (anchorDict["startLine"] as? Int) ?? 1,
            startColumn: (anchorDict["startColumn"] as? Int) ?? 1,
            endLine: (anchorDict["endLine"] as? Int) ?? 1,
            endColumn: (anchorDict["endColumn"] as? Int) ?? 1,
            anchorHash: (anchorDict["anchorHash"] as? String) ?? "",
            anchorText: (anchorDict["anchorText"] as? String) ?? "",
            leadingContext: (anchorDict["leadingContext"] as? String) ?? "",
            trailingContext: (anchorDict["trailingContext"] as? String) ?? "",
            domSelector: anchorDict["domSelector"] as? String,
            domTextOffset: anchorDict["domTextOffset"] as? Int,
            domTextLength: anchorDict["domTextLength"] as? Int,
            domFingerprint: anchorDict["domFingerprint"] as? String
        )

        return Comment(
            id: id,
            vibespaceID: vsID,
            filePath: filePath,
            parentID: dict["parentId"] as? String,
            body: body,
            authorKind: authorKind,
            authorLabel: dict["authorLabel"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            resolvedAt: resolvedAt,
            isStale: isStale,
            anchor: anchor,
            surfaceKind: surfaceKind
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO(_ s: String) -> Date? {
        isoFormatter.date(from: s)
    }
}
