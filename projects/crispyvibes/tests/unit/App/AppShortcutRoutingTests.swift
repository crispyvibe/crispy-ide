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
