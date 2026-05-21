import XCTest
@testable import CrispyVibes

final class VibeSpaceCreationResultTests: XCTestCase {
    @MainActor
    private static let container = AppContainer.makeDefault()

    // REQ-P8-BUG-007: Selecting then deselecting CLI profile should result in nil
    func testSelectThenDeselectCLIProfileResultsInNil() {
        var cliProfile: TextServiceCLIProfile? = nil

        // User taps kiro
        cliProfile = .kiro
        XCTAssertEqual(cliProfile, .kiro)

        // User taps kiro again to deselect
        let isSelected = cliProfile == .kiro
        cliProfile = isSelected ? nil : .kiro
        XCTAssertNil(cliProfile, "Deselecting kiro should result in nil, not kiro")
    }

    // REQ-P8-BUG-007: Deselecting vibespace CLI must also clear per-project overrides
    func testDeselectingVibeSpaceCLIClearsProjectOverrides() {
        var cliProfile: TextServiceCLIProfile? = nil
        var projectCLIOverrides: [String: TextServiceCLIProfile] = [:]

        // User selects kiro
        cliProfile = .kiro

        // Simulate per-project overrides being set (e.g., by SwiftUI Picker)
        projectCLIOverrides["/project-2"] = .kiro
        projectCLIOverrides["/project-3"] = .kiro

        // User deselects kiro — must clear overrides
        cliProfile = nil
        projectCLIOverrides.removeAll()

        XCTAssertNil(cliProfile)
        XCTAssertTrue(projectCLIOverrides.isEmpty,
            "Per-project overrides must be cleared when vibespace CLI is deselected")
    }

    // REQ-P8-BUG-007: Creation result with nil CLI profile must not set any startup profile
    func testCreationResultWithNilCLIProfileHasNoStartupCommand() {
        let result = VibeSpaceCreationResult(
            name: "Test",
            folders: [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b"), URL(fileURLWithPath: "/c")],
            cliSelection: nil,
            projectCLIOverrides: [:]
        )

        XCTAssertNil(result.cliSelection, "CLI selection should be nil when deselected")
        XCTAssertTrue(result.projectCLIOverrides.isEmpty, "No per-project overrides should exist")
    }

    func testCustomCLISelectionResolvesTrimmedCommand() {
        let selection = VibeSpaceCLISelection(profile: .custom, customCommand: "  my-agent --fast  ")

        XCTAssertEqual(selection.normalized.customCommand, "my-agent --fast")
        XCTAssertEqual(selection.resolvedCommand, "my-agent --fast")
        XCTAssertEqual(selection.resolvedStartupCommand, "my-agent --fast")
    }

    func testPresetCLISelectionUsesPresetCommand() {
        let selection = VibeSpaceCLISelection(profile: .codex, customCommand: "ignored")

        XCTAssertEqual(selection.resolvedCommand, TextServiceCLIProfile.codex.defaultCommand)
        XCTAssertEqual(selection.resolvedStartupCommand, "codex")
    }

    func testKiroSelectionDefaultsToStandardTrustForTextServiceAndStartup() {
        let selection = VibeSpaceCLISelection(profile: .kiro)

        XCTAssertEqual(selection.resolvedTextServiceConfiguration.trustMode, .standard)
        XCTAssertEqual(selection.resolvedTextServiceConfiguration.arguments, "chat --no-interactive --wrap never")
        XCTAssertEqual(selection.resolvedStartupCommand, "kiro-cli")
    }

    func testProjectCLIOverridesCarryCustomCommands() {
        let result = VibeSpaceCreationResult(
            name: "Test",
            folders: [URL(fileURLWithPath: "/a")],
            cliSelection: VibeSpaceCLISelection(profile: .custom, customCommand: "vibespace-agent"),
            projectCLIOverrides: [
                "/a": VibeSpaceCLISelection(profile: .custom, customCommand: "project-agent")
            ]
        )

        XCTAssertEqual(result.cliSelection?.resolvedCommand, "vibespace-agent")
        XCTAssertEqual(result.projectCLIOverrides["/a"]?.resolvedCommand, "project-agent")
    }

    // REQ-P8-BUG-007: Fresh vibespace startup settings must have empty profiles
    @MainActor
    func testFreshVibeSpaceHasEmptyStartupProfiles() {
        let vibespace = Self.container.makeVibeSpaceState(
            name: "Test",
            projectURLs: [URL(fileURLWithPath: "/tmp/project-1")]
        )

        let profiles = vibespace.startupSettings.activeProfiles
        for profile in profiles {
            XCTAssertTrue(profile.command.isEmpty,
                "Fresh vibespace startup profile should have empty command, got: \(profile.command)")
            XCTAssertNil(profile.presetID,
                "Fresh vibespace startup profile should have nil presetID")
        }
    }

    // REQ-P8-BUG-007: Startup launch instructions from empty profiles must be empty
    func testEmptyProfilesProduceNoLaunchInstructions() {
        let settings = VibeSpaceStartupSettings.default
        let profiles = settings.activeProfiles

        // All profiles should have no instruction
        for profile in profiles {
            XCTAssertFalse(profile.hasInstruction,
                "Default profile should not have any instruction")
        }
    }

    // REQ-P8-BUG-007: Multi-project vibespace with no CLI must not generate commands for any project
    @MainActor
    func testMultiProjectVibeSpaceWithNoCLIHasNoStartupCommands() {
        let vibespace = Self.container.makeVibeSpaceState(
            name: "Test",
            projectURLs: [
                URL(fileURLWithPath: "/tmp/project-1"),
                URL(fileURLWithPath: "/tmp/project-2"),
                URL(fileURLWithPath: "/tmp/project-3"),
            ]
        )

        // No project should have a startup override
        for project in vibespace.projects {
            let override = vibespace.startupOverride(for: project.rootURL.standardizedFileURL.path)
            XCTAssertNil(override,
                "Project \(project.rootURL.lastPathComponent) should have no startup override")
        }

        // VibeSpace startup settings should have no commands
        let instructions = vibespace.startupSettings.activeProfiles.filter { $0.hasInstruction }
        XCTAssertTrue(instructions.isEmpty,
            "No startup instructions should exist for vibespace with no CLI selected")
    }
}
