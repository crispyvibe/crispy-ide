import SwiftTerm
import XCTest
@testable import CrispyVibes

final class TerminalInteractiveTargetDetectorTests: XCTestCase {
    private struct TestGrid: TerminalInteractiveTextGrid {
        let lines: [[TerminalInteractiveCell]]
        var columnCount: Int? = nil

        var cols: Int {
            columnCount ?? (lines.map(\.count).max() ?? 0)
        }

        var rows: Int { lines.count }

        func cell(atColumn column: Int, row: Int) -> TerminalInteractiveCell? {
            guard row >= 0, row < lines.count else { return nil }
            let line = lines[row]
            guard column >= 0, column < line.count else { return nil }
            return line[column]
        }
    }

    private final class SwiftTermDelegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    func testDetectsPlainURLToken() {
        let target = TerminalInteractiveTargetDetector.detectTarget(
            fromRawToken: "https://example.com/docs",
            currentDirectory: nil
        )

        XCTAssertEqual(target, .link("https://example.com/docs"))
    }

    func testDetectsRelativeFilePathTokenUsingCurrentDirectory() throws {
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = rootDirectory.appendingPathComponent("src", isDirectory: true)
        let fileURL = sourceDirectory.appendingPathComponent("example.txt", isDirectory: false)

        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: fileURL)

        let target = TerminalInteractiveTargetDetector.detectTarget(
            fromRawToken: "src/example.txt:12:3",
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(
                TerminalFileSystemTarget(
                    url: fileURL.standardizedFileURL,
                    line: 12,
                    column: 3
                )
            )
        )
    }

    func testDetectsBareFilenameInCurrentDirectory() throws {
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootDirectory.appendingPathComponent("package.json", isDirectory: false)

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: fileURL)

        let target = TerminalInteractiveTargetDetector.detectTarget(
            fromRawToken: "package.json:12",
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(
                TerminalFileSystemTarget(
                    url: fileURL.standardizedFileURL,
                    line: 12,
                    column: nil
                )
            )
        )
    }

    func testDetectsExtensionlessBareFilenameWhenLineNumberIsPresent() throws {
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootDirectory.appendingPathComponent("script", isDirectory: false)

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Data("#!/bin/sh".utf8).write(to: fileURL)

        let target = TerminalInteractiveTargetDetector.detectTarget(
            fromRawToken: "script:7",
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(
                TerminalFileSystemTarget(
                    url: fileURL.standardizedFileURL,
                    line: 7,
                    column: nil
                )
            )
        )
    }

    func testRejectsTrailingColonFileReferenceShapes() throws {
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootDirectory.appendingPathComponent("example.txt", isDirectory: false)

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: fileURL)

        XCTAssertNil(
            TerminalInteractiveTargetDetector.detectTarget(
                fromRawToken: "example.txt:",
                currentDirectory: rootDirectory
            )
        )
        XCTAssertNil(
            TerminalInteractiveTargetDetector.detectTarget(
                fromRawToken: "example.txt:12:",
                currentDirectory: rootDirectory
            )
        )
        XCTAssertNil(
            TerminalInteractiveTargetDetector.detectTarget(
                fromRawToken: "example.txt:12:3:",
                currentDirectory: rootDirectory
            )
        )
    }

    func testRejectsPathologicalDottedTokenWithoutHanging() {
        let token = String(repeating: "segment.", count: 40) + ":x"
        let start = Date()

        for _ in 0..<20 {
            let target = TerminalInteractiveTargetDetector.detectTarget(
                fromRawToken: token,
                currentDirectory: nil
            )
            XCTAssertNil(target)
        }

        XCTAssertLessThan(
            Date().timeIntervalSince(start),
            0.5,
            "Interactive target detection should stay cheap on malformed dotted tokens."
        )
    }

    func testRejectsMalformedDottedFilenameShapes() throws {
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: rootDirectory.appendingPathComponent("foo.", isDirectory: false))
        try Data("sample".utf8).write(to: rootDirectory.appendingPathComponent("foo..bar", isDirectory: false))

        XCTAssertNil(
            TerminalInteractiveTargetDetector.detectTarget(
                fromRawToken: "foo.",
                currentDirectory: rootDirectory
            )
        )
        XCTAssertNil(
            TerminalInteractiveTargetDetector.detectTarget(
                fromRawToken: "foo..bar",
                currentDirectory: rootDirectory
            )
        )
    }

    func testGridPayloadLinkDetectionDoesNotDependOnSwiftTermTerminalType() {
        let grid = TestGrid(
            lines: [[
                TerminalInteractiveCell(
                    text: "x",
                    width: 1,
                    payload: "id=1;https://example.com/payload"
                )
            ]]
        )

        let target = TerminalInteractiveTargetDetector.detectTarget(
            in: grid,
            visibleColumn: 0,
            visibleRow: 0,
            currentDirectory: nil
        )

        XCTAssertEqual(target, .link("https://example.com/payload"))
    }

    func testGridReaderDetectsRelativeFileAtClickedColumn() throws {
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = rootDirectory.appendingPathComponent("src", isDirectory: true)
        let fileURL = sourceDirectory.appendingPathComponent("example.txt", isDirectory: false)

        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: fileURL)

        let line = "src/example.txt:12:3"
        let grid = TestGrid(
            lines: [line.map {
                TerminalInteractiveCell(text: String($0), width: 1, payload: nil)
            }]
        )

        let target = TerminalInteractiveTargetDetector.detectTarget(
            in: grid,
            visibleColumn: 5,
            visibleRow: 0,
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(
                TerminalFileSystemTarget(
                    url: fileURL.standardizedFileURL,
                    line: 12,
                    column: 3
                )
            )
        )
    }

    func testGridReaderReturnsTokenColumnsForHoverHighlight() {
        let line = "see https://example.com/docs now"
        let grid = TestGrid(
            lines: [line.map {
                TerminalInteractiveCell(text: String($0), width: 1, payload: nil)
            }]
        )

        let hit = TerminalInteractiveTargetDetector.detectHit(
            in: grid,
            visibleColumn: 10,
            visibleRow: 0,
            currentDirectory: nil
        )

        XCTAssertEqual(hit?.target, .link("https://example.com/docs"))
        XCTAssertEqual(hit?.columns, 4..<28)
        XCTAssertEqual(hit?.row, 0)
    }

    func testWrappedURLClickingFirstRowResolvesCompleteTarget() {
        let firstRow = "https://example.com/very/"
        let secondRow = "long/path"
        let grid = TestGrid(lines: [cells(firstRow), cells(secondRow)])

        let hit = TerminalInteractiveTargetDetector.detectHit(
            in: grid,
            visibleColumn: 10,
            visibleRow: 0,
            currentDirectory: nil
        )

        XCTAssertEqual(hit?.target, .link(firstRow + secondRow))
        XCTAssertEqual(hit?.row, 0)
        XCTAssertEqual(hit?.columns, 0..<firstRow.count)
    }

    func testWrappedURLClickingSecondRowResolvesCompleteTarget() {
        let firstRow = "https://example.com/very/"
        let secondRow = "long/path"
        let grid = TestGrid(lines: [cells(firstRow), cells(secondRow)])

        let hit = TerminalInteractiveTargetDetector.detectHit(
            in: grid,
            visibleColumn: 2,
            visibleRow: 1,
            currentDirectory: nil
        )

        XCTAssertEqual(hit?.target, .link(firstRow + secondRow))
        XCTAssertEqual(hit?.row, 1)
        XCTAssertEqual(hit?.columns, 0..<secondRow.count)
    }

    func testIndentedTUIWrappedURLClickingEveryRowResolvesCompleteTarget() throws {
        let url = "https://api.example.net/v1/organizations/engineering-"
            + "department/projects/customer-analytics/reports/quarte"
            + "rly-performance-summary"
        let indent = "  "
        let extractedRows = [
            "https://api.example.net/v1/organizations/engineering-",
            "department/projects/customer-analytics/reports/quarte",
            "rly-performance-summary"
        ]
        XCTAssertEqual(extractedRows.map(\.count), [53, 53, 23])
        let grid = TestGrid(
            lines: extractedRows.map { cells(indent + $0) },
            columnCount: 55
        )
        let expectedSegments = [
            TerminalInteractiveTargetSegment(row: 0, columns: 2..<55),
            TerminalInteractiveTargetSegment(row: 1, columns: 2..<55),
            TerminalInteractiveTargetSegment(row: 2, columns: 2..<25)
        ]

        for row in extractedRows.indices {
            let hit = try XCTUnwrap(
                TerminalInteractiveTargetDetector.detectHit(
                    in: grid,
                    visibleColumn: 5,
                    visibleRow: row,
                    currentDirectory: nil
                )
            )
            XCTAssertEqual(hit.target, .link(url), "row \(row) returned a truncated target")
            XCTAssertEqual(hit.segments, expectedSegments)
        }
    }

    func testSwiftTermGridResolvesIndentedTUIWrappedURLFromEveryRow() throws {
        let url = "https://api.example.net/v1/organizations/engineering-"
            + "department/projects/customer-analytics/reports/quarte"
            + "rly-performance-summary"
        let extractedRows = [
            "https://api.example.net/v1/organizations/engineering-",
            "department/projects/customer-analytics/reports/quarte",
            "rly-performance-summary"
        ]
        let delegate = SwiftTermDelegate()
        let terminal = Terminal(delegate: delegate)
        terminal.resize(cols: 55, rows: 5)
        for (row, text) in extractedRows.enumerated() {
            terminal.feed(text: "\u{1B}[\(row + 1);1H  \(text)")
        }
        let grid = SwiftTermTerminalInteractiveGrid(terminal: terminal)

        for row in extractedRows.indices {
            let hit = try XCTUnwrap(
                TerminalInteractiveTargetDetector.detectHit(
                    in: grid,
                    visibleColumn: 5,
                    visibleRow: row,
                    currentDirectory: nil
                )
            )
            XCTAssertEqual(hit.target, .link(url), "row \(row) returned a truncated target")
            XCTAssertEqual(hit.segments.count, extractedRows.count)
        }
    }

    func testGhosttyLogicalLineReflowsIntoCompleteMultiRowURLTarget() throws {
        let url = "https://media.example.tv/watch/documentaries/science-and-nature/"
            + "exploring-the-deepest-regions-of-the-pacific-ocean?episode=7&season=3"
            + "&quality=ultra-high-definition"
        let columns = 48
        let expectedRowCount = Int(ceil(Double(url.count) / Double(columns)))
        XCTAssertEqual(expectedRowCount, 4)
        let grid = GhosttyTerminalInteractiveGrid(
            visibleContents: url,
            cols: columns,
            rows: expectedRowCount
        )
        let expectedSegments = (0..<expectedRowCount).map { row in
            TerminalInteractiveTargetSegment(
                row: row,
                columns: 0..<min(columns, url.count - row * columns)
            )
        }

        for row in 0..<expectedRowCount {
            let hit = try XCTUnwrap(
                TerminalInteractiveTargetDetector.detectHit(
                    in: grid,
                    visibleColumn: 3,
                    visibleRow: row,
                    currentDirectory: nil
                )
            )
            XCTAssertEqual(hit.target, .link(url), "row \(row) returned a truncated target")
            XCTAssertEqual(hit.segments, expectedSegments)
        }
    }

    func testGhosttyPhysicalRowsWithOneColumnGridMismatchResolveCompleteURL() throws {
        let url = "https://media.example.tv/watch/documentaries/science-and-nature/"
            + "exploring-the-deepest-regions-of-the-pacific-ocean?episode=7&season=3"
            + "&quality=ultra-high-definition"
        let extractedRowWidth = 48
        let characters = Array(url)
        let extractedRows = stride(from: 0, to: characters.count, by: extractedRowWidth).map { start in
            String(characters[start..<min(start + extractedRowWidth, characters.count)])
        }
        let grid = GhosttyTerminalInteractiveGrid(
            visibleContents: extractedRows.joined(separator: "\n"),
            cols: extractedRowWidth + 1,
            rows: extractedRows.count
        )

        for row in extractedRows.indices {
            let hit = try XCTUnwrap(

                TerminalInteractiveTargetDetector.detectHit(
                    in: grid,
                    visibleColumn: 3,
                    visibleRow: row,
                    currentDirectory: nil
                )
            )
            XCTAssertEqual(hit.target, .link(url), "row \(row) returned a truncated target")
            XCTAssertEqual(hit.segments.count, extractedRows.count)
        }
    }

    func testGhosttyTrimmedTUIRowsWithTwoColumnInsetResolveCompleteURL() throws {
        let url = "https://api.example.net/v1/organizations/engineering-"
            + "department/projects/customer-analytics/reports/quarte"
            + "rly-performance-summary"
        let extractedRows = [
            "https://api.example.net/v1/organizations/engineering-",
            "department/projects/customer-analytics/reports/quarte",
            "rly-performance-summary"
        ]
        let grid = GhosttyTerminalInteractiveGrid(
            visibleContents: extractedRows.joined(separator: "\n"),
            cols: 55,
            rows: 3
        )

        for row in extractedRows.indices {
            let hit = try XCTUnwrap(
                TerminalInteractiveTargetDetector.detectHit(
                    in: grid,
                    visibleColumn: 5,
                    visibleRow: row,
                    currentDirectory: nil
                )
            )
            XCTAssertEqual(hit.target, .link(url), "row \(row) returned a truncated target")
            XCTAssertEqual(hit.segments.count, extractedRows.count)
        }
    }

    func testDoesNotJoinPriorRowWhenItDoesNotReachRightEdge() {
        let firstRow = "https://example.com/wra"
        let secondRow = "pped"
        let grid = TestGrid(lines: [cells(firstRow), cells(secondRow)], columnCount: 32)

        XCTAssertNil(
            TerminalInteractiveTargetDetector.detectTarget(
                in: grid,
                visibleColumn: 2,
                visibleRow: 1,
                currentDirectory: nil
            )
        )
    }

    func testWrappedFilePathClickingEitherRowResolvesCompleteTarget() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let directory = rootDirectory.appendingPathComponent("folder", isDirectory: true)
        let fileURL = directory.appendingPathComponent("verylong.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: fileURL)

        let firstRow = "folder/verylong"
        let secondRow = ".txt:8:2"
        let grid = TestGrid(lines: [cells(firstRow), cells(secondRow)])
        let expected = TerminalInteractiveTarget.fileSystem(
            TerminalFileSystemTarget(url: fileURL.standardizedFileURL, line: 8, column: 2)
        )

        XCTAssertEqual(
            TerminalInteractiveTargetDetector.detectTarget(
                in: grid,
                visibleColumn: 4,
                visibleRow: 0,
                currentDirectory: rootDirectory
            ),
            expected
        )
        XCTAssertEqual(
            TerminalInteractiveTargetDetector.detectTarget(
                in: grid,
                visibleColumn: 4,
                visibleRow: 1,
                currentDirectory: rootDirectory
            ),
            expected
        )
    }

    func testDetectsSingleQuotedPathWithSpacesAndLocation() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let fileURL = rootDirectory.appendingPathComponent("My File.txt")
        try Data("sample".utf8).write(to: fileURL)
        let grid = TestGrid(lines: [cells("'My File.txt':12:3")])

        let target = TerminalInteractiveTargetDetector.detectTarget(
            in: grid,
            visibleColumn: 3,
            visibleRow: 0,
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(TerminalFileSystemTarget(url: fileURL.standardizedFileURL, line: 12, column: 3))
        )
    }

    func testDetectsDoubleQuotedPathWithSpacesAndLocation() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let fileURL = rootDirectory.appendingPathComponent("Other File.txt")
        try Data("sample".utf8).write(to: fileURL)
        let grid = TestGrid(lines: [cells("\"Other File.txt\":7:2")])

        let target = TerminalInteractiveTargetDetector.detectTarget(
            in: grid,
            visibleColumn: 7,
            visibleRow: 0,
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(TerminalFileSystemTarget(url: fileURL.standardizedFileURL, line: 7, column: 2))
        )
    }

    func testDetectsBackslashEscapedPathWithSpacesAndLocation() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let fileURL = rootDirectory.appendingPathComponent("My File.txt")
        try Data("sample".utf8).write(to: fileURL)
        let grid = TestGrid(lines: [cells("My\\ File.txt:9:4")])

        let target = TerminalInteractiveTargetDetector.detectTarget(
            in: grid,
            visibleColumn: 3,
            visibleRow: 0,
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(TerminalFileSystemTarget(url: fileURL.standardizedFileURL, line: 9, column: 4))
        )
    }

    func testDetectsUniqueRawPathWithSpacesAndLocation() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let fileURL = rootDirectory.appendingPathComponent("My File.txt")
        try Data("sample".utf8).write(to: fileURL)
        let grid = TestGrid(lines: [cells("My File.txt:5:6")])

        let target = TerminalInteractiveTargetDetector.detectTarget(
            in: grid,
            visibleColumn: 2,
            visibleRow: 0,
            currentDirectory: rootDirectory
        )

        XCTAssertEqual(
            target,
            .fileSystem(TerminalFileSystemTarget(url: fileURL.standardizedFileURL, line: 5, column: 6))
        )
    }

    func testRejectsAmbiguousRawPathWithSpaces() throws {
        let rootDirectory = try makeTemporaryDirectory()
        try Data("sample".utf8).write(to: rootDirectory.appendingPathComponent("My File.txt"))
        try Data("sample".utf8).write(to: rootDirectory.appendingPathComponent("File.txt"))
        let grid = TestGrid(lines: [cells("My File.txt")])

        XCTAssertNil(
            TerminalInteractiveTargetDetector.detectTarget(
                in: grid,
                visibleColumn: 4,
                visibleRow: 0,
                currentDirectory: rootDirectory
            )
        )
    }

    func testClassifiesFileURLAsFileSystemTarget() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let fileURL = rootDirectory.appendingPathComponent("File With Space.txt")
        try Data("sample".utf8).write(to: fileURL)

        let target = TerminalInteractiveTargetDetector.detectTarget(
            fromRawToken: fileURL.absoluteString,
            currentDirectory: nil
        )

        XCTAssertEqual(
            target,
            .fileSystem(TerminalFileSystemTarget(url: fileURL.standardizedFileURL, line: nil, column: nil))
        )
    }

    private func cells(_ line: String) -> [TerminalInteractiveCell] {
        line.map { TerminalInteractiveCell(text: String($0), width: 1, payload: nil) }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
