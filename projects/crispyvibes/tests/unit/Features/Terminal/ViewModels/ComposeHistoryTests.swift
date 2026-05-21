import XCTest
@testable import CrispyVibes

@MainActor
final class ComposeHistoryStoreTests: XCTestCase {
    func testAppendAndRetrieve() {
        let store = ComposeHistoryStore()
        let key = UUID()
        store.append("ls", for: key)
        store.append("pwd", for: key)
        XCTAssertEqual(store.entries(for: key), ["ls", "pwd"])
    }

    func testDeduplicatesConsecutive() {
        let store = ComposeHistoryStore()
        let key = UUID()
        store.append("ls", for: key)
        store.append("ls", for: key)
        store.append("pwd", for: key)
        store.append("ls", for: key)
        XCTAssertEqual(store.entries(for: key), ["ls", "pwd", "ls"])
    }

    func testIgnoresEmptyAndWhitespace() {
        let store = ComposeHistoryStore()
        let key = UUID()
        store.append("", for: key)
        store.append("   ", for: key)
        store.append("\n", for: key)
        XCTAssertEqual(store.entries(for: key), [])
    }

    func testTrimsBeforeStoring() {
        let store = ComposeHistoryStore()
        let key = UUID()
        store.append("  ls  ", for: key)
        XCTAssertEqual(store.entries(for: key), ["ls"])
    }

    func testCapEnforced() {
        let store = ComposeHistoryStore(maxEntriesPerBucket: 3)
        let key = UUID()
        store.append("a", for: key)
        store.append("b", for: key)
        store.append("c", for: key)
        store.append("d", for: key)
        XCTAssertEqual(store.entries(for: key), ["b", "c", "d"])
    }

    func testClearRemovesBucket() {
        let store = ComposeHistoryStore()
        let key = UUID()
        store.append("ls", for: key)
        store.clear(for: key)
        XCTAssertEqual(store.entries(for: key), [])
    }

    func testBucketsAreIsolated() {
        let store = ComposeHistoryStore()
        let key1 = UUID()
        let key2 = UUID()
        store.append("a", for: key1)
        store.append("b", for: key2)
        XCTAssertEqual(store.entries(for: key1), ["a"])
        XCTAssertEqual(store.entries(for: key2), ["b"])
    }
}

@MainActor
final class ComposeHistoryNavigatorTests: XCTestCase {
    private func makeNavigator(entries: [String] = []) -> (ComposeHistoryNavigator, UUID) {
        let store = ComposeHistoryStore()
        let key = UUID()
        for entry in entries { store.append(entry, for: key) }
        let nav = ComposeHistoryNavigator(store: store)
        nav.attach(to: key)
        return (nav, key)
    }

    // MARK: - Empty history

    func testNavigateBackEmptyHistory() {
        let (nav, _) = makeNavigator()
        let result = nav.navigateBack(currentText: "draft")
        XCTAssertEqual(result, .noChange)
    }

    func testNavigateForwardWhenIdle() {
        let (nav, _) = makeNavigator(entries: ["ls"])
        let result = nav.navigateForward(currentText: "draft")
        XCTAssertEqual(result, .noChange)
    }

    // MARK: - Single entry

    func testSingleEntryRecallAndRestore() {
        let (nav, _) = makeNavigator(entries: ["ls"])
        let back = nav.navigateBack(currentText: "draft")
        XCTAssertEqual(back, .replace(text: "ls"))

        let forward = nav.navigateForward(currentText: "ls")
        XCTAssertEqual(forward, .replace(text: "draft"))

        // Now idle again
        let forwardAgain = nav.navigateForward(currentText: "draft")
        XCTAssertEqual(forwardAgain, .noChange)
    }

    // MARK: - Multiple entries

    func testMultipleEntriesTraversal() {
        let (nav, _) = makeNavigator(entries: ["a", "b", "c"])

        XCTAssertEqual(nav.navigateBack(currentText: "draft"), .replace(text: "c"))
        XCTAssertEqual(nav.navigateBack(currentText: "c"), .replace(text: "b"))
        XCTAssertEqual(nav.navigateBack(currentText: "b"), .replace(text: "a"))
        XCTAssertEqual(nav.navigateBack(currentText: "a"), .noChange) // at oldest

        XCTAssertEqual(nav.navigateForward(currentText: "a"), .replace(text: "b"))
        XCTAssertEqual(nav.navigateForward(currentText: "b"), .replace(text: "c"))
        XCTAssertEqual(nav.navigateForward(currentText: "c"), .replace(text: "draft"))
    }

    // MARK: - Reset on edit

    func testResetOnUnrelatedEdit() {
        let (nav, _) = makeNavigator(entries: ["a", "b"])
        _ = nav.navigateBack(currentText: "draft")
        nav.resetOnUnrelatedEdit()

        // Next back starts fresh from newest
        XCTAssertEqual(nav.navigateBack(currentText: "edited"), .replace(text: "b"))
    }

    func testResetDoesNotFireWhenIdle() {
        let (nav, _) = makeNavigator(entries: ["a"])
        nav.resetOnUnrelatedEdit() // should be no-op, no crash
        XCTAssertEqual(nav.navigateBack(currentText: "x"), .replace(text: "a"))
    }

    // MARK: - Append clears state

    func testAppendClearsPendingDraft() {
        let (nav, _) = makeNavigator(entries: ["a"])
        _ = nav.navigateBack(currentText: "draft A")
        nav.append("sent")

        // After send, navigating back should show "sent" (newest), not "draft A"
        let back = nav.navigateBack(currentText: "")
        XCTAssertEqual(back, .replace(text: "sent"))

        // Forward exits to empty (the current text at time of entering history), not "draft A"
        let forward = nav.navigateForward(currentText: "sent")
        XCTAssertEqual(forward, .replace(text: ""))
    }

    // MARK: - Attach resets

    func testAttachToNewKeyResetsState() {
        let (nav, _) = makeNavigator(entries: ["a", "b"])
        _ = nav.navigateBack(currentText: "draft")

        let newKey = UUID()
        nav.attach(to: newKey)

        // History for new key is empty
        XCTAssertEqual(nav.navigateBack(currentText: "x"), .noChange)
    }

    func testAttachToSameKeyIsNoOp() {
        let store = ComposeHistoryStore()
        let key = UUID()
        store.append("a", for: key)
        let nav = ComposeHistoryNavigator(store: store)
        nav.attach(to: key)
        _ = nav.navigateBack(currentText: "draft")

        // Re-attach to same key should NOT reset
        nav.attach(to: key)
        // Still in browsing state — forward should work
        XCTAssertEqual(nav.navigateForward(currentText: "a"), .replace(text: "draft"))
    }

    // MARK: - isApplyingNavigation flag

    func testIsApplyingNavigationDuringReplace() {
        let (nav, _) = makeNavigator(entries: ["a"])
        XCTAssertFalse(nav.isApplyingNavigation)
        // The flag is set synchronously during navigateBack/Forward but reset before return.
        // We can't observe it mid-call in a unit test, but we can verify it's false after.
        _ = nav.navigateBack(currentText: "x")
        XCTAssertFalse(nav.isApplyingNavigation)
    }
}
