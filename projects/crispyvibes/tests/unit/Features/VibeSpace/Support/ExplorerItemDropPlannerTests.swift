import Foundation
import XCTest
@testable import CrispyVibes

final class ExplorerItemDropPlannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-drop-planner")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testPlansMoveWithinSameProjectRoot() throws {
        let projectRoot = tempRoot.appendingPathComponent("project-a", isDirectory: true)
        let sourceDirectory = projectRoot.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = projectRoot.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceFile = sourceDirectory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: sourceFile)

        let plans = ExplorerItemDropPlanner.plans(
            for: [sourceFile],
            targetDirectoryURL: destinationDirectory,
            projectRootURLs: [projectRoot]
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.operation, .move)
        XCTAssertEqual(plans.first?.destinationURL.path, destinationDirectory.appendingPathComponent("notes.txt").path)
    }

    func testPlansCopyAcrossProjectBoundaries() throws {
        let projectA = tempRoot.appendingPathComponent("project-a", isDirectory: true)
        let projectB = tempRoot.appendingPathComponent("project-b", isDirectory: true)
        let sourceDirectory = projectA.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = projectB.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceFile = sourceDirectory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: sourceFile)

        let plans = ExplorerItemDropPlanner.plans(
            for: [sourceFile],
            targetDirectoryURL: destinationDirectory,
            projectRootURLs: [projectA, projectB]
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.operation, .copy)
    }

    func testPlansCopyWhenSourceIsOutsideKnownProjectRoots() throws {
        let externalDirectory = tempRoot.appendingPathComponent("external", isDirectory: true)
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let destinationDirectory = projectRoot.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceFile = externalDirectory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: sourceFile)

        let plans = ExplorerItemDropPlanner.plans(
            for: [sourceFile],
            targetDirectoryURL: destinationDirectory,
            projectRootURLs: [projectRoot]
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.operation, .copy)
    }

    func testPlansRejectMovingDirectoryIntoOwnDescendant() throws {
        let projectRoot = tempRoot.appendingPathComponent("project", isDirectory: true)
        let sourceDirectory = projectRoot.appendingPathComponent("Source", isDirectory: true)
        let nestedDestination = sourceDirectory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDestination, withIntermediateDirectories: true)

        let plans = ExplorerItemDropPlanner.plans(
            for: [sourceDirectory],
            targetDirectoryURL: nestedDestination,
            projectRootURLs: [projectRoot]
        )

        XCTAssertTrue(plans.isEmpty)
    }
}
