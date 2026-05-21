import Foundation

// MARK: - Terminal handlers

extension CLICommandRouter {

    // MARK: Terminal helpers

    /// Locates a terminal across all projects in the focused vibespace by UUID.
    func findTerminal(uuid: UUID) -> (provider: AnyTerminalProvider, tab: TerminalTab, session: TerminalSession)? {
        guard let vibespace = vibespaceCatalogStore?.vibespaces.first else { return nil }
        for project in vibespace.projects {
            if let session = project.terminal.session(for: uuid),
               let tab = project.terminal.tabs.first(where: { $0.id == uuid }) {
                return (project.terminal, tab, session)
            }
        }
        return nil
    }

    /// Resolves a `terminal_id` parameter (tagged or bare) plus channel-client
    /// env fallback. Returns `nil` if no terminal can be resolved.
    func resolveTerminal(
        explicitID: String?,
        env: CLIChannelClientEnv
    ) -> (provider: AnyTerminalProvider, tab: TerminalTab, session: TerminalSession)? {
        let raw = explicitID
            ?? env.context.flatMap { CLITaggedID(rawValue: $0)?.kind == "terminal" ? CLITaggedID(rawValue: $0)?.id : nil }
        guard let raw else { return nil }
        let bare = CLITaggedID.extractID(from: raw, expectedKind: "terminal")
        guard let uuid = UUID(uuidString: bare) else { return nil }
        return findTerminal(uuid: uuid)
    }

    /// Returns the terminal provider used for `terminal.create`.
    func providerForCreate() -> (provider: AnyTerminalProvider, project: AnyProjectSession)? {
        guard let vibespace = vibespaceCatalogStore?.vibespaces.first else { return nil }
        if let focused = vibespace.focusedProject {
            return (focused.terminal, focused)
        }
        if let first = vibespace.projects.first {
            return (first.terminal, first)
        }
        return nil
    }

    func tagTerminalID(_ uuid: UUID) -> String {
        "terminal.\(uuid.uuidString)"
    }

    // MARK: Terminal command handlers

    func handleTerminalList(_ request: CLIRequest) -> CLIResponse {
        guard let vibespace = vibespaceCatalogStore?.vibespaces.first else {
            return .ok(id: request.id, result: ["terminals": .array([])])
        }
        let env = request._env ?? .empty
        let callerUUID = env.context
            .flatMap { CLITaggedID(rawValue: $0) }
            .flatMap { $0.kind == "terminal" ? UUID(uuidString: $0.id) : nil }
        var entries: [CLIJSONValue] = []
        for project in vibespace.projects {
            let provider = project.terminal
            let activeID = provider.activeTabID
            for tab in provider.tabs {
                let session = provider.session(for: tab.id)
                let title = tab.customName ?? tab.sessionTitle ?? "Terminal"
                let cwd = session?.currentWorkingDirectory.path ?? tab.workingDirectory.path
                entries.append(.object([
                    "terminal_id": .string(tagTerminalID(tab.id)),
                    "title": .string(title),
                    "cwd": .string(cwd),
                    "focused": .bool(tab.id == activeID),
                    "is_caller": .bool(tab.id == callerUUID),
                ]))
            }
        }
        return .ok(id: request.id, result: ["terminals": .array(entries)])
    }

    func handleTerminalCreate(_ request: CLIRequest) -> CLIResponse {
        guard let context = providerForCreate() else {
            return .error(id: request.id, code: CLIErrorCode.notConnected, message: "No vibespace open")
        }
        let env = request._env ?? .empty
        let cwdParam = request.params?["cwd"]?.stringValue
        let cwdURL: URL?
        if let cwdParam, !cwdParam.isEmpty {
            guard cwdParam.hasPrefix("/") else {
                return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "cwd must be an absolute path")
            }
            cwdURL = URL(fileURLWithPath: cwdParam)
        } else if let projectPath = env.project_path, !projectPath.isEmpty {
            cwdURL = URL(fileURLWithPath: projectPath)
        } else {
            cwdURL = context.project.metadata.rootDirectoryURL
        }
        let name = request.params?["name"]?.stringValue?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let callerID = env.context
            .flatMap { CLITaggedID(rawValue: $0) }
            .flatMap { $0.kind == "terminal" ? $0.id : nil }
        context.provider.createTab(
            directoryURL: cwdURL,
            customName: name,
            origin: .agentCLI(callerTerminalID: callerID),
            tmuxSessionName: nil,
            startImmediately: true
        )
        guard let newID = context.provider.activeTabID else {
            return .error(id: request.id, code: CLIErrorCode.internalError, message: "Terminal created but ID not available")
        }
        return .ok(id: request.id, result: [
            "terminal_id": .string(tagTerminalID(newID)),
        ])
    }

    func handleTerminalSend(_ request: CLIRequest) -> CLIResponse {
        guard let text = request.params?["text"]?.stringValue else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "text is required")
        }
        guard let terminalParam = request.params?["terminal_id"]?.stringValue, !terminalParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "terminal_id is required")
        }
        let submit = request.params?["submit"]?.boolValue ?? false
        guard let resolved = resolveTerminal(explicitID: terminalParam, env: request._env ?? .empty) else {
            return .error(id: request.id, code: CLIErrorCode.terminalNotFound, message: "No terminal found for: \(terminalParam)")
        }
        let payload = submit ? text + "\n" : text
        resolved.session.sendRawText(payload)
        return .ok(id: request.id, result: [:])
    }

    func handleTerminalSendKey(_ request: CLIRequest) -> CLIResponse {
        guard let key = request.params?["key"]?.stringValue, !key.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "key is required")
        }
        guard let sequence = CLIKeyMapping.sequence(for: key) else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "Unknown key: \(key)")
        }
        guard let terminalParam = request.params?["terminal_id"]?.stringValue, !terminalParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "terminal_id is required")
        }
        guard let resolved = resolveTerminal(explicitID: terminalParam, env: request._env ?? .empty) else {
            return .error(id: request.id, code: CLIErrorCode.terminalNotFound, message: "No terminal found for: \(terminalParam)")
        }
        resolved.session.sendRawText(sequence)
        return .ok(id: request.id, result: [:])
    }

    func handleTerminalClose(_ request: CLIRequest) -> CLIResponse {
        guard let terminalParam = request.params?["terminal_id"]?.stringValue, !terminalParam.isEmpty else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "terminal_id is required")
        }
        guard let resolved = resolveTerminal(explicitID: terminalParam, env: request._env ?? .empty) else {
            return .error(id: request.id, code: CLIErrorCode.terminalNotFound, message: "No terminal found for: \(terminalParam)")
        }
        resolved.provider.closeTab(resolved.tab)
        return .ok(id: request.id, result: [:])
    }

    func handleTerminalWait(_ request: CLIRequest) async -> CLIResponse {
        let explicitID = request.params?["terminal_id"]?.stringValue
        let textPattern = request.params?["text"]?.stringValue
        let waitForExit = request.params?["exit"]?.boolValue ?? false
        let timeoutSec = request.params?["timeout"]?.intValue ?? 30

        let conditionsSet = (textPattern != nil ? 1 : 0) + (waitForExit ? 1 : 0)
        guard conditionsSet == 1 else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "Specify exactly one of: text, exit")
        }
        guard timeoutSec > 0, timeoutSec <= 600 else {
            return .error(id: request.id, code: CLIErrorCode.invalidParams, message: "timeout must be between 1 and 600 seconds")
        }
        guard let resolved = resolveTerminal(explicitID: explicitID, env: request._env ?? .empty) else {
            return .error(id: request.id, code: CLIErrorCode.terminalNotFound, message: "No terminal resolved from terminal_id or _env.context")
        }

        let session = resolved.session
        let timeoutNanos = UInt64(timeoutSec) * 1_000_000_000

        let outcome = await withTaskGroup(of: WaitOutcome.self) { group -> WaitOutcome in
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return .timeout
            }
            group.addTask { @MainActor in
                await withCheckedContinuation { (cont: CheckedContinuation<WaitOutcome, Never>) in
                    MainActor.assumeIsolated {
                        let previousOutput = session.onOutputReceived
                        let previousTerminate = session.onProcessTerminated
                        var resumed = false
                        func resume(_ outcome: WaitOutcome) {
                            guard !resumed else { return }
                            resumed = true
                            MainActor.assumeIsolated {
                                session.onOutputReceived = previousOutput
                                session.onProcessTerminated = previousTerminate
                            }
                            cont.resume(returning: outcome)
                        }
                        if waitForExit {
                            session.onProcessTerminated = { code in
                                previousTerminate?(code)
                                resume(.exited(code))
                            }
                        } else if let pattern = textPattern {
                            var buffer = ""
                            session.onOutputReceived = { chunk in
                                previousOutput?(chunk)
                                buffer += chunk
                                if buffer.count > 65_536 {
                                    buffer = String(buffer.suffix(65_536))
                                }
                                if buffer.contains(pattern) {
                                    resume(.matched(text: pattern))
                                }
                            }
                        }
                    }
                }
            }
            let firstResult = await group.next()!
            group.cancelAll()
            return firstResult
        }

        switch outcome {
        case .timeout:
            return .ok(id: request.id, result: [
                "matched": .bool(false),
            ])
        case .matched(let text):
            return .ok(id: request.id, result: [
                "matched": .bool(true),
                "text": .string(text),
            ])
        case .exited(let code):
            return .ok(id: request.id, result: [
                "matched": .bool(true),
                "exit_code": code.map { .int(Int($0)) } ?? .null,
            ])
        }
    }

    enum WaitOutcome {
        case timeout
        case matched(text: String)
        case exited(_ code: Int32?)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
