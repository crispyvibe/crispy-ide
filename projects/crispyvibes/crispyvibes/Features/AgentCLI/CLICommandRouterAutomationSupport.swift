import Foundation

struct AutomationCLIInputError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

extension CLIJSONValue {
    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> CLIJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(CLIJSONValue.self, from: data)
    }
}

extension CLICommandRouter {
    static let automationDateFormatter = ISO8601DateFormatter()
    static let automationFractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parseDate(_ value: String) throws -> Date {
        if let date = automationFractionalDateFormatter.date(from: value)
            ?? automationDateFormatter.date(from: value) {
            return date
        }
        throw AutomationCLIInputError("invalid ISO-8601 date: \(value)")
    }

    static func automationDateString(_ value: Date) -> String {
        automationDateFormatter.string(from: value)
    }

    static func validationResult(_ issues: [String]) -> [String: CLIJSONValue] {
        [
            "valid": .bool(issues.isEmpty),
            "issues": .array(issues.map { .string($0) }),
        ]
    }

    func automationInvalid(_ request: CLIRequest, _ message: String) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.invalidParams, message: message)
    }

    func automationUnavailable(_ request: CLIRequest, _ resource: String) -> CLIResponse {
        .error(id: request.id, code: CLIErrorCode.notConnected, message: "\(resource) unavailable")
    }

    func expectedVersionFailure(
        _ request: CLIRequest,
        currentVersion: Int,
        resource: String
    ) -> CLIResponse? {
        guard let expectedVersion = request.params?["expectedVersion"]?.intValue else {
            return automationInvalid(request, "`expectedVersion` is required")
        }
        guard expectedVersion == currentVersion else {
            return .error(
                id: request.id,
                code: CLIErrorCode.conflict,
                message: "\(resource) version conflict: expected \(expectedVersion), current \(currentVersion)"
            )
        }
        return nil
    }

    func automationPersistenceFailed(_ request: CLIRequest, _ detail: String?) -> CLIResponse {
        .error(
            id: request.id,
            code: CLIErrorCode.internalError,
            message: detail ?? "Automation persistence failed"
        )
    }
}

extension String {
    var automationNonEmpty: String? { isEmpty ? nil : self }
}
