import CryptoKit
import XCTest
@testable import CrispyVibes

// MARK: - Model Roundtrip Tests

final class VibeSpaceConfigModelTests: XCTestCase {

    func testAppStateFileRoundtrip() throws {
        let state = AppStateFile(recentVibeSpaceIDs: [UUID(), UUID(), UUID()])
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppStateFile.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testAppStateTouchMovesToFront() {
        var state = AppStateFile(recentVibeSpaceIDs: [UUID(), UUID(), UUID()])
        let last = state.recentVibeSpaceIDs[2]
        state.touchVibeSpace(last)
        XCTAssertEqual(state.recentVibeSpaceIDs.first, last)
        XCTAssertEqual(state.recentVibeSpaceIDs.count, 3)
    }

    func testAppStateTouchDeduplicates() {
        let id = UUID()
        var state = AppStateFile(recentVibeSpaceIDs: [id, UUID()])
        state.touchVibeSpace(id)
        XCTAssertEqual(state.recentVibeSpaceIDs.filter { $0 == id }.count, 1)
    }

    func testAppStateMaxCount() {
        var state = AppStateFile(recentVibeSpaceIDs: (0..<25).map { _ in UUID() })
        state.touchVibeSpace(UUID())
        XCTAssertEqual(state.recentVibeSpaceIDs.count, AppStateFile.maxRecentCount)
    }

    func testAppStatePruneRemovesNonExistent() {
        let existing = UUID()
        let gone = UUID()
        let state = AppStateFile(recentVibeSpaceIDs: [existing, gone])
        let pruned = state.pruned(existingIDs: [existing])
        XCTAssertEqual(pruned.recentVibeSpaceIDs, [existing])
    }

    func testAppStatePrunePreservesDisclaimerAcceptance() {
        let existing = UUID()
        let state = AppStateFile(
            recentVibeSpaceIDs: [existing],
            sidebarWidth: 240,
            hasAcceptedDisclaimer: true
        )

        let pruned = state.pruned(existingIDs: [existing])

        XCTAssertEqual(pruned.hasAcceptedDisclaimer, true)
        XCTAssertEqual(pruned.sidebarWidth, 240)
    }

    func testVibeSpaceConfigFileRoundtrip() throws {
        let config = VibeSpaceConfigFile(
            id: UUID(), name: "Test", projectPaths: ["/a", "/b"],
            unresolvedProjectPaths: ["/c"], focusedProjectPath: "/a",
            startupSettings: .default,
            defaultTerminalShell: .zsh,
            sourceControlSettings: VibeSpaceSourceControlSettings(
                ignoredDirectoryNames: ["DerivedData", "SourcePackages"],
                scanMaxDepth: 6,
                scanMaxRepositories: 24,
                autoPresentedRepositoryLimit: 8
            )
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VibeSpaceConfigFile.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testVibeSpaceConfigFileDecodeRequiresSourceControlSettings() {
        let vibespaceID = UUID()
        let incompleteJSON = """
        {
          "id": "\(vibespaceID.uuidString)",
          "name": "Strict",
          "projectPaths": ["/tmp/project"],
          "unresolvedProjectPaths": [],
          "focusedProjectPath": "/tmp/project",
          "startupSettings": {
            "startupTerminalCount": 1,
            "startupProfiles": [{"presetID": null, "command": ""}],
            "focusTerminalOnProjectSwitch": true
          },
          "version": 2
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(VibeSpaceConfigFile.self, from: Data(incompleteJSON.utf8))
        )
    }

    func testProjectConfigFileRoundtrip() throws {
        let config = ProjectConfigFile(
            projectPath: "/test", colorTag: "#336699", shortcutIndex: 1,
            startupOverride: VibeSpaceProjectStartupOverride(
                startupTerminalCount: 2,
                startupProfiles: [.init(presetID: nil, command: "npm start"), .empty]
            ),
            terminalShellOverride: .bash,
            terminalEntries: [
                TerminalSessionEntry(workingDirectoryPath: "/test", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
                TerminalSessionEntry(workingDirectoryPath: "/test/src", customName: nil, origin: .adHoc),
            ],
            activeTerminalDirectory: "/test",
            activeTerminalIdentity: "active-terminal"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProjectConfigFile.self, from: data)
        XCTAssertEqual(decoded, config)
    }
}

// MARK: - Validator Tests

final class VibeSpaceValidatorTests: XCTestCase {

    func testClampsTerminalCountToRange() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "Test", projectPaths: [], unresolvedProjectPaths: [],
            startupSettings: VibeSpaceStartupSettings(startupTerminalCount: 99, startupProfiles: [], focusTerminalOnProjectSwitch: true)
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertEqual(config.startupSettings.startupTerminalCount, 8)
    }

    func testClampsTerminalCountMinimum() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "Test", projectPaths: [], unresolvedProjectPaths: [],
            startupSettings: VibeSpaceStartupSettings(startupTerminalCount: 0, startupProfiles: [], focusTerminalOnProjectSwitch: true)
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertEqual(config.startupSettings.startupTerminalCount, 1)
    }

    func testPadsProfilesToMatchCount() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "Test", projectPaths: [], unresolvedProjectPaths: [],
            startupSettings: VibeSpaceStartupSettings(startupTerminalCount: 3, startupProfiles: [.empty], focusTerminalOnProjectSwitch: true)
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertEqual(config.startupSettings.startupProfiles.count, 3)
    }

    func testTruncatesExcessProfiles() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "Test", projectPaths: [], unresolvedProjectPaths: [],
            startupSettings: VibeSpaceStartupSettings(startupTerminalCount: 1, startupProfiles: [.empty, .empty, .empty], focusTerminalOnProjectSwitch: true)
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertEqual(config.startupSettings.startupProfiles.count, 1)
    }

    func testEmptyNameDefaultsToUntitled() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "   ", projectPaths: [], unresolvedProjectPaths: [],
            startupSettings: .default
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertEqual(config.name, "Untitled VibeSpace")
    }

    func testNormalizesProjectPaths() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "Test", projectPaths: ["/tmp/../tmp/test"], unresolvedProjectPaths: [],
            startupSettings: .default
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertEqual(config.projectPaths.first, "/tmp/test")
    }

    func testPreservesSSHProjectPaths() {
        let remoteIdentifier = "ssh://user@example.com:22/home/me/project"
        var config = VibeSpaceConfigFile(
            id: UUID(),
            name: "Remote",
            projectPaths: [remoteIdentifier],
            unresolvedProjectPaths: [],
            focusedProjectPath: remoteIdentifier,
            startupSettings: .default
        )

        config = VibeSpaceValidator.validateVibeSpaceConfig(config)

        XCTAssertEqual(config.projectPaths, [remoteIdentifier])
        XCTAssertEqual(config.focusedProjectPath, remoteIdentifier)
    }

    func testNormalizesSourceControlSettings() {
        var config = VibeSpaceConfigFile(
            id: UUID(),
            name: "Test",
            projectPaths: [],
            unresolvedProjectPaths: [],
            startupSettings: .default,
            sourceControlSettings: VibeSpaceSourceControlSettings(
                ignoredDirectoryNames: [" DerivedData ", "sourcepackages", "SourcePackages", ""],
                scanMaxDepth: 99,
                scanMaxRepositories: 0,
                autoPresentedRepositoryLimit: 999
            )
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)

        XCTAssertEqual(config.sourceControlSettings.ignoredDirectoryNames, ["DerivedData", "sourcepackages"])
        XCTAssertEqual(config.sourceControlSettings.scanMaxDepth, VibeSpaceSourceControlSettings.maximumScanDepth)
        XCTAssertEqual(config.sourceControlSettings.scanMaxRepositories, VibeSpaceSourceControlSettings.minimumRepositoryCount)
        XCTAssertEqual(
            config.sourceControlSettings.autoPresentedRepositoryLimit,
            VibeSpaceSourceControlSettings.minimumPresentedRepositoryCount
        )
    }

    func testInvalidShortcutCleared() {
        var project = ProjectConfigFile.empty(projectPath: "/test")
        project.shortcutIndex = 15
        let validated = VibeSpaceValidator.validateProjectConfig(project, validProjectPaths: [])
        XCTAssertNil(validated.shortcutIndex)
    }

    func testDeduplicateShortcuts() {
        var a = ProjectConfigFile.empty(projectPath: "/a")
        a.shortcutIndex = 1
        var b = ProjectConfigFile.empty(projectPath: "/b")
        b.shortcutIndex = 1
        let result = VibeSpaceValidator.deduplicateShortcuts([a, b])
        XCTAssertEqual(result[0].shortcutIndex, 1)
        XCTAssertNil(result[1].shortcutIndex, "Duplicate shortcut should be cleared")
    }
}

// MARK: - Signing Tests

final class IntegritySigningTests: XCTestCase {

    func testSignedRoundtripVerifies() {
        let store = AppPersistenceDataStore(
            appDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let key = SymmetricKey(size: .bits256)
        let fileURL = store.appFileURL(relativePath: "test-signed.json")

        let original = VibeSpaceConfigFile(
            id: UUID(), name: "Signed", projectPaths: ["/test"], unresolvedProjectPaths: [],
            startupSettings: .default
        )
        store.saveWithIntegrity(original, to: fileURL, using: key)

        let result = store.loadWithIntegrity(VibeSpaceConfigFile.self, from: fileURL, using: key)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.verified, "Untampered file should verify")
        XCTAssertEqual(result!.value.name, "Signed")

        // Cleanup
        store.removeFile(at: fileURL)
    }

    func testTamperedFileFailsVerification() throws {
        let store = AppPersistenceDataStore(
            appDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let key = SymmetricKey(size: .bits256)
        let fileURL = store.appFileURL(relativePath: "test-tampered.json")

        let original = VibeSpaceConfigFile(
            id: UUID(), name: "Original", projectPaths: [], unresolvedProjectPaths: [],
            startupSettings: .default
        )
        store.saveWithIntegrity(original, to: fileURL, using: key)

        // Tamper: modify the file on disk
        var fileData = try Data(contentsOf: fileURL)
        var json = try JSONDecoder().decode([String: String].self, from: fileData)
        // Re-encode payload with different content
        var tampered = original
        tampered.name = "HACKED"
        let tamperedPayload = try JSONEncoder().encode(tampered)
        json["payload"] = tamperedPayload.base64EncodedString()
        fileData = try JSONEncoder().encode(json)
        try fileData.write(to: fileURL)

        let result = store.loadWithIntegrity(VibeSpaceConfigFile.self, from: fileURL, using: key)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.verified, "Tampered file should fail verification")
        XCTAssertEqual(result!.value.name, "HACKED", "Tampered content should still be readable")

        store.removeFile(at: fileURL)
    }

    func testWrongKeyFailsVerification() {
        let store = AppPersistenceDataStore(
            appDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let fileURL = store.appFileURL(relativePath: "test-wrongkey.json")

        let original = VibeSpaceConfigFile(
            id: UUID(), name: "Test", projectPaths: [], unresolvedProjectPaths: [],
            startupSettings: .default
        )
        store.saveWithIntegrity(original, to: fileURL, using: key1)

        let result = store.loadWithIntegrity(VibeSpaceConfigFile.self, from: fileURL, using: key2)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.verified, "Wrong key should fail verification")

        store.removeFile(at: fileURL)
    }
}

private final class InMemorySigningKeychainBackend {
    var values: [String: Data] = [:]
}

private struct InMemorySigningKeychain: SigningKeychainStoring {
    let variant: SigningKeychainVariant
    let backend: InMemorySigningKeychainBackend

    func read(account: String) throws -> Data? {
        backend.values["\(variant.service):\(account)"]
    }

    func write(_ data: Data, account: String) throws {
        backend.values["\(variant.service):\(account)"] = data
    }
}

// MARK: - Service Tests

@MainActor
final class VibeSpaceManagementServiceTests: XCTestCase {

    private func makeTempService() -> (VibeSpaceManagementService, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppPersistenceDataStore(appDirectoryURL: tempDir)
        let persistenceStore = VibeSpacePersistenceStore(store: store)
        let service = VibeSpaceManagementService(persistenceStore: persistenceStore)
        return (service, tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func testCreateVibeSpaceReturnsValidConfig() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp")])
        XCTAssertEqual(config.name, "Test")
        XCTAssertEqual(config.projectPaths.count, 1)
        XCTAssertNotNil(config.focusedProjectPath)
    }

    func testCreateVibeSpaceAppearsInRefs() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp")])
        let refs = service.vibespaceRefs()
        XCTAssertTrue(refs.contains(where: { $0.id == config.id }))
    }

    func testCreateVibeSpaceAppearsInRecent() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp")])
        let recent = service.recentVibeSpaceIDs()
        XCTAssertEqual(recent.first, config.id)
    }

    func testDeleteVibeSpaceRemovesEverything() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp")])
        service.deleteVibeSpace(id: config.id)

        XCTAssertNil(service.loadVibeSpace(id: config.id))
        XCTAssertTrue(service.vibespaceRefs().isEmpty)
        XCTAssertTrue(service.recentVibeSpaceIDs().isEmpty)
    }

    func testRenameVibeSpace() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Old", projectURLs: [URL(fileURLWithPath: "/tmp")])
        service.renameVibeSpace(id: config.id, to: "New")
        service.flushAll()

        let loaded = service.loadVibeSpace(id: config.id)
        XCTAssertEqual(loaded?.config.name, "New")
    }

    func testDisclaimerAcceptanceDefaultsToFalse() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        XCTAssertFalse(service.hasAcceptedDisclaimer())
    }

    func testSetAcceptedDisclaimerPersists() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        service.setAcceptedDisclaimer(true)

        XCTAssertTrue(service.hasAcceptedDisclaimer())
    }

    func testClearingAcceptedDisclaimerReturnsToFalse() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        service.setAcceptedDisclaimer(true)
        service.setAcceptedDisclaimer(nil)

        XCTAssertFalse(service.hasAcceptedDisclaimer())
    }

    func testRemoveProjectDeletesProjectFile() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [
            URL(fileURLWithPath: "/tmp/a"),
            URL(fileURLWithPath: "/tmp/b"),
        ])
        service.removeProject(at: "/tmp/a", from: config.id)
        service.flushAll()

        let loaded = service.loadVibeSpace(id: config.id)
        XCTAssertEqual(loaded?.config.projectPaths.count, 1)
        XCTAssertNil(service.loadProjectConfig(forProject: "/tmp/a", in: config.id))
    }

    func testRemoveProjectDeletesProjectShortcuts() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [
            URL(fileURLWithPath: "/tmp/a"),
            URL(fileURLWithPath: "/tmp/b"),
        ])
        let shortcut = TerminalShortcutDefinition(name: "Build", command: "npm run build")
        service.setProjectShortcuts([shortcut], vibespaceID: config.id, projectPath: "/tmp/a")

        XCTAssertEqual(
            service.projectShortcuts(vibespaceID: config.id, projectPath: "/tmp/a"),
            [shortcut]
        )

        service.removeProject(at: "/tmp/a", from: config.id)

        XCTAssertTrue(
            service.projectShortcuts(vibespaceID: config.id, projectPath: "/tmp/a").isEmpty
        )
        XCTAssertNil(service.loadProjectConfig(forProject: "/tmp/a", in: config.id))
    }

    func testSetProjectColorTag() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        service.setProjectColorTag("#FF0000", forProject: "/tmp/a", in: config.id)

        let project = service.loadProjectConfig(forProject: "/tmp/a", in: config.id)
        XCTAssertEqual(project?.colorTag, "#FF0000")
    }

    func testSetProjectShortcut() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        service.setProjectShortcut(3, forProject: "/tmp/a", in: config.id)

        let project = service.loadProjectConfig(forProject: "/tmp/a", in: config.id)
        XCTAssertEqual(project?.shortcutIndex, 3)
    }

    func testLoadVibeSpaceReportsTrustStatus() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp")])
        let loaded = service.loadVibeSpace(id: config.id)
        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded!.trusted, "Freshly created vibespace should be trusted")
    }

    func testLoadVibeSpacePreservesRemoteProjectIdentifiers() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let vibespaceID = UUID()
        let remoteIdentifier = "ssh://user@example.com:22/home/me/project"
        service.saveVibeSpaceConfig(
            VibeSpaceConfigFile(
                id: vibespaceID,
                name: "Remote",
                projectPaths: [remoteIdentifier],
                unresolvedProjectPaths: [],
                focusedProjectPath: remoteIdentifier,
                startupSettings: .default
            )
        )

        let loaded = service.loadVibeSpace(id: vibespaceID)

        XCTAssertEqual(loaded?.config.projectPaths, [remoteIdentifier])
        XCTAssertEqual(loaded?.config.focusedProjectPath, remoteIdentifier)
    }

    func testPruneRemovesInvalidDirectories() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        // Create a vibespace then manually corrupt it
        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp")])
        let store = AppPersistenceDataStore(appDirectoryURL: tempDir)
        let wsDir = tempDir.appendingPathComponent("vibespaces/\(config.id.uuidString)")
        // Remove vibespace.json to simulate corruption
        try? FileManager.default.removeItem(at: wsDir.appendingPathComponent("vibespace.json"))

        service.pruneOnLaunch()

        XCTAssertTrue(service.vibespaceRefs().isEmpty, "Corrupted vibespace should be pruned")
    }

    func testSaveAndLoadProjectSession() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        let entries = [
            TerminalSessionEntry(workingDirectoryPath: "/tmp/a", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start")),
        ]
        service.saveProjectSession(
            entries: entries,
            activeDirectory: "/tmp/a",
            activeIdentity: "active-dev",
            forProject: "/tmp/a",
            in: config.id
        )

        let loaded = service.loadProjectSession(forProject: "/tmp/a", in: config.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.entries.count, 1)
        XCTAssertEqual(loaded?.entries.first?.customName, "Dev")
        XCTAssertEqual(loaded?.activeIdentity, "active-dev")
        XCTAssertTrue(loaded?.trusted ?? false)
    }

    func testLoadProjectSessionMigratesLegacyRemotePathToCanonicalIdentifier() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let vibespace = service.createVibeSpace(name: "Remote", projectURLs: [])
        let canonicalIdentifier = "ssh://testuser@example.com:22/srv/app"
        let legacyRemotePath = "/srv/app"
        let entries = [
            TerminalSessionEntry(
                workingDirectoryPath: legacyRemotePath,
                customName: "Legacy",
                origin: .adHoc,
                tmuxSessionName: "legacy-main"
            )
        ]

        service.saveProjectSession(
            entries: entries,
            activeDirectory: legacyRemotePath,
            activeIdentity: "legacy-active",
            forProject: legacyRemotePath,
            in: vibespace.id
        )

        let loaded = service.loadProjectSession(forProject: canonicalIdentifier, in: vibespace.id)

        XCTAssertEqual(loaded?.entries, entries)
        XCTAssertEqual(loaded?.activeDirectory, legacyRemotePath)
        XCTAssertEqual(loaded?.activeIdentity, "legacy-active")
        XCTAssertNil(service.loadProjectConfig(forProject: legacyRemotePath, in: vibespace.id))
        XCTAssertEqual(
            service.loadProjectConfig(forProject: canonicalIdentifier, in: vibespace.id)?.projectPath,
            canonicalIdentifier
        )
    }

    func testLoadProjectSessionMigratesMalformedNormalizedSSHIdentifierToCanonicalIdentifier() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let vibespace = service.createVibeSpace(name: "Remote", projectURLs: [])
        let canonicalIdentifier = "ssh://testuser@example.com:22/srv/app"
        let malformedIdentifier = URL(fileURLWithPath: canonicalIdentifier).standardizedFileURL.path
        let entries = [
            TerminalSessionEntry(
                workingDirectoryPath: "/srv/app",
                customName: "Legacy",
                origin: .adHoc,
                tmuxSessionName: "legacy-main"
            )
        ]

        service.saveProjectSession(
            entries: entries,
            activeDirectory: "/srv/app",
            activeIdentity: "legacy-active",
            forProject: malformedIdentifier,
            in: vibespace.id
        )

        let loaded = service.loadProjectSession(forProject: canonicalIdentifier, in: vibespace.id)

        XCTAssertEqual(loaded?.entries, entries)
        XCTAssertEqual(loaded?.activeDirectory, "/srv/app")
        XCTAssertEqual(loaded?.activeIdentity, "legacy-active")
        XCTAssertNil(service.loadProjectConfig(forProject: malformedIdentifier, in: vibespace.id))
        XCTAssertEqual(
            service.loadProjectConfig(forProject: canonicalIdentifier, in: vibespace.id)?.projectPath,
            canonicalIdentifier
        )
    }
}

// MARK: - SIGN-003: Untrusted vibespace blocks startup commands

@MainActor
final class VibeSpaceIntegrityBehaviorTests: XCTestCase {

    private func makeTempService() -> (VibeSpaceManagementService, VibeSpacePersistenceStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppPersistenceDataStore(appDirectoryURL: tempDir)
        let persistenceStore = VibeSpacePersistenceStore(store: store)
        let service = VibeSpaceManagementService(persistenceStore: persistenceStore)
        return (service, persistenceStore, tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // SIGN-003: Untrusted vibespace returns trusted=false
    func testTamperedVibeSpaceReturnsTrustedFalse() throws {
        let (service, persistenceStore, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp/a")])

        // Tamper the payload while keeping it decodable so the trust bit is exercised.
        let configURL = persistenceStore.vibespaceConfigURL(for: config.id)
        let wrapperData = try Data(contentsOf: configURL)
        var wrapper = try JSONDecoder().decode([String: String].self, from: wrapperData)
        var tamperedConfig = config
        tamperedConfig.name = "HACKED"
        let tamperedPayload = try JSONEncoder().encode(tamperedConfig)
        wrapper["payload"] = tamperedPayload.base64EncodedString()
        wrapper["signature"] = String(repeating: "0", count: 64)
        try JSONEncoder().encode(wrapper).write(to: configURL)

        let result = service.loadVibeSpace(id: config.id)
        XCTAssertNotNil(result, "Tampered vibespace should still load")
        XCTAssertFalse(result!.trusted, "Tampered vibespace must report trusted=false")
    }

    // SIGN-003: Freshly created vibespace is trusted
    func testFreshVibeSpaceIsTrusted() {
        let (service, _, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Fresh", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        let result = service.loadVibeSpace(id: config.id)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.trusted, "Freshly created vibespace must be trusted")
    }

    // SIGN-004: Re-saving restores trust
    func testResavingRestoresTrust() throws {
        let (service, persistenceStore, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp/a")])

        // Tamper by appending garbage to the file
        let configURL = persistenceStore.vibespaceConfigURL(for: config.id)
        var fileData = try Data(contentsOf: configURL)
        fileData.append(Data("TAMPERED".utf8))
        try fileData.write(to: configURL)

        // Verify untrusted (file can't decode properly after append)
        let untrusted = service.loadVibeSpace(id: config.id)
        // File is corrupted — either nil or untrusted
        XCTAssertTrue(untrusted == nil || untrusted?.trusted == false,
            "Corrupted file should be nil or untrusted")

        // Re-save through service
        service.renameVibeSpace(id: config.id, to: "Re-saved")
        service.flushAll()

        // Now should be trusted again
        let trusted = service.loadVibeSpace(id: config.id)
        XCTAssertNotNil(trusted)
        XCTAssertTrue(trusted?.trusted ?? false, "Re-saved vibespace must be trusted")
    }

    // SIGN-003: Untrusted project session returns trusted=false
    func testTamperedProjectSessionReturnsTrustedFalse() throws {
        let (service, persistenceStore, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        service.saveProjectSession(
            entries: [TerminalSessionEntry(workingDirectoryPath: "/tmp/a", customName: "Dev", origin: .preset(profileIndex: 0, command: "npm start"))],
            activeDirectory: "/tmp/a",
            activeIdentity: "active-dev",
            forProject: "/tmp/a",
            in: config.id
        )

        // Tamper with project config
        let projectURL = persistenceStore.projectConfigURL(for: "/tmp/a", in: config.id)
        if var json = try? JSONSerialization.jsonObject(with: Data(contentsOf: projectURL)) as? [String: Any] {
            json["payload"] = "dGFtcGVyZWQ="
            try JSONSerialization.data(withJSONObject: json).write(to: projectURL)
        }

        let result = service.loadProjectSession(forProject: "/tmp/a", in: config.id)
        // Should either be nil (can't decode tampered payload) or untrusted
        if let result {
            XCTAssertFalse(result.trusted, "Tampered project session must report trusted=false")
        }
        // Either way, the startup command should NOT be blindly trusted
    }
}

// MARK: - TEST-002: Per-project file independence

@MainActor
final class ProjectConfigIndependenceTests: XCTestCase {

    private func makeTempService() -> (VibeSpaceManagementService, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppPersistenceDataStore(appDirectoryURL: tempDir)
        let persistenceStore = VibeSpacePersistenceStore(store: store)
        let service = VibeSpaceManagementService(persistenceStore: persistenceStore)
        return (service, tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // TEST-002: Deleting project file does not affect vibespace.json
    func testDeleteProjectFileDoesNotAffectVibeSpaceConfig() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [
            URL(fileURLWithPath: "/tmp/a"),
            URL(fileURLWithPath: "/tmp/b"),
        ])

        // Set data on project A
        service.setProjectColorTag("#FF0000", forProject: "/tmp/a", in: config.id)
        service.setProjectShortcut(1, forProject: "/tmp/a", in: config.id)

        // Set data on project B
        service.setProjectColorTag("#00FF00", forProject: "/tmp/b", in: config.id)
        service.setProjectShortcut(2, forProject: "/tmp/b", in: config.id)

        // Remove project A
        service.removeProject(at: "/tmp/a", from: config.id)
        service.flushAll()

        // VibeSpace config should still have project B
        let loaded = service.loadVibeSpace(id: config.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.config.projectPaths.count, 1)
        XCTAssertTrue(loaded!.config.projectPaths.contains("/tmp/b"))

        // Project B config should be unaffected
        let projectB = service.loadProjectConfig(forProject: "/tmp/b", in: config.id)
        XCTAssertNotNil(projectB)
        XCTAssertEqual(projectB?.colorTag, "#00FF00")
        XCTAssertEqual(projectB?.shortcutIndex, 2)

        // Project A config should be gone
        let projectA = service.loadProjectConfig(forProject: "/tmp/a", in: config.id)
        XCTAssertNil(projectA, "Deleted project config should not exist")
    }

    // TEST-002: Updating project config does not modify vibespace.json
    func testUpdateProjectConfigDoesNotModifyVibeSpaceConfig() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        let originalName = config.name
        let originalPaths = config.projectPaths

        // Modify project config extensively
        service.setProjectColorTag("#FF0000", forProject: "/tmp/a", in: config.id)
        service.setProjectShortcut(5, forProject: "/tmp/a", in: config.id)
        service.setProjectStartupOverride(
            VibeSpaceProjectStartupOverride(startupTerminalCount: 2, startupProfiles: [.empty, .empty]),
            forProject: "/tmp/a", in: config.id
        )
        service.setProjectTerminalShell(.bash, forProject: "/tmp/a", in: config.id)
        service.saveProjectSession(
            entries: [TerminalSessionEntry(workingDirectoryPath: "/tmp/a", customName: "Dev", origin: .adHoc)],
            activeDirectory: "/tmp/a",
            activeIdentity: "active-dev",
            forProject: "/tmp/a",
            in: config.id
        )

        // VibeSpace config should be unchanged
        let loaded = service.loadVibeSpace(id: config.id)
        XCTAssertEqual(loaded?.config.name, originalName)
        XCTAssertEqual(loaded?.config.projectPaths, originalPaths)
        XCTAssertNil(loaded?.config.defaultTerminalShell, "VibeSpace shell should not change from project shell change")
    }

    // TEST-002: Each project has independent config
    func testProjectConfigsAreIndependent() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Test", projectURLs: [
            URL(fileURLWithPath: "/tmp/a"),
            URL(fileURLWithPath: "/tmp/b"),
            URL(fileURLWithPath: "/tmp/c"),
        ])

        service.setProjectColorTag("#FF0000", forProject: "/tmp/a", in: config.id)
        service.setProjectColorTag("#00FF00", forProject: "/tmp/b", in: config.id)
        // /tmp/c gets no color tag

        let a = service.loadProjectConfig(forProject: "/tmp/a", in: config.id)
        let b = service.loadProjectConfig(forProject: "/tmp/b", in: config.id)
        let c = service.loadProjectConfig(forProject: "/tmp/c", in: config.id)

        XCTAssertEqual(a?.colorTag, "#FF0000")
        XCTAssertEqual(b?.colorTag, "#00FF00")
        XCTAssertNil(c?.colorTag, "Unset project should have nil color tag")

        // Modifying A should not affect B or C
        service.setProjectShortcut(1, forProject: "/tmp/a", in: config.id)
        let bAfter = service.loadProjectConfig(forProject: "/tmp/b", in: config.id)
        XCTAssertNil(bAfter?.shortcutIndex, "Project B shortcut should not be affected by project A change")
    }
}

// MARK: - Additional Validator Edge Cases

final class VibeSpaceValidatorEdgeCaseTests: XCTestCase {

    func testFocusedProjectPathMustBeInProjectPaths() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "Test",
            projectPaths: ["/a", "/b"],
            unresolvedProjectPaths: [],
            focusedProjectPath: "/nonexistent",
            startupSettings: .default
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertEqual(config.focusedProjectPath, "/a",
            "Invalid focused path should fall back to first project")
    }

    func testEmptyProjectPathsFocusedBecomesNil() {
        var config = VibeSpaceConfigFile(
            id: UUID(), name: "Test",
            projectPaths: [],
            unresolvedProjectPaths: [],
            focusedProjectPath: "/gone",
            startupSettings: .default
        )
        config = VibeSpaceValidator.validateVibeSpaceConfig(config)
        XCTAssertNil(config.focusedProjectPath,
            "Focused path should be nil when no projects exist")
    }

    func testValidShortcutPassesThrough() {
        var project = ProjectConfigFile.empty(projectPath: "/test")
        project.shortcutIndex = 9
        let validated = VibeSpaceValidator.validateProjectConfig(project, validProjectPaths: [])
        XCTAssertEqual(validated.shortcutIndex, 9)
    }

    func testShortcutZeroIsInvalid() {
        var project = ProjectConfigFile.empty(projectPath: "/test")
        project.shortcutIndex = 0
        let validated = VibeSpaceValidator.validateProjectConfig(project, validProjectPaths: [])
        XCTAssertNil(validated.shortcutIndex, "Shortcut 0 is out of range 1-9")
    }

    func testNegativeShortcutIsInvalid() {
        var project = ProjectConfigFile.empty(projectPath: "/test")
        project.shortcutIndex = -1
        let validated = VibeSpaceValidator.validateProjectConfig(project, validProjectPaths: [])
        XCTAssertNil(validated.shortcutIndex)
    }
}

// MARK: - App State Edge Cases

final class AppStateEdgeCaseTests: XCTestCase {

    func testRemoveVibeSpaceFromRecent() {
        let a = UUID()
        let b = UUID()
        var state = AppStateFile(recentVibeSpaceIDs: [a, b])
        state.removeVibeSpace(a)
        XCTAssertEqual(state.recentVibeSpaceIDs, [b])
    }

    func testRemoveNonExistentVibeSpaceIsNoOp() {
        let a = UUID()
        var state = AppStateFile(recentVibeSpaceIDs: [a])
        state.removeVibeSpace(UUID())
        XCTAssertEqual(state.recentVibeSpaceIDs, [a])
    }

    func testTouchNewVibeSpaceAddsToFront() {
        let existing = UUID()
        let newID = UUID()
        var state = AppStateFile(recentVibeSpaceIDs: [existing])
        state.touchVibeSpace(newID)
        XCTAssertEqual(state.recentVibeSpaceIDs, [newID, existing])
    }

    func testPruneWithEmptyExistingSetClearsAll() {
        let state = AppStateFile(recentVibeSpaceIDs: [UUID(), UUID()])
        let pruned = state.pruned(existingIDs: [])
        XCTAssertTrue(pruned.recentVibeSpaceIDs.isEmpty)
    }

    func testEmptyStateRoundtrip() throws {
        let state = AppStateFile.empty
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppStateFile.self, from: data)
        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.recentVibeSpaceIDs.isEmpty)
    }
}

final class VibeSpaceShortcutSettingsSupportTests: XCTestCase {

    func testTargetOptionsAppendVibeSpaceSuffixOnlyOnNameCollision() {
        let sharedName = "Client"
        let projects = [
            VibeSpaceSettingsProjectItem(
                id: UUID(),
                title: sharedName,
                path: "/tmp/client-project",
                shortcutIndex: nil,
                colorTag: nil
            ),
            VibeSpaceSettingsProjectItem(
                id: UUID(),
                title: "Zeta",
                path: "/tmp/zeta",
                shortcutIndex: nil,
                colorTag: nil
            ),
        ]

        let options = VibeSpaceShortcutSettingsSupport.targetOptions(
            vibespaceName: sharedName,
            projects: projects
        )

        XCTAssertEqual(options.first?.title, "Client (vs)")
        XCTAssertEqual(options.dropFirst().map(\.title), ["Client", "Zeta"])
    }

    func testTargetOptionsSortProjectsByNameWithoutVibeSpaceSuffixWhenUnique() {
        let projects = [
            VibeSpaceSettingsProjectItem(
                id: UUID(),
                title: "zeta",
                path: "/tmp/zeta",
                shortcutIndex: nil,
                colorTag: nil
            ),
            VibeSpaceSettingsProjectItem(
                id: UUID(),
                title: "Alpha",
                path: "/tmp/alpha",
                shortcutIndex: nil,
                colorTag: nil
            ),
        ]

        let options = VibeSpaceShortcutSettingsSupport.targetOptions(
            vibespaceName: "VibeSpace",
            projects: projects
        )

        XCTAssertEqual(options.map(\.title), ["VibeSpace", "Alpha", "zeta"])
    }

    func testPersistencePlanDropsRemovedProjectRows() {
        let vibespaceShortcut = TerminalShortcutDefinition(name: "Root", command: "pwd")
        let validProjectShortcut = TerminalShortcutDefinition(name: "Build", command: "npm run build")
        let removedProjectShortcut = TerminalShortcutDefinition(name: "Old", command: "make old")

        let rows = [
            VibeSpaceShortcutPersistedRow(
                definition: vibespaceShortcut,
                target: .vibespace
            ),
            VibeSpaceShortcutPersistedRow(
                definition: validProjectShortcut,
                target: .project("/tmp/kept")
            ),
            VibeSpaceShortcutPersistedRow(
                definition: removedProjectShortcut,
                target: .project("/tmp/removed")
            ),
        ]

        let plan = VibeSpaceShortcutSettingsSupport.buildPersistencePlan(
            rows: rows,
            orderedProjectPaths: ["/tmp/kept"]
        )

        XCTAssertEqual(plan.vibespaceShortcuts, [vibespaceShortcut])
        XCTAssertEqual(plan.projectShortcutsByPath["/tmp/kept"], [validProjectShortcut])
        XCTAssertNil(plan.projectShortcutsByPath["/tmp/removed"])
    }

    func testPersistencePlanBucketsRowsByCurrentTarget() {
        let movedShortcut = TerminalShortcutDefinition(name: "Serve", command: "npm run dev")
        let vibespaceShortcut = TerminalShortcutDefinition(name: "Root", command: "pwd")

        let rows = [
            VibeSpaceShortcutPersistedRow(
                definition: movedShortcut,
                target: .project("/tmp/app")
            ),
            VibeSpaceShortcutPersistedRow(
                definition: vibespaceShortcut,
                target: .vibespace
            ),
        ]

        let plan = VibeSpaceShortcutSettingsSupport.buildPersistencePlan(
            rows: rows,
            orderedProjectPaths: ["/tmp/app", "/tmp/other"]
        )

        XCTAssertEqual(plan.vibespaceShortcuts, [vibespaceShortcut])
        XCTAssertEqual(plan.projectShortcutsByPath["/tmp/app"], [movedShortcut])
        XCTAssertEqual(plan.projectShortcutsByPath["/tmp/other"], [])
    }
}

@MainActor
final class AppShellStoreShortcutRoutingTests: XCTestCase {

    func testPresentVibeSpaceSettingsForActiveVibeSpaceCanOpenShortcutsCategory() {
        let store = AppShellStore()
        let vibespaceID = UUID()

        store.selectVibeSpace(vibespaceID)
        store.presentVibeSpaceSettingsForActiveVibeSpace(.shortcuts)

        XCTAssertEqual(
            store.activeSurface,
            .vibespaceSettings(vibespaceID, .shortcuts)
        )
        XCTAssertEqual(store.activeVibeSpaceSettingsCategory, .shortcuts)
    }
}
