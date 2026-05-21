import Combine
import Foundation

final class TerminalPresetAvailabilityDiagnostics {
    static let shared = TerminalPresetAvailabilityDiagnostics()

    private static let defaultsVersionKey = AppPreferences.terminalToolDiagnosticsVersionKey
    private static let defaultsInstalledToolsKey = AppPreferences.terminalToolDiagnosticsInstalledToolsKey
    private static let currentVersion = 2

    private let defaults: UserDefaults
    private var cachedInstalledToolIDs: Set<String>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func availablePresetIDs(from presets: [TerminalPresetDefinition]) -> Set<String> {
        if let override = uiTestOverridePresetIDs() {
            cachedInstalledToolIDs = override
            return override
        }

        if let cachedInstalledToolIDs {
            return cachedInstalledToolIDs
        }

        if let restored = loadPersistedPresetIDs() {
            cachedInstalledToolIDs = restored
            return restored
        }

        let detected = detectInstalledPresetIDs(from: presets)
        persistPresetIDs(detected)
        cachedInstalledToolIDs = detected
        return detected
    }

    func availablePresets(from presets: [TerminalPresetDefinition]) -> [TerminalPresetDefinition] {
        let installedIDs = availablePresetIDs(from: presets)
        return presets.filter { installedIDs.contains($0.id) }
    }

    private func loadPersistedPresetIDs() -> Set<String>? {
        let storedVersion = defaults.integer(forKey: Self.defaultsVersionKey)
        guard storedVersion == Self.currentVersion else { return nil }
        guard let storedIDs = defaults.array(forKey: Self.defaultsInstalledToolsKey) as? [String] else {
            return nil
        }
        return Set(storedIDs)
    }

    private func persistPresetIDs(_ presetIDs: Set<String>) {
        defaults.set(Self.currentVersion, forKey: Self.defaultsVersionKey)
        defaults.set(Array(presetIDs).sorted(), forKey: Self.defaultsInstalledToolsKey)
    }

    private func detectInstalledPresetIDs(
        from presets: [TerminalPresetDefinition]
    ) -> Set<String> {
        Set(
            presets.compactMap { preset in
                guard let executableName = executableName(from: preset.defaultCommand) else {
                    return nil
                }
                return isExecutableAvailable(named: executableName) ? preset.id : nil
            }
        )
    }

    private func executableName(from command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private func isExecutableAvailable(named executableName: String) -> Bool {
        if executableName.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executableName)
        }

        let searchPaths = CommandPathResolver.searchPaths()
        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path)
                .appendingPathComponent(executableName)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }

    private func uiTestOverridePresetIDs() -> Set<String>? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CRISPYVIBES_UI_TEST_MODE"] == "1" else { return nil }
        guard let rawOverride = environment["CRISPYVIBES_UI_TEST_TERMINAL_TOOLS"] else { return nil }
        let ids = rawOverride
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Set(ids)
    }
}

final class TerminalShortcutStore {
    static let shared = TerminalShortcutStore()
    static let didChangeNotification = Notification.Name.terminalShortcutStoreDidChange

    private static let shortcutsKey = AppPreferences.terminalShortcutDefinitionsKey
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [TerminalShortcutDefinition] {
        guard let data = defaults.data(forKey: Self.shortcutsKey) else {
            return []
        }
        guard let decoded = try? JSONDecoder().decode([TerminalShortcutDefinition].self, from: data) else {
            return []
        }
        return normalized(decoded)
    }

    func save(_ shortcuts: [TerminalShortcutDefinition]) {
        let normalizedShortcuts = normalized(shortcuts)
        guard let encoded = try? JSONEncoder().encode(normalizedShortcuts) else { return }
        defaults.set(encoded, forKey: Self.shortcutsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func normalized(_ shortcuts: [TerminalShortcutDefinition]) -> [TerminalShortcutDefinition] {
        var seenIDs = Set<UUID>()
        var resolved: [TerminalShortcutDefinition] = []
        for shortcut in shortcuts {
            guard seenIDs.insert(shortcut.id).inserted else { continue }
            let trimmedName = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCommand = shortcut.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !trimmedCommand.isEmpty else { continue }
            resolved.append(
                TerminalShortcutDefinition(
                    id: shortcut.id,
                    name: trimmedName,
                    command: trimmedCommand
                )
            )
        }
        return resolved.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

struct TerminalViewModelDependencies {
    var presetDiagnostics: TerminalPresetAvailabilityDiagnostics
    var shortcutStore: TerminalShortcutStore
    var terminalServices: TerminalServices
    var operationMetricsStore: OperationMetricsStore?
}

final class TerminalShellResolutionProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var context: TerminalShellResolutionContext
    private var cachedContext: TerminalShellResolutionContext?
    private var cachedResolution: TerminalShellResolution?

    init(initialContext: TerminalShellResolutionContext) {
        self.context = initialContext
    }

    func updateContext(_ context: TerminalShellResolutionContext) {
        lock.lock()
        defer { lock.unlock() }
        guard self.context != context else { return }
        self.context = context
        cachedContext = nil
        cachedResolution = nil
    }

    func resolve() -> TerminalShellResolution {
        lock.lock()
        if let cachedContext,
           cachedContext == context,
           let cachedResolution {
            lock.unlock()
            return cachedResolution
        }
        let snapshot = context
        lock.unlock()
        let resolved = TerminalShellResolver.resolve(context: snapshot)

        lock.lock()
        if context == snapshot {
            cachedContext = snapshot
            cachedResolution = resolved
        }
        lock.unlock()
        return resolved
    }
}

@MainActor
final class TerminalTabActivityState: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var isActive: Bool

    init(id: UUID, isActive: Bool = false) {
        self.id = id
        self.isActive = isActive
    }

    func update(isActive: Bool) -> Bool {
        guard self.isActive != isActive else { return false }
        self.isActive = isActive
        return true
    }
}

@MainActor
final class TerminalTabActivitySummary: ObservableObject {
    @Published private(set) var hasAnyActivity = false

    func update(hasAnyActivity: Bool) {
        guard self.hasAnyActivity != hasAnyActivity else { return }
        self.hasAnyActivity = hasAnyActivity
    }
}
