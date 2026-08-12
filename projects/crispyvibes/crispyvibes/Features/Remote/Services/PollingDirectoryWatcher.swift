// PollingDirectoryWatcher.swift — SSH Remote Development

import Foundation

/// Watches remote directories by comparing periodic SFTP directory snapshots.
/// Enhanced mode includes metadata so same-name file changes are observable.
@MainActor
final class PollingDirectoryWatcher: DirectoryWatching {
    enum SnapshotMode {
        case namesOnly
        case metadata
    }

    var onPathsChanged: ((_ changedPaths: Set<String>) -> Void)?

    private struct EntryFingerprint: Hashable {
        let name: String
        let isDirectory: Bool?
        let size: UInt64?
        let modificationTime: TimeInterval?
    }

    private let fileSystem: any FileSystemProviding
    private let interval: TimeInterval
    private let snapshotMode: SnapshotMode
    private var watchedPaths: [String] = []
    private var snapshots: [String: Set<EntryFingerprint>] = [:]
    private var pollTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        fileSystem: any FileSystemProviding,
        interval: TimeInterval = 5.0,
        snapshotMode: SnapshotMode = .namesOnly
    ) {
        self.fileSystem = fileSystem
        self.interval = interval
        self.snapshotMode = snapshotMode
    }

    func watch(paths: [String]) {
        watchedPaths = Array(Set(paths.map(Self.normalizePath))).sorted()
        let watchedSet = Set(watchedPaths)
        snapshots = snapshots.filter { watchedSet.contains($0.key) }
        restartPolling()
    }

    func stop() {
        generation &+= 1
        pollTask?.cancel()
        pollTask = nil
        watchedPaths.removeAll()
        snapshots.removeAll()
    }

    private func restartPolling() {
        generation &+= 1
        let requestGeneration = generation
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await poll(generation: requestGeneration)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(max(interval, 0.05) * 1_000_000_000)
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await poll(generation: requestGeneration)
            }
        }
    }

    private func poll(generation requestGeneration: UInt64) async {
        let paths = watchedPaths
        var changedPaths = Set<String>()

        for path in paths {
            guard !Task.isCancelled, requestGeneration == generation else { return }
            do {
                let descriptors = try await fileSystem.contentsOfDirectory(at: path)
                guard !Task.isCancelled, requestGeneration == generation else { return }
                let snapshot = Set(descriptors.map(fingerprint))
                if let previous = snapshots[path], previous != snapshot {
                    changedPaths.insert(path)
                }
                snapshots[path] = snapshot
            } catch {
                // Preserve the last successful snapshot. A reconnect or transient
                // SFTP failure must not turn an unavailable listing into a delete.
                continue
            }
        }

        guard !Task.isCancelled, requestGeneration == generation, !changedPaths.isEmpty else { return }
        onPathsChanged?(changedPaths)
    }

    private func fingerprint(_ descriptor: FileItemDescriptor) -> EntryFingerprint {
        switch snapshotMode {
        case .namesOnly:
            return EntryFingerprint(
                name: descriptor.name,
                isDirectory: nil,
                size: nil,
                modificationTime: nil
            )
        case .metadata:
            return EntryFingerprint(
                name: descriptor.name,
                isDirectory: descriptor.isDirectory,
                size: descriptor.size,
                modificationTime: descriptor.modificationDate?.timeIntervalSince1970
            )
        }
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    deinit {
        pollTask?.cancel()
    }
}
