import Foundation

/// Encodes ACP timeline types into JSON dictionaries for the persistence helper RPC.
/// This avoids adding Codable to the existing types which have complex enum cases.
enum ACPPersistenceEncoder {

    static func encodeMessage(
        id: String,
        threadId: String,
        turnId: String?,
        role: String,
        text: String,
        isStreaming: Bool
    ) -> [String: Any] {
        var params: [String: Any] = [
            "id": id,
            "threadId": threadId,
            "role": role,
            "text": text,
            "isStreaming": isStreaming,
        ]
        if let turnId { params["turnId"] = turnId }
        return params
    }

    static func encodeActivity(
        id: String,
        threadId: String,
        turnId: String?,
        kind: String,
        summary: String,
        payload: [String: Any]? = nil
    ) -> [String: Any] {
        var params: [String: Any] = [
            "id": id,
            "threadId": threadId,
            "kind": kind,
            "summary": summary,
        ]
        if let turnId { params["turnId"] = turnId }
        if let payload {
            // Extract itemType to top-level for the Rust handler (R28)
            if let itemType = payload["itemType"] as? String {
                params["itemType"] = itemType
            }
            if let json = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: json, encoding: .utf8) {
                params["payloadJson"] = str
            }
        }
        return params
    }

    static func encodeToolCallActivity(
        threadId: String,
        turnId: String?,
        toolCall: ACPToolCallState
    ) -> [String: Any] {
        let payload: [String: Any] = [
            "toolCallId": toolCall.id,
            "title": toolCall.title,
            "kind": toolCall.kind ?? "unknown",
            "status": toolCall.status.rawValue,
        ]
        return encodeActivity(
            id: UUID().uuidString,
            threadId: threadId,
            turnId: turnId,
            kind: "tool_call",
            summary: toolCall.title,
            payload: payload
        )
    }

    static func encodeSessionUpsert(
        threadId: String,
        provider: String,
        transportKind: String,
        status: String,
        resumeStrategy: String = "none",
        runtimeMode: String = "direct",
        capabilities: String? = nil,
        providerSessionId: String? = nil,
        resumeCursorJson: String? = nil
    ) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadId,
            "provider": provider,
            "transportKind": transportKind,
            "status": status,
            "resumeStrategy": resumeStrategy,
            "runtimeMode": runtimeMode,
        ]
        if let capabilities { params["capabilities"] = capabilities }
        if let providerSessionId { params["providerSessionId"] = providerSessionId }
        if let resumeCursorJson { params["resumeCursorJson"] = resumeCursorJson }
        return params
    }

    static func encodeThreadCreate(
        id: String,
        vibespaceId: String,
        projectPath: String,
        title: String,
        agentId: String,
        transportKind: String,
        model: String,
        threadKind: String = "conversation",
        parentThreadId: String? = nil,
        metadata: String = "{}",
        tags: String = "[]"
    ) -> [String: Any] {
        var params: [String: Any] = [
            "id": id,
            "vibespaceId": vibespaceId,
            "projectPath": projectPath,
            "title": title,
            "agentId": agentId,
            "transportKind": transportKind,
            "model": model,
            "threadKind": threadKind,
            "metadata": metadata,
            "tags": tags,
        ]
        if let parentThreadId { params["parentThreadId"] = parentThreadId }
        return params
    }
}
