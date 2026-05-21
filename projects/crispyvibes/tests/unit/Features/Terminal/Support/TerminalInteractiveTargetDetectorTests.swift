import XCTest
@testable import CrispyVibes

final class TerminalInteractiveTargetDetectorTests: XCTestCase {
    private struct TestGrid: TerminalInteractiveTextGrid {
        let lines: [[TerminalInteractiveCell]]

        var cols: Int {
            lines.map(\.count).max() ?? 0
        }

        var rows: Int { lines.count }

        func cell(atColumn column: Int, row: Int) -> TerminalInteractiveCell? {
            guard row >= 0, row < lines.count else { return nil }
            let line = lines[row]
            guard column >= 0, column < line.count else { return nil }
            return line[column]
        }
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
}
