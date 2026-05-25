import XCTest
@testable import CrispyVibes

final class TerminalSessionRestorerTests: XCTestCase {

    private let projectRoot = URL(fileURLWithPath: "/projects/test")

    // MARK: - Empty entries fallback

    func testEmptyEntriesWithNoPresets_createsSingleAdHocTab() {
        let actions = TerminalSessionRestorer.restoreActions(
            entries: [],
            presetProfiles: [],
            projectRoot: projectRoot
        )
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].origin, .adHoc)
        XCTAssertFalse(actions[0].shouldExecuteCommand)
        XCTAssertEqual(actions[0].directory, projectRoot)
    }

    func testEmptyEntriesWithPresets_createsPresetTabs() {
        let profiles: [TerminalSessionRestorer.IndexedProfile] = [
            .init(index: 0, command: "npm start", tabName: "Dev"),
            .init(index: 1, command: "npm test", tabName: "Test"),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: [],
            presetProfiles: profiles,
            projectRoot: projectRoot
        )
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].customName, "Dev")
        XCTAssertEqual(actions[0].command, "npm start")
        XCTAssertTrue(actions[0].shouldExecuteCommand)
        XCTAssertEqual(actions[1].customName, "Test")
        XCTAssertEqual(actions[1].command, "npm test")
        XCTAssertTrue(actions[1].shouldExecuteCommand)
    }

    // MARK: - Restore from entries

    func testPresetEntries_reExecuteCommands() {
        let entries: [TerminalSessionEntry] = [
            .init(workingDirectoryPath: "/projects/test", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: [],
            projectRoot: projectRoot
        )
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].customName, "Dev")
        XCTAssertTrue(actions[0].shouldExecuteCommand)
        XCTAssertEqual(actions[0].command, "npm start")
    }

    func testAdHocEntries_restoreNameOnly() {
        let entries: [TerminalSessionEntry] = [
            .init(workingDirectoryPath: "/projects/test/src", customName: "My Shell", origin: .adHoc),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: [],
            projectRoot: projectRoot
        )
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].customName, "My Shell")
        XCTAssertFalse(actions[0].shouldExecuteCommand)
        XCTAssertNil(actions[0].command)
    }

    func testMixedEntries_correctBehavior() {
        let entries: [TerminalSessionEntry] = [
            .init(workingDirectoryPath: "/projects/test", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
            .init(workingDirectoryPath: "/projects/test/src", customName: "Shell", origin: .adHoc),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: [],
            projectRoot: projectRoot
        )
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions[0].shouldExecuteCommand)
        XCTAssertFalse(actions[1].shouldExecuteCommand)
    }

    // MARK: - TERM-004a: Removed preset recreation

    func testRemovedPresetRecreatedFromConfig() {
        // User had preset at index 0 but removed it during session.
        // Only ad-hoc tab remains. Preset at index 0 should be recreated.
        let entries: [TerminalSessionEntry] = [
            .init(workingDirectoryPath: "/projects/test/src", customName: "Shell", origin: .adHoc),
        ]
        let profiles: [TerminalSessionRestorer.IndexedProfile] = [
            .init(index: 0, command: "npm start", tabName: "Dev"),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: profiles,
            projectRoot: projectRoot
        )
        XCTAssertEqual(actions.count, 2)
        // First: restored ad-hoc
        XCTAssertEqual(actions[0].customName, "Shell")
        XCTAssertFalse(actions[0].shouldExecuteCommand)
        // Second: recreated preset
        XCTAssertEqual(actions[1].customName, "Dev")
        XCTAssertTrue(actions[1].shouldExecuteCommand)
        XCTAssertEqual(actions[1].command, "npm start")
        XCTAssertEqual(actions[1].directory, projectRoot)
    }

    func testPresetPresentInEntries_notDuplicated() {
        let entries: [TerminalSessionEntry] = [
            .init(workingDirectoryPath: "/projects/test", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
        ]
        let profiles: [TerminalSessionRestorer.IndexedProfile] = [
            .init(index: 0, command: "npm start", tabName: "Dev"),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: profiles,
            projectRoot: projectRoot
        )
        // Preset already in entries — should NOT be duplicated
        XCTAssertEqual(actions.count, 1)
    }

    func testMultiplePresetsPartiallyRemoved() {
        // Had presets 0 and 1. User removed preset 1 during session.
        let entries: [TerminalSessionEntry] = [
            .init(workingDirectoryPath: "/projects/test", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
        ]
        let profiles: [TerminalSessionRestorer.IndexedProfile] = [
            .init(index: 0, command: "npm start", tabName: "Dev"),
            .init(index: 1, command: "npm test", tabName: "Test"),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: profiles,
            projectRoot: projectRoot
        )
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0].command, "npm start")
        XCTAssertEqual(actions[1].command, "npm test")
        XCTAssertEqual(actions[1].customName, "Test")
    }

    // MARK: - TerminalOrigin Codable roundtrip

    func testPresetOriginCodableRoundtrip() throws {
        let origin = TerminalOrigin.preset(profileIndex: 2, command: "cargo build")
        let data = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(TerminalOrigin.self, from: data)
        XCTAssertEqual(decoded, origin)
    }

    func testAdHocOriginCodableRoundtrip() throws {
        let origin = TerminalOrigin.adHoc
        let data = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(TerminalOrigin.self, from: data)
        XCTAssertEqual(decoded, origin)
    }

    func testACPOriginCodableRoundtrip() throws {
        let origin = TerminalOrigin.acp(sessionID: "acp-session-42")
        let data = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(TerminalOrigin.self, from: data)
        XCTAssertEqual(decoded, origin)
    }

    func testRestoreActionsSkipACPTerminals() {
        let entries: [TerminalSessionEntry] = [
            .init(workingDirectoryPath: "/projects/test", customName: "ACP", origin: .acp(sessionID: "acp-1")),
            .init(workingDirectoryPath: "/projects/test", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
        ]
        let profiles: [TerminalSessionRestorer.IndexedProfile] = [
            .init(index: 0, command: "npm start", tabName: "Dev"),
            .init(index: 1, command: "npm test", tabName: "Tests"),
        ]

        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: profiles,
            projectRoot: projectRoot
        )

        XCTAssertEqual(actions.count, 2)
        XCTAssertFalse(actions.contains(where: { if case .acp = $0.origin { return true } else { return false } }))
        XCTAssertEqual(actions.map(\.command), ["npm start", "npm test"])
    }

    // MARK: - TerminalSessionEntry Codable roundtrip

    func testSessionEntryCodableRoundtrip() throws {
        let entry = TerminalSessionEntry(
            workingDirectoryPath: "/projects/test",
            customName: "Dev Server",
            origin: .preset(profileIndex: 0, command: "npm start")
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TerminalSessionEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    // MARK: - VibeSpaceSessionState Codable roundtrip

    func testVibeSpaceSessionStateCodableRoundtrip() throws {
        let state = VibeSpaceSessionState(
            projectStates: [
                ProjectTerminalSessionState(
                    projectPath: "/projects/test",
                    terminalEntries: [
                        TerminalSessionEntry(workingDirectoryPath: "/projects/test", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
                        TerminalSessionEntry(workingDirectoryPath: "/projects/test/src", customName: nil, origin: .adHoc),
                    ],
                    activeTerminalDirectory: "/projects/test"
                )
            ],
            vibeCastTargetTabID: UUID()
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(VibeSpaceSessionState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    // MARK: - Edge cases

    func testEmptyCommandPresetInConfig_skipped() {
        let entries: [TerminalSessionEntry] = []
        let profiles: [TerminalSessionRestorer.IndexedProfile] = [
            .init(index: 0, command: "", tabName: nil),
        ]
        let actions = TerminalSessionRestorer.restoreActions(
            entries: entries,
            presetProfiles: profiles,
            projectRoot: projectRoot
        )
        // Empty command profile treated as ad-hoc fallback
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].origin, .adHoc)
        XCTAssertFalse(actions[0].shouldExecuteCommand)
    }
}
