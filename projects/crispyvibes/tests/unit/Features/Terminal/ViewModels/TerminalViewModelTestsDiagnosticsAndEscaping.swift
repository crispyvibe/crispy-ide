import AppKit
import Darwin
import Foundation
import XCTest
@testable import CrispyVibes

@MainActor
extension TerminalViewModelTests {
    func testTerminalPresetAvailabilityDiagnosticsDetectsExecutablesAndPersistsResults() throws {
        let suiteName = "TerminalPresetAvailability.detect.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to initialize isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binDirectory = tempRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let executableURL = binDirectory.appendingPathComponent("fixturetool")
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        if let originalPath {
            setenv("PATH", "\(binDirectory.path):\(originalPath)", 1)
        } else {
            setenv("PATH", binDirectory.path, 1)
        }
        defer {
            if let originalPath {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let diagnostics = TerminalPresetAvailabilityDiagnostics(defaults: defaults)
        let presets = [
            TerminalPresetDefinition(
                id: "fixture",
                title: "Fixture",
                shortLabel: "Fx",
                symbolName: "terminal",
                defaultCommand: "fixturetool --version"
            ),
            TerminalPresetDefinition(
                id: "subcommand",
                title: "Subcommand",
                shortLabel: "Sub",
                symbolName: "terminal",
                defaultCommand: "fixturetool tui"
            ),
            TerminalPresetDefinition(
                id: "missing",
                title: "Missing",
                shortLabel: "Mx",
                symbolName: "terminal",
                defaultCommand: "missing-tool"
            )
        ]

        let detected = diagnostics.availablePresetIDs(from: presets)
        XCTAssertEqual(detected, Set(["fixture", "subcommand"]))
        XCTAssertEqual(defaults.integer(forKey: AppPreferences.terminalToolDiagnosticsVersionKey), 2)
        XCTAssertEqual(
            Set(defaults.array(forKey: AppPreferences.terminalToolDiagnosticsInstalledToolsKey) as? [String] ?? []),
            Set(["fixture", "subcommand"])
        )
    }

    func testTerminalPresetAvailabilityDiagnosticsLoadsPersistedPresetIDsAndCachesResult() {
        let suiteName = "TerminalPresetAvailability.persisted.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to initialize isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(2, forKey: AppPreferences.terminalToolDiagnosticsVersionKey)
        defaults.set(["persisted"], forKey: AppPreferences.terminalToolDiagnosticsInstalledToolsKey)

        let diagnostics = TerminalPresetAvailabilityDiagnostics(defaults: defaults)
        let first = diagnostics.availablePresetIDs(from: TerminalViewModel.builtInPresets)
        XCTAssertEqual(first, Set(["persisted"]))

        defaults.set(["changed"], forKey: AppPreferences.terminalToolDiagnosticsInstalledToolsKey)
        let second = diagnostics.availablePresetIDs(from: TerminalViewModel.builtInPresets)
        XCTAssertEqual(second, Set(["persisted"]))
    }

    func testTerminalPresetAvailabilityDiagnosticsIgnoresStalePersistedVersion() throws {
        let suiteName = "TerminalPresetAvailability.stale.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to initialize isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(1, forKey: AppPreferences.terminalToolDiagnosticsVersionKey)
        defaults.set(["stale"], forKey: AppPreferences.terminalToolDiagnosticsInstalledToolsKey)

        let binDirectory = tempRoot.appendingPathComponent("stale-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let executableURL = binDirectory.appendingPathComponent("fixturetool")
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        if let originalPath {
            setenv("PATH", "\(binDirectory.path):\(originalPath)", 1)
        } else {
            setenv("PATH", binDirectory.path, 1)
        }
        defer {
            if let originalPath {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let diagnostics = TerminalPresetAvailabilityDiagnostics(defaults: defaults)
        let detected = diagnostics.availablePresetIDs(
            from: [
                TerminalPresetDefinition(
                    id: "fixture",
                    title: "Fixture",
                    shortLabel: "Fx",
                    symbolName: "terminal",
                    defaultCommand: "fixturetool"
                )
            ]
        )

        XCTAssertEqual(detected, Set(["fixture"]))
        XCTAssertEqual(defaults.integer(forKey: AppPreferences.terminalToolDiagnosticsVersionKey), 2)
    }

    func testTerminalViewModelStaticPresetHelpersRespectUITestAvailabilityOverride() {
        let originalUITestMode = ProcessInfo.processInfo.environment["CRISPYVIBES_UI_TEST_MODE"]
        let originalUITestTools = ProcessInfo.processInfo.environment["CRISPYVIBES_UI_TEST_TERMINAL_TOOLS"]
        setenv("CRISPYVIBES_UI_TEST_MODE", "1", 1)
        setenv("CRISPYVIBES_UI_TEST_TERMINAL_TOOLS", "codex", 1)
        defer {
            if let originalUITestMode {
                setenv("CRISPYVIBES_UI_TEST_MODE", originalUITestMode, 1)
            } else {
                unsetenv("CRISPYVIBES_UI_TEST_MODE")
            }
            if let originalUITestTools {
                setenv("CRISPYVIBES_UI_TEST_TERMINAL_TOOLS", originalUITestTools, 1)
            } else {
                unsetenv("CRISPYVIBES_UI_TEST_TERMINAL_TOOLS")
            }
        }

        XCTAssertNil(TerminalViewModel.preset(id: nil))
        XCTAssertNil(TerminalViewModel.preset(id: "unknown"))
        XCTAssertEqual(TerminalViewModel.preset(id: "codex")?.id, "codex")
        XCTAssertEqual(
            Set(TerminalViewModel.availableBuiltInPresets(using: container.terminalViewModelDependencies).map(\.id)),
            Set(["codex"])
        )
    }

    func testTerminalShellResolutionProviderUpdateContextRecomputesSelection() {
        let provider = TerminalShellResolutionProvider(
            initialContext: TerminalShellResolutionContext(
                processEnvironmentShell: "/definitely/missing-shell"
            )
        )

        let initial = provider.resolve()
        XCTAssertEqual(initial.selected.source, .hardcodedDefault)

        provider.updateContext(
            TerminalShellResolutionContext(
                processEnvironmentShell: "/bin/bash"
            )
        )
        let updated = provider.resolve()
        XCTAssertEqual(updated.selected.source, .processEnvironment)
        XCTAssertEqual(updated.selected.executablePath, "/bin/bash")
    }

    func testTerminalViewModelClipboardSelectionAndErrorHelpers() throws {
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let secondDirectory = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        viewModel.createTab(directoryURL: secondDirectory, startImmediately: false)

        let firstTab = try XCTUnwrap(viewModel.tabs.first)
        viewModel.selectTab(firstTab)
        XCTAssertEqual(viewModel.activeTabID, firstTab.id)

        viewModel.copy(tabID: firstTab.id)
        viewModel.paste(tabID: firstTab.id)
        viewModel.copyActiveTab()
        viewModel.pasteActiveTab()

        viewModel.errorMessage = "transient-error"
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)

        let inactiveA = viewModel.tabActivityStateOrInactive(for: UUID())
        let inactiveB = viewModel.tabActivityStateOrInactive(for: UUID())
        XCTAssertFalse(inactiveA.isActive)
        XCTAssertTrue(inactiveA === inactiveB)
    }

    func waitForFileToAppear(_ fileURL: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
