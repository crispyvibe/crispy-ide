import Combine
import Foundation

@MainActor
final class VibeSpaceShortcutProvider: ObservableObject {
    @Published private(set) var mergedShortcuts: [TerminalShortcutDefinition] = []
    @Published private(set) var vibespaceShortcuts: [TerminalShortcutDefinition] = []
    @Published private(set) var projectShortcuts: [TerminalShortcutDefinition] = []

    private let vibespaceManagement: VibeSpaceManagementService?
    private var vibespaceID: UUID?
    private var focusedProjectPath: String?
    private var shortcutChangeObserver: AnyCancellable?

    init(vibespaceManagement: VibeSpaceManagementService? = nil) {
        self.vibespaceManagement = vibespaceManagement
        shortcutChangeObserver = NotificationCenter.default
            .publisher(for: .vibespaceShortcutsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadShortcuts()
            }
    }

    func update(vibespaceID: UUID?, focusedProjectPath: String?) {
        self.vibespaceID = vibespaceID
        self.focusedProjectPath = focusedProjectPath
        reloadShortcuts()
    }

    func reloadShortcuts() {
        guard let vibespaceID, let vibespaceManagement else {
            vibespaceShortcuts = []
            projectShortcuts = []
            mergedShortcuts = []
            return
        }
        vibespaceShortcuts = vibespaceManagement.vibespaceShortcuts(vibespaceID: vibespaceID)
        if let focusedProjectPath, !focusedProjectPath.isEmpty {
            projectShortcuts = vibespaceManagement.projectShortcuts(vibespaceID: vibespaceID, projectPath: focusedProjectPath)
        } else {
            projectShortcuts = []
        }
        mergedShortcuts = vibespaceShortcuts + projectShortcuts
    }
}

enum SpotlightComposeInlineTrigger: Equatable {
    case universal(query: String, prefixText: String)

    var query: String {
        switch self {
        case let .universal(query, _):
            return query
        }
    }

    var prefixText: String {
        switch self {
        case let .universal(_, prefixText):
            return prefixText
        }
    }

    static func parse(_ text: String, triggerToken: String) -> SpotlightComposeInlineTrigger? {
        let normalizedTrigger = AppPreferences.normalizedTerminalComposeInlineTrigger(triggerToken)
        guard !normalizedTrigger.isEmpty else { return nil }

        var searchStart = text.startIndex
        var lastMatch: (prefix: String, query: String)?

        while searchStart < text.endIndex,
              let triggerRange = text.range(of: normalizedTrigger, range: searchStart..<text.endIndex) {
            let hasValidBoundary: Bool
            if triggerRange.lowerBound == text.startIndex {
                hasValidBoundary = true
            } else {
                let previousIndex = text.index(before: triggerRange.lowerBound)
                hasValidBoundary = text[previousIndex].isWhitespace
            }

            if hasValidBoundary {
                let prefixText = String(text[..<triggerRange.lowerBound])
                let rawQuery = String(text[triggerRange.upperBound...])
                lastMatch = (
                    prefix: prefixText,
                    query: rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            searchStart = triggerRange.upperBound
        }

        guard let lastMatch else { return nil }
        return .universal(query: lastMatch.query, prefixText: lastMatch.prefix)
    }
}

enum SpotlightComposeInlineResult: Identifiable {
    case path(SpotlightComposePathSearchMatch)
    case shortcut(TerminalShortcutDefinition)
    case promptAction(SpotlightComposeInlinePromptAction, query: String, isBusy: Bool)

    var id: String {
        switch self {
        case let .path(match):
            return "path:\(match.absolutePath)"
        case let .shortcut(shortcut):
            return "shortcut:\(shortcut.id.uuidString)"
        case let .promptAction(action, _, _):
            return "prompt:\(action.id)"
        }
    }

    var title: String {
        switch self {
        case let .path(match):
            return match.relativePath
        case let .shortcut(shortcut):
            return shortcut.name
        case let .promptAction(action, _, _):
            return action.title
        }
    }

    var subtitle: String? {
        switch self {
        case let .path(match):
            return match.isDirectory ? AppStrings.Terminal.ComposeTriggers.directoryKind : AppStrings.Terminal.ComposeTriggers.fileKind
        case let .shortcut(shortcut):
            return "\(AppStrings.Terminal.ComposeTriggers.shortcutKind) • \(shortcut.command)"
        case let .promptAction(action, query, _):
            let detail = query.isEmpty ? action.description : query
            return "\(AppStrings.Terminal.ComposeTriggers.promptActionKind) • \(detail)"
        }
    }

    var systemImage: String {
        switch self {
        case let .path(match):
            return match.isDirectory ? "folder" : "doc"
        case .shortcut:
            return "terminal"
        case let .promptAction(action, _, _):
            return action.systemImage
        }
    }

    var isDisabled: Bool {
        switch self {
        case .path:
            return false
        case .shortcut:
            return false
        case let .promptAction(_, query, isBusy):
            return query.isEmpty || isBusy
        }
    }

    var section: SpotlightComposeInlineSection {
        switch self {
        case .promptAction:
            return .promptActions
        case .shortcut:
            return .shortcuts
        case .path:
            return .paths
        }
    }

    var isPromptAction: Bool {
        if case .promptAction = self { return true }
        return false
    }

    var isShortcut: Bool {
        if case .shortcut = self { return true }
        return false
    }

    var isPath: Bool {
        if case .path = self { return true }
        return false
    }
}

enum SpotlightComposeInlineSection: Int {
    case promptActions
    case shortcuts
    case paths

    var title: String {
        switch self {
        case .promptActions:
            return AppStrings.Terminal.ComposeTriggers.promptActionsSection
        case .shortcuts:
            return AppStrings.Terminal.ComposeTriggers.shortcutsSection
        case .paths:
            return AppStrings.Terminal.ComposeTriggers.pathsSection
        }
    }
}

enum SpotlightComposeInlineResultProvider {
    private static let maxPathResults = 50
    private static let maxShortcutResults = 2
    private static let maxPromptResults = 1

    static func results(
        query: String,
        pathMatches: [SpotlightComposePathSearchMatch],
        shortcuts: [TerminalShortcutDefinition],
        promptActions: [SpotlightComposeInlinePromptAction],
        isRunningPromptAction: Bool
    ) -> [SpotlightComposeInlineResult] {
        let normalizedShortcutQuery = normalizedSearchText(query)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [SpotlightComposeInlineResult] = []

        results.append(contentsOf: filteredShortcuts(shortcuts, normalizedQuery: normalizedShortcutQuery)
            .prefix(maxShortcutResults)
            .map(SpotlightComposeInlineResult.shortcut))
        results.append(contentsOf: pathMatches
            .prefix(maxPathResults)
            .map(SpotlightComposeInlineResult.path))
        if !trimmedQuery.isEmpty {
            results.append(contentsOf: promptActions.prefix(maxPromptResults).map {
                SpotlightComposeInlineResult.promptAction($0, query: query, isBusy: isRunningPromptAction)
            })
        }
        return results
    }

    static func panelRows(
        from results: [SpotlightComposeInlineResult],
        selectedResultID: String?
    ) -> [SpotlightComposeInlinePanelRow] {
        let rowResults = results.filter { !$0.isPromptAction }
        var previousSection: SpotlightComposeInlineSection?
        return rowResults.map { result in
            let section = result.section
            defer { previousSection = section }
            return SpotlightComposeInlinePanelRow(
                id: result.id,
                title: result.title,
                subtitle: result.subtitle,
                systemImage: result.systemImage,
                isSelected: result.id == selectedResultID,
                isDisabled: result.isDisabled,
                sectionTitle: previousSection == section ? nil : section.title,
                kind: result.isPath ? .path : .shortcut
            )
        }
    }

    static func featuredAction(from results: [SpotlightComposeInlineResult]) -> SpotlightComposeInlineResult? {
        results.first(where: \.isPromptAction)
    }

    private static func filteredShortcuts(
        _ shortcuts: [TerminalShortcutDefinition],
        normalizedQuery: String
    ) -> [TerminalShortcutDefinition] {
        guard !normalizedQuery.isEmpty else { return shortcuts }
        return shortcuts
            .compactMap { shortcut -> (shortcut: TerminalShortcutDefinition, score: Int)? in
                let score = shortcutScore(shortcut: shortcut, normalizedQuery: normalizedQuery)
                return score > 0 ? (shortcut, score) : nil
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.shortcut.name.localizedCaseInsensitiveCompare($1.shortcut.name) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .map(\.shortcut)
    }

    private static func shortcutScore(shortcut: TerminalShortcutDefinition, normalizedQuery: String) -> Int {
        let name = normalizedSearchText(shortcut.name)
        let command = normalizedSearchText(shortcut.command)

        let nameScore = FuzzyTextMatcher.match(candidate: name, query: normalizedQuery).map {
            weightedShortcutScore(for: $0, baseBoost: 220)
        } ?? .min
        let commandScore = FuzzyTextMatcher.match(candidate: command, query: normalizedQuery).map {
            weightedShortcutScore(for: $0, baseBoost: 120)
        } ?? .min

        let bestScore = max(nameScore, commandScore)
        return bestScore == .min ? 0 : bestScore
    }

    private static func weightedShortcutScore(for match: FuzzyTextMatch, baseBoost: Int) -> Int {
        var score = baseBoost + match.score
        if match.isPrefix { score += 40 }
        if match.startsOnBoundary { score += 20 }
        score -= max(0, match.matchedSpan - 1)
        return score
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct SpotlightComposeInlinePromptContext {
    let terminalTitle: String
    let workingDirectoryPath: String
}

enum SpotlightComposeInlinePromptAction: String, CaseIterable, Identifiable {
    case generateCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generateCommand:
            return AppStrings.Terminal.ComposeTriggers.generateCommand
        }
    }

    var description: String {
        switch self {
        case .generateCommand:
            return AppStrings.Terminal.ComposeTriggers.generateCommandDescription
        }
    }

    var systemImage: String {
        switch self {
        case .generateCommand:
            return "sparkles"
        }
    }

    func buildPrompt(userInput: String, context: SpotlightComposeInlinePromptContext) -> String {
        let sharedContext = """
        CrispyVibes spotlight terminal compose input
        Terminal title: \(context.terminalTitle)
        Working directory: \(context.workingDirectoryPath)
        """

        switch self {
        case .generateCommand:
            return """
            \(sharedContext)

            Convert the request below into one shell command suitable for the current terminal context.
            Return only the shell command with no explanation, bullets, or markdown.

            Request:
            \(userInput)
            """
        }
    }
}

enum SpotlightComposeInlinePromptService {
    private static let timeoutSeconds: TimeInterval = 20
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

    static func run(
        action: SpotlightComposeInlinePromptAction,
        userInput: String,
        context: SpotlightComposeInlinePromptContext,
        userDefaults: UserDefaults = .standard
    ) -> String? {
        let configuration = AppPreferences.resolvedTextServiceCLIConfiguration(userDefaults: userDefaults)
        guard !configuration.command.isEmpty else { return nil }

        var arguments = [configuration.command] + CLICommandLineParser.splitArguments(configuration.arguments)
        if configuration.passAgentFlag,
           let agentName = AppPreferences.resolvedTextServiceAgentName(
               primaryEnvironmentKey: "CRISPYVIBES_KIRO_RESEARCH_AGENT",
               userDefaults: userDefaults
           ) {
            arguments.append(contentsOf: ["--agent", agentName])
        }
        arguments.append(action.buildPrompt(userInput: userInput, context: context))

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
        for (index, line) in lines[markerIndex...].enumerated() {
            var current = line
            if index == 0, let promptMarker = current.firstIndex(of: ">") {
                current = String(current[current.index(after: promptMarker)...])
            }
            if current.trimmingCharacters(in: .whitespaces).hasPrefix("▸ Time:") { break }
            result.append(current)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTerminalFormatting(_ text: String) -> String {
        var output = text
        for regex in terminalFormattingRegexes {
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(location: 0, length: output.utf16.count),
                withTemplate: ""
            )
        }
        return output
    }
}
