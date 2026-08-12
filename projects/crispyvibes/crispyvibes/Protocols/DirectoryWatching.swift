// DirectoryWatching.swift — SSH Remote Development

import Foundation

/// Abstraction over file system change observation.
/// Local: wraps FSEvents via DirectoryWatcher. Remote: wraps PollingDirectoryWatcher.
@MainActor
protocol DirectoryWatching: AnyObject {
    var onPathsChanged: ((_ changedPaths: Set<String>) -> Void)? { get set }
    func watch(paths: [String])
    func stop()
}
