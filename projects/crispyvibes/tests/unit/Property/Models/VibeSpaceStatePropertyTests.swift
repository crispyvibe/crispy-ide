import XCTest
@testable import CrispyVibes

@MainActor
final class VibeSpaceStatePropertyTests: XCTestCase {
    private var container: AppContainer!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = try makeTempDirectory(prefix: "crispyvibes-vibespace-prop")
        container = AppContainer.makeDefault()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        container = nil
    }

    func testSnapshotRoundTripPreservesProjectAndUnresolvedSetsAcrossRandomizedInputs() throws {
        for iteration in 0..<75 {
            let existingCount = Int.random(in: 1...5)
            let missingCount = Int.random(in: 0...4)

            var inputURLs: [URL] = []
            for index in 0..<existingCount {
                let url = tempRoot.appendingPathComponent("existing-\(iteration)-\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                inputURLs.append(url)
                if Bool.random() { inputURLs.append(url) }
            }

            for index in 0..<missingCount {
                let url = tempRoot.appendingPathComponent("missing-\(iteration)-\(index)", isDirectory: true)
                inputURLs.append(url)
                if Bool.random() { inputURLs.append(url) }
            }

            var vibespace = container.makeVibeSpaceState(name: "Prop \(iteration)", projectURLs: inputURLs)
            if let first = vibespace.projects.first {
                vibespace.focusedProjectID = first.id
                vibespace.setColorTag(ProjectColorTag(red: 0.4, green: 0.7, blue: 0.2), for: first.id)
            }

            let config = vibespace.configFile
            let restored = container.makeVibeSpaceState(config: config)

            let originalProjectPaths = Set(vibespace.projects.map { $0.rootURL.standardizedFileURL.path })
            let restoredProjectPaths = Set(restored.projects.map { $0.rootURL.standardizedFileURL.path })
            XCTAssertEqual(restoredProjectPaths, originalProjectPaths)
            XCTAssertEqual(Set(restored.unresolvedProjectPaths), Set(vibespace.unresolvedProjectPaths))
            XCTAssertEqual(restored.focusedProjectID == nil, vibespace.focusedProjectID == nil)
        }
    }

    func testProjectShortcutAssignmentsRemainUniqueUnderRandomMutations() throws {
        let projectURLs: [URL] = (0..<6).map { index in
            let url = tempRoot.appendingPathComponent("proj-\(index)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        var vibespace = container.makeVibeSpaceState(name: "Shortcuts", projectURLs: projectURLs)

        for _ in 0..<120 {
            guard let randomProject = vibespace.projects.randomElement() else {
                XCTFail("VibeSpace unexpectedly has no projects")
                return
            }
            let randomSlot = Int.random(in: 1...9)
            vibespace.setShortcut(randomSlot, forProjectPath: randomProject.rootURL.path)

            let assignedShortcuts = vibespace.projects.compactMap { vibespace.shortcutIndex(for: $0) }
            XCTAssertEqual(Set(assignedShortcuts).count, assignedShortcuts.count)
            XCTAssertTrue(assignedShortcuts.allSatisfy { (1...9).contains($0) })
        }
    }

    func testNormalizedPathIsIdempotentAcrossRandomizedInputs() {
        for iteration in 0..<220 {
            let segmentCount = Int.random(in: 1...5)
            let segments = (0..<segmentCount).map { index in
                "segment-\(iteration)-\(index)-\(Int.random(in: 0...9999))"
            }
            let basePath = "/" + segments.joined(separator: "/")
            let escapedPath = Bool.random()
                ? basePath.replacingOccurrences(of: "/", with: "\\/")
                : basePath

            let normalized = VibeSpaceState.normalizedPath(from: escapedPath)
            let normalizedAgain = VibeSpaceState.normalizedPath(from: normalized)

            XCTAssertEqual(normalizedAgain, normalized)
            XCTAssertFalse(normalized.contains("\\/"))
        }
    }

    func testEffectiveTerminalShellResolutionFollowsVibeSpaceThenAppDefault() throws {
        let projectURL = tempRoot.appendingPathComponent("shell-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        var vibespace = container.makeVibeSpaceState(name: "Shell Resolution", projectURLs: [projectURL])
        guard let projectPath = vibespace.projects.first?.rootURL.path else {
            XCTFail("Expected seeded project path")
            return
        }

        for _ in 0..<200 {
            let appDefault = Bool.random() ? TerminalShellPreference.zsh : TerminalShellPreference.bash
            let vibespaceDefault = Bool.random() ? TerminalShellPreference.allCases.randomElement() : nil

            vibespace.defaultTerminalShell = vibespaceDefault
            vibespace.setTerminalShellOverride(
                TerminalShellPreference.allCases.randomElement(),
                forProjectPath: projectPath
            )

            let resolved = vibespace.effectiveTerminalShell(
                for: projectPath,
                appDefault: appDefault
            )
            XCTAssertEqual(resolved, vibespaceDefault ?? appDefault)
        }
    }
}
