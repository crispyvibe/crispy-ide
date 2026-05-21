import Foundation
import OSLog

enum ACPTransportError: LocalizedError {
    case disconnected(String)
    case agentError(String)
    case requestTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .disconnected(let reason):
            return reason
        case .agentError(let message):
            return message
        case .requestTimedOut(let method):
            return "Timed out waiting for ACP response to \(method)."
        }
    }
}

protocol ACPTransportProtocol: AnyObject, Sendable {
    func start(executable: String, arguments: [String], environment: [String: String]?) async throws
    func send(method: String, params: [String: Any]?) async throws -> JSONRPCResponse
    func sendNotification(method: String, params: [String: Any]?) async throws
    func setRequestHandler(_ handler: @escaping @Sendable (String, [String: Any]) async throws -> Any) async
    func setTerminationHandler(_ handler: @escaping @Sendable (_ reason: String) -> Void) async
    func stop() async
    var isRunning: Bool { get async }
    var lastStderrOutput: String { get async }
    func notifications() async -> AsyncStream<JSONRPCNotification>
}

actor ACPTransport: ACPTransportProtocol {
    private struct RequestContext: Sendable {
        let method: String
        let startedAt: Date
    }

    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "acp.transport")
    private let localSessionID: String
    private let agentID: String
    private let projectToken: String?
    private let origin: String
    private let observabilityStore: ACPObservabilityStore?
    private let requestTimeout: Duration

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var nextRequestID = 1
    private var pendingRequests: [JSONRPCId: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var requestContexts: [JSONRPCId: RequestContext] = [:]
    private var pendingRequestTimeoutTasks: [JSONRPCId: Task<Void, Never>] = [:]
    private var notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation?
    private var requestHandler: (@Sendable (String, [String: Any]) async throws -> Any)?
    private var terminationHandler: (@Sendable (_ reason: String) -> Void)?
    private var readTask: Task<Void, Never>?
    private(set) var lastStderrOutput = ""

    init(
        localSessionID: String,
        agentID: String,
        projectToken: String?,
        origin: String,
        observabilityStore: ACPObservabilityStore?,
        requestTimeout: Duration = .seconds(10)
    ) {
        self.localSessionID = localSessionID
        self.agentID = agentID
        self.projectToken = projectToken
        self.origin = origin
        self.observabilityStore = observabilityStore
        self.requestTimeout = requestTimeout
    }

    var isRunning: Bool { process?.isRunning == true }

    func start(executable: String, arguments: [String], environment: [String: String]? = nil) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = environment ?? CommandPathResolver.environmentWithResolvedPath()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            observabilityStore?.record(
                ACPObservedEvent(
                    category: "error.process_start",
                    sessionLocalID: localSessionID,
                    agentID: agentID,
                    projectToken: projectToken,
                    succeeded: false,
                    errorClass: "launch_failed",
                    metadata: ["origin": origin]
                )
            )
            throw error
        }

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        observabilityStore?.record(
            ACPObservedEvent(
                category: "session.process_start",
                sessionLocalID: localSessionID,
                agentID: agentID,
                projectToken: projectToken,
                succeeded: true,
                metadata: [
                    "origin": origin,
                    "executable": AppDiagnostics.pathToken(executable),
                    "argumentsHash": AppDiagnostics.sha256Hex(arguments.joined(separator: "\u{1F}")).prefix(12).description,
                    "argumentCount": String(arguments.count),
                ]
            )
        )

        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleProcessTermination() }
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        readTask = Task { [weak self] in
            await self?.readLoop(handle: stdoutHandle)
        }

        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached { [weak self] in
            var buffer = ""
            while true {
                let data = stderrHandle.availableData
                guard !data.isEmpty else { break }
                if let chunk = String(data: data, encoding: .utf8) {
                    buffer += chunk
                    if buffer.count > 2048 {
                        buffer = String(buffer.suffix(2048))
                    }
                }
            }
            await self?.setStderr(buffer)
        }

        logger.info("ACP transport started for \(AppDiagnostics.pathToken(executable), privacy: .public) with \(arguments.count, privacy: .public) args")
    }

    func send(method: String, params: [String: Any]? = nil) async throws -> JSONRPCResponse {
        guard isRunning else {
            let reason = disconnectReason()
            throw ACPTransportError.disconnected(reason)
        }

        let id = nextRequestID
        nextRequestID += 1
        let jsonrpcID = JSONRPCId.int(id)
        let startedAt = Date()
        requestContexts[jsonrpcID] = RequestContext(method: method, startedAt: startedAt)

        observabilityStore?.record(
            ACPObservedEvent(
                category: "request.start",
                sessionLocalID: localSessionID,
                agentID: agentID,
                projectToken: projectToken,
                method: method,
                metadata: ["origin": origin]
            )
        )

        let request = JSONRPCRequest(id: id, method: method, params: params.map(AnyCodable.init))
        try writeJSON(request)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[jsonrpcID] = continuation
            // No timeout for long-running requests (agent prompts, permission approvals)
            let noTimeout = method == "session/prompt" || method == "session/request_permission"
            if !noTimeout {
                pendingRequestTimeoutTasks[jsonrpcID] = Task { [weak self] in
                    do {
                        try await Task.sleep(for: self?.requestTimeout ?? .seconds(10))
                    } catch {
                        return
                    }
                    await self?.failPendingRequest(id: jsonrpcID, error: ACPTransportError.requestTimedOut(method))
                }
            }
        }
    }

    func sendNotification(method: String, params: [String: Any]?) async throws {
        guard isRunning else { throw ACPTransportError.disconnected("Agent process not running.") }
        let notification = JSONRPCNotification(jsonrpc: "2.0", method: method, params: params.map(AnyCodable.init))
        try writeJSON(notification)
    }

    func setRequestHandler(_ handler: @escaping @Sendable (String, [String: Any]) async throws -> Any) async {
        requestHandler = handler
    }

    func setTerminationHandler(_ handler: @escaping @Sendable (_ reason: String) -> Void) async {
        terminationHandler = handler
    }

    func stop() async {
        readTask?.cancel()
        readTask = nil
        notificationContinuation?.finish()
        notificationContinuation = nil

        for continuation in pendingRequests.values {
            continuation.resume(throwing: ACPTransportError.disconnected(disconnectReason()))
        }
        pendingRequests.removeAll()
        for timeoutTask in pendingRequestTimeoutTasks.values {
            timeoutTask.cancel()
        }
        pendingRequestTimeoutTasks.removeAll()
        requestContexts.removeAll()

        let wasRunning = process?.isRunning == true
        process?.terminationHandler = nil
        if wasRunning {
            process?.terminate()
        }
        process = nil
        stdinHandle = nil

        observabilityStore?.record(
            ACPObservedEvent(
                category: "session.disconnect",
                sessionLocalID: localSessionID,
                agentID: agentID,
                projectToken: projectToken,
                succeeded: true,
                metadata: ["origin": origin]
            )
        )
    }

    func notifications() async -> AsyncStream<JSONRPCNotification> {
        notificationContinuation?.finish()
        return AsyncStream { continuation in
            notificationContinuation = continuation
        }
    }

    private func handleProcessTermination() async {
        guard process != nil else { return }

        // Capture exit info before stop() nils the process
        let exitCode = process?.terminationStatus
        let exitSignal = process?.terminationReason == .uncaughtSignal
        let stderr = lastStderrOutput

        observabilityStore?.record(
            ACPObservedEvent(
                category: "error.process_exit",
                sessionLocalID: localSessionID,
                agentID: agentID,
                projectToken: projectToken,
                succeeded: false,
                errorClass: "process_exit",
                metadata: [
                    "origin": origin,
                    "exitCode": exitCode.map(String.init) ?? "unknown",
                    "stderr": ACPStderrDiagnostics.summary(for: stderr) ?? "empty",
                ]
            )
        )

        // Build human-readable reason
        var reason = "Agent process exited"
        if let code = exitCode {
            reason += exitSignal ? " (signal \(code))" : " (code \(code))"
        }
        reason += "."
        if !stderr.isEmpty {
            let tail = stderr.count > 300 ? String(stderr.suffix(300)) : stderr
            reason += " " + tail
        }

        await stop()
        terminationHandler?(reason)
    }

    private func setStderr(_ output: String) {
        lastStderrOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a human-readable reason for why the transport is not running.
    private func disconnectReason() -> String {
        var parts: [String] = []
        if let proc = process {
            if !proc.isRunning {
                let code = proc.terminationStatus
                let reason = proc.terminationReason == .uncaughtSignal ? "signal" : "exit"
                parts.append("Agent process terminated (\(reason) code \(code)).")
            }
        } else {
            parts.append("Agent process not running.")
        }
        let stderr = lastStderrOutput
        if !stderr.isEmpty {
            // Show last ~200 chars of stderr for context
            let tail = stderr.count > 200 ? String(stderr.suffix(200)) : stderr
            parts.append(tail)
        }
        return parts.isEmpty ? "Agent is not connected." : parts.joined(separator: " ")
    }

    private func readLoop(handle: FileHandle) async {
        let stream = AsyncStream<Data> { continuation in
            let queue = DispatchQueue(label: "acp.transport.read")
            queue.async {
                var buffer = Data()
                while true {
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { break }
                    let rawStr = String(data: chunk, encoding: .utf8) ?? "<non-utf8>"
                    let entry = "[RAW_READ] bytes=\(chunk.count) data=\(rawStr.debugDescription.prefix(200))\n"
                    if let logData = entry.data(using: .utf8) {
                        let p = "/tmp/crispyvibes-chunk-debug.log"
                        if FileManager.default.fileExists(atPath: p) {
                            if let fh = FileHandle(forWritingAtPath: p) { fh.seekToEndOfFile(); fh.write(logData); fh.closeFile() }
                        } else { FileManager.default.createFile(atPath: p, contents: logData) }
                    }
                    buffer.append(chunk)
                    Self.extractJSONMessages(from: &buffer) { message in
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            }
        }

        for await lineData in stream {
            guard !Task.isCancelled else { break }
            await handleLine(lineData)
        }

        await stop()
    }

    /// Extracts complete JSON messages from a byte buffer, correctly handling
    /// literal newlines inside JSON string values. Tracks brace depth and
    /// string quoting state to find message boundaries.
    static func extractJSONMessages(from buffer: inout Data, yield: (Data) -> Void) {
        while !buffer.isEmpty {
            // Skip whitespace/newlines between messages
            while let first = buffer.first, first == 0x0A || first == 0x0D || first == 0x20 || first == 0x09 {
                buffer.removeFirst()
            }
            guard buffer.first == 0x7B /* { */ else { break } // Must start with {

            var depth = 0
            var inString = false
            var escaped = false
            var endIndex: Data.Index?

            for i in buffer.indices {
                let byte = buffer[i]
                if escaped { escaped = false; continue }
                if byte == 0x5C /* \ */ && inString { escaped = true; continue }
                if byte == 0x22 /* " */ { inString.toggle(); continue }
                if inString { continue }
                if byte == 0x7B /* { */ { depth += 1 }
                else if byte == 0x7D /* } */ {
                    depth -= 1
                    if depth == 0 { endIndex = buffer.index(after: i); break }
                }
            }

            guard let end = endIndex else { break } // Incomplete message, wait for more data
            var message = buffer.subdata(in: buffer.startIndex..<end)
            buffer.removeSubrange(buffer.startIndex..<end)
            // Sanitize literal newlines inside JSON string values — agents sometimes
            // send raw 0x0A bytes instead of the escaped \\n sequence.
            sanitizeLiteralNewlines(&message)
            yield(message)
        }
    }

    /// Replaces literal 0x0A and 0x0D bytes inside JSON string values with
    /// their escaped equivalents (\\n, \\r). Agents sometimes send raw newlines
    /// in string values which is invalid JSON per RFC 8259.
    static func sanitizeLiteralNewlines(_ data: inout Data) {
        var inString = false
        var escaped = false
        let backslashN = Data("\\n".utf8)
        let backslashR = Data("\\r".utf8)
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            if escaped { escaped = false; i = data.index(after: i); continue }
            if byte == 0x5C && inString { escaped = true; i = data.index(after: i); continue }
            if byte == 0x22 { inString.toggle(); i = data.index(after: i); continue }
            if inString && byte == 0x0A {
                data.replaceSubrange(i...i, with: backslashN)
                i = data.index(i, offsetBy: 2); continue
            }
            if inString && byte == 0x0D {
                data.replaceSubrange(i...i, with: backslashR)
                i = data.index(i, offsetBy: 2); continue
            }
            i = data.index(after: i)
        }
    }

    private func handleLine(_ data: Data) async {
        do {
            let message = try JSONRPCMessage.decode(from: data)
            switch message {
            case .response(let response):
                if let id = response.id {
                    pendingRequestTimeoutTasks.removeValue(forKey: id)?.cancel()
                    let context = requestContexts.removeValue(forKey: id)
                    finishObservedRequest(
                        context: context,
                        succeeded: response.error == nil,
                        errorClass: response.error == nil ? nil : "rpc_error"
                    )

                    // For session/prompt responses, inject a synthetic turn_completed notification
                    // into the notification stream AFTER the response. This ensures proper ordering:
                    // all notifications that arrived before the response are already in the stream,
                    // and this synthetic notification is ordered after them.
                    if response.isSuccess, context?.method == "session/prompt" {
                        let syntheticNotification = JSONRPCNotification(
                            jsonrpc: "2.0",
                            method: "session/update",
                            params: AnyCodable([
                                "sessionId": "",
                                "update": [
                                    "sessionUpdate": "turn_completed"
                                ]
                            ])
                        )
                        notificationContinuation?.yield(syntheticNotification)
                    }

                    pendingRequests.removeValue(forKey: id)?.resume(returning: response)
                }
            case .notification(let notification):
                if notification.method == "session/update",
                   let params = notification.params?.dictValue,
                   let update = params["update"] as? [String: Any],
                   let kind = update["sessionUpdate"] as? String {
                    observabilityStore?.record(
                        ACPObservedEvent(
                            category: "notification.update",
                            sessionLocalID: localSessionID,
                            agentID: agentID,
                            projectToken: projectToken,
                            metadata: [
                                "origin": origin,
                                "kind": kind,
                            ]
                        )
                    )
                }
                notificationContinuation?.yield(notification)
            case .request(let request):
                await handleIncomingRequest(request)
            }
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            let entry = "[DECODE_ERROR] \(error) | RAW: \(raw.debugDescription.prefix(300))\n"
            if let logData = entry.data(using: .utf8) {
                let p = "/tmp/crispyvibes-chunk-debug.log"
                if FileManager.default.fileExists(atPath: p) {
                    if let fh = FileHandle(forWritingAtPath: p) { fh.seekToEndOfFile(); fh.write(logData); fh.closeFile() }
                } else { FileManager.default.createFile(atPath: p, contents: logData) }
            }
            observabilityStore?.record(
                ACPObservedEvent(
                    category: "error.decode",
                    sessionLocalID: localSessionID,
                    agentID: agentID,
                    projectToken: projectToken,
                    succeeded: false,
                    errorClass: "jsonrpc_decode",
                    metadata: ["origin": origin]
                )
            )
        }
    }

    private func handleIncomingRequest(_ request: JSONRPCRequest) async {
        let params = request.params?.dictValue ?? [:]
        let rawID: Any
        switch request.id {
        case .int(let intValue):
            rawID = intValue
        case .string(let stringValue):
            rawID = stringValue
        }

        do {
            let result = try await requestHandler?(request.method, params) ?? NSNull()
            try writeRawJSON(["jsonrpc": "2.0", "id": rawID, "result": result])
        } catch {
            observabilityStore?.record(
                ACPObservedEvent(
                    category: "request.handler_error",
                    sessionLocalID: localSessionID,
                    agentID: agentID,
                    projectToken: projectToken,
                    method: request.method,
                    succeeded: false,
                    errorClass: "handler_error",
                    metadata: [
                        "origin": origin,
                        "message": diagnosticsSummary(for: error.localizedDescription, label: "error"),
                    ]
                )
            )
            try? writeRawJSON([
                "jsonrpc": "2.0",
                "id": rawID,
                "error": ["code": -32603, "message": error.localizedDescription],
            ])
        }
    }

    private func writeJSON<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        guard let stdinHandle else { throw ACPTransportError.disconnected("Agent stdin closed.") }
        stdinHandle.write(data + Data([0x0A]))
    }

    private func writeRawJSON(_ dict: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: dict)
        guard let stdinHandle else { throw ACPTransportError.disconnected("Agent stdin closed.") }
        stdinHandle.write(data + Data([0x0A]))
    }

    private func failPendingRequest(id: JSONRPCId, error: ACPTransportError) {
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        pendingRequestTimeoutTasks.removeValue(forKey: id)?.cancel()
        finishObservedRequest(id: id, succeeded: false, errorClass: "timeout")
        continuation.resume(throwing: error)
    }

    private func diagnosticsSummary(for value: String, label: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(label)=empty" }
        return "\(label)Hash=\(AppDiagnostics.sha256Hex(trimmed).prefix(12)) \(label)Bytes=\(trimmed.utf8.count)"
    }

    private func finishObservedRequest(id: JSONRPCId, succeeded: Bool, errorClass: String?) {
        guard let context = requestContexts.removeValue(forKey: id) else { return }
        finishObservedRequest(context: context, succeeded: succeeded, errorClass: errorClass)
    }

    private func finishObservedRequest(context: RequestContext?, succeeded: Bool, errorClass: String?) {
        guard let context else { return }
        observabilityStore?.record(
            ACPObservedEvent(
                category: "request.finish",
                sessionLocalID: localSessionID,
                agentID: agentID,
                projectToken: projectToken,
                method: context.method,
                duration: Date().timeIntervalSince(context.startedAt),
                succeeded: succeeded,
                errorClass: errorClass,
                metadata: ["origin": origin]
            )
        )
    }
}
