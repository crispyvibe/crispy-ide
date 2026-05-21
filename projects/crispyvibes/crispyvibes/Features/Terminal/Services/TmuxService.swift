import Foundation

enum TmuxService {
    private static let sessionPrefix = "crispyvibes-"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferences.experimentalTmuxIntegrationKey)
    }

    static var sessionBehavior: TmuxSessionBehavior {
        TmuxSessionBehavior(
            rawValue: UserDefaults.standard.string(forKey: AppPreferences.experimentalTmuxSessionBehaviorKey)
                ?? AppPreferences.experimentalTmuxSessionBehaviorDefault
        ) ?? .detach
    }

    static var tabCloseBehavior: TmuxSessionBehavior {
        TmuxSessionBehavior(
            rawValue: UserDefaults.standard.string(forKey: AppPreferences.experimentalTmuxTabCloseBehaviorKey)
                ?? AppPreferences.experimentalTmuxTabCloseBehaviorDefault
        ) ?? .terminate
    }

    static var tmuxPath: String? {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { tmuxPath != nil }

    static func generateSessionName() -> String {
        sessionPrefix + UUID().uuidString.prefix(12).lowercased()
    }

    static func launchArguments(sessionName: String, shell: String, workingDirectory: String) -> (executable: String, args: [String]) {
        guard let path = tmuxPath else { return (shell, []) }
        applyServerOptions(path: path)
        return (path, ["new-session", "-A", "-s", sessionName, "-c", workingDirectory, shell])
    }

    private static func applyServerOptions(path: String) {
        run(path, arguments: ["start-server"])
        run(path, arguments: ["set-option", "-g", "mouse", "on"])
        run(path, arguments: ["set-option", "-g", "history-limit", "50000"])
        run(path, arguments: ["set-option", "-g", "status", "off"])
        run(path, arguments: ["set-option", "-g", "escape-time", "0"])
    }

    private static func run(_ executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    static func sessionExists(_ name: String) -> Bool {
        guard let path = tmuxPath else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["has-session", "-t", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func killSession(_ name: String) {
        guard let path = tmuxPath else { return }
        run(path, arguments: ["kill-session", "-t", name])
    }

    static func killSessionAsync(_ name: String) {
        guard let path = tmuxPath else { return }
        DispatchQueue.global(qos: .utility).async {
            run(path, arguments: ["kill-session", "-t", name])
        }
    }

    struct SessionInfo: Identifiable, Sendable {
        let id: String
        let name: String
        let workingDirectory: String
        let currentCommand: String
        let createdAt: Date
        let lastActivity: Date
        let isAttached: Bool
    }

    static func listSessionDetails() -> [SessionInfo] {
        guard let path = tmuxPath else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "list-sessions", "-F",
            "#{session_name}\t#{session_path}\t#{session_created}\t#{session_activity}\t#{session_attached}"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output
                .split(separator: "\n")
                .compactMap { line -> SessionInfo? in
                    let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard parts.count >= 5 else { return nil }
                    let created = TimeInterval(parts[2]) ?? 0
                    let activity = TimeInterval(parts[3]) ?? 0
                    let attached = (Int(parts[4]) ?? 0) > 0
                    let command = paneCommand(path: path, session: parts[0])
                    return SessionInfo(
                        id: parts[0],
                        name: parts[0],
                        workingDirectory: parts[1],
                        currentCommand: command,
                        createdAt: Date(timeIntervalSince1970: created),
                        lastActivity: Date(timeIntervalSince1970: activity),
                        isAttached: attached
                    )
                }
        } catch {
            return []
        }
    }

    static func listSessionDetailsAsync() async -> [SessionInfo] {
        await Task.detached(priority: .utility) {
            listSessionDetails()
        }.value
    }

    private static func paneCommand(path: String, session: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["list-panes", "-t", session, "-F", "#{pane_current_command}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    static func killAllCrispyVibesSessions() {
        for name in listCrispyVibesSessions() {
            killSession(name)
        }
    }

    static func listCrispyVibesSessions() -> [String] {
        guard let path = tmuxPath else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["list-sessions", "-F", "#{session_name}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix(sessionPrefix) }
        } catch {
            return []
        }
    }
}
