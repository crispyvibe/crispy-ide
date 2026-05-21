import Foundation

struct VibeCastMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let targetTabID: UUID
    let targetTabName: String
    let timestamp: Date

    init(text: String, targetTabID: UUID, targetTabName: String) {
        self.id = UUID()
        self.text = text
        self.targetTabID = targetTabID
        self.targetTabName = targetTabName
        self.timestamp = Date()
    }
}

struct VibeCastMessageGroup: Identifiable {
    let id: UUID
    let targetTabID: UUID
    let targetTabName: String
    var messages: [VibeCastMessage]
}

@MainActor
final class VibeCastStore: ObservableObject {
    let id = UUID()
    @Published var messages: [VibeCastMessage] = []
    @Published var composeText: String = ""
    @Published var targetTabID: UUID?
    @Published var isRephrasing = false

    var groupedMessages: [VibeCastMessageGroup] {
        var groups: [VibeCastMessageGroup] = []
        for message in messages {
            if groups.last?.targetTabID == message.targetTabID {
                groups[groups.count - 1].messages.append(message)
            } else {
                groups.append(VibeCastMessageGroup(
                    id: message.id,
                    targetTabID: message.targetTabID,
                    targetTabName: message.targetTabName,
                    messages: [message]
                ))
            }
        }
        return groups
    }

    private static let maxMessages = 500

    func send(text: String, targetTabID: UUID, targetTabName: String) -> VibeCastMessage {
        let message = VibeCastMessage(text: text, targetTabID: targetTabID, targetTabName: targetTabName)
        messages.append(message)
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
        composeText = ""
        return message
    }

    func rephrase() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRephrasing else { return }
        isRephrasing = true
        Task.detached { [weak self] in
            let result = VibeCastRephraseService.rephrase(text)
            await MainActor.run { [weak self, result] in
                guard let self else { return }
                if let result {
                    self.composeText = result
                }
                self.isRephrasing = false
            }
        }
    }
}

enum VibeCastRephraseService {
    private static let timeoutSeconds: TimeInterval = 20
    private static let terminalFormattingRegexes: [NSRegularExpression] = {
        let esc = "\u{001B}"
        return [
            "\(esc)\\[[0-?]*[ -/]*[@-~]",
            "\(esc)\\][^\u{0007}]*\u{0007}",
            "\(esc)[PX^_].*?\(esc)\\\\",
            "\(esc)."
        ].compactMap { try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators]) }
    }()

    static func rephrase(_ text: String) -> String? {
        let defaults = UserDefaults.standard
        let configuration = AppPreferences.resolvedTextServiceCLIConfiguration(userDefaults: defaults)
        guard !configuration.command.isEmpty else { return nil }

        let template = defaults.string(forKey: AppPreferences.textServiceRephrasePromptKey)
            ?? AppPreferences.defaultTextServiceRephrasePrompt
        let prompt: String
        if template.isEmpty {
            prompt = "Rephrase and elaborate this prompt for an AI coding assistant, making it clearer and more detailed:\n\n\(text)"
        } else if template.contains("{{text}}") {
            prompt = template.replacingOccurrences(of: "{{text}}", with: text)
        } else {
            prompt = "\(template)\n\nText:\n\(text)"
        }

        var arguments = [configuration.command] + CLICommandLineParser.splitArguments(configuration.arguments)
        if configuration.passAgentFlag,
           let agentName = AppPreferences.resolvedTextServiceAgentName(
               primaryEnvironmentKey: "CRISPYVIBES_KIRO_REPHRASE_AGENT",
               userDefaults: defaults
           ) {
            arguments.append(contentsOf: ["--agent", agentName])
        }
        arguments.append(prompt)
        do {
            let result = try ManagedProcessRunner().run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: arguments,
                environment: CommandPathResolver.environmentWithResolvedPath(),
                timeout: timeoutSeconds,
                throwOnTimeout: true
            )
            guard result.terminationStatus == 0,
                  let raw = String(data: result.stdoutData, encoding: .utf8) else {
                return nil
            }
            let cleaned = stripTerminalFormatting(raw)
            let response = extractResponse(from: cleaned)
            return response.isEmpty ? nil : response
        } catch {
            return nil
        }
    }

    private static func extractResponse(from text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: .newlines)
        guard let markerIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result: [String] = []
        for (i, line) in lines[markerIndex...].enumerated() {
            var current = line
            if i == 0, let idx = current.firstIndex(of: ">") {
                current = String(current[current.index(after: idx)...])
            }
            if current.trimmingCharacters(in: .whitespaces).hasPrefix("▸ Time:") { break }
            result.append(current)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTerminalFormatting(_ text: String) -> String {
        var output = text
        for regex in terminalFormattingRegexes {
            output = regex.stringByReplacingMatches(in: output, range: NSRange(location: 0, length: output.utf16.count), withTemplate: "")
        }
        return output
    }

}
