// PollingDirectoryWatcher.swift — SSH Remote Development

import Foundation

/// Watches remote directories for changes by polling via SSH ls.
/// Used instead of FSEvents for remote file systems.
final class PollingDirectoryWatcher: DirectoryWatching {
    var onPathsChanged: ((_ changedPaths: Set<String>) -> Void)?

    private let connection: SSHConnection
    private let interval: TimeInterval
    private var watchedPaths: [String] = []
    private var snapshots: [String: Set<String>] = [:]
    private var pollTask: Task<Void, Never>?

    init(connection: SSHConnection, interval: TimeInterval = 5.0) {
        self.connection = connection
        self.interval = interval
    }

    func watch(paths: [String]) {
        watchedPaths = paths
        // Prune snapshots for paths no longer watched
        let watchedSet = Set(paths)
        snapshots = snapshots.filter { watchedSet.contains($0.key) }
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        snapshots.removeAll()
    }

    // MARK: - Private

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.interval ?? 5.0) * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await self.poll()
            }
        }
    }

    private func poll() async {
        let isConnected = await MainActor.run { connection.state == .connected }
        guard isConnected else { return }
        var changedPaths = Set<String>()

        for path in watchedPaths {
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            guard let output = try? await connection.executeCommand("ls -1a '\(escaped)' 2>/dev/null") else { continue }
            let entries = Set(output.split(whereSeparator: \.isNewline).map(String.init).filter { $0 != "." && $0 != ".." })

            if let previous = snapshots[path], previous != entries {
                changedPaths.insert(path)
            }
            snapshots[path] = entries
        }

        if !changedPaths.isEmpty {
            let pathsToReport = changedPaths
            await MainActor.run { self.onPathsChanged?(pathsToReport) }
        }
    }

    deinit { pollTask?.cancel() }
}
