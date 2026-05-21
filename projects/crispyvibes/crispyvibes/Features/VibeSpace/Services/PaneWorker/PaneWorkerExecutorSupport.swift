import Foundation

extension PaneWorkerExecutor {
    static func requiredArgument(_ key: String, from arguments: [String: String]) throws -> String {
        guard let value = arguments[key], !value.isEmpty else {
            throw PaneWorkerError.workerFailure("Missing required argument: \(key)")
        }
        return value
    }

    static func encodeJSONText<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PaneWorkerError.invalidResponse
        }
        return text
    }

    struct CommandResult {
        let terminationStatus: Int32
        let stdoutData: Data
        let stderrData: Data
    }
}
