import AppKit
import XCTest
@testable import CrispyVibes

@MainActor
final class AppShortcutRoutingTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppShortcutRoutingTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultIncreaseFontSizeAcceptsCommandPlusAlias() throws {
        let event = try keyEvent(
            keyCode: AppShortcutKeyCode.equal,
            modifiers: [.command, .shift],
            characters: "+",
            charactersIgnoringModifiers: "="
        )

        XCTAssertEqual(
            AppShortcutRegistry.action(matching: event, userDefaults: userDefaults),
            .increaseFontSize
        )
    }

    func testDefaultIncreaseFontSizeAcceptsLayoutSpecificPlusKey() throws {
        let event = try keyEvent(
            keyCode: AppShortcutKeyCode.rightBracket,
            modifiers: [.command, .shift],
            characters: "+",
            charactersIgnoringModifiers: "+"
        )

        XCTAssertEqual(
            AppShortcutRegistry.action(matching: event, userDefaults: userDefaults),
            .increaseFontSize
        )
    }

    func testDefaultDecreaseAndResetAcceptLayoutSpecificCharacters() throws {
        let minusEvent = try keyEvent(
            keyCode: AppShortcutKeyCode.leftBracket,
            modifiers: [.command, .shift],
            characters: "-",
            charactersIgnoringModifiers: "-"
        )
        let zeroEvent = try keyEvent(
            keyCode: AppShortcutKeyCode.nine,
            modifiers: [.command],
            characters: "0",
            charactersIgnoringModifiers: "0"
        )

        XCTAssertEqual(
            AppShortcutRegistry.action(matching: minusEvent, userDefaults: userDefaults),
            .decreaseFontSize
        )
        XCTAssertEqual(
            AppShortcutRegistry.action(matching: zeroEvent, userDefaults: userDefaults),
            .resetFontSize
        )
    }

    func testExactCustomBindingOutranksDefaultTextSizeAlias() throws {
        let customBinding = AppShortcutBinding(
            keyCode: AppShortcutKeyCode.equal,
            modifiers: [.command, .shift]
        )
        AppShortcutRegistry.setPreferenceValue(
            AppShortcutPreferenceValue(isEnabled: true, binding: customBinding),
            for: .saveDocument,
            userDefaults: userDefaults
        )
        let plusEvent = try keyEvent(
            keyCode: AppShortcutKeyCode.equal,
            modifiers: [.command, .shift],
            characters: "+",
            charactersIgnoringModifiers: "="
        )

        XCTAssertEqual(
            AppShortcutRegistry.action(matching: plusEvent, userDefaults: userDefaults),
            .saveDocument
        )
    }

    func testCustomIncreaseFontSizeBindingDisablesDefaultPlusAlias() throws {
        let customBinding = AppShortcutBinding(
            keyCode: AppShortcutKeyCode.m,
            modifiers: [.command, .shift]
        )
        AppShortcutRegistry.setPreferenceValue(
            AppShortcutPreferenceValue(isEnabled: true, binding: customBinding),
            for: .increaseFontSize,
            userDefaults: userDefaults
        )
        let defaultPlus = try keyEvent(
            keyCode: AppShortcutKeyCode.equal,
            modifiers: [.command, .shift],
            characters: "+",
            charactersIgnoringModifiers: "="
        )

        XCTAssertNotEqual(
            AppShortcutRegistry.action(matching: defaultPlus, userDefaults: userDefaults),
            .increaseFontSize
        )
        let customEvent = try keyEvent(
            keyCode: AppShortcutKeyCode.m,
            modifiers: [.command, .shift],
            characters: "",
            charactersIgnoringModifiers: ""
        )
        XCTAssertEqual(
            AppShortcutRegistry.action(matching: customEvent, userDefaults: userDefaults),
            .increaseFontSize
        )
    }

    func testCodeFontSizeMutationsClampAndReset() {
        userDefaults.set(
            AppPreferences.maximumCodeFontSize,
            forKey: AppPreferences.codeFontSizeKey
        )
        XCTAssertEqual(
            AppPreferences.adjustCodeFontSize(by: 1, userDefaults: userDefaults),
            AppPreferences.maximumCodeFontSize
        )

        userDefaults.set(
            AppPreferences.minimumCodeFontSize,
            forKey: AppPreferences.codeFontSizeKey
        )
        XCTAssertEqual(
            AppPreferences.adjustCodeFontSize(by: -1, userDefaults: userDefaults),
            AppPreferences.minimumCodeFontSize
        )
        XCTAssertEqual(
            AppPreferences.resetCodeFontSize(userDefaults: userDefaults),
            AppPreferences.defaultCodeFontSize
        )
        XCTAssertEqual(
            Double(AppPreferences.codeFontSize(userDefaults: userDefaults)),
            AppPreferences.defaultCodeFontSize
        )
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        charactersIgnoringModifiers: String
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    func testReservedTextEditingBindingIncludesCommandV() {
        let binding = AppShortcutBinding(keyCode: AppShortcutKeyCode.v, modifiers: [.command])

        XCTAssertTrue(AppShortcutRouting.isReservedTextEditingBinding(binding))
    }

    func testReservedBindingDoesNotInterceptWhenTextViewIsFocused() {
        let binding = AppShortcutBinding(keyCode: AppShortcutKeyCode.v, modifiers: [.command])
        let textView = NSTextView()

        XCTAssertFalse(
            AppShortcutRouting.shouldInterceptAppShortcut(
                binding: binding,
                firstResponder: textView
            )
        )
    }

    func testReservedBindingCanStillInterceptOutsideTextEditing() {
        let binding = AppShortcutBinding(keyCode: AppShortcutKeyCode.v, modifiers: [.command])
        let responder = NSView()

        XCTAssertTrue(
            AppShortcutRouting.shouldInterceptAppShortcut(
                binding: binding,
                firstResponder: responder
            )
        )
    }

    func testNonReservedBindingStillInterceptsInTextView() {
        let binding = AppShortcutBinding(keyCode: AppShortcutKeyCode.d, modifiers: [.command])
        let textView = NSTextView()

        XCTAssertTrue(
            AppShortcutRouting.shouldInterceptAppShortcut(
                binding: binding,
                firstResponder: textView
            )
        )
    }

    func testSettingsStoreRejectsReservedTextEditingBinding() {
        let store = AppShortcutSettingsStore(userDefaults: userDefaults)
        let binding = AppShortcutBinding(keyCode: AppShortcutKeyCode.v, modifiers: [.command])

        store.setBinding(binding, for: .openDetailedVibeSpaceView)

        XCTAssertEqual(store.message, "\"⌘V\" is reserved for text editing.")
        XCTAssertEqual(
            AppShortcutRegistry.binding(for: .openDetailedVibeSpaceView, userDefaults: userDefaults),
            AppShortcutRegistry.descriptor(for: .openDetailedVibeSpaceView).defaultBinding
        )
    }

    func testSettingsStoreAcceptsNonReservedBinding() {
        let store = AppShortcutSettingsStore(userDefaults: userDefaults)
        let binding = AppShortcutBinding(keyCode: AppShortcutKeyCode.a, modifiers: [.command, .option])

        store.setBinding(binding, for: .openDetailedVibeSpaceView)

        XCTAssertNil(store.message)
        XCTAssertEqual(
            AppShortcutRegistry.binding(for: .openDetailedVibeSpaceView, userDefaults: userDefaults),
            binding
        )
    }
}
