import Foundation

// MARK: - Startup Milestones

struct TerminalStartupMilestones {
    var sessionCreated: Date?
    var shellLaunched: Date?
    var firstRenderObserved: Date?
    var firstInteractivePromptObserved: Date?
    var bannerSuppressionTriggered: Date?
    var shellExecutable: String?
    var launchArguments: String?
    var workingDirectoryPath: String?

    var shellLaunchDuration: TimeInterval? {
        guard let s = sessionCreated, let l = shellLaunched else { return nil }
        return l.timeIntervalSince(s)
    }

    var renderLatency: TimeInterval? {
        guard let l = shellLaunched, let r = firstRenderObserved else { return nil }
        return r.timeIntervalSince(l)
    }

    var interactiveLatency: TimeInterval? {
        guard let l = shellLaunched, let p = firstInteractivePromptObserved else { return nil }
        return p.timeIntervalSince(l)
    }
}

// MARK: - Per-Session Row

struct TerminalSessionDiagnosticRow: Codable {
    let sessionDebugID: String
    let surfaceDebugID: String?
    let sessionID: String
    let vibespaceID: String?
    let source: String
    let isVisible: Bool
    let isOccluded: Bool
    let isFocused: Bool
    let pixelWidth: UInt32
    let pixelHeight: UInt32
    let pollingActive: Bool
    let lastLifecycleEvent: String?
    let lastLifecycleTimestamp: String?
    let sessionCreated: String?
    let shellLaunched: String?
    let firstRenderObserved: String?
    let firstInteractivePromptObserved: String?
    let bannerSuppressionTriggered: String?
    let shellExecutable: String?
    let launchArguments: String?
    let workingDirectoryPath: String?
    let shellLaunchDuration: Double?
    let renderLatency: Double?
    let interactiveLatency: Double?
}

// MARK: - Global Snapshot

struct TerminalDiagnosticsPayload: Codable {
    let capturedAt: String
    let activeSessionCount: Int
    let activeGhosttySurfaceCount: Int
    let activeHostCount: Int
    let activePollingTimerCount: Int
    let boardStandaloneViewModelCount: Int
    let visibleBoardTileCount: Int
    let visibleRailTerminalCount: Int
    let spotlightActive: Bool
    let perVibeSpaceSessionCounts: [String: Int]
    let sessions: [TerminalSessionDiagnosticRow]
}

// MARK: - Registration

@MainActor
final class TerminalDiagnosticsSnapshot {
    static let shared = TerminalDiagnosticsSnapshot()

    struct SessionEntry {
        let sessionDebugID: Int
        let sessionID: UUID
        weak var engine: (any TerminalSessionEngine)?
        var surfaceDebugID: Int?
        var vibespaceID: UUID?
        var source: TerminalPresentationSource = .unknown
        var isVisible: Bool = false
        var isOccluded: Bool = false
        var isFocused: Bool = false
        var pixelWidth: UInt32 = 0
        var pixelHeight: UInt32 = 0
        var pollingActive: Bool = false
        var lastLifecycleEvent: TerminalLifecycleEvent?
        var lastLifecycleTimestamp: Date?
        var startupMilestones: TerminalStartupMilestones?
    }

    private(set) var entries: [UUID: SessionEntry] = [:]
    var hostCount: Int = 0
    var visibleBoardTileCount: Int = 0
    var visibleRailTerminalCount: Int = 0
    var visibleRailTerminalCountProvider: (() -> Int)?
    var spotlightActive: Bool = false
    var boardStandaloneViewModelCountProvider: (() -> Int)?

    func register(sessionID: UUID, sessionDebugID: Int, engine: any TerminalSessionEngine) {
        entries[sessionID] = SessionEntry(
            sessionDebugID: sessionDebugID,
            sessionID: sessionID,
            engine: engine
        )
    }

    func unregister(sessionID: UUID) {
        entries.removeValue(forKey: sessionID)
    }

    func update(sessionID: UUID, _ mutate: (inout SessionEntry) -> Void) {
        guard var entry = entries[sessionID] else { return }
        mutate(&entry)
        entries[sessionID] = entry
    }

    func recordEvent(sessionID: UUID, event: TerminalLifecycleEvent) {
        update(sessionID: sessionID) { entry in
            entry.lastLifecycleEvent = event
            entry.lastLifecycleTimestamp = Date()
        }
    }

    func recordStartupMilestone(sessionID: UUID, _ mutate: (inout TerminalStartupMilestones) -> Void) {
        update(sessionID: sessionID) { entry in
            var milestones = entry.startupMilestones ?? TerminalStartupMilestones()
            mutate(&milestones)
            entry.startupMilestones = milestones
        }
    }

    // MARK: - Snapshot Capture

    func capture() -> TerminalDiagnosticsPayload {
        let liveEntries = entries.values.filter { $0.engine != nil }
        var perVibeSpace: [String: Int] = [:]
        for entry in liveEntries {
            let key = entry.vibespaceID?.uuidString ?? "none"
            perVibeSpace[key, default: 0] += 1
        }

        let surfaceCount = liveEntries.filter { $0.surfaceDebugID != nil }.count
        let pollingCount = liveEntries.filter { $0.pollingActive }.count

        let rows: [TerminalSessionDiagnosticRow] = liveEntries
            .sorted { $0.sessionDebugID < $1.sessionDebugID }
            .map { entry in
                let ms = entry.startupMilestones
                return TerminalSessionDiagnosticRow(
                    sessionDebugID: "S\(entry.sessionDebugID)",
                    surfaceDebugID: entry.surfaceDebugID.map { "SF\($0)" },
                    sessionID: entry.sessionID.uuidString,
                    vibespaceID: entry.vibespaceID?.uuidString,
                    source: entry.source.rawValue,
                    isVisible: entry.isVisible,
                    isOccluded: entry.isOccluded,
                    isFocused: entry.isFocused,
                    pixelWidth: entry.pixelWidth,
                    pixelHeight: entry.pixelHeight,
                    pollingActive: entry.pollingActive,
                    lastLifecycleEvent: entry.lastLifecycleEvent?.rawValue,
                    lastLifecycleTimestamp: entry.lastLifecycleTimestamp.map(AppDiagnostics.iso8601Timestamp),
                    sessionCreated: ms?.sessionCreated.map(AppDiagnostics.iso8601Timestamp),
                    shellLaunched: ms?.shellLaunched.map(AppDiagnostics.iso8601Timestamp),
                    firstRenderObserved: ms?.firstRenderObserved.map(AppDiagnostics.iso8601Timestamp),
                    firstInteractivePromptObserved: ms?.firstInteractivePromptObserved.map(AppDiagnostics.iso8601Timestamp),
                    bannerSuppressionTriggered: ms?.bannerSuppressionTriggered.map(AppDiagnostics.iso8601Timestamp),
                    shellExecutable: ms?.shellExecutable,
                    launchArguments: ms?.launchArguments,
                    workingDirectoryPath: ms?.workingDirectoryPath,
                    shellLaunchDuration: ms?.shellLaunchDuration,
                    renderLatency: ms?.renderLatency,
                    interactiveLatency: ms?.interactiveLatency
                )
            }

        return TerminalDiagnosticsPayload(
            capturedAt: AppDiagnostics.iso8601Timestamp(Date()),
            activeSessionCount: liveEntries.count,
            activeGhosttySurfaceCount: surfaceCount,
            activeHostCount: hostCount,
            activePollingTimerCount: pollingCount,
            boardStandaloneViewModelCount: boardStandaloneViewModelCountProvider?() ?? 0,
            visibleBoardTileCount: visibleBoardTileCount,
            visibleRailTerminalCount: visibleRailTerminalCountProvider?() ?? visibleRailTerminalCount,
            spotlightActive: spotlightActive,
            perVibeSpaceSessionCounts: perVibeSpace,
            sessions: rows
        )
    }

    // MARK: - JSON Export

    func exportToFile() -> URL? {
        let payload = capture()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }

        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CrispyVibes")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = logsDir.appendingPathComponent("terminal-diagnostics-\(timestamp).json")
        try? data.write(to: fileURL, options: .atomic)

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .notice,
            event: "diagnostics_snapshot_exported",
            metadata: ["path": fileURL.path]
        )
        return fileURL
    }
}
