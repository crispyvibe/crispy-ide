import Foundation

/// F049-R03 + F049-R07: handlers for `comments.*` JSON-RPC methods invoked
/// over the agent CLI Unix socket. Resolves the active vibespace and project
/// from the calling channel client's `_env`, validates that the file path
/// lies inside the active vibespace (F049-T02 path traversal mitigation),
/// then delegates to `VibeSpaceCommentStore`.
extension CLICommandRouter {

    /// Shared formatter for ISO-8601 timestamp strings emitted by the CLI.
    /// Reusing a single instance avoids per-comment allocator churn when
    /// listing or searching large vibespaces.
    fileprivate static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - comments.add

    func handleCommentsAdd(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceCommentStore else {
            return notConnected(request, "comment store not attached")
        }
        guard let filePath = request.params?["file"]?.stringValue, !filePath.isEmpty else {
            return invalidParams(request, "`file` is required")
        }
        guard let body = request.params?["body"]?.stringValue, !body.isEmpty else {
            return invalidParams(request, "`body` is required")
        }
        // F049-v2: surface_kind discriminates file (default) vs browser.
        // For browser surfaces, `file` is treated as a URL (canonicalized).
        let surfaceRaw = request.params?["surface_kind"]?.stringValue ?? "file"
        guard let surfaceKind = CommentSurfaceKind(rawValue: surfaceRaw) else {
            return invalidParams(request, "surface_kind must be 'file' or 'browser'")
        }
        let startLine = max(1, request.params?["start_line"]?.intValue ?? 1)
        let startColumn = max(1, request.params?["start_column"]?.intValue ?? 1)
        let endLine = max(startLine, request.params?["end_line"]?.intValue ?? startLine)
        let endColumn = max(1, request.params?["end_column"]?.intValue ?? (startColumn + max(0, body.count)))

        let resolved: String
        switch surfaceKind {
        case .file:
            guard let r = resolveFilePath(filePath, env: request._env) else {
                return .error(
                    id: request.id,
                    code: CLIErrorCode.fileNotFound,
                    message: "file not in active vibespace: \(filePath)"
                )
            }
            resolved = r
        case .browser:
            // Canonicalize URL for stable lookup. Reject anything not URL-shaped.
            guard let url = URL(string: filePath), url.scheme != nil else {
                return invalidParams(request, "browser surface requires a URL with a scheme")
            }
            resolved = BrowserCommentURLNormalizer.canonicalize(url)
        }

        // Best-effort anchor text.
        let anchorText: String
        if surfaceKind == .file {
            anchorText = readFileSnippet(
                path: resolved,
                startLine: startLine,
                startColumn: startColumn,
                endLine: endLine,
                endColumn: endColumn
            ) ?? ""
        } else {
            // Browser comments — caller supplies anchor_text directly (the
            // CLI doesn't fetch the page).
            anchorText = request.params?["anchor_text"]?.stringValue ?? ""
        }

        let anchor = CommentAnchor(
            startLine: startLine,
            startColumn: startColumn,
            endLine: endLine,
            endColumn: endColumn,
            anchorHash: CommentAnchor.hash(anchorText),
            anchorText: anchorText,
            leadingContext: "",
            trailingContext: "",
            domSelector: request.params?["dom_selector"]?.stringValue,
            domTextOffset: request.params?["dom_text_offset"]?.intValue,
            domTextLength: request.params?["dom_text_length"]?.intValue,
            domFingerprint: request.params?["dom_fingerprint"]?.stringValue
        )

        let parentID = request.params?["parent_id"]?.stringValue
        let agentLabel = request._env?.context

        guard let created = await store.add(
            filePath: resolved,
            anchor: anchor,
            body: body,
            authorKind: .agent,
            authorLabel: agentLabel,
            parentID: parentID,
            surfaceKind: surfaceKind
        ) else {
            return .error(
                id: request.id,
                code: CLIErrorCode.internalError,
                message: store.lastErrorMessage ?? "comment.add failed"
            )
        }

        return .ok(id: request.id, result: encodeComment(created))
    }

    // MARK: - comments.list

    func handleCommentsList(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceCommentStore else {
            return notConnected(request, "comment store not attached")
        }
        guard let vibespaceID = store.currentVibeSpaceID() else {
            return .error(id: request.id, code: CLIErrorCode.vibespaceNotFound, message: "no active vibespace")
        }
        let statusRaw = request.params?["status"]?.stringValue ?? "active"
        guard let status = CommentStatusFilter(rawValue: statusRaw) else {
            return invalidParams(request, "status must be active, resolved, stale, or all")
        }

        let resolvedFile: String?
        if let raw = request.params?["file"]?.stringValue, !raw.isEmpty {
            guard let r = resolveFilePath(raw, env: request._env) else {
                return .error(
                    id: request.id,
                    code: CLIErrorCode.fileNotFound,
                    message: "file not in active vibespace: \(raw)"
                )
            }
            resolvedFile = r
            await store.refreshFile(vibespaceID: vibespaceID, filePath: r)
        } else {
            resolvedFile = nil
            await store.refreshAll()
        }

        let threads: [CommentThread]
        if let path = resolvedFile {
            threads = store.threads(forFile: path)
        } else {
            threads = store.threadsByFile.values.flatMap { $0 }
        }

        let filtered = threads.filter { status == .all || $0.status == status }
        let comments = filtered.flatMap { $0.allComments }
        return .ok(id: request.id, result: [
            "comments": .array(comments.map { .object(encodeComment($0)) }),
        ])
    }

    // MARK: - comments.reply

    func handleCommentsReply(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceCommentStore else {
            return notConnected(request, "comment store not attached")
        }
        guard let parentID = request.params?["id"]?.stringValue, !parentID.isEmpty else {
            return invalidParams(request, "`id` is required")
        }
        guard let body = request.params?["body"]?.stringValue, !body.isEmpty else {
            return invalidParams(request, "`body` is required")
        }

        // O(1) parent comment lookup via the store's index.
        guard let parent = store.comment(withID: parentID) else {
            return .error(id: request.id, code: CLIErrorCode.internalError, message: "parent comment not found: \(parentID)")
        }

        let agentLabel = request._env?.context
        guard let created = await store.add(
            filePath: parent.filePath,
            anchor: parent.anchor,
            body: body,
            authorKind: .agent,
            authorLabel: agentLabel,
            parentID: parentID,
            surfaceKind: parent.surfaceKind
        ) else {
            return .error(
                id: request.id,
                code: CLIErrorCode.internalError,
                message: store.lastErrorMessage ?? "comments.reply failed"
            )
        }
        return .ok(id: request.id, result: encodeComment(created))
    }

    // MARK: - comments.update

    func handleCommentsUpdate(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceCommentStore else {
            return notConnected(request, "comment store not attached")
        }
        guard let id = request.params?["id"]?.stringValue, !id.isEmpty else {
            return invalidParams(request, "`id` is required")
        }
        guard let body = request.params?["body"]?.stringValue, !body.isEmpty else {
            return invalidParams(request, "`body` is required")
        }
        let ok = await store.update(id: id, body: body)
        if !ok {
            return .error(id: request.id, code: CLIErrorCode.internalError, message: store.lastErrorMessage ?? "update failed")
        }
        return .ok(id: request.id, result: ["id": .string(id), "body": .string(body)])
    }

    // MARK: - comments.resolve

    func handleCommentsResolve(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceCommentStore else {
            return notConnected(request, "comment store not attached")
        }
        guard let id = request.params?["id"]?.stringValue, !id.isEmpty else {
            return invalidParams(request, "`id` is required")
        }
        let unresolve = request.params?["unresolve"]?.boolValue ?? false
        let ok = await store.resolve(id: id, unresolve: unresolve)
        if !ok {
            return .error(id: request.id, code: CLIErrorCode.internalError, message: store.lastErrorMessage ?? "resolve failed")
        }
        return .ok(id: request.id, result: [
            "id": .string(id),
            "resolvedAt": unresolve ? .null : .string(Self.isoFormatter.string(from: Date())),
        ])
    }

    // MARK: - comments.delete

    func handleCommentsDelete(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceCommentStore else {
            return notConnected(request, "comment store not attached")
        }
        guard let id = request.params?["id"]?.stringValue, !id.isEmpty else {
            return invalidParams(request, "`id` is required")
        }
        let count = await store.delete(id: id)
        return .ok(id: request.id, result: [
            "id": .string(id),
            "deletedCount": .int(count),
        ])
    }

    // MARK: - comments.search

    /// Routes through the Rust `comment.search` RPC (FTS5-backed). Avoids
    /// the prior client-side `refreshAll() + substring filter` approach
    /// which defeated the purpose of the persistence helper's index.
    func handleCommentsSearch(_ request: CLIRequest) async -> CLIResponse {
        guard let store = vibespaceCommentStore else {
            return notConnected(request, "comment store not attached")
        }
        let query = request.params?["query"]?.stringValue ?? ""
        let filePrefix = request.params?["file_prefix"]?.stringValue
        let statusRaw = request.params?["status"]?.stringValue ?? "active"
        guard let status = CommentStatusFilter(rawValue: statusRaw) else {
            return invalidParams(request, "status must be active, resolved, stale, or all")
        }
        let comments = await store.search(query: query, filePrefix: filePrefix, status: status)
        return .ok(id: request.id, result: [
            "comments": .array(comments.map { .object(encodeComment($0)) }),
        ])
    }

    // MARK: - Helpers

    /// Resolves a file path against the calling agent's project root and the
    /// active vibespace. Returns the canonical absolute path or nil if the
    /// path falls outside any project root in the active vibespace
    /// (F049-T02 mitigation).
    private func resolveFilePath(_ raw: String, env: CLIChannelClientEnv?) -> String? {
        let url: URL
        if raw.hasPrefix("/") {
            url = URL(fileURLWithPath: raw).standardizedFileURL
        } else if let project = env?.project_path, !project.isEmpty {
            url = URL(fileURLWithPath: project)
                .appendingPathComponent(raw)
                .standardizedFileURL
        } else {
            url = URL(fileURLWithPath: raw).standardizedFileURL
        }
        let canonical = url.path
        guard let vibespace = activeVibeSpace else { return nil }
        for project in vibespace.projects {
            let prefix = project.projectIdentifier.hasSuffix("/")
                ? project.projectIdentifier
                : project.projectIdentifier + "/"
            if canonical == project.projectIdentifier || canonical.hasPrefix(prefix) {
                return canonical
            }
        }
        return nil
    }

    /// Best-effort: read the file at `path` and extract the substring at the
    /// given 1-based range. Returns nil if the file can't be read.
    private func readFileSnippet(
        path: String,
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int
    ) -> String? {
        guard let content = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            return nil
        }
        let lines = content.components(separatedBy: "\n")
        return CommentAnchorRelocator.extractSnippet(
            lines: lines,
            startLine: startLine,
            startColumn: startColumn,
            endLine: endLine,
            endColumn: endColumn
        )
    }

    private func encodeComment(_ c: Comment) -> [String: CLIJSONValue] {
        let iso = Self.isoFormatter
        var anchor: [String: CLIJSONValue] = [
            "startLine": .int(c.anchor.startLine),
            "startColumn": .int(c.anchor.startColumn),
            "endLine": .int(c.anchor.endLine),
            "endColumn": .int(c.anchor.endColumn),
            "anchorHash": .string(c.anchor.anchorHash),
            "anchorText": .string(c.anchor.anchorText),
            "leadingContext": .string(c.anchor.leadingContext),
            "trailingContext": .string(c.anchor.trailingContext),
        ]
        if let s = c.anchor.domSelector { anchor["domSelector"] = .string(s) }
        if let o = c.anchor.domTextOffset { anchor["domTextOffset"] = .int(o) }
        if let l = c.anchor.domTextLength { anchor["domTextLength"] = .int(l) }
        if let f = c.anchor.domFingerprint { anchor["domFingerprint"] = .string(f) }

        return [
            "id": .string(c.id),
            "vibespaceId": .string(c.vibespaceID),
            "filePath": .string(c.filePath),
            "parentId": c.parentID.map { .string($0) } ?? .null,
            "body": .string(c.body),
            "authorKind": .string(c.authorKind.rawValue),
            "authorLabel": c.authorLabel.map { .string($0) } ?? .null,
            "surfaceKind": .string(c.surfaceKind.rawValue),
            "createdAt": .string(iso.string(from: c.createdAt)),
            "updatedAt": .string(iso.string(from: c.updatedAt)),
            "resolvedAt": c.resolvedAt.map { .string(iso.string(from: $0)) } ?? .null,
            "isStale": .bool(c.isStale),
            "anchor": .object(anchor),
        ]
    }

    private func invalidParams(_ request: CLIRequest, _ message: String) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.invalidParams, message: message)
    }

    private func notConnected(_ request: CLIRequest, _ message: String) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.notConnected, message: message)
    }

    /// The vibespace that the comment store is currently scoped to. Uses
    /// the store's resolver (which reads `appShellStore.activeVibeSpaceID`)
    /// rather than `vibespaces.first`.
    private var activeVibeSpace: VibeSpaceState? {
        guard let vsID = vibespaceCommentStore?.currentVibeSpaceID(),
              let uuid = UUID(uuidString: vsID) else { return nil }
        return vibespaceCatalogStore?.vibespaces.first(where: { $0.id == uuid })
    }
}
