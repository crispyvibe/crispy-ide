import Foundation

struct ACPClientInfo {
    let name: String
    let title: String
    let version: String

    static let crispyvibes = ACPClientInfo(
        name: "crispyvibes",
        title: "Crispy",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    )
}

enum JSONRPCId: Codable, Hashable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCId
    let method: String
    let params: AnyCodable?

    init(id: Int, method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.id = .int(id)
        self.method = method
        self.params = params
    }
}

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: AnyCodable?
    let error: JSONRPCError?

    var isSuccess: Bool { error == nil }
}

struct JSONRPCNotification: Codable, Sendable {
    let jsonrpc: String
    let method: String
    let params: AnyCodable?
}

struct JSONRPCError: Codable, Error, LocalizedError, Sendable {
    let code: Int
    let message: String

    var errorDescription: String? { message }
}

enum JSONRPCMessage {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case notification(JSONRPCNotification)

    static func decode(from data: Data) throws -> JSONRPCMessage {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let hasMethod = object["method"] != nil
        let hasID = object["id"] != nil
        if hasMethod && hasID {
            return .request(try JSONDecoder().decode(JSONRPCRequest.self, from: data))
        }
        if hasMethod {
            return .notification(try JSONDecoder().decode(JSONRPCNotification.self, from: data))
        }
        return .response(try JSONDecoder().decode(JSONRPCResponse.self, from: data))
    }
}

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map(\.value)
        } else if let objectValue = try? container.decode([String: AnyCodable].self) {
            value = objectValue.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map(AnyCodable.init))
        case let objectValue as [String: Any]:
            try container.encode(objectValue.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unsupported JSON type"))
        }
    }

    var dictValue: [String: Any]? { value as? [String: Any] }
    subscript(key: String) -> Any? { dictValue?[key] }
}

struct ACPInitializeResult: Codable, Sendable {
    let protocolVersion: Int
    let agentCapabilities: ACPAgentCapabilities?
    let agentInfo: ACPAgentInfo?
    let authMethods: [String]?
}

struct ACPAgentCapabilities: Codable, Sendable {
    let loadSession: Bool?
    let sessionCapabilities: ACPSessionCapabilities?
    let promptCapabilities: ACPPromptCapabilities?
    let mcpCapabilities: ACPMCPCapabilities?
}

struct ACPSessionCapabilities: Codable, Sendable {
    let resume: AnyCodable?
    let close: AnyCodable?

    var supportsResume: Bool { resume != nil }
    var supportsClose: Bool { close != nil }
}

struct ACPPromptCapabilities: Codable, Sendable {
    let image: Bool?
    let audio: Bool?
    let embeddedContext: Bool?
}

struct ACPMCPCapabilities: Codable, Sendable {
    let http: Bool?
    let sse: Bool?
}

struct ACPAgentInfo: Codable, Sendable {
    let name: String?
    let title: String?
    let version: String?
}

struct ACPModelInfo: Identifiable, Equatable, Sendable {
    let modelId: String
    let name: String
    let description: String?

    var id: String { modelId }
}

struct ACPSessionModelState: Sendable {
    let availableModels: [ACPModelInfo]
    let currentModelId: String

    static func parse(from dict: [String: Any]) -> ACPSessionModelState? {
        guard
            let models = dict["availableModels"] as? [[String: Any]],
            let currentModelId = dict["currentModelId"] as? String
        else {
            return nil
        }

        let parsedModels = models.compactMap { model -> ACPModelInfo? in
            guard let modelId = model["modelId"] as? String else { return nil }
            return ACPModelInfo(
                modelId: modelId,
                name: model["name"] as? String ?? modelId,
                description: model["description"] as? String
            )
        }
        return ACPSessionModelState(availableModels: parsedModels, currentModelId: currentModelId)
    }
}

struct ACPModeInfo: Identifiable, Equatable, Sendable {
    let modeId: String
    let name: String
    let description: String?

    var id: String { modeId }
}

struct ACPSessionModeState: Sendable {
    let availableModes: [ACPModeInfo]
    let currentModeId: String

    static func parse(from dict: [String: Any]) -> ACPSessionModeState? {
        guard
            let modes = dict["availableModes"] as? [[String: Any]],
            let currentModeId = dict["currentModeId"] as? String
        else {
            return nil
        }

        let parsedModes = modes.compactMap { mode -> ACPModeInfo? in
            guard let modeId = mode["id"] as? String else { return nil }
            return ACPModeInfo(
                modeId: modeId,
                name: mode["name"] as? String ?? modeId,
                description: mode["description"] as? String
            )
        }
        return ACPSessionModeState(availableModes: parsedModes, currentModeId: currentModeId)
    }
}

enum ACPContentBlock: Codable, Sendable {
    case text(String)
}

struct ACPToolCallUpdate: Sendable {
    let toolCallId: String
    let title: String?
    let kind: String?
    let status: ACPToolCallStatus?
    let content: [ACPToolCallContent]
    let locations: [ACPToolCallLocation]
}

struct ACPToolCallStatusUpdate: Sendable {
    let toolCallId: String
    let status: ACPToolCallStatus
    let content: [ACPToolCallContent]
}

enum ACPToolCallStatus: String, Sendable, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
    case error
}

enum ACPToolCallContent: Equatable, Sendable, Codable {
    case text(String)
    case diff(ACPDiff)
    case terminal(String)

    private enum CodingKeys: String, CodingKey { case type, value, path, oldText, newText }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try container.encode("text", forKey: .type)
            try container.encode(s, forKey: .value)
        case .diff(let d):
            try container.encode("diff", forKey: .type)
            try container.encode(d.path, forKey: .path)
            try container.encodeIfPresent(d.oldText, forKey: .oldText)
            try container.encode(d.newText, forKey: .newText)
        case .terminal(let s):
            try container.encode("terminal", forKey: .type)
            try container.encode(s, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "diff":
            let path = try container.decode(String.self, forKey: .path)
            let oldText = try container.decodeIfPresent(String.self, forKey: .oldText)
            let newText = try container.decode(String.self, forKey: .newText)
            self = .diff(ACPDiff(path: path, oldText: oldText, newText: newText))
        case "terminal":
            self = .terminal(try container.decode(String.self, forKey: .value))
        default:
            self = .text(try container.decode(String.self, forKey: .value))
        }
    }
}

struct ACPDiff: Equatable, Sendable, Codable {
    let path: String
    let oldText: String?
    let newText: String
}

struct ACPToolCallLocation: Equatable, Sendable, Codable {
    let path: String
    let line: Int?
}

struct ACPPermissionOption: Sendable {
    let optionId: String
    let name: String
    let kind: String
}

/// A structured question from the agent requesting user input (#4).
struct ACPUserInputRequest: Identifiable, Sendable {
    let id: String
    let question: String
    let options: [ACPUserInputOption]
    let allowCustom: Bool
}

struct ACPUserInputOption: Identifiable, Sendable {
    let id: String
    let label: String
    let description: String?
}

enum ACPPermissionOutcome: Sendable {
    case cancelled
    case selected(optionId: String)

    var responseDict: [String: Any] {
        switch self {
        case .cancelled:
            return ["outcome": ["outcome": "cancelled"]]
        case .selected(let optionId):
            return ["outcome": ["outcome": "selected", "optionId": optionId]]
        }
    }
}

enum ACPToolCallContentParser {
    static func parse(_ raw: [[String: Any]]?) -> [ACPToolCallContent] {
        guard let raw else { return [] }
        return raw.compactMap { item in
            switch item["type"] as? String {
            case "diff":
                guard let newText = item["newText"] as? String else { return nil }
                return .diff(
                    ACPDiff(
                        path: item["path"] as? String ?? "",
                        oldText: item["oldText"] as? String,
                        newText: newText
                    )
                )
            case "content":
                if let content = item["content"] as? [String: Any], let text = content["text"] as? String {
                    return .text(text)
                }
                return nil
            case "text":
                if let text = item["text"] as? String {
                    return .text(text)
                }
                return nil
            case "terminal":
                return (item["terminalId"] as? String).map { .terminal($0) }
            default:
                // Try to extract text from unknown types
                if let text = item["text"] as? String { return .text(text) }
                return nil
            }
        }
    }

    static func parseLocations(_ raw: [[String: Any]]?) -> [ACPToolCallLocation] {
        guard let raw else { return [] }
        return raw.compactMap { item in
            guard let path = item["path"] as? String else { return nil }
            return ACPToolCallLocation(path: path, line: item["line"] as? Int)
        }
    }
}

enum ACPUpdate {
    case agentMessageChunk(ACPContentBlock)
    case userMessageChunk(ACPContentBlock)
    case thoughtChunk(ACPContentBlock)
    case toolCall(ACPToolCallUpdate)
    case toolCallUpdate(ACPToolCallStatusUpdate)
    case availableCommandsUpdate([[String: Any]])
    case currentModeUpdate(String)
    case configOptionUpdate([String: Any])
    case sessionInfoUpdate([String: Any])
    case error(String)
    case userInputRequest(ACPUserInputRequest)
    case turnCompleted
    case unknown(String)

    static func decode(from dict: [String: Any]) -> ACPUpdate {
        guard let sessionUpdate = dict["sessionUpdate"] as? String else {
            return .unknown("missing sessionUpdate")
        }

        switch sessionUpdate {
        case "agent_message_chunk":
            return decodeChunk(from: dict).map { .agentMessageChunk($0) } ?? .unknown("bad agent chunk")
        case "user_message_chunk":
            return decodeChunk(from: dict).map { .userMessageChunk($0) } ?? .unknown("bad user chunk")
        case "agent_thought_chunk":
            return decodeChunk(from: dict).map { .thoughtChunk($0) } ?? .unknown("bad thought chunk")
        case "tool_call":
            return decodeToolCall(from: dict).map { .toolCall($0) } ?? .unknown("bad tool call")
        case "tool_call_update":
            return decodeToolCallUpdate(from: dict).map { .toolCallUpdate($0) } ?? .unknown("bad tool call update")
        case "available_commands_update":
            return .availableCommandsUpdate(
                (dict["commands"] as? [[String: Any]])
                    ?? (dict["availableCommands"] as? [[String: Any]])
                    ?? []
            )
        case "current_mode_update":
            return .currentModeUpdate(dict["currentModeId"] as? String ?? "")
        case "config_option_update":
            return .configOptionUpdate(dict)
        case "session_info_update":
            return .sessionInfoUpdate(dict)
        case "user_input_request":
            return decodeUserInputRequest(from: dict).map { .userInputRequest($0) } ?? .unknown("bad user input request")
        case "turn_completed":
            return .turnCompleted
        default:
            return .unknown(sessionUpdate)
        }
    }

    private static func decodeChunk(from dict: [String: Any]) -> ACPContentBlock? {
        guard let content = dict["content"] as? [String: Any], let text = content["text"] as? String else {
            return nil
        }
        return .text(text)
    }

    private static func decodeToolCall(from dict: [String: Any]) -> ACPToolCallUpdate? {
        guard let toolCallId = dict["toolCallId"] as? String else { return nil }
        return ACPToolCallUpdate(
            toolCallId: toolCallId,
            title: dict["title"] as? String,
            kind: dict["kind"] as? String,
            status: (dict["status"] as? String).flatMap(ACPToolCallStatus.init(rawValue:)),
            content: ACPToolCallContentParser.parse(dict["content"] as? [[String: Any]]),
            locations: ACPToolCallContentParser.parseLocations(dict["locations"] as? [[String: Any]])
        )
    }

    private static func decodeToolCallUpdate(from dict: [String: Any]) -> ACPToolCallStatusUpdate? {
        guard let toolCallId = dict["toolCallId"] as? String else { return nil }
        return ACPToolCallStatusUpdate(
            toolCallId: toolCallId,
            status: (dict["status"] as? String).flatMap(ACPToolCallStatus.init(rawValue:)) ?? .inProgress,
            content: ACPToolCallContentParser.parse(dict["content"] as? [[String: Any]])
        )
    }

    private static func decodeUserInputRequest(from dict: [String: Any]) -> ACPUserInputRequest? {
        guard let id = dict["requestId"] as? String,
              let question = dict["question"] as? String else { return nil }
        let rawOptions = dict["options"] as? [[String: Any]] ?? []
        let options = rawOptions.map { opt in
            ACPUserInputOption(
                id: opt["id"] as? String ?? UUID().uuidString,
                label: opt["label"] as? String ?? opt["name"] as? String ?? "",
                description: opt["description"] as? String
            )
        }
        return ACPUserInputRequest(
            id: id,
            question: question,
            options: options,
            allowCustom: dict["allowCustom"] as? Bool ?? false
        )
    }
}
