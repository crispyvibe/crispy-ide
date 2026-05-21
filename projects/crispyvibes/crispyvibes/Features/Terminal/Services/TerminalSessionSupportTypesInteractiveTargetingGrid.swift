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

    init(visibleContents: String, cols: Int, rows: Int) {
        self.cols = max(cols, 0)
        self.rows = max(rows, 0)

        let rawLines = visibleContents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let boundedLines = Array(rawLines.prefix(self.rows))
        let paddedLineCount = max(self.rows - boundedLines.count, 0)
        let normalizedLines = boundedLines + Array(repeating: "", count: paddedLineCount)

        self.lines = normalizedLines.map { line in
            line.map { character in
                TerminalInteractiveCell(
                    text: String(character),
                    width: 1,
                    payload: nil
                )
            }
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
}
