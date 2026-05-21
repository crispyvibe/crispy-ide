@testable import CrispyVibes
import XCTest

@MainActor
final class AutosaveSchedulerTests: XCTestCase {

    private func makeBuffer(content: String = "base") -> DocumentBuffer {
        let buf = DocumentBuffer(id: "test", fileURL: URL(fileURLWithPath: "/tmp/test.md"))
        buf.didLoad(content: content)
        return buf
    }

    func test_scheduleSave_firesWriter() async {
        let wrote = XCTestExpectation(description: "writer called")
        let scheduler = AutosaveScheduler(delay: 0.01) { _, _ in
            wrote.fulfill()
        }
        let buf = makeBuffer()
        buf.applyEdit("dirty")
        scheduler.scheduleSave(for: buf)
        await fulfillment(of: [wrote], timeout: 1)
        XCTAssertFalse(buf.isDirty)
    }

    func test_scheduleSave_noopForNonDirtyBuffer() {
        let wrote = XCTestExpectation(description: "should not fire")
        wrote.isInverted = true
        let scheduler = AutosaveScheduler(delay: 0.01) { _, _ in
            wrote.fulfill()
        }
        let buf = makeBuffer()
        scheduler.scheduleSave(for: buf)
        wait(for: [wrote], timeout: 0.1)
    }

    func test_cancel_preventsPendingSave() {
        let wrote = XCTestExpectation(description: "should not fire")
        wrote.isInverted = true
        let scheduler = AutosaveScheduler(delay: 0.05) { _, _ in
            wrote.fulfill()
        }
        let buf = makeBuffer()
        buf.applyEdit("dirty")
        scheduler.scheduleSave(for: buf)
        scheduler.cancel(for: buf.id)
        wait(for: [wrote], timeout: 0.15)
    }

    func test_cancelAll_cancelsEverything() {
        let wrote = XCTestExpectation(description: "should not fire")
        wrote.isInverted = true
        let scheduler = AutosaveScheduler(delay: 0.05) { _, _ in
            wrote.fulfill()
        }
        let buf = makeBuffer()
        buf.applyEdit("dirty")
        scheduler.scheduleSave(for: buf)
        scheduler.cancelAll()
        wait(for: [wrote], timeout: 0.15)
    }

    func test_contentIntegrityGuard_rejectsEmptyContentWhenBaselineNonEmpty() async {
        let wrote = XCTestExpectation(description: "should not write")
        wrote.isInverted = true
        let scheduler = AutosaveScheduler(delay: 0.01) { _, _ in
            wrote.fulfill()
        }
        let buf = makeBuffer(content: "non-empty")
        buf.applyEdit("")
        scheduler.scheduleSave(for: buf)

        // Wait for scheduler to fire and reject
        let delay = XCTestExpectation(description: "delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { delay.fulfill() }
        await fulfillment(of: [delay], timeout: 1)

        // Writer never called; buffer remains dirty (save was rejected)
        XCTAssertTrue(buf.isDirty)
        wait(for: [wrote], timeout: 0.01)
    }

    func test_contentIntegrityGuard_allowsSaveWhenBaselineEmpty() async {
        let wrote = XCTestExpectation(description: "writer called")
        let scheduler = AutosaveScheduler(delay: 0.01) { _, _ in
            wrote.fulfill()
        }
        // Baseline is empty, content is non-empty → guard should not block
        let buf = makeBuffer(content: "")
        buf.applyEdit("new content")
        scheduler.scheduleSave(for: buf)
        await fulfillment(of: [wrote], timeout: 1)
        XCTAssertFalse(buf.isDirty)
    }
}
