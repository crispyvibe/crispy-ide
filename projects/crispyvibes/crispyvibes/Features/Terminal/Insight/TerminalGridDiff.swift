// TerminalGridDiff.swift — Terminal Insight (Phase 18)
// Traceability: REQ-P18-INS-011 through REQ-P18-INS-014

import Foundation

/// Pure diff function: compares two frames of per-line hashes and classifies the change.
enum TerminalGridDiff {
    private static let maxScrollOffset = 20
    private static let scrollMatchThreshold = 0.7

    /// Diff two consecutive frames represented as per-line hashes.
    /// Returns the classified change event.
    static func diff(old: [Int], new: [Int]) -> TerminalChangeEvent {
        guard old.count == new.count, !old.isEmpty else {
            return old.isEmpty && new.isEmpty ? .noChange : .fullRedraw
        }

        let count = old.count

        // Fast path: identical frames
        if old == new { return .noChange }

        // Count changed lines
        var changedIndices = [Int]()
        for i in 0..<count where old[i] != new[i] {
            changedIndices.append(i)
        }

        // Single line edit
        if changedIndices.count == 1 {
            return .singleLineEdit(lineIndex: changedIndices[0])
        }

        // Try scroll detection
        if let result = detectScroll(old: old, new: new, count: count) {
            return result
        }

        // Classify by change ratio
        let ratio = Double(changedIndices.count) / Double(count)
        if ratio > 0.7 {
            return .fullRedraw
        }
        return .partialRedraw(changedLineIndices: changedIndices)
    }

    private static func detectScroll(old: [Int], new: [Int], count: Int) -> TerminalChangeEvent? {
        var bestOffset = 0
        var bestMatches = 0

        for offset in 1...min(maxScrollOffset, count - 1) {
            let overlapCount = count - offset
            var matches = 0
            for i in 0..<overlapCount where new[i] == old[i + offset] {
                matches += 1
            }
            if matches > bestMatches {
                bestMatches = matches
                bestOffset = offset
            }
        }

        guard bestOffset > 0 else { return nil }
        let overlapCount = count - bestOffset
        let matchRatio = Double(bestMatches) / Double(overlapCount)
        guard matchRatio >= scrollMatchThreshold else { return nil }

        let newLineCount = bestOffset

        // Check for edits in the overlapping region
        if bestMatches == overlapCount {
            return .scroll(offset: bestOffset, newLineCount: newLineCount)
        }

        var editedIndices = [Int]()
        for i in 0..<overlapCount where new[i] != old[i + bestOffset] {
            editedIndices.append(i)
        }
        return .scrollWithEdits(scrollOffset: bestOffset, newLineCount: newLineCount, editedLineIndices: editedIndices)
    }
}
