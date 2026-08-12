import Foundation
import SwiftTerm

struct SwiftTermTerminalInteractiveGrid: TerminalInteractiveTextGrid {
    let terminal: Terminal

    var cols: Int { terminal.cols }
    var rows: Int { terminal.rows }

    func cell(atColumn column: Int, row: Int) -> TerminalInteractiveCell? {
        guard let charData = terminal.getCharData(col: column, row: row) else { return nil }
        return TerminalInteractiveCell(
            text: String(terminal.getCharacter(for: charData)),
            width: max(Int(charData.width), 1),
            payload: charData.getPayload() as? String
        )
    }
}

struct GhosttyTerminalInteractiveGrid: TerminalInteractiveTextGrid {
    let cols: Int
    let rows: Int
    private let lines: [[TerminalInteractiveCell]]
    private let wrappedContinuationUpperRows: Set<Int>

    init(visibleContents: String, cols: Int, rows: Int) {
        let normalizedColumns = max(cols, 0)
        let normalizedRows = max(rows, 0)
        self.cols = normalizedColumns
        self.rows = normalizedRows

        let rawLines = visibleContents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var physicalLines: [[TerminalInteractiveCell]] = []
        var continuationUpperRows = Set<Int>()
        for rawLine in rawLines {
            let reflowedRows = Self.physicalRows(
                from: rawLine,
                columns: normalizedColumns
            )
            for (index, row) in reflowedRows.enumerated() {
                if index > 0 {
                    continuationUpperRows.insert(physicalLines.count - 1)
                }
                physicalLines.append(row)
            }
        }

        let boundedLines = Array(physicalLines.prefix(normalizedRows))
        let paddedLineCount = max(normalizedRows - boundedLines.count, 0)
        self.lines = boundedLines + Array(repeating: [], count: paddedLineCount)
        self.wrappedContinuationUpperRows = Set(
            continuationUpperRows.filter { $0 + 1 < normalizedRows }
        )
    }

    private static func physicalRows(
        from logicalLine: String,
        columns: Int
    ) -> [[TerminalInteractiveCell]] {
        guard columns > 0 else { return [[]] }
        let cells = logicalLine.map { character in
            TerminalInteractiveCell(
                text: String(character),
                width: 1,
                payload: nil
            )
        }
        guard !cells.isEmpty else { return [[]] }

        return stride(from: 0, to: cells.count, by: columns).map { start in
            Array(cells[start..<min(start + columns, cells.count)])
        }
    }

    func cell(atColumn column: Int, row: Int) -> TerminalInteractiveCell? {
        guard row >= 0, row < rows else { return nil }
        guard column >= 0, column < cols else { return nil }
        guard row < lines.count else {
            return TerminalInteractiveCell(text: " ", width: 1, payload: nil)
        }

        let line = lines[row]
        guard column < line.count else {
            return TerminalInteractiveCell(text: " ", width: 1, payload: nil)
        }

        return line[column]
    }

    func isWrappedContinuation(upperRow: Int, lowerRow: Int) -> Bool? {
        guard lowerRow == upperRow + 1,
              upperRow >= 0,
              lowerRow < rows else { return nil }
        return wrappedContinuationUpperRows.contains(upperRow) ? true : nil
    }
}
