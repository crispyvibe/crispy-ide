import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
final class StackedRailPresentationTests: XCTestCase {
    var container: AppContainer!
    var tempRoot: URL!

    override func setUpWithError() throws {
        container = AppContainer.makeDefault()
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-stacked-rail")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testPresentationGroupsVisibleTerminalsByProjectInVibeSpaceOrder() throws {
        let projectAURL = tempRoot.appendingPathComponent("project-a", isDirectory: true)
        let projectBURL = tempRoot.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: projectAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectBURL, withIntermediateDirectories: true)

        let projectA = container.makeProjectSession(rootURL: projectAURL, vibespaceID: nil)
        let projectB = container.makeProjectSession(rootURL: projectBURL, vibespaceID: nil)
        projectA.activateIfNeeded()
        projectB.activateIfNeeded()
        projectA.terminal.createTab(directoryURL: projectAURL, startImmediately: false)
        projectA.terminal.createTab(directoryURL: projectAURL, startImmediately: false)
        projectB.terminal.createTab(directoryURL: projectBURL, startImmediately: false)

        let store = StackedRailTerminalStore()
        store.syncProjects([projectA, projectB])

        let presentation = StackedRailPresentation(
            projects: [projectA, projectB],
            stackedRailStore: store,
            hiddenTerminalIDsByProjectPath: [:]
        )

        XCTAssertEqual(
            presentation.visibleGroups.map(\.projectPath),
            [projectAURL.standardizedFileURL.path, projectBURL.standardizedFileURL.path]
        )
        XCTAssertEqual(presentation.visibleGroups.map { $0.orderedVisibleEntries.count }, [3, 2])
    }

    func testOrderedTabsPreferActiveTerminalThenSelectedFallbackWithinProject() throws {
        let projectURL = tempRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let project = container.makeProjectSession(rootURL: projectURL, vibespaceID: nil)
        project.activateIfNeeded()
        project.terminal.createTab(directoryURL: projectURL, startImmediately: false)
        project.terminal.createTab(directoryURL: projectURL, startImmediately: false)
        project.terminal.createTab(directoryURL: projectURL, startImmediately: false)

        let tabs = project.terminal.tabs
        XCTAssertEqual(tabs.count, 4)

        project.terminal.selectTab(tabs[1])

        let store = StackedRailTerminalStore()
        store.syncProjects([project])

        let selectedFirst = store.orderedTabs(
            for: projectURL.standardizedFileURL.path,
            tabs: project.terminal.tabs,
            terminalProvider: project.terminal
        )
        XCTAssertEqual(selectedFirst.first?.id, tabs[1].id)

        project.terminalViewModel.setTabActivity(tabID: tabs[0].id, isActive: true)

        let activeFirst = store.orderedTabs(
            for: projectURL.standardizedFileURL.path,
            tabs: project.terminal.tabs,
            terminalProvider: project.terminal
        )
        XCTAssertEqual(activeFirst.first?.id, tabs[0].id)
    }
}
