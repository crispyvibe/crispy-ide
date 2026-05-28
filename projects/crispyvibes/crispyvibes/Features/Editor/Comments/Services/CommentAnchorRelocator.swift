import Foundation

/// F049-R05 anchor relocation: when a file's content changes, attempt to keep
/// each comment pointing at the same logical text.
///
/// Strategy (in order):
/// 1. **Exact hash match at original line range** — accept silently
/// 2. **Fuzzy match on `anchorText` within ±50 lines of original line** — accept and shift
/// 3. **Context corroboration** — search anywhere for a window whose
///    `leadingContext`/`trailingContext` match
/// 4. **None match** — `isStale = true`, position preserved
///
/// Performance target: ≤100 ms for files under 10 000 lines (PERF-3).
enum CommentAnchorRelocator {

    /// Result of a relocation attempt for a single comment.
    enum Outcome: Equatable, Sendable {
        case unchanged
        case relocated(newAnchor: CommentAnchor, confidence: Double)
        case stale
    }

    /// Maximum lines to search above/below the original line.
    static let nearbyLineWindow = 50

    // MARK: - Entry point

    /// Returns the relocation outcome for a single comment given the file's
    /// current line array. Pure function — easy to unit-test.
    static func relocate(anchor: CommentAnchor, in lines: [String]) -> Outcome {
        guard !lines.isEmpty else { return .stale }

        // Step 1: exact match at the original range
        if let snippet = extractSnippet(lines: lines, startLine: anchor.startLine, startColumn: anchor.startColumn, endLine: anchor.endLine, endColumn: anchor.endColumn),
           !anchor.anchorText.isEmpty,
           CommentAnchor.hash(snippet) == anchor.anchorHash {
            return .unchanged
        }

        // Step 2: fuzzy line-level scan within ±50 lines
        if let hit = fuzzyLineSearch(lines: lines, anchor: anchor) {
            return .relocated(newAnchor: hit.newAnchor, confidence: hit.confidence)
        }

        // Step 3: context corroboration scan across whole file
        if let hit = contextSearch(lines: lines, anchor: anchor) {
            return .relocated(newAnchor: hit.newAnchor, confidence: hit.confidence)
        }

        // Step 4: stale
        return .stale
    }

    // MARK: - Step 1 helpers

    /// Returns the substring of `lines` covering the given 1-based range, or
    /// nil if the range is out of bounds.
    static func extractSnippet(
        lines: [String],
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int
    ) -> String? {
        guard startLine >= 1, startLine <= lines.count,
              endLine >= startLine, endLine <= lines.count,
              startColumn >= 1, endColumn >= 1
        else { return nil }

        if startLine == endLine {
            let line = lines[startLine - 1]
            let s = line.utf16.index(line.utf16.startIndex, offsetBy: min(startColumn - 1, line.utf16.count))
            let endOff = min(endColumn - 1, line.utf16.count)
            let e = line.utf16.index(line.utf16.startIndex, offsetBy: endOff)
            guard e >= s, let ss = String.Index(s, within: line), let ee = String.Index(e, within: line) else {
                return nil
            }
            return String(line[ss..<ee])
        }

        var out = ""
        for li in (startLine - 1)...(endLine - 1) {
            let line = lines[li]
            if li == startLine - 1 {
                let off = min(startColumn - 1, line.utf16.count)
                let i = line.utf16.index(line.utf16.startIndex, offsetBy: off)
                if let si = String.Index(i, within: line) {
                    out.append(String(line[si...]))
                    out.append("\n")
                }
            } else if li == endLine - 1 {
                let off = min(endColumn - 1, line.utf16.count)
                let i = line.utf16.index(line.utf16.startIndex, offsetBy: off)
                if let ei = String.Index(i, within: line) {
                    out.append(String(line[..<ei]))
                }
            } else {
                out.append(line)
                out.append("\n")
            }
        }
        return out
    }

    // MARK: - Step 2: fuzzy line search

    private struct LineHit {
        let newAnchor: CommentAnchor
        let confidence: Double
    }

    private static func fuzzyLineSearch(lines: [String], anchor: CommentAnchor) -> LineHit? {
        // Normalize search by trimming whitespace at line edges
        let needle = trimmedAnchor(anchor.anchorText)
        guard !needle.isEmpty else { return nil }

        let originalLine = max(1, anchor.startLine)
        let lo = max(1, originalLine - nearbyLineWindow)
        let hi = min(lines.count, originalLine + nearbyLineWindow)

        // First pass: exact substring match line-by-line, prefer closest to original
        var bestHit: (line: Int, column: Int, confidence: Double)? = nil
        for li in lo...hi {
            let line = lines[li - 1]
            if let range = line.range(of: needle) {
                let col = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                let dist = abs(li - originalLine)
                let confidence = 1.0 - (Double(dist) / Double(nearbyLineWindow + 1))
                if (bestHit.map { confidence > $0.confidence }) ?? true {
                    bestHit = (li, col, confidence)
                }
            }
        }
        guard let hit = bestHit else { return nil }

        // Reconstruct the anchor on the new line range
        let newAnchor = adjustedAnchor(from: anchor, lines: lines, foundAtLine: hit.line, foundAtColumn: hit.column)
        return LineHit(newAnchor: newAnchor, confidence: hit.confidence)
    }

    // MARK: - Step 3: context corroboration

    private static func contextSearch(lines: [String], anchor: CommentAnchor) -> LineHit? {
        let leading = trimmedAnchor(anchor.leadingContext)
        let trailing = trimmedAnchor(anchor.trailingContext)
        guard !leading.isEmpty || !trailing.isEmpty else { return nil }

        let needle = trimmedAnchor(anchor.anchorText)
        if needle.isEmpty { return nil }

        var best: (line: Int, column: Int, score: Int)? = nil
        for li in 1...lines.count {
            let line = lines[li - 1]
            guard let range = line.range(of: needle) else { continue }
            let col = line.distance(from: line.startIndex, to: range.lowerBound) + 1
            var score = 1
            if !leading.isEmpty && line.hasPrefix(leading) { score += 2 }
            if !trailing.isEmpty && line.hasSuffix(trailing) { score += 2 }
            // Look at sibling lines for context
            if !leading.isEmpty, li > 1, lines[li - 2].contains(leading) { score += 1 }
            if !trailing.isEmpty, li < lines.count, lines[li].contains(trailing) { score += 1 }
            if (best.map { score > $0.score }) ?? true {
                best = (li, col, score)
            }
        }
        guard let b = best, b.score >= 3 else { return nil }
        let newAnchor = adjustedAnchor(from: anchor, lines: lines, foundAtLine: b.line, foundAtColumn: b.column)
        let conf = min(1.0, Double(b.score) / 5.0)
        return LineHit(newAnchor: newAnchor, confidence: conf)
    }

    // MARK: - Helpers

    private static func trimmedAnchor(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Recompute end line/column for the anchor given a new start position.
    private static func adjustedAnchor(
        from old: CommentAnchor,
        lines: [String],
        foundAtLine: Int,
        foundAtColumn: Int
    ) -> CommentAnchor {
        let lineSpan = old.endLine - old.startLine
        let colSpan = old.endColumn - old.startColumn
        let newEndLine = min(lines.count, foundAtLine + lineSpan)
        let newEndColumn: Int
        if lineSpan == 0 {
            newEndColumn = foundAtColumn + colSpan
        } else {
            newEndColumn = max(1, old.endColumn)
        }
        return CommentAnchor(
            startLine: foundAtLine,
            startColumn: foundAtColumn,
            endLine: newEndLine,
            endColumn: newEndColumn,
            anchorHash: old.anchorHash,
            anchorText: old.anchorText,
            leadingContext: old.leadingContext,
            trailingContext: old.trailingContext
        )
    }
}
