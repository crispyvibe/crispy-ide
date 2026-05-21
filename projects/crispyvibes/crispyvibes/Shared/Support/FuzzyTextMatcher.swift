import Foundation

struct FuzzyTextMatch: Sendable {
    let score: Int
    let firstOffset: Int
    let matchedSpan: Int
    let isPrefix: Bool
    let isContiguous: Bool
    let startsOnBoundary: Bool
}

enum FuzzyTextMatcher {
    static func match(candidate: String, query: String) -> FuzzyTextMatch? {
        match(candidateUnits: Array(candidate.utf16), queryUnits: Array(query.utf16))
    }

    static func match(candidateUnits: [UInt16], queryUnits: [UInt16]) -> FuzzyTextMatch? {
        guard !queryUnits.isEmpty else { return nil }

        var matchedOffsets: [Int] = []
        matchedOffsets.reserveCapacity(queryUnits.count)

        var queryIndex = 0

        for (offset, unit) in candidateUnits.enumerated() {
            guard queryIndex < queryUnits.count else { break }
            if unit == queryUnits[queryIndex] {
                matchedOffsets.append(offset)
                queryIndex += 1
            }
        }

        guard queryIndex == queryUnits.count,
              let firstOffset = matchedOffsets.first,
              let lastOffset = matchedOffsets.last else {
            return nil
        }

        let queryLength = queryUnits.count
        let matchedSpan = lastOffset - firstOffset + 1
        let gapCount = max(0, matchedSpan - queryLength)
        let isContiguous = gapCount == 0
        let isPrefix = firstOffset == 0 && isContiguous
        let isExact = isPrefix && candidateUnits.count == queryLength
        let candidateOverhang = max(0, candidateUnits.count - queryLength)
        let startsOnBoundary = firstOffset == 0 || isBoundary(candidateUnits[safe: firstOffset - 1])

        var score = 0
        if isExact { score += 1_000 }
        if isPrefix { score += 700 }
        if isContiguous { score += 280 }
        if startsOnBoundary { score += 120 }

        score += max(0, 240 - (gapCount * 24))
        score += max(0, 140 - (firstOffset * 6))
        score += max(0, 120 - (candidateOverhang / 2))

        return FuzzyTextMatch(
            score: score,
            firstOffset: firstOffset,
            matchedSpan: matchedSpan,
            isPrefix: isPrefix,
            isContiguous: isContiguous,
            startsOnBoundary: startsOnBoundary
        )
    }

    private static func isBoundary(_ value: UInt16?) -> Bool {
        guard let value else { return true }
        switch value {
        case 47, 92, 45, 95, 32, 9, 46:
            return true
        default:
            return false
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
