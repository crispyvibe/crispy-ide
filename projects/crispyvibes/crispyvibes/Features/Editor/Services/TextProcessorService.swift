import AppKit
import Foundation
import OSLog

final class TextProcessorService: NSObject {
    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "services")
    private static var commandTimeoutSeconds: TimeInterval {
        let environment = ProcessInfo.processInfo.environment
        if let rawTimeout = environment["CRISPYVIBES_TEXT_SERVICE_TIMEOUT_SECONDS"],
           let timeout = Double(rawTimeout),
           timeout > 0 {
            return timeout
        }
        return 20
    }
    private static let promptChunkSize = 4_000
    private static let maximumPromptChunkCount = 6
    private static let terminalFormattingRegexes: [NSRegularExpression] = {
        let escape = "\u{001B}"
        let patterns = [
            "\(escape)\\[[0-?]*[ -/]*[@-~]",
            "\(escape)\\][^\u{0007}]*\u{0007}",
            "\(escape)[PX^_].*?\(escape)\\\\",
            "\(escape)."
        ]
        return patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators])
        }
    }()

    private enum ServiceKind {
        case rephrase
        case research

        var defaultPrompt: String {
            switch self {
            case .rephrase:
                return AppPreferences.defaultTextServiceRephrasePrompt
            case .research:
                return AppPreferences.defaultTextServiceResearchPrompt
            }
        }

        var agentEnvKey: String {
            switch self {
            case .rephrase:
                return "CRISPYVIBES_KIRO_REPHRASE_AGENT"
            case .research:
                return "CRISPYVIBES_KIRO_RESEARCH_AGENT"
            }
        }

        var promptSettingsKey: String {
            switch self {
            case .rephrase:
                return AppPreferences.textServiceRephrasePromptKey
            case .research:
                return AppPreferences.textServiceResearchPromptKey
            }
        }
    }

    private enum ServiceError: LocalizedError {
        case missingInput
        case emptyResponse
        case commandFailed(exitCode: Int32, details: String)
        case launchFailed(String)
        case timedOut(TimeInterval)

        var errorDescription: String? {
            switch self {
            case .missingInput:
                return "No selected text was provided."
            case .emptyResponse:
                return "The configured CLI returned an empty response."
            case let .commandFailed(exitCode, details):
                if details.isEmpty {
                    return "The configured CLI failed with exit code \(exitCode)."
                }
                return "The configured CLI failed (\(exitCode)): \(details)"
            case let .launchFailed(message):
                return "Unable to launch the configured CLI: \(message)"
            case let .timedOut(timeout):
                return "The configured CLI timed out after \(Int(timeout.rounded())) seconds."
            }
        }
    }

    private struct CommandResult {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String
    }

    @objc(rephrase:)
    dynamic func rephrase(_ pasteboard: NSPasteboard) {
        processText(in: pasteboard, kind: .rephrase, error: nil)
    }

    @objc(rephrase:userData:)
    dynamic func rephrase(_ pasteboard: NSPasteboard, userData: NSString?) {
        processText(in: pasteboard, kind: .rephrase, error: nil)
    }

    @objc(rephrase:userData:error:)
    dynamic func rephrase(
        _ pasteboard: NSPasteboard,
        userData: NSString?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        processText(in: pasteboard, kind: .rephrase, error: error)
    }

    @objc(research:)
    dynamic func research(_ pasteboard: NSPasteboard) {
        processText(in: pasteboard, kind: .research, error: nil)
    }

    @objc(research:userData:)
    dynamic func research(_ pasteboard: NSPasteboard, userData: NSString?) {
        processText(in: pasteboard, kind: .research, error: nil)
    }

    @objc(research:userData:error:)
    dynamic func research(
        _ pasteboard: NSPasteboard,
        userData: NSString?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        processText(in: pasteboard, kind: .research, error: error)
    }

    @objc(openInTerminal:)
    dynamic func openInTerminal(_ pasteboard: NSPasteboard) {
        openInTerminal(pasteboard, userData: nil, error: nil)
    }

    @objc(openInTerminal:userData:)
    dynamic func openInTerminal(_ pasteboard: NSPasteboard, userData: NSString?) {
        openInTerminal(pasteboard, userData: userData, error: nil)
    }

    @objc(openInTerminal:userData:error:)
    dynamic func openInTerminal(
        _ pasteboard: NSPasteboard,
        userData: NSString?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let rawURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let normalizedURLs = rawURLs.compactMap { url -> URL? in
            let normalized = url.standardizedFileURL
            return FileManager.default.fileExists(atPath: normalized.path) ? normalized : nil
        }

        guard !normalizedURLs.isEmpty else {
            error?.pointee = "No valid file or folder was provided." as NSString
            return
        }

        DispatchQueue.main.async {
            ExternalOpenRelay.submit(
                .init(
                    urls: normalizedURLs,
                    preferTerminal: true
                )
            )
        }
    }

    private func processText(
        in pasteboard: NSPasteboard,
        kind: ServiceKind,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        logger.info("Service invoked: \(String(describing: kind), privacy: .public)")
        guard let selectedText = pasteboard.string(forType: .string), !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("Service input missing")
            error?.pointee = (ServiceError.missingInput.errorDescription ?? "Missing input.") as NSString
            return
        }

        do {
            let updatedText = try runConfiguredTextService(for: selectedText, kind: kind)
            pasteboard.clearContents()
            pasteboard.setString(updatedText, forType: .string)
            logger.info("Service completed successfully")
        } catch let serviceError {
            logger.error("Service failed: \(serviceError.localizedDescription, privacy: .public)")
            error?.pointee = serviceError.localizedDescription as NSString
        }
    }

    private func runConfiguredTextService(for selectedText: String, kind: ServiceKind) throws -> String {
        let prompt = renderedPrompt(for: chunkedPromptInput(selectedText), kind: kind)
        let configuration = AppPreferences.resolvedTextServiceCLIConfiguration()
        guard !configuration.command.isEmpty else {
            throw ServiceError.launchFailed("No CLI command is configured.")
        }
        let passAgentFlag = configuration.passAgentFlag
        let preferredAgent = passAgentFlag ? configuredAgentName(for: kind) : nil
        let attempts: [String?] = passAgentFlag && preferredAgent != nil ? [preferredAgent, nil] : [nil]
        var lastError: Error?

        for agent in attempts {
            do {
                let result = try runTextServiceCommand(
                    configuration: configuration,
                    prompt: prompt,
                    agentName: agent
                )
                guard result.exitCode == 0 else {
                    throw ServiceError.commandFailed(
                        exitCode: result.exitCode,
                        details: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }

                let response = extractAssistantResponse(from: result.standardOutput)
                guard !response.isEmpty else {
                    throw ServiceError.emptyResponse
                }
                return response
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ServiceError.emptyResponse
    }

    private func runTextServiceCommand(
        configuration: TextServiceCLIConfiguration,
        prompt: String,
        agentName: String?
    ) throws -> CommandResult {
        let runner = ManagedProcessRunner()
        do {
            let result = try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: commandArguments(
                    configuration: configuration,
                    prompt: prompt,
                    agentName: agentName
                ),
                environment: commandEnvironment(),
                timeout: Self.commandTimeoutSeconds,
                throwOnTimeout: true
            )

            let outputText = String(data: result.stdoutData, encoding: .utf8) ?? ""
            let errorText = String(data: result.stderrData, encoding: .utf8) ?? ""

            return CommandResult(
                exitCode: result.terminationStatus,
                standardOutput: outputText,
                standardError: errorText
            )
        } catch ManagedProcessRunnerError.timedOut(let timeout) {
            throw ServiceError.timedOut(timeout)
        } catch {
            throw ServiceError.launchFailed(error.localizedDescription)
        }
    }

    private func commandArguments(
        configuration: TextServiceCLIConfiguration,
        prompt: String,
        agentName: String?
    ) -> [String] {
        var arguments = [configuration.command] + CLICommandLineParser.splitArguments(configuration.arguments)
        if configuration.passAgentFlag,
           let agentName,
           !agentName.isEmpty {
            arguments.append(contentsOf: ["--agent", agentName])
        }
        arguments.append(prompt)
        return arguments
    }

    private func configuredAgentName(for kind: ServiceKind) -> String? {
        AppPreferences.resolvedTextServiceAgentName(primaryEnvironmentKey: kind.agentEnvKey)
    }

    private func renderedPrompt(for selectedText: String, kind: ServiceKind) -> String {
        let defaults = UserDefaults.standard
        let template = AppPreferences.normalizedSetting(
            defaults.string(forKey: kind.promptSettingsKey),
            fallback: kind.defaultPrompt
        )
        if template.contains("{{text}}") {
            return template.replacingOccurrences(of: "{{text}}", with: selectedText)
        }
        return """
        \(template)

        Text:
        \(selectedText)
        """
    }

    private func chunkedPromptInput(_ selectedText: String) -> String {
        guard selectedText.count > Self.promptChunkSize else {
            return selectedText
        }

        var chunks: [String] = []
        chunks.reserveCapacity(Self.maximumPromptChunkCount)
        var startIndex = selectedText.startIndex
        var chunkIndex = 0
        while startIndex < selectedText.endIndex,
              chunkIndex < Self.maximumPromptChunkCount {
            let endIndex = selectedText.index(
                startIndex,
                offsetBy: Self.promptChunkSize,
                limitedBy: selectedText.endIndex
            ) ?? selectedText.endIndex
            chunks.append(String(selectedText[startIndex..<endIndex]))
            startIndex = endIndex
            chunkIndex += 1
        }

        let hasTruncatedTail = startIndex < selectedText.endIndex
        var rendered = chunks.enumerated().map { index, chunk in
            "Chunk \(index + 1):\n\(chunk)"
        }.joined(separator: "\n\n")
        if hasTruncatedTail {
            let truncatedCharacterCount = Self.promptChunkSize * Self.maximumPromptChunkCount
            rendered += "\n\n[Truncated after \(truncatedCharacterCount) characters.]"
        }
        return rendered
    }

    private func commandEnvironment() -> [String: String] {
        CommandPathResolver.environmentWithResolvedPath()
    }

    private func extractAssistantResponse(from rawOutput: String) -> String {
        let cleaned = stripTerminalFormatting(from: rawOutput).replacingOccurrences(of: "\r", with: "\n")
        let lines = cleaned.components(separatedBy: .newlines)
        guard let markerIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }) else {
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var responseLines: [String] = []
        for (index, line) in lines[markerIndex...].enumerated() {
            var currentLine = line
            if index == 0, let promptMarker = currentLine.firstIndex(of: ">") {
                currentLine = String(currentLine[currentLine.index(after: promptMarker)...])
            }
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("▸ Time:") {
                break
            }
            responseLines.append(currentLine)
        }

        return responseLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripTerminalFormatting(from text: String) -> String {
        var output = text
        for regex in Self.terminalFormattingRegexes {
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: NSRange(location: 0, length: output.utf16.count),
                withTemplate: ""
            )
        }

        return output
    }
}
