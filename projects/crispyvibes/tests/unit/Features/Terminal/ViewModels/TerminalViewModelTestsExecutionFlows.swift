import AppKit
import Darwin
import Foundation
import os.signpost
import XCTest
@testable import CrispyVibes

@MainActor
extension TerminalViewModelTests {
    func testLaunchPresetQueuesResolvedCommandInTerminalSession() throws {
        let markerFileURL = tempRoot.appendingPathComponent("preset-executed.txt")
        try? FileManager.default.removeItem(at: markerFileURL)
        let expectedCommand = "/usr/bin/touch \(markerFileURL.path)"

        let preset = TerminalPresetDefinition(
            id: "fixtureexec",
            title: "Fixture Exec",
            shortLabel: "FxExec",
            symbolName: "terminal",
            defaultCommand: expectedCommand
        )

        viewModel.launchPreset(preset, mode: .standard, directoryURL: tempRoot)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTab?.customName, "FxExec")
        let session = try XCTUnwrap(viewModel.activeTab.flatMap { viewModel.session(for: $0.id) })
        XCTAssertEqual(session.pendingCommands.count, 1)
        XCTAssertEqual(session.pendingCommands.first?.text, expectedCommand)
    }

    func testTerminalSessionQueuesCommandUntilRenderableOutputArrives() throws {
        let earlyMarkerURL = tempRoot.appendingPathComponent("command-too-early.txt")
        let receivedMarkerURL = tempRoot.appendingPathComponent("command-received.txt")
        let probeScriptURL = tempRoot.appendingPathComponent("shell-probe.py")
        let shellWrapperURL = tempRoot.appendingPathComponent("shell-probe-wrapper")
        let queuedCommand = "queued-command"

        let escapedEarlyMarkerPath = earlyMarkerURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedReceivedMarkerPath = receivedMarkerURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let probeScript = """
import os
import pathlib
import select
import sys
import time

early_marker = pathlib.Path('\(escapedEarlyMarkerPath)')
received_marker = pathlib.Path('\(escapedReceivedMarkerPath)')

sys.stdout.write("\\x1b]697;shell-integration\\x07")
sys.stdout.flush()

readable, _, _ = select.select([sys.stdin], [], [], 0.35)
if readable:
    early_bytes = os.read(sys.stdin.fileno(), 4096)
    early_text = early_bytes.decode("utf-8", errors="ignore")
    if "\(queuedCommand)" in early_text:
        early_marker.write_text("early", encoding="utf-8")

time.sleep(0.8)
sys.stdout.write("ready\\n")
sys.stdout.flush()

line = sys.stdin.readline()
if line:
    received_marker.write_text(line.strip(), encoding="utf-8")
"""
        try probeScript.write(to: probeScriptURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexec /usr/bin/python3 \(probeScriptURL.path)\n".write(
            to: shellWrapperURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: shellWrapperURL.path
        )

        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: shellWrapperURL.path,
            source: .processEnvironment
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: tempRoot,
            terminalServices: TerminalServices(),
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        session.sendCommand(queuedCommand)

        XCTAssertFalse(
            waitForFileToAppear(earlyMarkerURL, timeout: 0.7),
            "Expected command to stay queued until renderable shell output arrives."
        )
        let deadline = Date().addingTimeInterval(3.5)
        var receivedCommandReady = false
        while Date() < deadline {
            if let receivedCommand = try? String(contentsOf: receivedMarkerURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                receivedCommand == queuedCommand
            {
                receivedCommandReady = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(
            receivedCommandReady,
            "Expected queued command to be dispatched after shell output signaled readiness."
        )
    }

    func testEnsureActiveTerminalFallsBackToFirstTabWhenActiveSelectionIsMissing() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        viewModel.createTab(directoryURL: second, startImmediately: false)
        viewModel.activeTabID = UUID()

        viewModel.ensureActiveTerminal(defaultDirectory: tempRoot, transitionID: "fallback-test")
        XCTAssertEqual(viewModel.activeTabID, viewModel.tabs.first?.id)
    }

    func testRestartPaneClearsStateAndCreatesFreshTab() throws {
        let other = tempRoot.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        viewModel.createTab(directoryURL: other, startImmediately: false)
        viewModel.errorMessage = "test-error"

        viewModel.restartPane()

        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertNotNil(viewModel.activeTabID)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRestartTabReplacesOnlyTargetedTerminal() throws {
        let other = tempRoot.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: tempRoot, customName: "Primary", startImmediately: false)
        viewModel.createTab(directoryURL: other, customName: "Worker", startImmediately: false)

        let originalTabs = viewModel.tabs
        let restartedTab = try XCTUnwrap(viewModel.tabs.last)
        viewModel.activeTabID = originalTabs.first?.id

        viewModel.restartTab(restartedTab.id, activateTab: false)

        XCTAssertEqual(viewModel.tabs.count, 2)
        XCTAssertEqual(viewModel.activeTabID, originalTabs.first?.id)
        XCTAssertEqual(viewModel.tabs[0].id, originalTabs[0].id)
        XCTAssertEqual(viewModel.tabs[1].id, restartedTab.id)
        XCTAssertEqual(viewModel.tabs[1].workingDirectory.standardizedFileURL.path, other.standardizedFileURL.path)
        XCTAssertEqual(viewModel.tabs[1].customName, "Worker")
        XCTAssertNil(viewModel.tabs[1].exitCode)
        XCTAssertNotNil(viewModel.sessions[restartedTab.id])
        XCTAssertNotNil(viewModel.tabActivityState(for: restartedTab.id))
    }

    func testRestoreTabsFallsBackToFirstWhenActiveDirectoryNotPresent() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.restoreTabs(
            directories: [first, second],
            activeDirectory: tempRoot.appendingPathComponent("missing", isDirectory: true),
            defaultDirectory: first
        )

        XCTAssertEqual(viewModel.activeTab?.workingDirectory.standardizedFileURL.path, first.standardizedFileURL.path)
    }

    func testTerminalPresetDefinitions() {
        XCTAssertEqual(TerminalPresetLaunchMode.standard.title, "Standard")
        XCTAssertEqual(TerminalPresetLaunchMode.fullTrust.title, "Full Trust")
        XCTAssertTrue(TerminalViewModel.builtInPresets.contains(where: { $0.id == "codex" }))
        XCTAssertTrue(TerminalViewModel.builtInPresets.contains(where: { $0.id == "copilot" }))
        XCTAssertTrue(TerminalViewModel.builtInPresets.contains(where: { $0.id == "opencode" }))
        guard let kiroPreset = TerminalViewModel.builtInPresets.first(where: { $0.id == "kiro" }) else {
            XCTFail("Expected built-in Kiro preset.")
            return
        }
        XCTAssertEqual(kiroPreset.command(for: .fullTrust), "kiro-cli chat --trust-all-tools")
        XCTAssertTrue(kiroPreset.supportsFullTrust)
        XCTAssertEqual(
            TerminalViewModel.builtInPresets.first(where: { $0.id == "copilot" })?.command(for: .fullTrust),
            "copilot --allow-all"
        )

        let preset = TerminalPresetDefinition(
            id: "preset",
            title: "Preset",
            shortLabel: "P",
            symbolName: "bolt",
            defaultCommand: "normal",
            fullTrustCommand: "full"
        )
        XCTAssertEqual(preset.command(for: .standard), "normal")
        XCTAssertEqual(preset.command(for: .fullTrust), "full")
    }

    func testShortcutLifecycleSupportsCreateAndDelete() {
        XCTAssertTrue(viewModel.shortcutCommands.isEmpty)

        XCTAssertFalse(viewModel.addShortcut(name: "", command: "echo hi"))
        XCTAssertFalse(viewModel.addShortcut(name: "Quick", command: "   "))

        XCTAssertTrue(viewModel.addShortcut(name: "List", command: "ls -la"))
        XCTAssertEqual(viewModel.shortcutCommands.count, 1)
        XCTAssertEqual(viewModel.shortcutCommands.first?.name, "List")
        XCTAssertEqual(viewModel.shortcutCommands.first?.command, "ls -la")

        if let shortcutID = viewModel.shortcutCommands.first?.id {
            viewModel.removeShortcut(id: shortcutID)
        }
        XCTAssertTrue(viewModel.shortcutCommands.isEmpty)
    }

    func testRunShortcutCreatesTerminalWhenNoTabsExist() {
        XCTAssertTrue(viewModel.tabs.isEmpty)
        let shortcut = TerminalShortcutDefinition(name: "Pwd", command: "pwd")

        viewModel.runShortcut(shortcut, defaultDirectory: tempRoot)

        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTab?.workingDirectory.standardizedFileURL.path, tempRoot.standardizedFileURL.path)
        XCTAssertEqual(viewModel.session(for: viewModel.activeTabID!)?.pendingCommands.map(\.text), ["pwd"])
    }

    func testRunShortcutInCurrentTerminalUsesFocusedTabAndQueuesCommand() throws {
        let first = tempRoot.appendingPathComponent("first", isDirectory: true)
        let second = tempRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        viewModel.createTab(directoryURL: first, startImmediately: false)
        let firstTabID = try XCTUnwrap(viewModel.activeTabID)
        viewModel.createTab(directoryURL: second, startImmediately: false)
        let secondTabID = try XCTUnwrap(viewModel.activeTabID)
        viewModel.activeTabID = firstTabID

        let shortcut = TerminalShortcutDefinition(
            name: "Status",
            command: "git status",
            launchBehavior: .currentTerminal
        )

        viewModel.runShortcut(shortcut, defaultDirectory: tempRoot)

        XCTAssertEqual(viewModel.tabs.count, 2)
        XCTAssertEqual(viewModel.activeTabID, firstTabID)
        XCTAssertEqual(viewModel.session(for: firstTabID)?.pendingCommands.map(\.text), ["git status"])
        XCTAssertTrue(viewModel.session(for: firstTabID)?.isStarted == true)
        XCTAssertTrue(viewModel.session(for: secondTabID)?.pendingCommands.isEmpty == true)
    }

    func testRunShortcutInNewPermanentTerminalCreatesDedicatedTab() throws {
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let existingTabID = try XCTUnwrap(viewModel.activeTabID)
        let shortcut = TerminalShortcutDefinition(
            name: "Build",
            command: "make test",
            launchBehavior: .newPermanentTerminal
        )

        viewModel.runShortcut(shortcut, defaultDirectory: tempRoot)

        XCTAssertEqual(viewModel.tabs.count, 2)
        XCTAssertNotEqual(viewModel.activeTabID, existingTabID)
        XCTAssertEqual(viewModel.activeTab?.customName, "Build")
        XCTAssertEqual(viewModel.session(for: viewModel.activeTabID!)?.pendingCommands.map(\.text), ["make test"])
    }

    func testExecuteTerminalShortcutInTemporaryTerminalUsesDelegateWhenAvailable() throws {
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let activeTabID = try XCTUnwrap(viewModel.activeTabID)
        let activeDirectory = try XCTUnwrap(viewModel.activeTab?.workingDirectory.standardizedFileURL)
        let shortcut = TerminalShortcutDefinition(
            name: "Dev Server",
            command: "npm run dev",
            launchBehavior: .newTemporaryTerminal
        )

        var delegatedShortcut: TerminalShortcutDefinition?
        var delegatedDirectory: URL?
        var interactionCount = 0
        var activatedTabID: UUID?

        executeTerminalShortcut(
            shortcut,
            viewModel: viewModel,
            defaultDirectory: tempRoot,
            onTemporaryShortcutRequested: { delegatedShortcut = $0; delegatedDirectory = $1 },
            onTerminalInteraction: { interactionCount += 1 },
            onActiveTabChanged: { activatedTabID = $0 }
        )

        XCTAssertEqual(interactionCount, 1)
        XCTAssertEqual(delegatedShortcut, shortcut)
        XCTAssertEqual(delegatedDirectory?.standardizedFileURL.path, activeDirectory.path)
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTabID, activeTabID)
        XCTAssertNil(activatedTabID)
        XCTAssertTrue(viewModel.session(for: activeTabID)?.pendingCommands.isEmpty == true)
    }

    func testExecuteTerminalShortcutInTemporaryTerminalFallsBackToQueuedCommandWhenDelegateMissing() throws {
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let activeTabID = try XCTUnwrap(viewModel.activeTabID)
        let shortcut = TerminalShortcutDefinition(
            name: "Logs",
            command: "tail -f app.log",
            launchBehavior: .newTemporaryTerminal
        )

        var interactionCount = 0
        var activatedTabID: UUID?

        executeTerminalShortcut(
            shortcut,
            viewModel: viewModel,
            defaultDirectory: tempRoot,
            onTerminalInteraction: { interactionCount += 1 },
            onActiveTabChanged: { activatedTabID = $0 }
        )

        XCTAssertEqual(interactionCount, 1)
        XCTAssertEqual(viewModel.tabs.count, 1)
        XCTAssertEqual(viewModel.activeTabID, activeTabID)
        XCTAssertEqual(activatedTabID, activeTabID)
        XCTAssertEqual(viewModel.session(for: activeTabID)?.pendingCommands.map(\.text), ["tail -f app.log"])
    }

    func testShortcutDefinitionDecodesLegacyPayloadWithDefaultLaunchBehavior() throws {
        let payload = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Pwd",
          "command": "pwd"
        }
        """.data(using: .utf8)

        let decoded = try JSONDecoder().decode(
            TerminalShortcutDefinition.self,
            from: try XCTUnwrap(payload)
        )

        XCTAssertEqual(decoded.launchBehavior, .currentTerminal)
    }

    func testPresetAvailabilityDiagnosticsRespectsUITestOverride() {
        let suiteName = "TerminalPresetAvailabilityDiagnosticsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to initialize isolated defaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let originalUITestMode = ProcessInfo.processInfo.environment["CRISPYVIBES_UI_TEST_MODE"]
        let originalUITestTools = ProcessInfo.processInfo.environment["CRISPYVIBES_UI_TEST_TERMINAL_TOOLS"]
        setenv("CRISPYVIBES_UI_TEST_MODE", "1", 1)
        setenv("CRISPYVIBES_UI_TEST_TERMINAL_TOOLS", "codex,kiro", 1)
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
            defaults.removePersistentDomain(forName: suiteName)
        }

        let diagnostics = TerminalPresetAvailabilityDiagnostics(defaults: defaults)
        let presetIDs = diagnostics.availablePresetIDs(from: TerminalViewModel.builtInPresets)
        XCTAssertEqual(presetIDs, Set(["codex", "kiro"]))
    }

    func testSessionCallbacksUpdateTabMetadataAndActivity() throws {
        viewModel.createTab(directoryURL: tempRoot, startImmediately: false)
        let activeTabID = try XCTUnwrap(viewModel.activeTabID)
        let session = try XCTUnwrap(viewModel.session(for: activeTabID))
        let newDirectory = tempRoot.appendingPathComponent("nested", isDirectory: true)

        session.onTitleChanged?("Build Session")
        session.onDirectoryChanged?(newDirectory)
        session.onProcessTerminated?(42)
        session.onActivityChanged?(true)

        let updated = try XCTUnwrap(viewModel.activeTab)
        let activityState = try XCTUnwrap(viewModel.tabActivityState(for: activeTabID))
        XCTAssertEqual(updated.sessionTitle, "Build Session")
        XCTAssertEqual(updated.workingDirectory.standardizedFileURL.path, newDirectory.standardizedFileURL.path)
        XCTAssertEqual(updated.exitCode, 42)
        XCTAssertTrue(activityState.isActive)

        session.onActivityChanged?(false)
        XCTAssertFalse(activityState.isActive)
    }

    func testTerminalContainerOwnershipRequiresFreshAttachAndAllowsPriorityPreemption() {
        let session = TerminalSession(id: UUID(), workingDirectory: tempRoot, terminalServices: viewModel.terminalServices)
        defer {
            session.terminate()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 280))
        let primaryHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )
        let secondaryHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 420, y: 0, width: 420, height: 280)
        )
        root.addSubview(primaryHost)
        root.addSubview(secondaryHost)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = root

        primaryHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === primaryHost,
            "Primary host should own terminal after first attach."
        )

        secondaryHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .compact,
            isActive: false,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === primaryHost,
            "Secondary host should not preempt a mounted owner immediately."
        )

        primaryHost.removeFromSuperview()
        root.layoutSubtreeIfNeeded()
        let secondaryReclaimDeadline = Date().addingTimeInterval(1.0)
        var secondaryReclaimed = session.hostedView.superview === secondaryHost
        while !secondaryReclaimed, Date() < secondaryReclaimDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            root.layoutSubtreeIfNeeded()
            secondaryReclaimed = session.hostedView.superview === secondaryHost
        }
        XCTAssertTrue(
            secondaryReclaimed,
            "Secondary host should claim terminal after primary owner release."
        )

        root.addSubview(primaryHost)
        primaryHost.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === secondaryHost,
            "Stale host should not reclaim terminal without a new attach request."
        )

        primaryHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === primaryHost,
            "Higher-priority regular host should preempt compact owner after a fresh attach request."
        )

        secondaryHost.removeFromSuperview()
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === primaryHost,
            "Remaining regular host should retain ownership after compact host removal."
        )

        window.contentView = nil
    }

    func testRegularFocusedHostPreemptsCompactHostWhenBothMounted() {
        let session = TerminalSession(id: UUID(), workingDirectory: tempRoot, terminalServices: viewModel.terminalServices)
        defer {
            session.terminate()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 280))
        let regularHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )
        let compactHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 420, y: 0, width: 420, height: 280)
        )
        root.addSubview(regularHost)
        root.addSubview(compactHost)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = root

        compactHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .compact,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === compactHost,
            "Compact host should own terminal when it attaches first."
        )

        regularHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === regularHost,
            "Regular focused host should preempt compact host immediately."
        )

        window.contentView = nil
    }

    func testNonParticipatingHostCannotPreemptVisibleOwner() {
        let session = TerminalSession(id: UUID(), workingDirectory: tempRoot, terminalServices: viewModel.terminalServices)
        defer {
            session.terminate()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 280))
        let visibleHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )
        let hiddenHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 420, y: 0, width: 420, height: 280)
        )
        root.addSubview(visibleHost)
        root.addSubview(hiddenHost)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = root

        visibleHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === visibleHost,
            "Visible host should own terminal after first attach."
        )

        hiddenHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: false,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            session.hostedView.superview === visibleHost,
            "Non-participating host must not steal ownership from the visible host."
        )

        window.contentView = nil
    }

    func testRequestKeyboardFocusMovesFirstResponderToHostedView() {
        let engine = TestTerminalSessionEngine()
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: tempRoot,
            terminalServices: viewModel.terminalServices,
            engineFactory: { _ in engine }
        )
        defer {
            session.terminate()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 280))
        let host = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 840, height: 280)
        )
        root.addSubview(host)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = root

        host.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(window.firstResponder === window)

        session.requestKeyboardFocus()

        let focusDeadline = Date().addingTimeInterval(1.0)
        while window.firstResponder !== session.hostedView, Date() < focusDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertTrue(
            window.firstResponder === session.hostedView,
            "Session should move keyboard focus directly to the hosted terminal view."
        )

        window.contentView = nil
    }

    func testNonOwningHostDoesNotOverwriteVisibleHostActionHandlers() {
        let engine = TestTerminalSessionEngine()
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: tempRoot,
            terminalServices: viewModel.terminalServices,
            engineFactory: { _ in engine }
        )
        defer {
            session.terminate()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 280))
        let visibleHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )
        let hiddenHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 420, y: 0, width: 420, height: 280)
        )
        root.addSubview(visibleHost)
        root.addSubview(hiddenHost)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = root

        var visibleLinkActivationCount = 0
        let visibleLinkHandler: (URL) -> Void = { _ in
            visibleLinkActivationCount += 1
        }

        visibleHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: visibleLinkHandler,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertNotNil(
            engine.lastActionHandlers.onLinkTargetActivated,
            "Owning host should publish its link handler to the shared session engine."
        )

        hiddenHost.attach(
            session.hostedView,
            session: session,
            sessionID: session.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: false,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertNotNil(
            engine.lastActionHandlers.onLinkTargetActivated,
            "Non-owning hosts must not clear the active host's link handler."
        )
        engine.lastActionHandlers.onLinkTargetActivated?(URL(string: "https://example.com")!)
        XCTAssertEqual(visibleLinkActivationCount, 1)

        window.contentView = nil
    }

    func testMultipleVisibleHostsForDifferentSessionsRemainMountedSimultaneously() {
        let firstSession = TerminalSession(id: UUID(), workingDirectory: tempRoot, terminalServices: viewModel.terminalServices)
        let secondDirectory = tempRoot.appendingPathComponent("secondary", isDirectory: true)
        let secondSession = TerminalSession(
            id: UUID(),
            workingDirectory: secondDirectory,
            terminalServices: viewModel.terminalServices
        )
        defer {
            firstSession.terminate()
            secondSession.terminate()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 280))
        let firstHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )
        let secondHost = TerminalContainerView(
            ownershipCoordinator: viewModel.terminalServices.hostOwnershipCoordinator,
            frame: NSRect(x: 420, y: 0, width: 420, height: 280)
        )
        root.addSubview(firstHost)
        root.addSubview(secondHost)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = root

        firstHost.attach(
            firstSession.hostedView,
            session: firstSession,
            sessionID: firstSession.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        secondHost.attach(
            secondSession.hostedView,
            session: secondSession,
            sessionID: secondSession.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(firstSession.hostedView.superview === firstHost)
        XCTAssertTrue(secondSession.hostedView.superview === secondHost)

        firstHost.attach(
            firstSession.hostedView,
            session: firstSession,
            sessionID: firstSession.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        secondHost.attach(
            secondSession.hostedView,
            session: secondSession,
            sessionID: secondSession.id,
            displayDensity: .regular,
            isActive: true,
            allowsOwnershipParticipation: true,
            onSplitTerminalRequested: nil,
            onTemporaryTerminalRequested: nil,
            onOpenInEditorPaneRequested: nil,
            onLinkTargetActivated: nil,
            onFileSystemTargetActivated: nil
        )
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(firstSession.hostedView.superview === firstHost)
        XCTAssertTrue(secondSession.hostedView.superview === secondHost)

        window.contentView = nil
    }

}

@MainActor
final class GhosttyTerminalEngineTests: XCTestCase {
    @MainActor
    func testGhosttyWorkingDirectoryChangeDoesNotMarkSessionInteractive() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())
        let delegate = GhosttyTerminalEngineDelegateSpy()

        engine.configure(
            delegate: delegate,
            initialFont: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            optionAsMetaKey: true,
            historySize: 1_000
        )

        engine.handleWorkingDirectoryChange(FileManager.default.temporaryDirectory.path)

        XCTAssertEqual(delegate.directoryUpdates, [FileManager.default.temporaryDirectory.path])
        XCTAssertEqual(delegate.renderableSamples.count, 0)
        XCTAssertEqual(delegate.interactiveEventCount, 0)
    }

    func testStartupCommandsDispatchAfterFallbackWithoutRenderableOutput() {
        let engine = TestTerminalSessionEngine()
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        session.startupCommandFallbackDelay = 0.02
        session.startProcess(
            shellResolution: shellResolution,
            environment: [],
            signpostID: OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        )
        session.activitySuppressedUntil = .distantPast

        session.sendStartupCommand("echo startup")
        XCTAssertTrue(engine.sentText.isEmpty)

        let deadline = Date().addingTimeInterval(0.3)
        while engine.sentText.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(engine.sentText, ["echo startup\n"])
        XCTAssertFalse(session.hasReceivedOutput)
    }

    func testStartupCommandsDoNotDispatchOnDirectoryUpdateBeforeRenderableOutput() {
        let engine = TestTerminalSessionEngine()
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        session.startupCommandFallbackDelay = 0.15
        session.startProcess(
            shellResolution: shellResolution,
            environment: [],
            signpostID: OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        )
        session.activitySuppressedUntil = .distantPast

        session.sendStartupCommand("echo startup")
        session.terminalEngine(engine, didUpdateCurrentDirectory: FileManager.default.temporaryDirectory.path)

        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(
            engine.sentText.isEmpty,
            "Startup commands should not dispatch just because Ghostty reported an early cwd."
        )

        let deadline = Date().addingTimeInterval(0.4)
        while engine.sentText.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(engine.sentText, ["echo startup\n"])
    }

    func testGhosttyStartupCommandsWaitForInteractivePromptSignal() {
        let engine = TestTerminalSessionEngine()
        engine.requiresInteractivePromptForStartupCommandsOverride = true
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        session.startupCommandFallbackDelay = 1.0
        session.startProcess(
            shellResolution: shellResolution,
            environment: [],
            signpostID: OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        )
        session.activitySuppressedUntil = .distantPast

        session.sendStartupCommand("echo startup")
        session.terminalEngine(engine, didReceiveRenderableOutput: "Last login: yesterday")

        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(
            engine.sentText.isEmpty,
            "Renderable output alone should not unlock Ghostty startup commands before prompt readiness."
        )

        session.terminalEngineDidBecomeInteractive(engine)

        XCTAssertEqual(engine.sentText, ["echo startup\n"])
    }

    func testGhosttyStartupFallbackWaitsForQuietPeriodAfterLatestOutput() {
        let engine = TestTerminalSessionEngine()
        engine.requiresInteractivePromptForStartupCommandsOverride = true
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root
        engine.hostedView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        root.addSubview(engine.hostedView)
        defer {
            session.terminate()
            window.contentView = nil
        }

        session.startupCommandFallbackDelay = 0.05
        session.startProcess(
            shellResolution: shellResolution,
            environment: [],
            signpostID: OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        )
        session.activitySuppressedUntil = .distantPast

        session.sendStartupCommand("echo startup")
        RunLoop.current.run(until: Date().addingTimeInterval(0.07))
        XCTAssertTrue(
            engine.sentText.isEmpty,
            "Ghostty startup fallback should not run before the terminal has produced visible output."
        )

        session.terminalEngine(engine, didChangeSizeToCols: 120, rows: 32)
        session.terminalEngine(engine, didReceiveRenderableOutput: "Last login: today")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        XCTAssertTrue(
            engine.sentText.isEmpty,
            "Ghostty startup fallback should still wait after the first visible startup output."
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        session.terminalEngine(engine, didReceiveRenderableOutput: "loading shell plugins")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        XCTAssertTrue(
            engine.sentText.isEmpty,
            "Later startup output should reset Ghostty fallback timing until the shell settles."
        )

        let deadline = Date().addingTimeInterval(0.25)
        while engine.sentText.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(engine.sentText, ["echo startup\n"])
    }

    func testSendingCommandDoesNotMarkActivityBeforeOutputArrives() {
        let engine = TestTerminalSessionEngine()
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        var activityEvents: [Bool] = []
        session.onActivityChanged = { isActive in
            activityEvents.append(isActive)
        }

        session.startIfNeeded()
        let startupDeadline = Date().addingTimeInterval(0.3)
        while !engine.processIsRunning, Date() < startupDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(engine.processIsRunning)
        session.activitySuppressedUntil = .distantPast

        session.sendCommand("pwd")

        XCTAssertTrue(engine.sentText.isEmpty)
        XCTAssertTrue(activityEvents.isEmpty)

        session.terminalEngine(engine, didReceiveRenderableOutput: "/tmp")

        XCTAssertEqual(engine.sentText, ["pwd\n"])
        XCTAssertEqual(activityEvents, [true])
    }

    func testFirstRenderableOutputMarksSessionActive() {
        let engine = TestTerminalSessionEngine()
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        var activityEvents: [Bool] = []
        session.onActivityChanged = { isActive in
            activityEvents.append(isActive)
        }

        session.startProcess(
            shellResolution: shellResolution,
            environment: [],
            signpostID: OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        )
        session.activitySuppressedUntil = .distantPast

        session.terminalEngine(engine, didReceiveRenderableOutput: "build finished")

        XCTAssertEqual(activityEvents, [true])
        XCTAssertTrue(session.hasReceivedOutput)
        XCTAssertTrue(session.isCurrentlyActive)
    }

    func testInitialRenderableOutputStaysIdleDuringStartupSuppression() {
        let engine = TestTerminalSessionEngine()
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        var activityEvents: [Bool] = []
        session.onActivityChanged = { isActive in
            activityEvents.append(isActive)
        }

        session.startProcess(
            shellResolution: shellResolution,
            environment: [],
            signpostID: OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        )
        session.activitySuppressedUntil = Date().addingTimeInterval(5)

        session.terminalEngine(engine, didReceiveRenderableOutput: "Last login: today")

        XCTAssertTrue(activityEvents.isEmpty)
        XCTAssertFalse(session.isCurrentlyActive)
        XCTAssertTrue(session.hasReceivedOutput)
    }

    func testSignificantOutputMarksSessionActiveDuringStartupSuppression() {
        let engine = TestTerminalSessionEngine()
        let shellCandidate = TerminalShellResolutionCandidate(
            executablePath: "/bin/zsh",
            source: .hardcodedDefault
        )
        let shellResolution = TerminalShellResolution(
            requested: shellCandidate,
            selected: shellCandidate,
            rejectedCandidates: []
        )
        let session = TerminalSession(
            id: UUID(),
            workingDirectory: FileManager.default.temporaryDirectory,
            terminalServices: TerminalServices(),
            engineFactory: { _ in engine },
            shellResolutionProvider: { shellResolution }
        )
        defer {
            session.terminate()
        }

        var activityEvents: [Bool] = []
        session.onActivityChanged = { isActive in
            activityEvents.append(isActive)
        }

        session.startProcess(
            shellResolution: shellResolution,
            environment: [],
            signpostID: OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        )
        session.activitySuppressedUntil = Date().addingTimeInterval(5)

        session.terminalEngineDidReceiveSignificantOutput(engine)

        XCTAssertEqual(activityEvents, [true])
        XCTAssertTrue(session.isCurrentlyActive)
    }

    func testGhosttyEngineQueuesTextUntilSurfaceExists() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())

        engine.send(text: "echo queued\n")

        XCTAssertEqual(engine.pendingTextForTesting, ["echo queued\n"])
    }

    func testGhosttyLaunchCommandPreservesShellArguments() {
        let engine = GhosttyTerminalEngine(terminalServices: TerminalServices())

        engine.startProcess(
            executable: "/bin/zsh",
            args: ["-l", "-i"],
            environment: [],
            currentDirectory: FileManager.default.temporaryDirectory.path
        )

        XCTAssertEqual(engine.launchCommand, "/bin/zsh -l -i")
    }

    func testStartupBootstrapSuppressesInitialLoginBanner() {
        XCTAssertEqual(
            GhosttyTerminalEngineSupport.startupBootstrapCommand(),
            "printf '\\033[H\\033[2J\\033[3J' >/dev/tty"
        )
        XCTAssertNil(GhosttyTerminalEngineSupport.initialSurfaceInput())
        XCTAssertTrue(
            GhosttyTerminalEngineSupport.shouldSuppressInitialLoginBanner(
                in: """
Last login: Sun Mar  8 22:54:10 on ttys014
crispyvibes %
"""
            )
        )
        XCTAssertTrue(
            GhosttyTerminalEngineSupport.likelyInteractivePrompt(
                in: """
Projects/crispyvibes-dev/AppDistribution on main
❯
"""
            )
        )
    }

    func testStartupBootstrapIgnoresNormalRenderableOutput() {
        XCTAssertFalse(
            GhosttyTerminalEngineSupport.shouldSuppressInitialLoginBanner(
                in: """
build finished successfully
crispyvibes %
"""
            )
        )
        XCTAssertTrue(
            GhosttyTerminalEngineSupport.likelyInteractivePrompt(
                in: """
build finished successfully
crispyvibes %
"""
            )
        )
        XCTAssertFalse(
            GhosttyTerminalEngineSupport.likelyInteractivePrompt(
                in: """
Compiling sources
Linking app bundle
"""
            )
        )
    }

    // MARK: - Disabled: Ghostty engine removed
    // TODO: Remove or rewrite for SwiftTerm once theme override API is ported
    /*
    func testThemeOverrideConfigUsesThemeTokens() {
        let palette = AppThemePalette(
            windowBackground: ProjectColorTag(red: 0.03, green: 0.04, blue: 0.05),
            canvasBackground: ProjectColorTag(red: 0.07, green: 0.08, blue: 0.09),
            canvasSecondaryBackground: ProjectColorTag(red: 0.10, green: 0.11, blue: 0.12),
            borderColor: ProjectColorTag(red: 0.13, green: 0.14, blue: 0.15),
            accent: ProjectColorTag(red: 0.20, green: 0.40, blue: 0.60),
            success: ProjectColorTag(red: 0.16, green: 0.50, blue: 0.25),
            warning: ProjectColorTag(red: 0.70, green: 0.55, blue: 0.20),
            error: ProjectColorTag(red: 0.80, green: 0.25, blue: 0.25),
            selectionBackground: ProjectColorTag(red: 0.80, green: 0.20, blue: 0.30),
            terminalForeground: ProjectColorTag(red: 0.92, green: 0.93, blue: 0.94)
        )

        let config = GhosttyTerminalEngineSupport.themeOverrideConfigContents(for: palette)

        XCTAssertTrue(config.contains("background = #121417"))
        XCTAssertTrue(config.contains("foreground = #EBEDF0"))
        XCTAssertTrue(config.contains("cursor-color = #336699"))
        XCTAssertTrue(config.contains("selection-background = #5E2D40"))
        XCTAssertTrue(config.contains("selection-foreground = cell-foreground"))
    }
    */
}

@MainActor
private final class TestTerminalSessionEngine: TerminalSessionEngine {
    let hostedView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    var effectiveAppearance: NSAppearance { NSAppearance(named: .darkAqua)! }
    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    var processIsRunning = false
    var shellProcessID: Int32 = 0
    let debugIdentifier = "test-terminal-engine"
    var sessionID: UUID?
    var requiresInteractivePromptForStartupCommandsOverride = false
    var sentText: [String] = []
    var enterPressCount = 0
    var submitVariants: [TerminalSubmitVariant] = []
    var lastActionHandlers = TerminalSessionActionHandlers()
    var requiresInteractivePromptForStartupCommands: Bool {
        requiresInteractivePromptForStartupCommandsOverride
    }

    func configure(
        delegate: any TerminalSessionEngineDelegate,
        initialFont: NSFont,
        optionAsMetaKey: Bool,
        historySize: Int
    ) {
        font = initialFont
        _ = delegate
        _ = optionAsMetaKey
        _ = historySize
    }

    func startProcess(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String
    ) {
        processIsRunning = true
        shellProcessID = 42
        _ = executable
        _ = args
        _ = environment
        _ = currentDirectory
    }

    func terminate() {
        processIsRunning = false
        shellProcessID = 0
    }

    func copySelection() {}
    func pasteFromClipboard() {}

    func send(text: String) {
        sentText.append(text)
    }

    func typeCharacters(_ text: String) {
        sentText.append(text)
    }

    func pressEnter() {
        enterPressCount += 1
    }

    func pressSubmitVariant(_ variant: TerminalSubmitVariant) {
        submitVariants.append(variant)
        if variant == .returnKey {
            enterPressCount += 1
        }
    }

    func registerOscHandler(code: Int, handler: @escaping (ArraySlice<UInt8>) -> Void) {
        _ = code
        _ = handler
    }

    func currentDimensions() -> (cols: Int, rows: Int) {
        (120, 32)
    }

    func resize(cols: Int, rows: Int) {
        _ = cols
        _ = rows
    }

    func updateActionHandlers(_ handlers: TerminalSessionActionHandlers) {
        lastActionHandlers = handlers
    }

    func applyThemePalette(_ palette: AppThemePalette) {
        _ = palette
    }

    func setSurfaceFocus(_ focused: Bool) {
        _ = focused
    }
}

@MainActor
private final class GhosttyTerminalEngineDelegateSpy: TerminalSessionEngineDelegate {
    var directoryUpdates: [String?] = []
    var renderableSamples: [String?] = []
    var interactiveEventCount = 0

    func terminalEngine(_ engine: any TerminalSessionEngine, didChangeSizeToCols cols: Int, rows: Int) {
        _ = engine
        _ = cols
        _ = rows
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didChangeTitle title: String) {
        _ = engine
        _ = title
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didUpdateCurrentDirectory directory: String?) {
        _ = engine
        directoryUpdates.append(directory)
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didTerminateWithExitCode exitCode: Int32?) {
        _ = engine
        _ = exitCode
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didReceiveRenderableOutput sample: String?) {
        _ = engine
        renderableSamples.append(sample)
    }

    func terminalEngineDidBecomeInteractive(_ engine: any TerminalSessionEngine) {
        _ = engine
        interactiveEventCount += 1
    }

    func terminalEngineDidReceiveSignificantOutput(_ engine: any TerminalSessionEngine) {
        _ = engine
    }
}
