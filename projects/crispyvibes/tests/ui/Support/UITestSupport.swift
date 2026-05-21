import Foundation
import XCTest
#if os(macOS)
import AppKit
import CoreGraphics
import ImageIO
import Darwin
#endif

struct UITestFixture {
    let root: URL
    let projects: [URL]
    let catalogJSON: String
}

struct UITestShortcut {
    let id: UUID
    let name: String
    let command: String
    let launchBehavior: String

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        launchBehavior: String
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.launchBehavior = launchBehavior
    }
}

private enum UITestAppTarget: CaseIterable {
    case local
    case main

    static var compiledDefault: UITestAppTarget {
#if LOCAL_APP
        .local
#else
        .main
#endif
    }

    static var current: UITestAppTarget {
        let environment = ProcessInfo.processInfo.environment
        if let rawValue = environment["CRISPYVIBES_UI_TEST_APP_TARGET"]?.lowercased() {
            switch rawValue {
            case "local":
                return .local
            case "main":
                return .main
            default:
                break
            }
        }

        return compiledDefault
    }

    var bundleIdentifier: String {
        switch self {
        case .local:
            return "com.crispyvibe.app.local"
        case .main:
            return "com.crispyvibe.app"
        }
    }

    var executableSuffix: String {
        switch self {
        case .local:
            return "/CrispyLocal.app/Contents/MacOS/CrispyLocal"
        case .main:
            return "/Crispy.app/Contents/MacOS/Crispy"
        }
    }

    var supportDirectoryName: String {
        switch self {
        case .local:
            return "CrispyLocal"
        case .main:
            return "Crispy"
        }
    }
}

func appUnderTestSupportURL() -> URL {
    // NSHomeDirectory() in UI test runner may resolve to a sandbox path.
    // Use pw_dir to get the real user home directory.
    let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)
    return URL(fileURLWithPath: realHome)
        .appendingPathComponent("Library/Application Support")
        .appendingPathComponent(UITestAppTarget.current.supportDirectoryName, isDirectory: true)
}

func appUnderTestVibeSpacesURL() -> URL {
    appUnderTestSupportURL().appendingPathComponent("vibespaces", isDirectory: true)
}

func makeFixture(
    projectCount: Int,
    assignColorTagToFirstProject: Bool = false,
    vibespaceShortcuts: [UITestShortcut] = []
) throws -> UITestFixture {
    let base = FileManager.default.temporaryDirectory
    let root = base.appendingPathComponent("crispyvibes-ui-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    var projects: [URL] = []
    if projectCount > 0 {
        for index in 1...projectCount {
            let projectURL = root.appendingPathComponent("project-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

            let readme = projectURL.appendingPathComponent("README.md")
            try Data("# Project \(index)\n".utf8).write(to: readme)
            let notes = projectURL.appendingPathComponent("notes.txt")
            try Data("hello".utf8).write(to: notes)
            let swiftFile = projectURL.appendingPathComponent("app.swift")
            try Data("print(\"project \(index)\")\n".utf8).write(to: swiftFile)
            let jsFile = projectURL.appendingPathComponent("script.js")
            try Data("export const project = \(index);\n".utf8).write(to: jsFile)
            let sqlFile = projectURL.appendingPathComponent("query.sql")
            try Data("SELECT * FROM projects WHERE id = \(index);\n".utf8).write(to: sqlFile)
            let rFile = projectURL.appendingPathComponent("analysis.r")
            try Data("summary(c(1, 2, 3, \(index)))\n".utf8).write(to: rFile)
            let marker = projectURL.appendingPathComponent("project-\(index)-marker.txt")
            try Data("marker-\(index)\n".utf8).write(to: marker)
            let pngFile = projectURL.appendingPathComponent("preview.png")
            try samplePNGData().write(to: pngFile)
            let svgFile = projectURL.appendingPathComponent("diagram.svg")
            try Data(
                """
                <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
                  <rect width="32" height="32" fill="#ffffff" />
                  <circle cx="16" cy="16" r="8" fill="#000000" />
                </svg>
                """.utf8
            ).write(to: svgFile)
            let folder = projectURL.appendingPathComponent("Sources", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("print(\"ok\")\n".utf8).write(to: folder.appendingPathComponent("main.swift"))

            projects.append(projectURL)
        }
    }

    let vibespaceID = UUID()
    var projectColorTags: [String: String] = [:]
    if assignColorTagToFirstProject, let first = projects.first {
        projectColorTags[first.path] = "#336699"
    }

    let config: [String: Any] = [
        "id": vibespaceID.uuidString,
        "name": "UI Fixture",
        "projectPaths": projects.map(\.path),
        "unresolvedProjectPaths": [],
        "focusedProjectPath": projects.first?.path ?? NSNull(),
        "startupSettings": [
            "startupTerminalCount": 1,
            "startupProfiles": [["presetID": NSNull(), "command": ""]],
            "focusTerminalOnProjectSwitch": true
        ],
        "sourceControlSettings": [
            "ignoredDirectoryNames": [
                ".build",
                ".cache",
                ".derived",
                ".next",
                ".nuxt",
                ".swiftpm",
                "Build",
                "Carthage",
                "DerivedData",
                "Pods",
                "SourcePackages",
                "build",
                "checkouts",
                "dist",
                "node_modules",
                "out"
            ],
            "scanMaxDepth": 8,
            "scanMaxRepositories": 64,
            "autoPresentedRepositoryLimit": 12
        ],
        "shortcuts": vibespaceShortcuts.map { shortcut in
            [
                "id": shortcut.id.uuidString,
                "name": shortcut.name,
                "command": shortcut.command,
                "launchBehavior": shortcut.launchBehavior
            ]
        },
        "version": 2
    ]
    var entry: [String: Any] = ["config": config]
    if !projectColorTags.isEmpty {
        entry["projectColorTags"] = projectColorTags
    }
    let data = try JSONSerialization.data(withJSONObject: [entry], options: [])
    let catalogJSON = try XCTUnwrap(String(data: data, encoding: .utf8))
    return UITestFixture(root: root, projects: projects, catalogJSON: catalogJSON)
}

private func samplePNGData() throws -> Data {
    let filePath = URL(fileURLWithPath: #filePath)
    let fixtureImage = filePath
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/preview.png")

    guard FileManager.default.fileExists(atPath: fixtureImage.path) else {
        throw NSError(
            domain: "UITestSupport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing UI fixture PNG at \(fixtureImage.path)."]
        )
    }

    return try Data(contentsOf: fixtureImage, options: .mappedIfSafe)
}

func makeApplication(
    fixture: UITestFixture,
    resetState: Bool = true,
    extraLaunchArguments: [String] = [],
    extraLaunchEnvironment: [String: String] = [:]
) -> XCUIApplication {
    ensureAppUnderTestIsNotRunning()
    let app = XCUIApplication()
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] + extraLaunchArguments
    app.launchEnvironment["CRISPYVIBES_UI_TEST_MODE"] = "1"
    app.launchEnvironment["CRISPYVIBES_UI_TEST_RESET_STATE"] = resetState ? "1" : "0"
    app.launchEnvironment["CRISPYVIBES_UI_TEST_VIBESPACE_CATALOG"] = fixture.catalogJSON
    app.launchEnvironment["CRISPYVIBES_UI_TEST_APPEARANCE"] = "dark"
    app.launchEnvironment["CRISPYVIBES_UI_TEST_START_IN_VIBESPACE"] = "1"
    app.launchEnvironment["CRISPYVIBES_UI_TEST_DISABLE_AUTO_WALKTHROUGH"] = "1"
    app.launchEnvironment["CRISPYVIBES_UI_TEST_RESET_WALKTHROUGH"] = "1"
    for (key, value) in extraLaunchEnvironment {
        app.launchEnvironment[key] = value
    }
    return app
}

func ensureAppUnderTestIsNotRunning(timeout: TimeInterval = 4) {
#if os(macOS)
    let runningApps = NSWorkspace.shared.runningApplications.filter { app in
        UITestAppTarget.allCases.contains { target in
            if app.bundleIdentifier == target.bundleIdentifier {
                return true
            }
            if let executablePath = app.executableURL?.path,
               executablePath.hasSuffix(target.executableSuffix) {
                return true
            }
            return false
        }
    }
    guard !runningApps.isEmpty else { return }

    for app in runningApps {
        let processID = app.processIdentifier
        if !app.terminate() {
            app.forceTerminate()
        }
        if !app.isTerminated {
            _ = kill(processID, SIGKILL)
        }
    }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let stillRunning = NSWorkspace.shared.runningApplications.contains { app in
            UITestAppTarget.allCases.contains { target in
                if app.bundleIdentifier == target.bundleIdentifier {
                    return !app.isTerminated
                }
                if let executablePath = app.executableURL?.path,
                   executablePath.hasSuffix(target.executableSuffix) {
                    return !app.isTerminated
                }
                return false
            }
        }
        if !stillRunning {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
        guard
            UITestAppTarget.allCases.contains(where: { target in
                app.bundleIdentifier == target.bundleIdentifier ||
                (app.executableURL?.path.hasSuffix(target.executableSuffix) ?? false)
            })
        else { continue }
        let processID = app.processIdentifier
        app.forceTerminate()
        _ = kill(processID, SIGKILL)
    }
#endif
}

func searchField(in app: XCUIApplication) -> XCUIElement {
    app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Search files")).firstMatch
}

func newTerminalTabButton(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "terminal.tab.add", "New Terminal Tab")).firstMatch
}

func closeTerminalTabButtons(in app: XCUIApplication) -> XCUIElementQuery {
    app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "terminal.tab.close", "Close Terminal Tab"))
}

func terminalTabs(in app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "terminal.tab")
}

func visibleTerminalTabCount(in app: XCUIApplication) -> Int {
    terminalTabs(in: app)
        .allElementsBoundByIndex
        .filter { $0.exists }
        .count
}

func visibleTerminalCloseButtonCount(in app: XCUIApplication) -> Int {
    closeTerminalTabButtons(in: app)
        .allElementsBoundByIndex
        // `isHittable` is flaky in macOS UI tests for toolbar/tab controls; use existence for stable counts.
        .filter { $0.exists }
        .count
}

@discardableResult
func openTerminalOnlyVibeSpaceView(
    in app: XCUIApplication,
    timeout: TimeInterval = 10
) -> Bool {
    let terminalOnlyCanvas = identifiedElement(in: app, identifier: "vibespace.terminal-only")
    app.typeKey("t", modifierFlags: [.command])
    if waitForVisibleElement(terminalOnlyCanvas, timeout: timeout) {
        return true
    }

    let vibespaceViewPicker = identifiedElement(
        in: app,
        identifier: "toolbar.vibespace-view"
    )
    guard vibespaceViewPicker.waitForExistence(timeout: timeout) else {
        return false
    }
    vibespaceViewPicker.tap()
    return waitForVisibleElement(terminalOnlyCanvas, timeout: timeout)
}

@discardableResult
func openDetailedVibeSpaceView(
    in app: XCUIApplication,
    timeout: TimeInterval = 10
) -> Bool {
    let detailedSidebar = identifiedElement(in: app, identifier: "vibespace.sidebar.files")
    app.typeKey("d", modifierFlags: [.command])
    if waitForVisibleElement(detailedSidebar, timeout: min(timeout, 1.5)) {
        return true
    }

    let vibespaceViewPicker = identifiedElement(
        in: app,
        identifier: "toolbar.vibespace-view"
    )
    guard vibespaceViewPicker.waitForExistence(timeout: timeout) else {
        return false
    }
    vibespaceViewPicker.tap()
    return waitForVisibleElement(detailedSidebar, timeout: timeout)
}

@discardableResult
func addTerminalTabWithRetry(
    in app: XCUIApplication,
    expectedMinimumCount: Int,
    attempts: Int = 3
) -> Bool {
    let addButton = newTerminalTabButton(in: app)
    for _ in 0..<attempts {
        app.activate()
        guard addButton.waitForExistence(timeout: 3) else { continue }
        if addButton.isHittable {
            addButton.tap()
        } else {
            addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        if waitForCondition(timeout: 3, condition: {
            visibleTerminalTabCount(in: app) >= expectedMinimumCount
        }) {
            return true
        }
    }

    return visibleTerminalTabCount(in: app) >= expectedMinimumCount
}

func projectSpecificFile(in app: XCUIApplication, index: Int) -> XCUIElement {
    app.staticTexts["project-\(index)-marker.txt"].firstMatch
}

func identifiedElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

func waitForVisibleElement(
    _ element: XCUIElement,
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.1
) -> Bool {
    if element.waitForExistence(timeout: timeout) && element.isHittable {
        return true
    }

    return waitForCondition(timeout: timeout, pollInterval: pollInterval) {
        element.exists && !element.frame.isEmpty && element.isHittable
    }
}

func elementByIdentifierOrLabel(
    in app: XCUIApplication,
    identifier: String,
    label: String,
    timeout: TimeInterval = 2
) -> XCUIElement {
    let identified = identifiedElement(in: app, identifier: identifier)
    if identified.waitForExistence(timeout: timeout) {
        return identified
    }
    return app.buttons[label].firstMatch
}

func waitForFocusedProjectShell(
    in app: XCUIApplication,
    index: Int,
    timeout: TimeInterval
) -> Bool {
    waitForCondition(timeout: timeout) {
        identifiedElement(in: app, identifier: "project.focused").exists &&
        projectSpecificFile(in: app, index: index).exists
    }
}

func waitForFocusedTerminalReady(
    in app: XCUIApplication,
    timeout: TimeInterval
) -> Bool {
    waitForCondition(timeout: timeout) {
        let readyTerminalHost = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND value == %@",
                "terminal.focused.host",
                "ready"
            )
        )
        return readyTerminalHost.count > 0
    }
}

@discardableResult
func focusProjectViaRailCard(
    in app: XCUIApplication,
    index: Int,
    timeout: TimeInterval = 2
) -> Bool {
    let targetTitle = "project-\(index)"
    let railCardQuery = app.descendants(matching: .any).matching(
        NSPredicate(
            format: "identifier == %@ AND label == %@",
            "project.stacked.card",
            targetTitle
        )
    )
    let railTitleQuery = app.descendants(matching: .any).matching(
        NSPredicate(
            format: "identifier == %@ AND label == %@",
            "project.stacked.title",
            targetTitle
        )
    )

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let cards = railCardQuery.allElementsBoundByIndex.filter {
            $0.exists && !$0.frame.isEmpty
        }
        let titles = railTitleQuery.allElementsBoundByIndex.filter {
            $0.exists && !$0.frame.isEmpty
        }

        if let hittableCard = cards.first(where: \.isHittable) {
            hittableCard.tap()
        } else if let card = cards.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) {
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else if let hittableTitle = titles.first(where: \.isHittable) {
            hittableTitle.tap()
        } else if let title = titles.first {
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            _ = railCardQuery.firstMatch.waitForExistence(timeout: 0.2)
            _ = railTitleQuery.firstMatch.waitForExistence(timeout: 0.2)
            continue
        }

        if waitForFocusedProjectShell(in: app, index: index, timeout: 1.2) {
            return true
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    }
    return waitForFocusedProjectShell(in: app, index: index, timeout: 0.6)
}

func waitForFocusedTerminalText(
    in app: XCUIApplication,
    timeout: TimeInterval
) -> Bool {
    #if os(macOS)
    waitForCondition(timeout: timeout) {
        focusedTerminalTextProbe(in: app).success
    }
    #else
    false
    #endif
}

func focusedTerminalTextDebugReport(in app: XCUIApplication) -> String {
    #if os(macOS)
    focusedTerminalTextProbe(in: app).summary
    #else
    "terminal text probing is unavailable on this platform"
    #endif
}

func waitForAllStackedTerminalText(
    in app: XCUIApplication,
    expectedMinimumCount: Int,
    timeout: TimeInterval
) -> Bool {
    #if os(macOS)
    waitForCondition(timeout: timeout, pollInterval: 0.25) {
        stackedTerminalTextProbe(
            in: app,
            expectedMinimumCount: expectedMinimumCount,
            requireAllHostsToRenderText: true
        ).success
    }
    #else
    false
    #endif
}

func waitForAnyStackedTerminalText(
    in app: XCUIApplication,
    expectedMinimumCount: Int,
    timeout: TimeInterval
) -> Bool {
    #if os(macOS)
    waitForCondition(timeout: timeout, pollInterval: 0.25) {
        stackedTerminalTextProbe(
            in: app,
            expectedMinimumCount: expectedMinimumCount,
            requireAllHostsToRenderText: false
        ).success
    }
    #else
    false
    #endif
}

func stackedTerminalTextDebugReport(
    in app: XCUIApplication,
    expectedMinimumCount: Int
) -> String {
    #if os(macOS)
    stackedTerminalTextProbe(
        in: app,
        expectedMinimumCount: expectedMinimumCount,
        requireAllHostsToRenderText: true
    ).summary
    #else
    "terminal text probing is unavailable on this platform"
    #endif
}

func stackedTerminalAnyTextDebugReport(
    in app: XCUIApplication,
    expectedMinimumCount: Int
) -> String {
    #if os(macOS)
    stackedTerminalTextProbe(
        in: app,
        expectedMinimumCount: expectedMinimumCount,
        requireAllHostsToRenderText: false
    ).summary
    #else
    "terminal text probing is unavailable on this platform"
    #endif
}

#if os(macOS)
private struct TerminalInkMetrics {
    let inkPixels: Int
    let edgePixels: Int
    let totalPixels: Int

    var ratio: Double {
        guard totalPixels > 0 else { return 0 }
        return Double(inkPixels) / Double(totalPixels)
    }
}

private struct TerminalHostTextProbe {
    let identifier: String
    let frame: CGRect
    let inkPixels: Int
    let edgePixels: Int
    let totalPixels: Int
    let inkThreshold: Int
    let edgeThreshold: Int
    let hasText: Bool
    let failureReason: String?

    var ratio: Double {
        guard totalPixels > 0 else { return 0 }
        return Double(inkPixels) / Double(totalPixels)
    }

    func summary(index: Int) -> String {
        let frameDescription = String(
            format: "(%.1f,%.1f %.1fx%.1f)",
            frame.minX,
            frame.minY,
            frame.width,
            frame.height
        )
        let ratioDescription = String(format: "%.4f", ratio)
        let reason = failureReason ?? "none"
        return "#\(index) id=\(identifier) text=\(hasText) ink=\(inkPixels)/\(totalPixels) edges=\(edgePixels) ratio=\(ratioDescription) inkThreshold=\(inkThreshold) edgeThreshold=\(edgeThreshold) frame=\(frameDescription) reason=\(reason)"
    }
}

private struct TerminalTextProbeReport {
    let queriedCount: Int
    let expectedMinimumCount: Int
    let requireAllHostsToRenderText: Bool
    let hostProbes: [TerminalHostTextProbe]

    var visibleCount: Int {
        hostProbes.count
    }

    var renderedCount: Int {
        hostProbes.filter(\.hasText).count
    }

    var hasMinimumHosts: Bool {
        visibleCount >= expectedMinimumCount
    }

    var success: Bool {
        guard hasMinimumHosts else { return false }
        if requireAllHostsToRenderText {
            return renderedCount == visibleCount && renderedCount >= expectedMinimumCount
        }
        return renderedCount > 0
    }

    var summary: String {
        let hostSummary = hostProbes.enumerated().map { index, probe in
            probe.summary(index: index)
        }.joined(separator: "; ")
        return "queried=\(queriedCount) visible=\(visibleCount) expected>=\(expectedMinimumCount) rendered=\(renderedCount) requireAll=\(requireAllHostsToRenderText) hosts=[\(hostSummary)]"
    }
}

private enum TerminalProbeRegion {
    case fullInterior
    case lowerViewport
}

private func focusedTerminalTextProbe(in app: XCUIApplication) -> TerminalTextProbeReport {
    let focusedHostQuery = app.descendants(matching: .any).matching(identifier: "terminal.focused.host")
    let focusedHosts = focusedHostQuery
        .allElementsBoundByIndex
        .filter { $0.exists }
    return terminalTextProbe(
        from: focusedHosts,
        queriedCount: focusedHostQuery.count,
        expectedMinimumCount: 1,
        requireAllHostsToRenderText: false,
        region: .fullInterior
    )
}

private func stackedTerminalTextProbe(
    in app: XCUIApplication,
    expectedMinimumCount: Int,
    requireAllHostsToRenderText: Bool
) -> TerminalTextProbeReport {
    let stackedCardQuery = app.descendants(matching: .any).matching(identifier: "project.stacked.card")
    let queriedCount = stackedCardQuery.count
    guard queriedCount >= expectedMinimumCount else {
        return TerminalTextProbeReport(
            queriedCount: queriedCount,
            expectedMinimumCount: expectedMinimumCount,
            requireAllHostsToRenderText: requireAllHostsToRenderText,
            hostProbes: []
        )
    }

    let stackedCards = stackedCardQuery
        .allElementsBoundByIndex
        .filter {
            $0.exists &&
            !$0.frame.isEmpty &&
            $0.frame.width >= 120 &&
            $0.frame.height >= 80
        }
        .sorted { lhs, rhs in
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            if abs(lhsArea - rhsArea) > 1 {
                return lhsArea > rhsArea
            }
            if abs(lhs.frame.minY - rhs.frame.minY) < 0.5 {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }
    let cardsToProbe = Array(stackedCards.prefix(expectedMinimumCount))

    return terminalTextProbe(
        from: cardsToProbe,
        queriedCount: queriedCount,
        expectedMinimumCount: expectedMinimumCount,
        requireAllHostsToRenderText: requireAllHostsToRenderText,
        region: .lowerViewport
    )
}

private func terminalTextProbe(
    from hosts: [XCUIElement],
    queriedCount: Int,
    expectedMinimumCount: Int,
    requireAllHostsToRenderText: Bool,
    region: TerminalProbeRegion
) -> TerminalTextProbeReport {
    let filteredHosts = hosts
        .filter { !$0.frame.isEmpty && $0.frame.width > 1 && $0.frame.height > 1 }
        .sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) < 0.5 {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }

    let hostProbes = filteredHosts.enumerated().map { _, host in
        terminalHostTextProbe(for: host, region: region)
    }

    return TerminalTextProbeReport(
        queriedCount: queriedCount,
        expectedMinimumCount: expectedMinimumCount,
        requireAllHostsToRenderText: requireAllHostsToRenderText,
        hostProbes: hostProbes
    )
}

private func terminalHostTextProbe(
    for host: XCUIElement,
    region: TerminalProbeRegion
) -> TerminalHostTextProbe {
    let identifier = host.identifier.isEmpty ? "unknown" : host.identifier
    guard host.exists else {
        return TerminalHostTextProbe(
            identifier: identifier,
            frame: host.frame,
            inkPixels: 0,
            edgePixels: 0,
            totalPixels: 0,
            inkThreshold: 0,
            edgeThreshold: 0,
            hasText: false,
            failureReason: "host-missing"
        )
    }
    let hostScreenshot = host.screenshot()
    guard let hostImage = cgImage(from: hostScreenshot.pngRepresentation) else {
        return TerminalHostTextProbe(
            identifier: identifier,
            frame: host.frame,
            inkPixels: 0,
            edgePixels: 0,
            totalPixels: 0,
            inkThreshold: 0,
            edgeThreshold: 0,
            hasText: false,
            failureReason: "host-screenshot-unavailable"
        )
    }

    guard let croppedImage = cropProbeRegion(from: hostImage, region: region) else {
        return TerminalHostTextProbe(
            identifier: identifier,
            frame: host.frame,
            inkPixels: 0,
            edgePixels: 0,
            totalPixels: 0,
            inkThreshold: 0,
            edgeThreshold: 0,
            hasText: false,
            failureReason: "interior-crop-failed"
        )
    }

    guard let metrics = terminalInkMetrics(for: croppedImage) else {
        return TerminalHostTextProbe(
            identifier: identifier,
            frame: host.frame,
            inkPixels: 0,
            edgePixels: 0,
            totalPixels: 0,
            inkThreshold: 0,
            edgeThreshold: 0,
            hasText: false,
            failureReason: "ink-metrics-failed"
        )
    }

    let inkRatioThreshold = 0.0009
    let edgeRatioThreshold = 0.0006
    let inkThreshold = max(550, Int(Double(metrics.totalPixels) * inkRatioThreshold))
    let edgeThreshold = max(420, Int(Double(metrics.totalPixels) * edgeRatioThreshold))
    let hasText = metrics.inkPixels >= inkThreshold && metrics.edgePixels >= edgeThreshold

    return TerminalHostTextProbe(
        identifier: identifier,
        frame: host.frame,
        inkPixels: metrics.inkPixels,
        edgePixels: metrics.edgePixels,
        totalPixels: metrics.totalPixels,
        inkThreshold: inkThreshold,
        edgeThreshold: edgeThreshold,
        hasText: hasText,
        failureReason: hasText ? nil : "ink-or-edge-below-threshold"
    )
}

private func cropProbeRegion(
    from image: CGImage,
    region: TerminalProbeRegion
) -> CGImage? {
    guard let interior = cropInterior(from: image) else { return nil }
    switch region {
    case .fullInterior:
        return interior
    case .lowerViewport:
        let width = interior.width
        let height = interior.height
        guard width > 4, height > 4 else { return interior }
        let topInset = Int(Double(height) * 0.28)
        let cropHeight = max(1, height - topInset)
        let cropRect = CGRect(
            x: 0,
            y: topInset,
            width: width,
            height: cropHeight
        )
        return interior.cropping(to: cropRect)
    }
}

private func cgImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func cropInterior(from image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    guard width > 8, height > 8 else { return image }

    let insetX = max(2, Int(Double(width) * 0.04))
    let insetY = max(2, Int(Double(height) * 0.03))
    let croppedWidth = max(1, width - (insetX * 2))
    let croppedHeight = max(1, height - (insetY * 2))
    let cropRect = CGRect(
        x: insetX,
        y: insetY,
        width: croppedWidth,
        height: croppedHeight
    )
    return image.cropping(to: cropRect)
}

private func terminalInkMetrics(for image: CGImage) -> TerminalInkMetrics? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    var luminances = [UInt8](repeating: 0, count: width * height)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var luminanceHistogram = [Int](repeating: 0, count: 256)
    var totalPixels = 0
    for pixelIndex in 0..<(width * height) {
        let index = pixelIndex * 4
        let alpha = Int(pixels[index + 3])
        guard alpha > 0 else { continue }
        let red = Int(pixels[index])
        let green = Int(pixels[index + 1])
        let blue = Int(pixels[index + 2])
        let luminance = (299 * red + 587 * green + 114 * blue) / 1000
        luminances[pixelIndex] = UInt8(clamping: luminance)
        luminanceHistogram[luminance] += 1
        totalPixels += 1
    }

    guard totalPixels > 0 else {
        return TerminalInkMetrics(inkPixels: 0, edgePixels: 0, totalPixels: 0)
    }

    let dominantLuminance = luminanceHistogram
        .enumerated()
        .max(by: { $0.element < $1.element })?
        .offset ?? 0

    var inkPixels = 0
    var edgePixels = 0
    for pixelIndex in 0..<(width * height) {
        let index = pixelIndex * 4
        let alpha = Int(pixels[index + 3])
        guard alpha > 0 else { continue }

        let red = Int(pixels[index])
        let green = Int(pixels[index + 1])
        let blue = Int(pixels[index + 2])
        let luminance = (299 * red + 587 * green + 114 * blue) / 1000
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let chroma = maxChannel - minChannel
        let highContrast = (luminance - dominantLuminance) >= 24
        let coloredInk = chroma >= 22 && maxChannel >= max(16, dominantLuminance + 8)

        if highContrast || coloredInk {
            inkPixels += 1
        }

        let x = pixelIndex % width
        let y = pixelIndex / width
        if x > 0 {
            let left = Int(luminances[pixelIndex - 1])
            if abs(luminance - left) >= 30 {
                edgePixels += 1
            }
        }
        if y > 0 {
            let top = Int(luminances[pixelIndex - width])
            if abs(luminance - top) >= 30 {
                edgePixels += 1
            }
        }
    }

    return TerminalInkMetrics(
        inkPixels: inkPixels,
        edgePixels: edgePixels,
        totalPixels: totalPixels
    )
}
#endif

func waitForAnyExplorerGitState(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
    waitForCondition(timeout: timeout) {
        [
            "explorer.git.state.loading",
            "explorer.git.state.clean",
            "explorer.git.state.not-repo",
            "explorer.git.state.unavailable",
            "explorer.git.state.error"
        ].contains { identifiedElement(in: app, identifier: $0).exists }
    }
}

func waitForCondition(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.1,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
    }
    return condition()
}
