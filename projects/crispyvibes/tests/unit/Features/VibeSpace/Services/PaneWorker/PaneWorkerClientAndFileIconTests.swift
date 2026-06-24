import AppKit
import Darwin
import Foundation
import XCTest
@testable import CrispyVibes

final class PaneWorkerClientAndFileIconTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-worker-client")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testPaneWorkerErrorDescriptionsAreUserFacing() {
        XCTAssertTrue(PaneWorkerError.executableNotFound.errorDescription?.contains("locate") == true)
        XCTAssertTrue(PaneWorkerError.timeout(2.5).errorDescription?.contains("2.5") == true)
        XCTAssertTrue(PaneWorkerError.invalidResponse.errorDescription?.contains("invalid response") == true)
        XCTAssertEqual(PaneWorkerError.workerFailure("boom").errorDescription, "boom")
    }

    func testPaneWorkerExecutionModeDefaultsToSubprocessOutsidePaneTask() {
        let modeKey = "CRISPYVIBES_PANE_WORKER_EXECUTION_MODE"
        let originalMode = ProcessInfo.processInfo.environment[modeKey]
        unsetenv(modeKey)
        defer {
            if let originalMode {
                setenv(modeKey, originalMode, 1)
            }
        }

        XCTAssertEqual(
            PaneWorkerExecutionMode.resolve(
                from: ProcessInfo.processInfo.environment,
                isPaneTaskProcess: false
            ),
            .subprocess
        )
    }

    func testInvalidExecutionModeOverrideStillUsesSubprocess() {
        XCTAssertEqual(
            PaneWorkerExecutionMode.resolve(
                from: ["CRISPYVIBES_PANE_WORKER_EXECUTION_MODE": "unexpected-value"],
                isPaneTaskProcess: false
            ),
            .subprocess
        )
        XCTAssertEqual(
            PaneWorkerExecutionMode.resolve(
                from: [:],
                isPaneTaskProcess: true
            ),
            .inProcess
        )
    }

    func testPaneWorkerClientInProcessExecutionAndFailurePaths() async throws {
        let modeKey = "CRISPYVIBES_PANE_WORKER_EXECUTION_MODE"
        let originalMode = ProcessInfo.processInfo.environment[modeKey]
        setenv(modeKey, "inprocess", 1)
        defer {
            if let originalMode {
                setenv(modeKey, originalMode, 1)
            } else {
                unsetenv(modeKey)
            }
        }

        let listTarget = tempRoot.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: listTarget, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: listTarget.appendingPathComponent("note.txt"))

        let explorerClient = PaneWorkerClient(pane: .explorer)
        let listValue = try await explorerClient.execute(
            .listTree,
            arguments: ["rootPath": tempRoot.path],
            timeout: 3
        )
        let nodes: [WorkerFileNode] = try decodeJSON(listValue)
        XCTAssertTrue(nodes.contains(where: { $0.path.hasSuffix("folder") && $0.isDirectory }))

        let terminalClient = PaneWorkerClient(pane: .terminal)
        do {
            _ = try await terminalClient.execute(.readFile, arguments: [:], timeout: 3)
            XCTFail("Expected terminal worker failure for unsupported method.")
        } catch let error as PaneWorkerError {
            guard case let .workerFailure(message) = error else {
                return XCTFail("Expected workerFailure, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported terminal worker method"))
        }
    }

    func testPaneWorkerClientSubprocessExecutionPath() async throws {
        let modeKey = "CRISPYVIBES_PANE_WORKER_EXECUTION_MODE"
        let originalMode = ProcessInfo.processInfo.environment[modeKey]
        setenv(modeKey, "subprocess", 1)
        defer {
            if let originalMode {
                setenv(modeKey, originalMode, 1)
            } else {
                unsetenv(modeKey)
            }
        }

        let explorerClient = PaneWorkerClient(pane: .explorer)
        let pingValue = try await explorerClient.execute(.ping, arguments: [:], timeout: 5)
        XCTAssertNotNil(pingValue)
        let secondPingValue = try await explorerClient.execute(.ping, arguments: [:], timeout: 5)
        XCTAssertNotNil(secondPingValue)

        let terminalClient = PaneWorkerClient(pane: .terminal)
        do {
            _ = try await terminalClient.execute(.readFile, arguments: [:], timeout: 5)
            XCTFail("Expected subprocess worker failure for unsupported terminal method.")
        } catch let error as PaneWorkerError {
            guard case let .workerFailure(message) = error else {
                return XCTFail("Expected workerFailure, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported terminal worker method"))
        }
    }

    @MainActor
    func testAppContainerSharesPaneWorkerInstancesByKind() {
        let container = AppContainer.makeDefault()

        let firstExplorer = container.makePaneWorker(pane: .explorer) as AnyObject
        let secondExplorer = container.makePaneWorker(pane: .explorer) as AnyObject
        XCTAssertTrue(firstExplorer === secondExplorer)

        let firstSourceControl = container.makePaneWorker(pane: .sourceControl) as AnyObject
        let secondSourceControl = container.makePaneWorker(pane: .sourceControl) as AnyObject
        XCTAssertTrue(firstSourceControl === secondSourceControl)

        let firstEditor = container.makePaneWorker(pane: .editor) as AnyObject
        let secondEditor = container.makePaneWorker(pane: .editor) as AnyObject
        XCTAssertTrue(firstEditor === secondEditor)

        XCTAssertFalse(firstExplorer === firstEditor)
        XCTAssertFalse(firstExplorer === firstSourceControl)
        XCTAssertFalse(firstSourceControl === firstEditor)
    }

    func testPaneTaskSubprocessHandlesValidAndInvalidRequests() throws {
        let executableURL = try XCTUnwrap(Bundle.main.executableURL)

        let successRequest = try JSONEncoder().encode(
            PaneWorkerRequest(method: .ping, arguments: [:])
        )
        let successResponse = try runPaneTaskSubprocess(
            executableURL: executableURL,
            pane: .editor,
            requestData: successRequest
        )
        XCTAssertEqual(successResponse.terminationStatus, 0)
        let parsedSuccess = try JSONDecoder().decode(PaneWorkerResponse.self, from: successResponse.stdout)
        XCTAssertTrue(parsedSuccess.success)
        XCTAssertNotNil(parsedSuccess.value)

        let invalidResponse = try runPaneTaskSubprocess(
            executableURL: executableURL,
            pane: .editor,
            requestData: Data("not-json".utf8)
        )
        XCTAssertEqual(invalidResponse.terminationStatus, 0)
        let parsedInvalid = try JSONDecoder().decode(PaneWorkerResponse.self, from: invalidResponse.stdout)
        XCTAssertFalse(parsedInvalid.success)
        XCTAssertTrue((parsedInvalid.error ?? "").contains("Invalid worker request"))
    }

    func testFileIconProviderMappingsAreStableAndCaseInsensitive() {
        XCTAssertEqual(FileIconProvider.iconName(for: "swift"), "swift")
        XCTAssertEqual(FileIconProvider.iconName(for: "SWIFT"), "swift")
        XCTAssertEqual(FileIconProvider.iconName(for: "TsX"), "react")
        XCTAssertEqual(FileIconProvider.iconName(for: "json"), "json")
        XCTAssertEqual(FileIconProvider.iconName(for: "ipynb"), "notebook")
        XCTAssertEqual(FileIconProvider.iconName(for: "DOCKERFILE"), "docker")
        XCTAssertNil(FileIconProvider.iconName(for: "unknown-ext"))
        XCTAssertNil(FileIconProvider.iconImage(for: "unknown-ext"))
    }

    func testFileIconProviderMapsLatexExtensionsToTexIcon() {
        XCTAssertEqual(FileIconProvider.iconName(for: "tex"), "tex")
        XCTAssertEqual(FileIconProvider.iconName(for: "latex"), "tex")
        XCTAssertEqual(FileIconProvider.iconName(for: "LTX"), "tex")
    }

    func testTexIconIsTemplateTintedSoItStaysVisibleOnDarkThemes() {
        // tex.svg's glyph paths have no explicit fill (default black) and only a
        // decorative `fill="none"`. It must be treated as monochrome and
        // template-tinted, otherwise it renders as invisible black on dark.
        guard let texImage = FileIconProvider.iconImage(for: "tex") else {
            return XCTFail("tex icon should resolve from bundled SetiIcons")
        }
        XCTAssertTrue(texImage.isTemplate, "tex icon must be template-tinted to stay visible")

        // Sanity: a genuinely colored icon must NOT be template-tinted.
        XCTAssertEqual(FileIconProvider.iconImage(for: "md")?.isTemplate, false)
    }

    func testFileIconProviderPythonMappingHandlesRandomizedCasing() {
        for _ in 0..<120 {
            let randomized = randomizeCasing("py")
            XCTAssertEqual(FileIconProvider.iconName(for: randomized), "python")
        }
    }

    private func randomizeCasing(_ value: String) -> String {
        String(value.map { character in
            Bool.random()
                ? Character(String(character).uppercased())
                : Character(String(character).lowercased())
        })
    }

    private func runPaneTaskSubprocess(
        executableURL: URL,
        pane: PaneWorkerKind,
        requestData: Data
    ) throws -> (terminationStatus: Int32, stdout: Data, stderr: Data) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--pane-task", pane.rawValue]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        stdinPipe.fileHandleForWriting.write(requestData)
        stdinPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, stdout, stderr)
    }
}
