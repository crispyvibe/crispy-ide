// FolderExplorerViewModel+FolderExploring.swift — SSH Remote Development
// Conformance of existing FolderExplorerViewModel to the FolderExploring protocol.

import Foundation

extension FolderExplorerViewModel: FolderExploring {
    var supportsLiveWatching: Bool { true }
    var supportsFileTransfers: Bool { true }
}
