import Foundation
import OSLog

/// Unified text generation service. Takes a prompt, runs the user's configured CLI,
/// returns the output. Used by rephrase, research, thread title generation, and
/// any future text generation needs.
final class TextGenerationService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.crispyvibe.app", category: "textGeneration")
    private static let timeoutSeconds: TimeInterval = 20

    /// Run a prompt through the configured text service CLI and return the output.
    /// Uses print mode (one-shot) invocation with the correct flags per CLI.
    func generate(prompt: String) -> String? {
        let configuration = AppPreferences.resolvedTextServiceCLIConfiguration()
        guard !configuration.command.isEmpty else { return nil }

        let catalog = CLIToolCatalog.definition(for: configuration.profile)
        guard let invocation = catalog?.textServiceInvocation else { return nil }

        let printArgs = invocation.printModeArguments ?? invocation.standardArguments
        let inputMode = invocation.printModeInputMode

        var arguments = [configuration.command] + CLICommandLineParser.splitArguments(printArgs)

        // Agent flag (kiro-specific)
        if configuration.passAgentFlag {
            let agentName = AppPreferences.resolvedTextServiceAgentName(
                primaryEnvironmentKey: "CRISPYVIBES_KIRO_AGENT"
            )
            if let agentName, !agentName.isEmpty {
                arguments.append(contentsOf: ["--agent", agentName])
            }
        }

        // Deliver prompt based on input mode
        let stdinData: Data?
        switch inputMode {
        case .positionalArg:
            arguments.append(prompt)
            stdinData = nil
        case .stdin:
            stdinData = prompt.data(using: .utf8)
        }

        do {
            let runner = ManagedProcessRunner()
            let result = try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: arguments,
                environment: Self.expandedEnvironment(),
                stdinData: stdinData,
                timeout: Self.timeoutSeconds,
                throwOnTimeout: true
            )

            guard result.terminationStatus == 0 else {
                logger.info("Text generation CLI exited with \(result.terminationStatus)")
                return nil
            }

            let output = Self.stripANSI(
                String(data: result.stdoutData, encoding: .utf8) ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        } catch {
            logger.info("Text generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Generate a thread title from the user's first message.
    func generateThreadTitle(from userMessage: String) -> String? {
        let prompt = """
        You write concise thread titles for coding conversations.
        Return ONLY a JSON object with key: title.
        Rules:
        - Title should summarize the user's request, not restate it verbatim.
        - Keep it short and specific (3-8 words).
        - Avoid quotes, filler, prefixes, and trailing punctuation.

        User message:
        \(String(userMessage.prefix(4000)))
        """

        guard let output = generate(prompt: prompt), !output.isEmpty else { return nil }

        // Try to find JSON anywhere in the output (CLI may add markers/formatting)
        if let title = extractJSONTitle(from: output) {
            return sanitize(title)
        }

        // Fallback: if output looks like a clean title (no special chars, reasonable length)
        let cleaned = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix(">") && !$0.hasPrefix("{") }
            .first

        if let cleaned, cleaned.count >= 3, cleaned.count <= 60 {
            return sanitize(cleaned)
        }

        return nil
    }

    private func extractJSONTitle(from text: String) -> String? {
        // Strategy 1: Find standalone {"title":"..."} anywhere in text
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
               let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = json["title"] as? String, !title.isEmpty {
                return title
            }
        }

        // Strategy 2: Parse CLI result envelope — {"type":"result","result":"```json\n{...}\n```"}
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String {
            // Strip markdown code fences
            let cleaned = result
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let innerData = cleaned.data(using: .utf8),
               let innerJSON = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any],
               let title = innerJSON["title"] as? String, !title.isEmpty {
                return title
            }
            // Result might be plain text title
            if !cleaned.isEmpty, cleaned.count <= 60, !cleaned.contains("{") {
                return cleaned
            }
        }

        return nil
    }

    private func sanitize(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^['\"`]+|['\"`]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            ?? raw
        if normalized.isEmpty { return "New conversation" }
        if normalized.count <= 50 { return normalized }
        return String(normalized.prefix(47).trimmingCharacters(in: .whitespaces)) + "…"
    }

    private static let ansiRegexes: [NSRegularExpression] = {
        let esc = "\u{001B}"
        return [
            "\(esc)\\[[0-?]*[ -/]*[@-~]",
            "\(esc)\\][^\u{0007}]*\u{0007}",
            "\(esc)[PX^_].*?\(esc)\\\\",
            "\(esc).",
        ].compactMap { try? NSRegularExpression(pattern: $0, options: .dotMatchesLineSeparators) }
    }()

    private static func stripANSI(_ text: String) -> String {
        var output = text
        for regex in ansiRegexes {
            output = regex.stringByReplacingMatches(
                in: output, range: NSRange(location: 0, length: output.utf16.count), withTemplate: ""
            )
        }
        return output
    }

    private static func expandedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let missing = extraPaths.filter { !currentPath.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [currentPath]).joined(separator: ":")
        }
        return env
    }
}
