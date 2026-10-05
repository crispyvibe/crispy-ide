import AppKit
import Carbon
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

    func test_onlyOneScreenCaptureDescriptorUsesEnabledControlShift4SystemWide() {
        let rows = AppShortcutRegistry.descriptors.filter { $0.section == .screenCapture }
        let defaultBinding = AppShortcutBinding(
            keyCode: AppShortcutKeyCode.four,
            modifiers: [.control, .shift]
        )
        let appleRegionBinding = AppShortcutBinding(
            keyCode: AppShortcutKeyCode.four,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(rows.map(\.action), [.captureScreen])
        XCTAssertEqual(rows[0].scope, .systemWide)
        XCTAssertEqual(rows[0].defaultBinding, defaultBinding)
        XCTAssertEqual(rows[0].defaultBinding?.keyCode, 21)
        XCTAssertEqual(rows[0].defaultBinding?.displayString, "⌃⇧4")
        XCTAssertEqual(
            AppShortcutRegistry.binding(for: .captureScreen, userDefaults: defaults),
            defaultBinding
        )
        XCTAssertNotEqual(defaultBinding, appleRegionBinding)
        XCTAssertTrue(AppShortcutRouting.isReservedAppleScreenshotBinding(appleRegionBinding))
        XCTAssertEqual(GlobalCaptureShortcutCommand.allCases, [.captureScreen])
    }

    func test_compiledDefaultChangeDoesNotOverwriteCustomizedCaptureBinding() throws {
        let customized = AppShortcutPreferenceValue(
            isEnabled: true,
            binding: .init(keyCode: AppShortcutKeyCode.six, modifiers: [.command, .option])
        )
        try storeOverrides(["captureScreen": customized])

        AppShortcutRegistry.migrateLegacyScreenCaptureOverrides(userDefaults: defaults)

        XCTAssertEqual(try loadOverrides(), ["captureScreen": customized])
        XCTAssertEqual(
            AppShortcutRegistry.binding(for: .captureScreen, userDefaults: defaults),
            customized.binding
        )
    }

    func test_captureDefaultDoesNotReserveStandardShiftCommandSSaveAs() throws {
        let saveAsBinding = AppShortcutBinding(
            keyCode: AppShortcutKeyCode.s,
            modifiers: [.command, .shift]
        )
        XCTAssertNotEqual(
            AppShortcutRegistry.descriptor(for: .captureScreen).defaultBinding,
            saveAsBinding
        )

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "S",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: AppShortcutKeyCode.s
        ))
        XCTAssertNil(AppShortcutRegistry.action(matching: event, userDefaults: defaults))
    }

    func test_systemWideActionIsExcludedFromLocalEventMatching() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "4",
            charactersIgnoringModifiers: "4",
            isARepeat: false,
            keyCode: AppShortcutKeyCode.four
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


@MainActor
final class CarbonGlobalCaptureShortcutManagerTests: XCTestCase {
    private final class FakeCarbonAPI {
        var installStatus: OSStatus = noErr
        var registerStatus: OSStatus = noErr
        var unregisterStatus: OSStatus = noErr
        var removeStatus: OSStatus = noErr
        var suppliesHandlerOnInstallFailure = false
        var routedIdentifier = EventHotKeyID(signature: 0x43525350, id: 1)
        private(set) var operations: [String] = []
        private(set) var callback: EventHandlerUPP?
        private(set) var userData: UnsafeMutableRawPointer?
        private(set) var registrationOptions: [OptionBits] = []

        private let handlerReference = OpaquePointer(bitPattern: 0x101)
        private let hotKeyReference = OpaquePointer(bitPattern: 0x202)
        private let eventReference = OpaquePointer(bitPattern: 0x303)

        func makeAPI() -> CarbonGlobalShortcutAPI {
            CarbonGlobalShortcutAPI(
                installEventHandler: { [weak self] _, callback, userData, handler in
                    guard let self else { return OSStatus(eventInternalErr) }
                    operations.append("install")
                    self.callback = callback
                    self.userData = userData
                    if installStatus == noErr || suppliesHandlerOnInstallFailure {
                        handler = handlerReference
                    }
                    return installStatus
                },
                registerEventHotKey: { [weak self] _, _, options, reference in
                    guard let self else { return OSStatus(eventInternalErr) }
                    operations.append("register")
                    registrationOptions.append(options)
                    if registerStatus == noErr {
                        reference = hotKeyReference
                    }
                    return registerStatus
                },
                unregisterEventHotKey: { [weak self] _ in
                    guard let self else { return OSStatus(eventInternalErr) }
                    operations.append("unregister")
                    return unregisterStatus
                },
                removeEventHandler: { [weak self] _ in
                    guard let self else { return OSStatus(eventInternalErr) }
                    operations.append("remove")
                    return removeStatus
                },
                readEventHotKeyID: { [weak self] _, identifier in
                    guard let self else { return OSStatus(eventInternalErr) }
                    operations.append("read")
                    identifier = routedIdentifier
                    return noErr
                }
            )
        }

        func invokeInstalledHandler() throws -> OSStatus {
            let callback = try XCTUnwrap(callback)
            let userData = try XCTUnwrap(userData)
            let eventReference = try XCTUnwrap(eventReference)
            return callback(nil, eventReference, userData)
        }
    }

    private let firstShortcut = GlobalCaptureShortcut(
        keyCode: UInt32(AppShortcutKeyCode.four),
        modifiers: UInt32(controlKey | shiftKey)
    )
    private let secondShortcut = GlobalCaptureShortcut(
        keyCode: 20,
        modifiers: UInt32(cmdKey | optionKey)
    )

    func test_handlerInstallsBeforeRegistrationAndCallbackDispatchesTypedCommand() throws {
        let fake = FakeCarbonAPI()
        var commands: [GlobalCaptureShortcutCommand] = []
        var statuses: [(String, OSStatus)] = []
        let manager = CarbonGlobalCaptureShortcutManager(
            api: fake.makeAPI(),
            statusHandler: { operation, status in
                statuses.append((operation, status))
            },
            commandHandler: { command in
                commands.append(command)
            }
        )
        defer { manager.shutdown() }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))
        XCTAssertEqual(fake.operations, ["install", "register"])
        XCTAssertEqual(statuses.map(\.0), ["InstallEventHandler", "RegisterEventHotKey"])
        XCTAssertEqual(statuses.map(\.1), [noErr, noErr])

        XCTAssertEqual(try fake.invokeInstalledHandler(), noErr)
        XCTAssertEqual(commands, [.captureScreen])
        XCTAssertEqual(fake.operations, ["install", "register", "read"])
    }

    func test_installFailureDoesNotRegisterAndRemovesPartialHandler() {
        let fake = FakeCarbonAPI()
        fake.installStatus = OSStatus(eventInternalErr)
        fake.suppliesHandlerOnInstallFailure = true
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }
        defer { manager.shutdown() }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .failed(firstShortcut))
        XCTAssertEqual(fake.operations, ["install", "remove"])
        XCTAssertEqual(manager.lastInstallEventHandlerStatus, OSStatus(eventInternalErr))
        XCTAssertEqual(manager.lastRemoveEventHandlerStatus, noErr)
    }

    func test_registrationConflictReturnsConflictAndReleasesUnusedHandler() {
        let fake = FakeCarbonAPI()
        fake.registerStatus = OSStatus(eventHotKeyExistsErr)
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }
        defer { manager.shutdown() }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .conflict(firstShortcut))
        XCTAssertEqual(fake.operations, ["install", "register", "remove"])
    }

    func test_registrationFailureReturnsFailedAndReleasesUnusedHandler() {
        let fake = FakeCarbonAPI()
        fake.registerStatus = OSStatus(eventInternalErr)
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }
        defer { manager.shutdown() }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .failed(firstShortcut))
        XCTAssertEqual(fake.operations, ["install", "register", "remove"])
    }

    func test_rebindUnregistersBeforeRegisterAndShutdownReleasesBothResources() {
        let fake = FakeCarbonAPI()
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))
        XCTAssertEqual(manager.rebind(.captureScreen, to: secondShortcut), .registered(secondShortcut))
        manager.shutdown()

        XCTAssertEqual(
            fake.operations,
            ["install", "register", "unregister", "register", "unregister", "remove"]
        )
        XCTAssertEqual(manager.registration(for: .captureScreen), .disabled)
    }

    func test_exactRebindUnregistersBeforeReplacingOwnedHotKey() {
        let fake = FakeCarbonAPI()
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }
        defer { manager.shutdown() }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))
        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))

        XCTAssertEqual(fake.operations, ["install", "register", "unregister", "register"])
    }

    func test_unregisterReleasesHotKeyThenHandlerAndShutdownDoesNotRepeatWork() {
        let fake = FakeCarbonAPI()
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))
        manager.unregister(.captureScreen)
        manager.shutdown()

        XCTAssertEqual(fake.operations, ["install", "register", "unregister", "remove"])
        XCTAssertEqual(manager.registration(for: .captureScreen), .disabled)
    }

    func test_unregisterFailurePreventsReplacementRegistrationAndIsReported() {
        let fake = FakeCarbonAPI()
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }
        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))
        fake.unregisterStatus = OSStatus(eventInternalErr)

        XCTAssertEqual(manager.rebind(.captureScreen, to: secondShortcut), .failed(secondShortcut))
        XCTAssertEqual(fake.operations, ["install", "register", "unregister"])
        XCTAssertEqual(manager.lastUnregisterEventHotKeyStatus, OSStatus(eventInternalErr))

        fake.unregisterStatus = noErr
        manager.shutdown()
    }

    func test_liveCarbonObscureChordConflictsThenShutdownReleasesIt() throws {
        let obscureShortcut = GlobalCaptureShortcut(
            keyCode: 105,
            modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)
        )
        let first = CarbonGlobalCaptureShortcutManager { _ in }
        let second = CarbonGlobalCaptureShortcutManager { _ in }
        defer {
            first.shutdown()
            second.shutdown()
        }

        guard first.rebind(.captureScreen, to: obscureShortcut) == .registered(obscureShortcut) else {
            throw XCTSkip("The obscure Carbon integration-test chord is unavailable on this machine")
        }
        XCTAssertEqual(second.rebind(.captureScreen, to: obscureShortcut), .conflict(obscureShortcut))

        first.shutdown()
        let afterRelease = CarbonGlobalCaptureShortcutManager { _ in }
        defer { afterRelease.shutdown() }
        XCTAssertEqual(afterRelease.rebind(.captureScreen, to: obscureShortcut), .registered(obscureShortcut))
    }

    func test_registrationUsesExclusiveCarbonOwnershipAndReportsDispatchDiagnostics() throws {
        let fake = FakeCarbonAPI()
        var diagnostics: [(String, String, UInt64)] = []
        let manager = CarbonGlobalCaptureShortcutManager(
            api: fake.makeAPI(),
            diagnosticHandler: { diagnostics.append(($0, $1, $2)) },
            commandHandler: { _ in }
        )
        defer { manager.shutdown() }

        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))
        XCTAssertEqual(fake.registrationOptions, [CarbonGlobalCaptureShortcutManager.exclusiveRegistrationOptions])
        XCTAssertEqual(fake.registrationOptions, [OptionBits(kEventHotKeyExclusive)])
        XCTAssertEqual(try fake.invokeInstalledHandler(), noErr)
        XCTAssertEqual(diagnostics.map(\.0), ["hotKeyCallback", "commandDispatch"])
        XCTAssertEqual(diagnostics.map(\.1), ["received", "dispatched"])
        XCTAssertEqual(diagnostics.map(\.2), [1, 1])
    }

    func test_cachedRegistrationWithMissingHandlerOwnershipReportsFailedAndReconciles() {
        let fake = FakeCarbonAPI()
        let manager = CarbonGlobalCaptureShortcutManager(api: fake.makeAPI()) { _ in }
        defer { manager.shutdown() }
        XCTAssertEqual(manager.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))

        manager.simulateMissingEventHandlerOwnershipForTesting()

        XCTAssertEqual(manager.registration(for: .captureScreen), .failed(firstShortcut))
        XCTAssertEqual(fake.operations, ["install", "register", "unregister", "remove"])
    }

    func test_failedHandlerRemovalLeavesSafeRetainedCallbackContextAfterManagerDeinit() throws {
        let fake = FakeCarbonAPI()
        fake.removeStatus = OSStatus(eventInternalErr)
        weak var releasedManager: CarbonGlobalCaptureShortcutManager?
        do {
            var manager: CarbonGlobalCaptureShortcutManager? = CarbonGlobalCaptureShortcutManager(
                api: fake.makeAPI()
            ) { _ in }
            releasedManager = manager
            XCTAssertEqual(manager?.rebind(.captureScreen, to: firstShortcut), .registered(firstShortcut))
            manager?.shutdown()
            manager = nil
        }

        XCTAssertNil(releasedManager)
        XCTAssertEqual(try fake.invokeInstalledHandler(), OSStatus(eventNotHandledErr))
        XCTAssertEqual(fake.operations.filter { $0 == "remove" }.count, 2)
    }

    func test_directCoordinatorCompositionSurvivesFactoryScopeAndDispatchesToSelection() async throws {
        let fake = FakeCarbonAPI()
        let composition = makeCoordinatorComposition(api: fake.makeAPI())
        defer { composition.manager.shutdown() }
        XCTAssertEqual(
            composition.manager.rebind(.captureScreen, to: firstShortcut),
            .registered(firstShortcut)
        )

        XCTAssertEqual(try fake.invokeInstalledHandler(), noErr)
        try await waitForIntegration { composition.selection.selectCount == 1 }
        let counts = await composition.provider.counts()
        XCTAssertEqual(counts.catalog, 1)
        XCTAssertEqual(counts.capture, 0)
        XCTAssertEqual(composition.selection.selectCount, 1)
    }

    func test_realApplicationTargetCarbonEventDispatchesSynchronouslyToCoordinatorOnce() async throws {
        var registrationOptions: [OptionBits] = []
        let fakeHotKeyReference = try XCTUnwrap(OpaquePointer(bitPattern: 0x909))
        let api = CarbonGlobalShortcutAPI(
            installEventHandler: { eventType, callback, userData, handler in
                InstallEventHandler(
                    GetApplicationEventTarget(), callback, 1, &eventType, userData, &handler
                )
            },
            registerEventHotKey: { _, _, options, reference in
                registrationOptions.append(options)
                reference = fakeHotKeyReference
                return noErr
            },
            unregisterEventHotKey: { _ in noErr },
            removeEventHandler: { RemoveEventHandler($0) },
            readEventHotKeyID: { event, identifier in
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
            }
        )
        let composition = makeCoordinatorComposition(api: api)
        defer { composition.manager.shutdown() }
        XCTAssertEqual(
            composition.manager.rebind(.captureScreen, to: firstShortcut),
            .registered(firstShortcut)
        )

        var event: EventRef?
        XCTAssertEqual(
            CreateEvent(
                nil,
                OSType(kEventClassKeyboard),
                UInt32(kEventHotKeyPressed),
                GetCurrentEventTime(),
                EventAttributes(kEventAttributeUserEvent),
                &event
            ),
            noErr
        )
        let createdEvent = try XCTUnwrap(event)
        defer { ReleaseEvent(createdEvent) }
        var identifier = composition.manager.hotKeyID(for: .captureScreen)
        XCTAssertEqual(
            SetEventParameter(
                createdEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                MemoryLayout<EventHotKeyID>.size,
                &identifier
            ),
            noErr
        )

        let sendStatus = SendEventToEventTarget(createdEvent, GetApplicationEventTarget())

        XCTAssertEqual(sendStatus, noErr)
        XCTAssertFalse(composition.coordinator.canBeginCapture)
        XCTAssertEqual(registrationOptions, [OptionBits(kEventHotKeyExclusive)])
        try await waitForIntegration { composition.selection.selectCount == 1 }
        let counts = await composition.provider.counts()
        XCTAssertEqual(counts.catalog, 1)
        XCTAssertEqual(counts.capture, 0)
        XCTAssertEqual(composition.selection.selectCount, 1)
    }

    private final class IntegrationAuthorizer: ScreenCaptureAuthorizing {
        var cachedAuthorizationState: ScreenCaptureAuthorizationState { .granted }
        func authorizationStatus() -> ScreenCaptureAuthorizationState { .granted }
        func requestAuthorization() -> ScreenCaptureAuthorizationState { .granted }
        func openScreenRecordingSettings() {}
    }

    private actor IntegrationProvider: ScreenCaptureProviding {
        private var catalogCount = 0
        private var captureCount = 0
        func catalog() async throws -> ScreenCaptureCatalog {
            catalogCount += 1
            return ScreenCaptureCatalog(generation: 1, displays: [], windows: [])
        }
        func capture(
            selection: CaptureSelectionDescriptor,
            excludingWindowIDs: Set<CGWindowID>
        ) async throws -> CapturedScreenImage {
            captureCount += 1
            throw ScreenCaptureError.captureFailed
        }
        func counts() -> (catalog: Int, capture: Int) { (catalogCount, captureCount) }
    }

    private final class IntegrationPreferences: ScreenCapturePreferencesProviding {
        var screenCapturePreferences: ScreenCapturePreferences = .default
        func updateRememberedMode(_ mode: CaptureMode) {}
    }

    private final class IntegrationSelection: ScreenCaptureSelectionControlling {
        private(set) var selectCount = 0
        func selectTarget(
            from catalog: ScreenCaptureCatalog,
            initialMode: CaptureMode,
            options: CaptureOptions,
            sessionGeneration: UInt64
        ) async throws -> CaptureSelectionDescriptor? {
            selectCount += 1
            return nil
        }
        func dismissSelection() {}
        func shutdown() {}
    }

    private final class IntegrationHiddenToken: ScreenCaptureHiddenSurfaceRestoring {
        func restore() {}
    }

    private final class IntegrationExclusion: ScreenCaptureUIExclusionProviding {
        var excludedCaptureWindowIDs: Set<CGWindowID> = []
        func prepareForCapture() async -> any ScreenCaptureHiddenSurfaceRestoring {
            IntegrationHiddenToken()
        }
    }

    private final class IntegrationStudio: ScreenCaptureStudioRouting {
        func present(_ capture: AcquiredScreenCapture) {}
        func shutdown() {}
    }

    private final class IntegrationOrigin: OriginFocusTracking {
        func captureOrigin() -> OriginFocusContext? { nil }
        func restoreIfNeeded(_ context: OriginFocusContext) {}
    }

    private func makeCoordinatorComposition(
        api: CarbonGlobalShortcutAPI
    ) -> (
        manager: CarbonGlobalCaptureShortcutManager,
        coordinator: ScreenCaptureCoordinator,
        provider: IntegrationProvider,
        selection: IntegrationSelection
    ) {
        let provider = IntegrationProvider()
        let selection = IntegrationSelection()
        let coordinator = ScreenCaptureCoordinator(
            authorizer: IntegrationAuthorizer(),
            provider: provider,
            preferences: IntegrationPreferences(),
            selectionController: selection,
            exclusionProvider: IntegrationExclusion(),
            studioRouter: IntegrationStudio(),
            originTracker: IntegrationOrigin()
        )
        let manager = CarbonGlobalCaptureShortcutManager(api: api) { [weak coordinator] command in
            switch command {
            case .captureScreen:
                coordinator?.beginCapture()
            }
        }
        return (manager, coordinator, provider, selection)
    }

    private func waitForIntegration(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for Carbon coordinator dispatch")
    }
}
