// TerminalGridSnapshot.swift — Terminal Insight (Phase 18)
// Traceability: REQ-P18-INS-009, REQ-P18-INS-010

import Foundation

/// Captures a terminal grid frame as per-line hashes for efficient diffing.
struct TerminalGridSnapshot {
    let lineHashes: [Int]

    /// Create a snapshot from raw visible contents string.
    init(contents: String) {
        lineHashes = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hashValue }
    }
}
