import Foundation

/// Channel client context inherited from the calling agent's environment.
/// Sent in the request's `_env` field; values are convenience defaults only,
/// never trusted for authorization (see F044-T03 in threat-model.md).
///
/// `context` is a tagged ID like `"terminal.<uuid>"` or `"acpchat.<uuid>"`
/// telling the server *what kind* of process is calling. `vibespace` is
/// `"vibespace.<uuid>"`. `project_path` is an absolute file system path.
struct CLIChannelClientEnv: Codable {
    let context: String?
    let vibespace: String?
    let project_path: String?

    static let empty = CLIChannelClientEnv(
        context: nil,
        vibespace: nil,
        project_path: nil
    )
}

/// Parsed `<kind>.<uuid>` tagged identifier. Use `init(rawValue:)` to attempt
/// parsing; returns `nil` if the input has no prefix.
struct CLITaggedID {
    let kind: String
    let id: String

    init?(rawValue: String) {
        guard let dot = rawValue.firstIndex(of: ".") else { return nil }
        let kindPart = rawValue[..<dot]
        let idPart = rawValue[rawValue.index(after: dot)...]
        guard !kindPart.isEmpty, !idPart.isEmpty else { return nil }
        self.kind = String(kindPart)
        self.id = String(idPart)
    }

    var stringValue: String { "\(kind).\(id)" }

    /// Strip the prefix from a possibly-tagged ID. If `expectedKind` is given
    /// and doesn't match, returns `raw` unchanged. Pass through for bare UUIDs.
    static func extractID(from raw: String, expectedKind: String? = nil) -> String {
        guard let tagged = CLITaggedID(rawValue: raw) else { return raw }
        if let expectedKind, tagged.kind != expectedKind { return raw }
        return tagged.id
    }
}

/// JSON-RPC v2 request as sent by the CLI client.
struct CLIRequest: Decodable {
    let id: String
    let method: String
    /// Free-form parameters; commands decode this further.
    let params: [String: CLIJSONValue]?
    /// Channel client environment — convenience defaults, not authorization.
    let _env: CLIChannelClientEnv?
}

/// JSON-RPC v2 response written back to the CLI client.
enum CLIResponse {
    case ok(id: String, result: [String: CLIJSONValue])
    case error(id: String, code: String, message: String)

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        switch self {
        case let .ok(id, result):
            let payload = OkPayload(id: id, ok: true, result: result)
            return try encoder.encode(payload)
        case let .error(id, code, message):
            let payload = ErrorPayload(
                id: id,
                ok: false,
                error: ErrorBody(code: code, message: message)
            )
            return try encoder.encode(payload)
        }
    }

    private struct OkPayload: Encodable {
        let id: String
        let ok: Bool
        let result: [String: CLIJSONValue]
    }

    private struct ErrorPayload: Encodable {
        let id: String
        let ok: Bool
        let error: ErrorBody
    }

    private struct ErrorBody: Encodable {
        let code: String
        let message: String
    }
}

/// Canonical CLI error codes (see spec.md Error Codes table).
enum CLIErrorCode {
    static let unknownMethod = "unknown_method"
    static let invalidParams = "invalid_params"
    static let terminalNotFound = "terminal_not_found"
    static let vibespaceNotFound = "vibespace_not_found"
    static let paneNotFound = "pane_not_found"
    static let fileNotFound = "file_not_found"
    static let permissionDenied = "permission_denied"
    static let unsupportedEngine = "unsupported_engine"
    static let timeoutCode = "timeout"
    static let notConnected = "not_connected"
    static let internalError = "internal_error"
}

/// Minimal type-erased Codable JSON value for params/result payloads.
/// Supports primitives, arrays, and dictionaries — enough for our CLI surface.
enum CLIJSONValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([CLIJSONValue])
    case object([String: CLIJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CLIJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CLIJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .int(value): return value
        case let .double(value): return Int(value)
        default: return nil
        }
    }

    var arrayValue: [CLIJSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var objectValue: [String: CLIJSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }
}
