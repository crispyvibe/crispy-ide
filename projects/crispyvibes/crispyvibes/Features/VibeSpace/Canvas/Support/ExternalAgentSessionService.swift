import Foundation
import OSLog

enum ExternalAgentSessionProvider: String, CaseIterable, Codable, Identifiable {
    case codex
    case claude
    case kiro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .kiro: "Kiro CLI"
        }
    }
}

struct ExternalAgentSessionSummary: Identifiable, Codable, Equatable {
    let provider: ExternalAgentSessionProvider
    let providerName: String
    let sessionId: String
    let title: String
    let projectPath: String
    let sourcePath: String
    let createdAt: String
    let updatedAt: String
    let modifiedAtEpoch: UInt64
    let messageCount: Int
    let hasToolActivity: Bool
    let parseStatus: String
    let parseErrors: [ExternalAgentSessionDiagnostic]
    let parentSessionId: String?
    let searchSnippet: String?
    let searchSnippets: [String]
    let matchCount: Int

    var id: String { "\(provider.rawValue):\(sourcePath)" }

    var projectDisplayName: String {
        projectPath.isEmpty ? "External" : URL(fileURLWithPath: projectPath).lastPathComponent
    }

    var relativeTime: String {
        guard let date = lastActivityDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var lastActivityDate: Date? {
        if modifiedAtEpoch > 0 {
            return Date(timeIntervalSince1970: TimeInterval(modifiedAtEpoch))
        }
        let raw = updatedAt.isEmpty ? createdAt : updatedAt
        return ISO8601DateFormatter.externalAgentSession.date(from: raw)
            ?? ISO8601DateFormatter.externalAgentSessionLoose.date(from: raw)
    }

    var matchCountLabel: String {
        AppStrings.Sidebar.ExternalSessions.matchCount(matchCount)
    }

    var displaySearchSnippets: [String] {
        if !searchSnippets.isEmpty { return searchSnippets }
        return searchSnippet.map { [$0] } ?? []
    }

    var resumeCommand: String {
        switch provider {
        case .codex:
            return "codex resume \(sessionId)"
        case .claude:
            return "claude --resume \(sessionId)"
        case .kiro:
            return "kiro-cli chat --resume-id \(sessionId)"
        }
    }

    var shortSessionId: String {
        String(sessionId.prefix(8))
    }
}

struct ExternalAgentTranscriptEntry: Identifiable, Codable, Equatable {
    let role: String
    let timestamp: String
    let text: String
    let metadata: [String: JSONValue]

    var id: String { "\(role):\(timestamp):\(text.hashValue)" }
}

struct ExternalAgentTranscript: Codable, Equatable {
    let session: ExternalAgentSessionSummary
    let entries: [ExternalAgentTranscriptEntry]
    let parseErrors: [ExternalAgentSessionDiagnostic]
}

struct ExternalAgentSessionDiagnostic: Codable, Equatable, Identifiable {
    let provider: String
    let sourcePath: String
    let parser: String
    let line: Int?
    let context: String
    let message: String

    var id: String {
        "\(provider):\(sourcePath):\(line ?? 0):\(context):\(message)"
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct ExternalAgentSessionScanResult: Codable, Equatable {
    let sessions: [ExternalAgentSessionSummary]
    let diagnostics: [ExternalAgentSessionDiagnostic]
}

final class ExternalAgentSessionService: @unchecked Sendable {
    enum ServiceError: LocalizedError {
        case helperUnavailable
        case helperFailed(String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                return "External session helper is unavailable."
            case .helperFailed(let message):
                return message
            case .invalidResponse(let message):
                return "External session helper returned invalid output: \(message)"
            }
        }
    }

    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "externalAgentSessions")
    private let helperURL: URL?

    init(helperURL: URL? = ExternalAgentSessionService.resolveHelperURL()) {
        self.helperURL = helperURL
    }

    func scan(provider: ExternalAgentSessionProvider? = nil, limit: Int = 500) async throws -> ExternalAgentSessionScanResult {
        var arguments = ["scan", "--limit", "\(limit)"]
        if let provider {
            arguments += ["--provider", provider.rawValue]
        }
        let result = try await run(arguments: arguments, decoding: ExternalAgentSessionScanResult.self)
        recordDiagnostics(result.diagnostics, operation: "scan")
        return result
    }

    func search(
        query: String,
        provider: ExternalAgentSessionProvider? = nil,
        limit: Int = 100
    ) async throws -> ExternalAgentSessionScanResult {
        var arguments = ["search", query, "--limit", "\(limit)"]
        if let provider {
            arguments += ["--provider", provider.rawValue]
        }
        let result = try await run(arguments: arguments, decoding: ExternalAgentSessionScanResult.self)
        recordDiagnostics(result.diagnostics, operation: "search")
        return result
    }

    func load(session: ExternalAgentSessionSummary) async throws -> ExternalAgentTranscript {
        let result = try await run(
            arguments: [
                "load",
                "--provider", session.provider.rawValue,
                "--source-path", session.sourcePath,
            ],
            decoding: ExternalAgentTranscript.self
        )
        recordDiagnostics(result.parseErrors, operation: "load")
        return result
    }

    private func run<T: Decodable>(arguments: [String], decoding type: T.Type) async throws -> T {
        try await Task.detached(priority: .userInitiated) { [helperURL, logger] in
            guard let helperURL else { throw ServiceError.helperUnavailable }

            let process = Process()
            process.executableURL = helperURL
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                throw ServiceError.helperFailed(error.localizedDescription)
            }

            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorOutput, encoding: .utf8) ?? "status \(process.terminationStatus)"
                logger.error("External session helper failed: \(message, privacy: .public)")
                throw ServiceError.helperFailed(message)
            }

            do {
                let decoder = JSONDecoder()
                return try decoder.decode(type, from: output)
            } catch {
                let raw = String(data: output, encoding: .utf8) ?? ""
                logger.error("External session helper decode failed: \(error.localizedDescription, privacy: .public)")
                throw ServiceError.invalidResponse(raw)
            }
        }.value
    }

    private static func resolveHelperURL() -> URL? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        let url = execURL.deletingLastPathComponent()
            .appendingPathComponent("crispyvibes-external-sessions-helper", isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func recordDiagnostics(_ diagnostics: [ExternalAgentSessionDiagnostic], operation: String) {
        for diagnostic in diagnostics {
            var metadata = [
                "operation": operation,
                "provider": diagnostic.provider,
                "sourcePath": diagnostic.sourcePath,
                "parser": diagnostic.parser,
                "context": diagnostic.context,
                "message": diagnostic.message,
            ]
            if let line = diagnostic.line {
                metadata["line"] = String(line)
            }
            AppDiagnostics.record(
                category: .externalSessions,
                level: .error,
                event: "external_session_parse_diagnostic",
                metadata: metadata
            )
        }
    }
}

private extension ISO8601DateFormatter {
    static let externalAgentSession: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let externalAgentSessionLoose: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
