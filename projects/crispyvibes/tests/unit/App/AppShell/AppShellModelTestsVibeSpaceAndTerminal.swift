import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
extension AppShellModelTests {
    func testProjectRailPositionMetadata() {
        XCTAssertFalse(ProjectRailPosition.left.isHorizontalRail)
        XCTAssertFalse(ProjectRailPosition.right.isHorizontalRail)
        XCTAssertTrue(ProjectRailPosition.top.isHorizontalRail)
        XCTAssertTrue(ProjectRailPosition.bottom.isHorizontalRail)
        XCTAssertEqual(ProjectRailPosition.left.title, "Left")
        XCTAssertEqual(ProjectRailPosition.right.symbolName, "sidebar.right")
    }

    /// Guards that rail position is a single app-wide preference stored under
    /// ``AppPreferences/defaultRailPositionKey`` as the ``ProjectRailPosition``
    /// raw value. Any regression that changes the key, storage format, or
    /// re-introduces per-vibespace rail position will break this test.
    func testDefaultRailPositionIsGlobalUserDefaultsPreference() {
        let defaults = UserDefaults(suiteName: "crispyvibes.test.defaultRailPosition")!
        defer {
            defaults.removePersistentDomain(forName: "crispyvibes.test.defaultRailPosition")
        }
        XCTAssertEqual(AppPreferences.defaultRailPositionKey, "defaultRailPosition")
        XCTAssertEqual(
            AppPreferences.defaultRailPositionRawValue,
            AppFirstRunExperience.Layout.defaultRailPosition.rawValue
        )

        defaults.set(ProjectRailPosition.right.rawValue, forKey: AppPreferences.defaultRailPositionKey)
        XCTAssertEqual(
            ProjectRailPosition(rawValue: defaults.string(forKey: AppPreferences.defaultRailPositionKey) ?? ""),
            .right
        )
    }

    func testVibeSpaceCanvasModeMetadata() {
        XCTAssertEqual(VibeSpaceCanvasMode.detailed.title, "Detailed")
        XCTAssertEqual(VibeSpaceCanvasMode.detailed.symbolName, "square.split.2x1")
        XCTAssertEqual(VibeSpaceCanvasMode.terminalOnly.title, "Terminal Board")
        XCTAssertEqual(VibeSpaceCanvasMode.terminalOnly.symbolName, "square.grid.2x2")
    }

    func testVibeSpaceTerminalOnlyLayoutOrientationMetadata() {
        XCTAssertEqual(VibeSpaceTerminalOnlyLayoutOrientation.vertical.title, "Vertical")
        XCTAssertEqual(
            VibeSpaceTerminalOnlyLayoutOrientation.vertical.symbolName,
            "square.split.2x1"
        )
        XCTAssertEqual(VibeSpaceTerminalOnlyLayoutOrientation.horizontal.title, "Horizontal")
        XCTAssertEqual(
            VibeSpaceTerminalOnlyLayoutOrientation.horizontal.symbolName,
            "square.split.1x2"
        )
    }

    func testTerminalTraversalAdjacentTargetCrossesProjectBoundaries() {
        let project1 = UUID()
        let project2 = UUID()
        let tab1 = UUID()
        let tab2 = UUID()
        let tab3 = UUID()

        let snapshots = [
            TerminalTraversalProjectSnapshot(
                projectID: project1,
                tabIDs: [tab1, tab2],
                activeTabID: tab2
            ),
            TerminalTraversalProjectSnapshot(
                projectID: project2,
                tabIDs: [tab3],
                activeTabID: tab3
            )
        ]

        XCTAssertEqual(
            TerminalTraversal.adjacentTarget(
                in: snapshots,
                focusedProjectID: project1,
                offset: 1
            ),
            TerminalTraversalTarget(projectID: project2, tabID: tab3)
        )
        XCTAssertEqual(
            TerminalTraversal.adjacentTarget(
                in: snapshots,
                focusedProjectID: project2,
                offset: 1
            ),
            TerminalTraversalTarget(projectID: project1, tabID: tab1)
        )
    }

    func testTerminalTraversalFallsBackToFirstFocusedTabWhenActiveTabMissing() {
        let project1 = UUID()
        let project2 = UUID()
        let tab1 = UUID()
        let tab2 = UUID()
        let tab3 = UUID()

        let snapshots = [
            TerminalTraversalProjectSnapshot(
                projectID: project1,
                tabIDs: [tab1, tab2],
                activeTabID: nil
            ),
            TerminalTraversalProjectSnapshot(
                projectID: project2,
                tabIDs: [tab3],
                activeTabID: tab3
            )
        ]

        XCTAssertEqual(
            TerminalTraversal.adjacentTarget(
                in: snapshots,
                focusedProjectID: project1,
                offset: 1
            ),
            TerminalTraversalTarget(projectID: project1, tabID: tab2)
        )
        XCTAssertEqual(
            TerminalTraversal.adjacentTarget(
                in: snapshots,
                focusedProjectID: project1,
                offset: -1
            ),
            TerminalTraversalTarget(projectID: project2, tabID: tab3)
        )
    }

    func testTerminalTraversalReturnsNilForZeroOffsetAndEmptyTabs() {
        let project1 = UUID()
        let tab1 = UUID()

        let withTabs = [
            TerminalTraversalProjectSnapshot(
                projectID: project1,
                tabIDs: [tab1],
                activeTabID: tab1
            )
        ]
        XCTAssertNil(
            TerminalTraversal.adjacentTarget(
                in: withTabs,
                focusedProjectID: project1,
                offset: 0
            )
        )

        let empty: [TerminalTraversalProjectSnapshot] = [
            TerminalTraversalProjectSnapshot(projectID: project1, tabIDs: [], activeTabID: nil)
        ]
        XCTAssertNil(
            TerminalTraversal.adjacentTarget(
                in: empty,
                focusedProjectID: project1,
                offset: 1
            )
        )
    }

    func testProjectColorTagRoundTripFromHexToken() {
        let tag = ProjectColorTag(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
        let token = tag.storageToken
        let decoded = ProjectColorTag(storageToken: token)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.red ?? 0, tag.red, accuracy: 0.01)
        XCTAssertEqual(decoded?.green ?? 0, tag.green, accuracy: 0.01)
        XCTAssertEqual(decoded?.blue ?? 0, tag.blue, accuracy: 0.01)
        XCTAssertEqual(decoded?.alpha ?? 0, tag.alpha, accuracy: 0.01)
        XCTAssertNil(ProjectColorTag(storageToken: "not-a-color-token"))
    }

    func testProjectColorTagClampsRanges() {
        let tag = ProjectColorTag(red: -2.0, green: 1.8, blue: 0.5, alpha: 4.2)
        XCTAssertEqual(tag.red, 0)
        XCTAssertEqual(tag.green, 1)
        XCTAssertEqual(tag.blue, 0.5)
        XCTAssertEqual(tag.alpha, 1)
    }

    func testGlobalClampedHelper() {
        XCTAssertEqual(clamped(9, min: 2, max: 7), 7)
        XCTAssertEqual(clamped(-1, min: 2, max: 7), 2)
        XCTAssertEqual(clamped(4, min: 2, max: 7), 4)
    }

    func testVibeSpaceStartupSettingsNormalization() {
        let raw = VibeSpaceStartupSettings(
            startupTerminalCount: 99,
            startupProfiles: [
                VibeSpaceTerminalStartupProfile(
                    presetID: "  KIRO  ",
                    command: "  codex --approval-mode auto  "
                )
            ],
            focusTerminalOnProjectSwitch: false
        )
        let normalized = raw.normalized()
        XCTAssertEqual(normalized.startupTerminalCount, VibeSpaceStartupSettings.maximumTerminalCount)
        XCTAssertEqual(normalized.startupProfiles.count, VibeSpaceStartupSettings.maximumTerminalCount)
        XCTAssertNil(normalized.startupProfiles[0].presetID)
        XCTAssertEqual(normalized.startupProfiles[0].command, "codex --approval-mode auto")
        XCTAssertFalse(normalized.focusTerminalOnProjectSwitch)
    }

    func testVibeSpaceStartupSettingsDefaultValues() {
        let defaults = VibeSpaceStartupSettings.default
        XCTAssertEqual(defaults.startupTerminalCount, 1)
        XCTAssertEqual(defaults.startupProfiles, [.empty])
        XCTAssertTrue(defaults.focusTerminalOnProjectSwitch)
    }

    func testVibeSpaceStartupSettingsPerTerminalProfilesRoundTrip() throws {
        let raw = VibeSpaceStartupSettings(
            startupTerminalCount: 2,
            startupProfiles: [
                VibeSpaceTerminalStartupProfile(presetID: "  CLAUDE  ", command: ""),
                VibeSpaceTerminalStartupProfile(presetID: nil, command: " npm run dev ")
            ],
            focusTerminalOnProjectSwitch: false
        )

        let normalized = raw.normalized()
        XCTAssertEqual(normalized.startupTerminalCount, 2)
        XCTAssertEqual(normalized.profile(at: 0).presetID, "claude")
        XCTAssertTrue(normalized.profile(at: 0).command.isEmpty)
        XCTAssertNil(normalized.profile(at: 1).presetID)
        XCTAssertEqual(normalized.profile(at: 1).command, "npm run dev")
        XCTAssertEqual(normalized.activeProfiles.count, 2)
    }

    func testVibeSpaceStartupSettingsDecodeWithoutProfilesUsesDefaults() throws {
        let json = """
        {
          "startupTerminalCount": 2,
          "focusTerminalOnProjectSwitch": true
        }
        """
        let decoded = try JSONDecoder().decode(
            VibeSpaceStartupSettings.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.startupTerminalCount, 2)
        XCTAssertNil(decoded.profile(at: 0).presetID)
        XCTAssertTrue(decoded.profile(at: 0).command.isEmpty)
        XCTAssertEqual(decoded.activeProfiles.count, 2)
        XCTAssertEqual(decoded.activeProfiles[1], .empty)
    }

    func testVibeSpaceProjectStartupOverrideNormalization() {
        let raw = VibeSpaceProjectStartupOverride(
            startupTerminalCount: 2,
            startupProfiles: [
                VibeSpaceTerminalStartupProfile(
                    presetID: "  CODEX  ",
                    command: "  codex --approval-mode yolo  "
                )
            ]
        )
        let normalized = raw.normalized()

        XCTAssertEqual(normalized.startupTerminalCount, 2)
        XCTAssertNil(normalized.profile(at: 0).presetID)
        XCTAssertEqual(normalized.profile(at: 0).command, "codex --approval-mode yolo")
        XCTAssertEqual(normalized.profile(at: 1), .empty)
        XCTAssertTrue(normalized.hasAnyInstruction)

        let empty = VibeSpaceProjectStartupOverride.empty.normalized()
        XCTAssertEqual(empty.startupTerminalCount, 1)
        XCTAssertNil(empty.startupPresetID)
        XCTAssertTrue(empty.startupCommand.isEmpty)
        XCTAssertFalse(empty.hasAnyInstruction)
    }

    func testVibeSpaceProjectStartupOverrideLegacyDecodingSeedsFirstTerminal() throws {
        let json = """
        {
          "startupPresetID": "claude",
          "startupCommand": ""
        }
        """
        let decoded = try JSONDecoder().decode(
            VibeSpaceProjectStartupOverride.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.startupTerminalCount, 1)
        XCTAssertEqual(decoded.profile(at: 0).presetID, "claude")
        XCTAssertTrue(decoded.profile(at: 0).command.isEmpty)
    }

    func testVibeSpaceProjectStartupOverrideTracksMultipleTerminalProfiles() {
        var startupOverride = VibeSpaceProjectStartupOverride.empty
        startupOverride.startupTerminalCount = 2
        startupOverride.setProfile(
            VibeSpaceTerminalStartupProfile(
                presetID: "codex",
                command: ""
            ),
            at: 0
        )
        startupOverride.setProfile(
            VibeSpaceTerminalStartupProfile(
                presetID: nil,
                command: "npm run dev"
            ),
            at: 1
        )

        let normalized = startupOverride.normalized()
        XCTAssertEqual(normalized.startupTerminalCount, 2)
        XCTAssertEqual(normalized.activeProfiles.count, 2)
        XCTAssertEqual(normalized.profile(at: 0).presetID, "codex")
        XCTAssertEqual(normalized.profile(at: 1).command, "npm run dev")
    }

    func testVibeSpaceHydrationTargetsIncludeVibeSpaceDefaultsForEveryProject() throws {
        let tempRoot = try makeTempDirectory(prefix: "crispyvibes-vibespace-hydration")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let firstProjectURL = tempRoot.appendingPathComponent("project-a", isDirectory: true)
        let secondProjectURL = tempRoot.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProjectURL, withIntermediateDirectories: true)

        var vibespace = container.makeVibeSpaceState(
            name: "Hydration",
            projectURLs: [firstProjectURL, secondProjectURL]
        )
        vibespace.focusedProjectID = vibespace.projects.last?.id
        defer { vibespace.shutdownProjects() }

        let targets = VibeSpaceHydrationUseCase().hydrationTargets(for: vibespace)

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].projectID, vibespace.projects[1].id)
        XCTAssertEqual(targets[1].projectID, vibespace.projects[0].id)
        XCTAssertTrue(targets.allSatisfy(\.includeVibeSpaceDefault))
    }

    func testInfoPlistIdentityMetadata() throws {
        let infoPlist = try loadRepositoryInfoPlist()
        XCTAssertEqual(infoPlist["CFBundleDisplayName"] as? String, "Crispy")
        XCTAssertEqual(infoPlist["CFBundleName"] as? String, "Crispy")
        XCTAssertEqual(infoPlist["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertEqual(
            infoPlist[AppPreferences.infoPlistAppUpdateFeedURLKey] as? String,
            "https://crispyvibe.com/updates/macos/dev/appcast.xml"
        )
    }
}
