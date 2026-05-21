import AppKit
import CryptoKit
import Foundation
import OSLog
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import os.signpost

enum DiagnosticsLevel: String, Codable {
    case debug
    case info
    case notice
    case error
    case fault
}

enum DiagnosticsCategory: String, Codable {
    case vibespaceLifecycle = "vibespace.lifecycle"
    case terminalLifecycle = "terminal.lifecycle"
    case terminalHost = "terminal.host"
    case remote = "remote"
    case auth = "auth"
    case externalSessions = "external.sessions"
}

struct DiagnosticsEventRecord: Codable {
    let timestamp: String
    let category: String
    let level: String
    let event: String
    let metadata: [String: String]
}

final class DiagnosticsEventStore {
    private let lock = NSLock()
    private let maxEvents: Int
    private var events: [DiagnosticsEventRecord] = []

    init(maxEvents: Int) {
        self.maxEvents = maxEvents
    }

    func append(_ record: DiagnosticsEventRecord) {
        lock.lock()
        defer { lock.unlock() }
        events.append(record)
        let overflow = events.count - maxEvents
        if overflow > 0 {
            events.removeFirst(overflow)
        }
    }

    func snapshot() -> [DiagnosticsEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

enum ACPObservabilityMode: String, Codable, Sendable {
    case disabled
    case baseline
    case verbose
}

struct ACPObservedEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: String
    let category: String
    let sessionLocalID: String?
    let agentID: String?
    let projectToken: String?
    let method: String?
    let duration: TimeInterval?
    let succeeded: Bool?
    let errorClass: String?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: String = AppDiagnostics.iso8601Timestamp(Date()),
        category: String,
        sessionLocalID: String? = nil,
        agentID: String? = nil,
        projectToken: String? = nil,
        method: String? = nil,
        duration: TimeInterval? = nil,
        succeeded: Bool? = nil,
        errorClass: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.sessionLocalID = sessionLocalID
        self.agentID = agentID
        self.projectToken = projectToken
        self.method = method
        self.duration = duration
        self.succeeded = succeeded
        self.errorClass = errorClass
        self.metadata = metadata
    }
}

struct ACPObservedSessionSnapshot: Identifiable, Codable, Sendable {
    let id: String
    let agentID: String
    let projectToken: String?
    let transportKind: String
    let origin: String
    let connectionState: String
    let remoteSessionID: String?
    let currentMode: String?
    let currentModel: String?
    let lastActivityAt: String?
    let lastErrorClass: String?
}

struct ACPObservedTurnCounts: Codable, Sendable {
    let assistantChunkCount: Int
    let thoughtChunkCount: Int
    let toolCallCount: Int
    let planUpdateCount: Int
    let permissionRequestCount: Int
    let terminalRequestCount: Int
    let fileOperationCount: Int

    static let zero = ACPObservedTurnCounts(
        assistantChunkCount: 0,
        thoughtChunkCount: 0,
        toolCallCount: 0,
        planUpdateCount: 0,
        permissionRequestCount: 0,
        terminalRequestCount: 0,
        fileOperationCount: 0
    )
}

struct ACPObservedTurnSummary: Identifiable, Codable, Sendable {
    let id: String
    let sessionLocalID: String
    let agentID: String?
    let projectToken: String?
    let startedAt: String
    let endedAt: String?
    let stopReason: String?
    let counts: ACPObservedTurnCounts
}

struct ACPObservedAggregate: Codable, Sendable {
    let key: String
    var count: Int = 0
    var totalDuration: TimeInterval = 0
    var maxDuration: TimeInterval = 0
    var failureCount: Int = 0

    var averageDuration: TimeInterval {
        count > 0 ? totalDuration / Double(count) : 0
    }

    mutating func incorporate(duration: TimeInterval?, succeeded: Bool?) {
        count += 1
        if let duration {
            totalDuration += duration
            if duration > maxDuration {
                maxDuration = duration
            }
        }
        if succeeded == false {
            failureCount += 1
        }
    }
}

struct ACPObservabilityPayload: Codable, Sendable {
    let capturedAt: String
    let mode: ACPObservabilityMode
    let eventCount: Int
    let sessionCount: Int
    let turnCount: Int
    let events: [ACPObservedEvent]
    let sessions: [ACPObservedSessionSnapshot]
    let turns: [ACPObservedTurnSummary]
    let byAgent: [String: ACPObservedAggregate]
    let byProject: [String: ACPObservedAggregate]
    let byMethod: [String: ACPObservedAggregate]
    let byErrorClass: [String: ACPObservedAggregate]
}

final class ACPObservabilityStore: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private let turnCapacity: Int
    private var buffer: [ACPObservedEvent?]
    private var state: (head: Int, count: Int)
    private var sessions: [String: ACPObservedSessionSnapshot]
    private var turns: [ACPObservedTurnSummary]

    init(capacity: Int = 500, turnCapacity: Int = 100) {
        self.capacity = capacity
        self.turnCapacity = turnCapacity
        self.buffer = Array(repeating: nil, count: capacity)
        self.state = (head: 0, count: 0)
        self.sessions = [:]
        self.turns = []
    }

    func record(_ event: ACPObservedEvent) {
        lock.lock()
        defer { lock.unlock() }
        let writeIndex = (state.head + state.count) % capacity
        buffer[writeIndex] = event
        if state.count < capacity {
            state.count += 1
        } else {
            state.head = (state.head + 1) % capacity
        }
    }

    func upsertSession(_ snapshot: ACPObservedSessionSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        sessions[snapshot.id] = snapshot
    }

    func removeSession(id: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: id)
    }

    func recordTurn(_ summary: ACPObservedTurnSummary) {
        lock.lock()
        defer { lock.unlock() }
        turns.removeAll { $0.id == summary.id }
        turns.append(summary)
        turns.sort { $0.startedAt > $1.startedAt }
        let overflow = turns.count - turnCapacity
        if overflow > 0 {
            turns.removeLast(overflow)
        }
    }

    func snapshotEvents() -> [ACPObservedEvent] {
        lock.lock()
        defer { lock.unlock() }
        let snapshotState = state
        var result: [ACPObservedEvent] = []
        result.reserveCapacity(snapshotState.count)
        for index in 0..<snapshotState.count {
            if let event = buffer[(snapshotState.head + index) % capacity] {
                result.append(event)
            }
        }
        return result
    }

    func snapshotSessions() -> [ACPObservedSessionSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return sessions.values.sorted { lhs, rhs in
            if lhs.lastActivityAt == rhs.lastActivityAt {
                return lhs.id < rhs.id
            }
            return (lhs.lastActivityAt ?? "") > (rhs.lastActivityAt ?? "")
        }
    }

    func snapshotTurns() -> [ACPObservedTurnSummary] {
        lock.lock()
        defer { lock.unlock() }
        return turns
    }

    func aggregateByAgent() -> [String: ACPObservedAggregate] {
        aggregate(using: \.agentID, fallback: "unknown")
    }

    func aggregateByProject() -> [String: ACPObservedAggregate] {
        aggregate(using: \.projectToken, fallback: "none")
    }

    func aggregateByMethod() -> [String: ACPObservedAggregate] {
        aggregate(using: \.method, fallback: "unspecified")
    }

    func aggregateByErrorClass() -> [String: ACPObservedAggregate] {
        aggregate(using: \.errorClass, fallback: "none")
    }

    func exportPayload(mode: ACPObservabilityMode) -> ACPObservabilityPayload {
        let events = snapshotEvents()
        let sessions = snapshotSessions()
        let turns = snapshotTurns()
        return ACPObservabilityPayload(
            capturedAt: AppDiagnostics.iso8601Timestamp(Date()),
            mode: mode,
            eventCount: events.count,
            sessionCount: sessions.count,
            turnCount: turns.count,
            events: events,
            sessions: sessions,
            turns: turns,
            byAgent: aggregateByAgent(),
            byProject: aggregateByProject(),
            byMethod: aggregateByMethod(),
            byErrorClass: aggregateByErrorClass()
        )
    }

    private func aggregate(
        using keyPath: KeyPath<ACPObservedEvent, String?>,
        fallback: String
    ) -> [String: ACPObservedAggregate] {
        let events = snapshotEvents()
        var result: [String: ACPObservedAggregate] = [:]
        for event in events {
            let key = event[keyPath: keyPath] ?? fallback
            var aggregate = result[key] ?? ACPObservedAggregate(key: key)
            aggregate.incorporate(duration: event.duration, succeeded: event.succeeded)
            result[key] = aggregate
        }
        return result
    }
}

enum AppDiagnostics {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.crispyvibe.app"
    static let deepDiagnosticsEnvironmentKey = "CRISPYVIBES_TERMINAL_DIAGNOSTICS"
    static let eventStore = DiagnosticsEventStore(maxEvents: 1500)

    static let vibespaceLogger = Logger(subsystem: subsystem, category: "vibespace.lifecycle")
    static let terminalLogger = Logger(subsystem: subsystem, category: "terminal.lifecycle")
    static let terminalHostLogger = Logger(subsystem: subsystem, category: "terminal.host")
    static let remoteLogger = Logger(subsystem: subsystem, category: "remote")
    static let authLogger = Logger(subsystem: subsystem, category: "auth")
    static let externalSessionsLogger = Logger(subsystem: subsystem, category: "external.sessions")

    static let vibespaceSignpostLog = OSLog(subsystem: subsystem, category: "vibespace.signpost")
    static let terminalSignpostLog = OSLog(subsystem: subsystem, category: "terminal.signpost")
    static let terminalHostSignpostLog = OSLog(subsystem: subsystem, category: "terminal.host.signpost")
    private static let timestampLock = NSLock()
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var deepDiagnosticsEnabled: Bool {
        ProcessInfo.processInfo.environment[deepDiagnosticsEnvironmentKey] == "1"
    }

    static func record(
        category: DiagnosticsCategory,
        level: DiagnosticsLevel,
        event: String,
        metadata: [String: String] = [:]
    ) {
        if level == .debug, !deepDiagnosticsEnabled {
            return
        }

        let renderedMetadata = metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let message = renderedMetadata.isEmpty ? event : "\(event) \(renderedMetadata)"

        let logger: Logger
        switch category {
        case .vibespaceLifecycle:
            logger = vibespaceLogger
        case .terminalLifecycle:
            logger = terminalLogger
        case .terminalHost:
            logger = terminalHostLogger
        case .remote:
            logger = remoteLogger
        case .auth:
            logger = authLogger
        case .externalSessions:
            logger = externalSessionsLogger
        }

        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .notice:
            logger.notice("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        }

        eventStore.append(
            DiagnosticsEventRecord(
                timestamp: iso8601Timestamp(Date()),
                category: category.rawValue,
                level: level.rawValue,
                event: event,
                metadata: metadata
            )
        )
    }

    static func hostDebug(_ message: String) {
        guard deepDiagnosticsEnabled else { return }
        terminalHostLogger.debug("\(message, privacy: .private(mask: .hash))")
    }

    static func pathToken(_ path: String) -> String {
        "path#" + sha256Hex(path).prefix(12)
    }

    static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func iso8601Timestamp(_ date: Date) -> String {
        timestampLock.lock()
        defer { timestampLock.unlock() }
        return timestampFormatter.string(from: date)
    }
}

private struct DiagnosticsVibeSpaceSummary: Codable {
    let vibespaceCount: Int
    let totalProjects: Int
    let totalUnresolvedPaths: Int
}

private struct DiagnosticsExportPayload: Codable {
    let exportedAt: String
    let bundleID: String
    let appVersion: String
    let appBuild: String
    let macOSVersion: String
    let deepDiagnosticsEnabled: Bool
    let defaultsSnapshot: [String: String]
    let vibespaceSummary: DiagnosticsVibeSpaceSummary?
    let vibespaceCatalogSanitizedJSON: String?
    let layoutStateSanitizedJSON: String?
    let operationMetrics: OperationMetricsPayload?
    let acpObservability: ACPObservabilityPayload?
    let recentEvents: [DiagnosticsEventRecord]
}

enum DiagnosticsExportService {
    @MainActor
    static func exportInteractive(
        using store: VibeSpacePersistenceStore,
        operationMetricsStore: OperationMetricsStore? = nil,
        acpObservabilityStore: ACPObservabilityStore? = nil,
        acpObservabilityMode: ACPObservabilityMode = .disabled
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "crispyvibe-diagnostics-\(timestampForFileName()).json"
        panel.prompt = "Export"
        panel.title = "Export Diagnostics"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            _ = try export(
                to: destinationURL,
                using: store,
                operationMetricsStore: operationMetricsStore,
                acpObservabilityStore: acpObservabilityStore,
                acpObservabilityMode: acpObservabilityMode
            )
        } catch {
            AppDiagnostics.record(
                category: .vibespaceLifecycle,
                level: .error,
                event: "diagnostics_export_failed",
                metadata: ["error": String(describing: error)]
            )
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Diagnostics Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @discardableResult
    static func export(
        to destinationURL: URL,
        using store: VibeSpacePersistenceStore,
        operationMetricsStore: OperationMetricsStore? = nil,
        acpObservabilityStore: ACPObservabilityStore? = nil,
        acpObservabilityMode: ACPObservabilityMode = .disabled
    ) throws -> Int {
        let payload = buildPayload(
            using: store,
            operationMetricsStore: operationMetricsStore,
            acpObservabilityStore: acpObservabilityStore,
            acpObservabilityMode: acpObservabilityMode
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: destinationURL, options: [.atomic])

        AppDiagnostics.record(
            category: .vibespaceLifecycle,
            level: .notice,
            event: "diagnostics_export_succeeded",
            metadata: [
                "file": AppDiagnostics.pathToken(destinationURL.path),
                "events": String(payload.recentEvents.count)
            ]
        )
        return payload.recentEvents.count
    }

    private static func buildPayload(
        using store: VibeSpacePersistenceStore,
        operationMetricsStore: OperationMetricsStore? = nil,
        acpObservabilityStore: ACPObservabilityStore? = nil,
        acpObservabilityMode: ACPObservabilityMode = .disabled
    ) -> DiagnosticsExportPayload {
        let defaults = UserDefaults.standard
        let recentIDs = store.loadAppState().recentVibeSpaceIDs
        let vibespaceSummary = summarizeVibeSpaces(recentIDs: recentIDs, store: store)

        let bundle = Bundle.main
        let defaultsSnapshot: [String: String] = [
            AppPreferences.appearancePreferenceKey: defaults.string(forKey: AppPreferences.appearancePreferenceKey) ?? "unset",
            "appearancePreference": defaults.string(forKey: AppPreferences.appearancePreferenceKey) ?? "unset",
            AppPreferences.terminalPresetLaunchModeKey: defaults.string(forKey: AppPreferences.terminalPresetLaunchModeKey) ?? "unset",
            "terminalPresetLaunchMode": defaults.string(forKey: AppPreferences.terminalPresetLaunchModeKey) ?? "unset",
            "railTerminalCompactFontSize": defaults.object(forKey: AppPreferences.railTerminalCompactFontSizeKey).map { String(describing: $0) } ?? "unset",
            "codeFontFamily": defaults.string(forKey: AppPreferences.codeFontFamilyKey) ?? "unset",
            "codeFontSize": defaults.object(forKey: AppPreferences.codeFontSizeKey).map { String(describing: $0) } ?? "unset",
            "autoUpdateChecksEnabled": String(AppPreferences.autoUpdateChecksEnabled(userDefaults: defaults)),
            "appUpdateFeedURL": AppPreferences.normalizedAppUpdateFeedURL(
                defaults.string(forKey: AppPreferences.appUpdateFeedURLKey),
                fallback: AppPreferences.defaultAppUpdateFeedURL
            ),
            "textServiceCLIProfile": defaults.string(forKey: AppPreferences.textServiceCLIProfileKey) ?? "unset",
            "textServiceCLITrustMode": defaults.string(forKey: AppPreferences.textServiceCLITrustModeKey) ?? "unset",
            "textServiceCLICommand": defaults.string(forKey: AppPreferences.textServiceCLICommandKey) ?? "unset",
            "textServiceCLIArguments": defaults.string(forKey: AppPreferences.textServiceCLIArgumentsKey) ?? "unset",
            "textServicePassAgentFlag": defaults.object(forKey: AppPreferences.textServicePassAgentFlagKey).map { String(describing: $0) } ?? "unset",
            "textServiceDefaultAgent": defaults.string(forKey: AppPreferences.textServiceDefaultAgentKey) ?? "unset",
            "experimentalACPObservability": String(defaults.bool(forKey: AppPreferences.experimentalACPObservabilityKey)),
            "experimentalACPObservabilityVerbose": String(defaults.bool(forKey: AppPreferences.experimentalACPObservabilityVerboseKey)),
            "vibespaceCatalogHash": "migrated-to-per-vibespace"
        ]

        return DiagnosticsExportPayload(
            exportedAt: AppDiagnostics.iso8601Timestamp(Date()),
            bundleID: bundle.bundleIdentifier ?? AppDiagnostics.subsystem,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deepDiagnosticsEnabled: AppDiagnostics.deepDiagnosticsEnabled,
            defaultsSnapshot: defaultsSnapshot,
            vibespaceSummary: vibespaceSummary,
            vibespaceCatalogSanitizedJSON: nil,
            layoutStateSanitizedJSON: nil,
            operationMetrics: operationMetricsStore?.exportPayload(),
            acpObservability: acpObservabilityStore?.exportPayload(mode: acpObservabilityMode),
            recentEvents: AppDiagnostics.eventStore.snapshot()
        )
    }

    private static func summarizeVibeSpaces(recentIDs: [UUID], store: VibeSpacePersistenceStore) -> DiagnosticsVibeSpaceSummary? {
        guard !recentIDs.isEmpty else { return nil }
        var totalProjects = 0
        var totalUnresolvedPaths = 0
        for id in recentIDs {
            if let result = store.loadVibeSpaceConfig(for: id) {
                totalProjects += result.value.projectPaths.count
                totalUnresolvedPaths += result.value.unresolvedProjectPaths.count
            }
        }
        return DiagnosticsVibeSpaceSummary(
            vibespaceCount: recentIDs.count,
            totalProjects: totalProjects,
            totalUnresolvedPaths: totalUnresolvedPaths
        )
    }

    private static func sanitizeJSONText(_ raw: String?) -> String? {
        guard let raw,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let sanitized = sanitizeJSONObject(object)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let encoded = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }

    private static func sanitizeJSONObject(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                sanitized[key] = sanitizeJSONObject(nestedValue)
            }
            return sanitized
        }

        if let array = value as? [Any] {
            return array.map(sanitizeJSONObject)
        }

        if let string = value as? String {
            return sanitizeString(string)
        }

        return value
    }

    private static func sanitizeString(_ value: String) -> String {
        guard looksLikePath(value) else { return value }
        return AppDiagnostics.pathToken(value)
    }

    private static func looksLikePath(_ value: String) -> Bool {
        value.hasPrefix("/") || value.contains("/Users/") || value.contains("\\Users\\")
    }

    private static func timestampForFileName() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
