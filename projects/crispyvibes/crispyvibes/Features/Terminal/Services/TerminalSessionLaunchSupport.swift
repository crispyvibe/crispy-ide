import Foundation

extension TerminalSession {
    nonisolated static let launchEnvironment: [String] = buildTerminalEnvironment()

    @MainActor
    static func makeDefaultEngine(terminalServices: TerminalServices) -> any TerminalSessionEngine {
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let forceSwiftTerm = ProcessInfo.processInfo.environment["CRISPYVIBES_FORCE_SWIFTTERM"] == "1"
        let forceGhostty = ProcessInfo.processInfo.environment["CRISPYVIBES_FORCE_GHOSTTY"] == "1"

        if forceSwiftTerm { return SwiftTermTerminalEngine(terminalServices: terminalServices) }
        if isTestEnvironment && !forceGhostty { return SwiftTermTerminalEngine(terminalServices: terminalServices) }

        let preference = UserDefaults.standard.string(forKey: AppPreferences.nerdTerminalEngineKey)
            ?? AppPreferences.nerdTerminalEngineDefault
        if preference == "swiftterm" { return SwiftTermTerminalEngine(terminalServices: terminalServices) }
        if preference == "ghostty", terminalServices.ghosttyRuntime.isAvailable {
            return GhosttyTerminalEngine(terminalServices: terminalServices)
        }

        if terminalServices.ghosttyRuntime.isAvailable {
            return GhosttyTerminalEngine(terminalServices: terminalServices)
        }
        return SwiftTermTerminalEngine(terminalServices: terminalServices)
    }

    nonisolated static func buildTerminalEnvironment() -> [String] {
        var environment = CommandPathResolver.environmentWithResolvedPath()
        environment.removeValue(forKey: "NO_COLOR")
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        environment["LC_CTYPE"] = environment["LC_CTYPE"] ?? environment["LANG"]
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = environment["TERM_PROGRAM"] ?? "Apple_Terminal"
        environment["TERM_PROGRAM_VERSION"] = environment["TERM_PROGRAM_VERSION"] ?? "1.0"
        environment["CLICOLOR"] = "1"
        environment["CLICOLOR_FORCE"] = "1"
        environment["FORCE_COLOR"] = "3"
        injectAgentCLIEnvironment(into: &environment)
        return environment.map { "\($0.key)=\($0.value)" }
    }

    /// Adds Agent CLI discovery vars and prepends the bundled CLI binary
    /// directory to PATH so spawned shells can invoke `crispy` directly.
    /// See F044-R04 / F044-R05 in the Agent CLI spec.
    nonisolated static func injectAgentCLIEnvironment(into environment: inout [String: String]) {
        // CRISPY_SOCKET — the Unix socket the running app is listening on.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let socketPath = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("crispy.sock", isDirectory: false)
            .path
        environment["CRISPY_SOCKET"] = socketPath
        environment["CRISPY_BUNDLE_ID"] = bundleID

        // Prepend bundled CLI bin directory to PATH.
        let binDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/bin", isDirectory: true)
            .path
        let existingPath = environment["PATH"] ?? ""
        if !existingPath.split(separator: ":").contains(where: { $0 == Substring(binDir) }) {
            environment["PATH"] = existingPath.isEmpty ? binDir : "\(binDir):\(existingPath)"
        }
    }
}
