// TerminalChangeEvent.swift — Terminal Insight (Phase 18)
// Traceability: REQ-P18-INS-014

import Foundation

/// Classifies a single frame-to-frame terminal grid change.
enum TerminalChangeEvent: Equatable {
    case noChange
    case scroll(offset: Int, newLineCount: Int)
    case scrollWithEdits(scrollOffset: Int, newLineCount: Int, editedLineIndices: [Int])
    case singleLineEdit(lineIndex: Int)
    case partialRedraw(changedLineIndices: [Int])
    case fullRedraw
    case streamingOutput
}
