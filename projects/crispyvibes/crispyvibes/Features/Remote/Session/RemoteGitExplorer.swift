// RemoteGitExplorer.swift — SSH Remote Development
//
// Remote git explorer. Identical to LocalGitExplorer but constructed
// with a RemoteCommandExecutor. The GitExploring protocol and
// GitOutputParser handle the rest — no code duplication needed.

import Foundation

typealias RemoteGitExplorer = LocalGitExplorer
