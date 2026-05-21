// LocalProjectMetadata.swift — SSH Remote Development

import Combine
import Foundation

/// ProjectMetadata for local (on-disk) projects.
/// identifier is the normalized file path. hostLabel and connectionState are nil.
struct LocalProjectMetadata: ProjectMetadata {
    let identifier: String
    let displayName: String
    let displayPath: String
    let rootDirectoryURL: URL
    let hostLabel: String? = nil
    let connectionState: AnyPublisher<ConnectionState, Never>? = nil

    init(rootURL: URL) {
        let normalized = rootURL.standardizedFileURL
        self.rootDirectoryURL = normalized
        self.identifier = normalized.path
        self.displayName = normalized.lastPathComponent.isEmpty ? normalized.path : normalized.lastPathComponent
        self.displayPath = normalized.path
    }
}
