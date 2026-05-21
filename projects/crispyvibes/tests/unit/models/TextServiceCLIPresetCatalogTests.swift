import XCTest
@testable import CrispyVibes

final class TextServiceCLIPresetCatalogTests: XCTestCase {
    func testDisplayProfilesCoverAllCLIProfilesExactlyOnce() {
        XCTAssertEqual(
            Set(CLIToolCatalog.textServiceDisplayProfiles),
            Set(TextServiceCLIProfile.allCases)
        )
        XCTAssertEqual(
            CLIToolCatalog.textServiceDisplayProfiles.count,
            Set(CLIToolCatalog.textServiceDisplayProfiles).count
        )
    }

    func testCustomProfileRemainsLastInDisplayOrder() {
        XCTAssertEqual(CLIToolCatalog.textServiceDisplayProfiles.last, .custom)
    }

    func testTerminalPresetCatalogAlsoIncludesTerminalOnlyTools() {
        let presetIDs = Set(CLIToolCatalog.terminalPresetDefinitions.map(\.id))
        XCTAssertTrue(presetIDs.contains("copilot"))
    }

    func testStandardTextServiceDefaultsDoNotSilentlyEscalateTrust() throws {
        let defaults = try XCTUnwrap(CLIToolCatalog.textServiceDefaults(for: .kiro, trustMode: .standard))
        XCTAssertEqual(defaults.command, "kiro-cli")
        XCTAssertEqual(defaults.arguments, "chat --no-interactive --wrap never")
        XCTAssertTrue(defaults.passAgentFlag)
    }

    func testFullTrustDefaultsRemainAvailableWhenExplicitlySelected() throws {
        let defaults = try XCTUnwrap(CLIToolCatalog.textServiceDefaults(for: .kiro, trustMode: .fullTrust))
        XCTAssertEqual(defaults.arguments, "chat --no-interactive --trust-all-tools --wrap never")
    }

    func testAppDefaultTextServiceTrustModeRemainsStandard() {
        XCTAssertEqual(AppPreferences.defaultTextServiceCLITrustMode, CLITrustMode.standard.rawValue)
    }

    func testResolvedTextServiceConfigurationDefaultsToStandardTrustMode() {
        let suiteName = "crispyvibes.text-service.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppPreferences.resolvedTextServiceCLIConfiguration(userDefaults: defaults)
        XCTAssertEqual(configuration.profile, .kiro)
        XCTAssertEqual(configuration.trustMode, .standard)
        XCTAssertEqual(configuration.command, "kiro-cli")
        XCTAssertEqual(configuration.arguments, "chat --no-interactive --wrap never")
        XCTAssertTrue(configuration.passAgentFlag)
    }

    func testSupportedTrustModesMatchCatalogCapabilities() {
        XCTAssertEqual(CLIToolCatalog.supportedTrustModes(for: .kiro), [.standard, .fullTrust])
        XCTAssertEqual(CLIToolCatalog.supportedTrustModes(for: .opencode), [.standard])
        XCTAssertEqual(CLIToolCatalog.supportedTrustModes(for: .custom), [.standard])
    }

    func testTerminalPresetProjectionPreservesStandardAndFullTrustCommands() throws {
        let codexPreset = try XCTUnwrap(CLIToolCatalog.terminalPreset(id: "codex"))
        XCTAssertEqual(codexPreset.title, "Codex")
        XCTAssertEqual(codexPreset.command(for: .standard), "codex")
        XCTAssertEqual(
            codexPreset.command(for: .fullTrust),
            "codex --dangerously-bypass-approvals-and-sandbox"
        )
    }

    func testTerminalCommandUsesTerminalRecipeInsteadOfTextServiceDefaults() {
        XCTAssertEqual(CLIToolCatalog.terminalCommand(for: .kiro, trustMode: .standard), "kiro-cli")
        XCTAssertEqual(
            CLIToolCatalog.terminalCommand(for: .kiro, trustMode: .fullTrust),
            "kiro-cli chat --trust-all-tools"
        )
        XCTAssertNil(CLIToolCatalog.terminalCommand(for: .custom, trustMode: .standard))
    }

    func testCustomProfileHasNoPackagedTextServiceDefaults() {
        XCTAssertNil(CLIToolCatalog.textServiceDefaults(for: .custom, trustMode: .standard))
    }

    func testCommandLineParserHandlesQuotesAndEscapes() {
        let tokens = CLICommandLineParser.splitArguments(
            #"chat --message "hello world" --path /tmp/my\ folder --literal 'keep spaces'"#
        )

        XCTAssertEqual(
            tokens,
            ["chat", "--message", "hello world", "--path", "/tmp/my folder", "--literal", "keep spaces"]
        )
    }
}
