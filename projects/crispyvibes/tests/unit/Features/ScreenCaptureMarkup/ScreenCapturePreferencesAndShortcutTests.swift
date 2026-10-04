import AppKit
import XCTest
@testable import CrispyVibes

/// F062 preference-v3 and single system-wide shortcut migration coverage.
@MainActor
final class ScreenCapturePreferencesAndShortcutTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ScreenCapturePreferencesAndShortcutTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_schemaV1DecodesFieldByFieldDiscardsBehaviorAndPersistsCanonicalV3() throws {
        let legacy = try JSONSerialization.data(withJSONObject: [
            "mode": "window",
            "options": ["delay": 5, "includesPointer": true],
            "postCaptureBehavior": "quickAccess"
        ])
        defaults.set(legacy, forKey: AppPreferences.screenCapturePreferencesKey)

        let store = ScreenCapturePreferencesStore(userDefaults: defaults)

        XCTAssertEqual(store.screenCapturePreferences.schemaVersion, 3)
        XCTAssertEqual(store.screenCapturePreferences.mode, .window)
        XCTAssertEqual(store.screenCapturePreferences.options.delay, .fiveSeconds)
        XCTAssertTrue(store.screenCapturePreferences.options.includesPointer)
        try assertCanonicalV3(defaults.data(forKey: AppPreferences.screenCapturePreferencesKey))
    }

    func test_schemaV2MalformedDelayStillPreservesIndependentModeAndPointerFields() throws {
        let legacy = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "mode": "display",
            "options": ["delay": 99, "includesPointer": true],
            "postCaptureBehavior": "copyImmediately"
        ])
        defaults.set(legacy, forKey: AppPreferences.screenCapturePreferencesKey)

        let restored = ScreenCapturePreferencesStore(userDefaults: defaults)

        XCTAssertEqual(restored.screenCapturePreferences.mode, .display)
        XCTAssertEqual(restored.screenCapturePreferences.options.delay, .none)
        XCTAssertTrue(restored.screenCapturePreferences.options.includesPointer)
        try assertCanonicalV3(defaults.data(forKey: AppPreferences.screenCapturePreferencesKey))
    }

    func test_schemaV3PersistsOnlySchemaModeDelayAndPointer() throws {
        let preferences = ScreenCapturePreferences(
            mode: .region,
            options: .init(delay: .tenSeconds, includesPointer: true)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "mode", "delay", "includesPointer"])
        XCTAssertNil(object["postCaptureBehavior"])
        XCTAssertNil(object["options"])
    }

    func test_existingCaptureScreenDisabledOverrideWinsAndLegacyKeysAreRemoved() throws {
        let existing = AppShortcutPreferenceValue(isEnabled: false, binding: nil)
        let legacy = AppShortcutPreferenceValue(
            isEnabled: true,
            binding: .init(keyCode: AppShortcutKeyCode.six, modifiers: [.command, .shift])
        )
        try storeOverrides([
            "captureScreen": existing,
            "captureAndMarkup": legacy,
            "captureToClipboard": legacy,
            "repeatLastArea": legacy
        ])

        AppShortcutRegistry.migrateLegacyScreenCaptureOverrides(userDefaults: defaults)
        AppShortcutRegistry.migrateLegacyScreenCaptureOverrides(userDefaults: defaults)

        let migrated = try loadOverrides()
        XCTAssertEqual(migrated, ["captureScreen": existing])
        XCTAssertNil(AppShortcutRegistry.binding(for: .captureScreen, userDefaults: defaults))
    }

    func test_missingCaptureScreenAdoptsFirstEnabledLegacyBinding() throws {
        let markup = AppShortcutPreferenceValue(
            isEnabled: true,
            binding: .init(keyCode: AppShortcutKeyCode.six, modifiers: [.command, .shift])
        )
        let clipboard = AppShortcutPreferenceValue(
            isEnabled: true,
            binding: .init(keyCode: AppShortcutKeyCode.seven, modifiers: [.command, .shift])
        )
        try storeOverrides([
            "captureAndMarkup": markup,
            "captureToClipboard": clipboard,
            "repeatLastArea": .init(isEnabled: true, binding: nil)
        ])

        AppShortcutRegistry.migrateLegacyScreenCaptureOverrides(userDefaults: defaults)

        XCTAssertEqual(try loadOverrides(), ["captureScreen": markup])
    }

    func test_disabledMarkupFallsThroughToEnabledClipboardBinding() throws {
        let clipboard = AppShortcutPreferenceValue(
            isEnabled: true,
            binding: .init(keyCode: AppShortcutKeyCode.eight, modifiers: [.command, .shift])
        )
        try storeOverrides([
            "captureAndMarkup": .init(isEnabled: false, binding: nil),
            "captureToClipboard": clipboard
        ])

        AppShortcutRegistry.migrateLegacyScreenCaptureOverrides(userDefaults: defaults)

        XCTAssertEqual(try loadOverrides(), ["captureScreen": clipboard])
    }

    func test_onlyOneScreenCaptureDescriptorUsesEnabledShiftCommand2SystemWide() {
        let rows = AppShortcutRegistry.descriptors.filter { $0.section == .screenCapture }
        XCTAssertEqual(rows.map(\.action), [.captureScreen])
        XCTAssertEqual(rows[0].scope, .systemWide)
        XCTAssertEqual(rows[0].defaultBinding, AppShortcutBinding(
            keyCode: AppShortcutKeyCode.two,
            modifiers: [.command, .shift]
        ))
        XCTAssertEqual(GlobalCaptureShortcutCommand.allCases, [.captureScreen])
    }

    func test_systemWideActionIsExcludedFromLocalEventMatching() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "@",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: AppShortcutKeyCode.two
        ))
        XCTAssertNil(AppShortcutRegistry.action(matching: event, userDefaults: defaults))
    }

    func test_settingsLoadUsesCachedPermissionWithoutTCCProbe() {
        var preflightCount = 0
        let history = UserDefaultsScreenCaptureAuthorizationHistoryStore(
            defaults: defaults,
            key: "test.authorizationHistory"
        )
        let authorizer = ScreenCaptureTCCAuthorizer(
            historyStore: history,
            preflightAccess: { preflightCount += 1; return false },
            requestAccess: { XCTFail("Settings must not request access"); return false },
            openSettings: { _ in }
        )
        let viewModel = ScreenCaptureSettingsViewModel(
            preferenceStore: ScreenCapturePreferencesStore(userDefaults: defaults),
            authorizer: authorizer,
            registrationProvider: { .disabled },
            historyStore: ScreenCaptureHistoryStore(repository: EmptyRepository()),
            clearHistory: {}
        )

        XCTAssertEqual(preflightCount, 0)
        XCTAssertEqual(viewModel.authorizationState, .undetermined)
        viewModel.refreshRegistrationStatus()
        XCTAssertEqual(preflightCount, 0)
        viewModel.recheckPermission()
        XCTAssertEqual(preflightCount, 1)
    }

    func test_preferencesPersistRememberedModeDelayAndPointer() {
        var store: ScreenCapturePreferencesStore? = ScreenCapturePreferencesStore(userDefaults: defaults)
        store?.updateRememberedMode(.window)
        store?.updateDelay(.fiveSeconds)
        store?.updateIncludesPointer(true)
        store = nil

        let restored = ScreenCapturePreferencesStore(userDefaults: defaults)
        XCTAssertEqual(restored.screenCapturePreferences.mode, .window)
        XCTAssertEqual(restored.screenCapturePreferences.options.delay, .fiveSeconds)
        XCTAssertTrue(restored.screenCapturePreferences.options.includesPointer)
    }

    private func assertCanonicalV3(_ data: Data?) throws {
        let data = try XCTUnwrap(data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "mode", "delay", "includesPointer"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 3)
    }

    private func storeOverrides(_ values: [String: AppShortcutPreferenceValue]) throws {
        defaults.set(try JSONEncoder().encode(values), forKey: AppPreferences.appShortcutOverridesKey)
    }

    private func loadOverrides() throws -> [String: AppShortcutPreferenceValue] {
        let data = try XCTUnwrap(defaults.data(forKey: AppPreferences.appShortcutOverridesKey))
        return try JSONDecoder().decode([String: AppShortcutPreferenceValue].self, from: data)
    }
}

private actor EmptyRepository: ScreenCaptureHistoryRepository {
    func loadEntries() async throws -> [ScreenCaptureHistoryEntry] { [] }
    func add(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        throw ScreenCaptureHistoryError.fileOperationFailed
    }
    func update(id: UUID, content: ScreenCaptureHistoryContent) async throws -> ScreenCaptureHistoryEntry {
        throw ScreenCaptureHistoryError.fileOperationFailed
    }
    func thumbnail(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        throw ScreenCaptureHistoryError.itemNotFound
    }
    func flattenedSource(for id: UUID) async throws -> ScreenCaptureHistoryImage {
        throw ScreenCaptureHistoryError.itemNotFound
    }
    func delete(id: UUID) async throws { throw ScreenCaptureHistoryError.itemNotFound }
    func clear() async throws {}
}
