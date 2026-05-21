import XCTest
@testable import CrispyVibes

final class GitHeadWatcherTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitHeadWatcherTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Basic notification

    func testNotifiesOnFileWrite() throws {
        let filePath = tempDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(to: filePath, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "onChange called")
        let watcher = GitHeadWatcher(path: filePath.path) {
            expectation.fulfill()
        }

        try "ref: refs/heads/feature\n".write(to: filePath, atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 2)
        watcher.invalidate()
    }

    // MARK: - Survives atomic rename (git's write pattern)

    func testNotifiesAfterAtomicRename() throws {
        let filePath = tempDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(to: filePath, atomically: true, encoding: .utf8)

        let firstChange = expectation(description: "first change")
        let secondChange = expectation(description: "second change")
        var callCount = 0
        let watcher = GitHeadWatcher(path: filePath.path) {
            callCount += 1
            if callCount == 1 { firstChange.fulfill() }
            if callCount >= 2 { secondChange.fulfill() }
        }

        // First rename (simulates git checkout)
        let tmp1 = tempDir.appendingPathComponent("HEAD.lock1")
        try "ref: refs/heads/feature-a\n".write(to: tmp1, atomically: false, encoding: .utf8)
        _ = rename(tmp1.path, filePath.path)

        wait(for: [firstChange], timeout: 2)

        // Wait for watcher to re-attach after rename
        let reattach = expectation(description: "reattach delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reattach.fulfill() }
        wait(for: [reattach], timeout: 1)

        // Second rename — watcher must have re-attached to new inode
        let tmp2 = tempDir.appendingPathComponent("HEAD.lock2")
        try "ref: refs/heads/feature-b\n".write(to: tmp2, atomically: false, encoding: .utf8)
        _ = rename(tmp2.path, filePath.path)

        wait(for: [secondChange], timeout: 2)
        watcher.invalidate()
    }

    // MARK: - Invalidation stops notifications

    func testInvalidateStopsNotifications() throws {
        let filePath = tempDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(to: filePath, atomically: true, encoding: .utf8)

        var called = false
        let watcher = GitHeadWatcher(path: filePath.path) {
            called = true
        }
        watcher.invalidate()

        try "ref: refs/heads/other\n".write(to: filePath, atomically: true, encoding: .utf8)

        let delay = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { delay.fulfill() }
        wait(for: [delay], timeout: 1)

        XCTAssertFalse(called)
    }

    // MARK: - Non-existent file

    func testNonExistentFileDoesNotCrash() {
        let bogusPath = tempDir.appendingPathComponent("does-not-exist").path
        let watcher = GitHeadWatcher(path: bogusPath) {}
        watcher.invalidate()
    }
}
