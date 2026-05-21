import SwiftUI

extension MarkdownEditorView {
    func activateFind(replaceMode: Bool) {
        guard viewModel.canEditCurrentDocument else {
            viewModel.errorMessage = "Find and replace is available only for editable markdown and HTML files."
            return
        }

        isFindBarVisible = true
        isReplaceModeVisible = replaceMode
        findStatusMessage = ""
        refreshFindState(resetSelection: true)
        DispatchQueue.main.async {
            isFindFieldFocused = true
        }
    }

    func resetFindUI() {
        isFindBarVisible = false
        isReplaceModeVisible = false
        findQuery = ""
        replaceQuery = ""
        findMatchCount = 0
        selectedMatchIndex = nil
        findStatusMessage = ""
        isFindFieldFocused = false
        invalidateFindCache()
    }

    func findNext() {
        let ranges = cachedMatchRanges()
        guard !ranges.isEmpty else {
            selectedMatchIndex = nil
            findStatusMessage = "No matches"
            return
        }

        let nextIndex: Int
        if let selectedMatchIndex {
            nextIndex = (selectedMatchIndex + 1) % ranges.count
        } else {
            nextIndex = 0
        }
        selectedMatchIndex = nextIndex
        findStatusMessage = ""
    }

    func replaceNext() {
        let ranges = cachedMatchRanges()
        guard !ranges.isEmpty else {
            selectedMatchIndex = nil
            findStatusMessage = "No matches"
            return
        }

        let targetIndex = min(selectedMatchIndex ?? 0, ranges.count - 1)
        let range = ranges[targetIndex]

        var updatedText = viewModel.displayContent
        updatedText.replaceSubrange(range, with: replaceQuery)
        viewModel.userDidEdit(updatedText)

        refreshFindState(resetSelection: false)
        if findMatchCount > 0 {
            selectedMatchIndex = min(targetIndex, findMatchCount - 1)
            findStatusMessage = ""
        } else {
            selectedMatchIndex = nil
            findStatusMessage = "No matches"
        }
    }

    func replaceAll() {
        let query = normalizedFindQuery
        let ranges = cachedMatchRanges()
        guard !ranges.isEmpty else {
            selectedMatchIndex = nil
            findStatusMessage = "No matches"
            return
        }

        let updatedText = viewModel.displayContent.replacingOccurrences(
            of: query,
            with: replaceQuery,
            options: [.caseInsensitive]
        )
        viewModel.userDidEdit(updatedText)

        refreshFindState(resetSelection: true)
        findStatusMessage = "Replaced \(ranges.count) occurrence\(ranges.count == 1 ? "" : "s")"
    }

    func refreshFindState(resetSelection: Bool) {
        findMatchCount = cachedMatchRanges().count
        if resetSelection || (selectedMatchIndex ?? 0) >= findMatchCount {
            selectedMatchIndex = nil
        }
        if findQuery.isEmpty {
            findStatusMessage = ""
        } else if findMatchCount == 0 {
            findStatusMessage = "No matches"
        } else if findStatusMessage == "No matches" {
            findStatusMessage = ""
        }
    }

    var normalizedFindQuery: String {
        findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func invalidateFindCache() {
        cachedFindSource = ""
        cachedFindQuery = ""
        cachedFindRanges = []
    }

    func cachedMatchRanges() -> [Range<String.Index>] {
        let query = normalizedFindQuery
        let content = viewModel.displayContent
        if cachedFindSource == content,
           cachedFindQuery == query {
            return cachedFindRanges
        }

        let ranges = matchRanges(in: content, query: query)
        cachedFindSource = content
        cachedFindQuery = query
        cachedFindRanges = ranges
        return ranges
    }

    func matchRanges(in content: String, query: String) -> [Range<String.Index>] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = content.startIndex

        while searchStart < content.endIndex,
              let range = content.range(of: trimmedQuery, options: [.caseInsensitive], range: searchStart..<content.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }

        return ranges
    }
}
