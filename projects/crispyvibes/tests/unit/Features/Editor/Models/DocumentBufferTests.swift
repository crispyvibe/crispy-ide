@testable import CrispyVibes
import XCTest

@MainActor
final class DocumentBufferTests: XCTestCase {

    private func makeBuffer() -> DocumentBuffer {
        DocumentBuffer(id: "test", fileURL: URL(fileURLWithPath: "/tmp/test.md"))
    }

    // MARK: - Load Transitions

    func test_didLoad_transitionsLoadingToClean() {
        let buf = makeBuffer()
        buf.didLoad(content: "hello")
        XCTAssertEqual(buf.state, .clean(content: "hello"))
    }

    func test_didFailLoad_transitionsLoadingToFailed() {
        let buf = makeBuffer()
        buf.didFailLoad(message: "oops")
        XCTAssertEqual(buf.state, .failed(message: "oops"))
    }

    // MARK: - Edit Transitions

    func test_applyEdit_cleanToDirty() {
        let buf = makeBuffer()
        buf.didLoad(content: "original")
        buf.applyEdit("changed")
        XCTAssertEqual(buf.state, .dirty(content: "changed", baseline: "original"))
    }

    func test_applyEdit_cleanSameContentIsNoop() {
        let buf = makeBuffer()
        buf.didLoad(content: "same")
        buf.applyEdit("same")
        XCTAssertEqual(buf.state, .clean(content: "same"))
    }

    func test_applyEdit_dirtyToCleanWhenMatchingBaseline() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("edited")
        buf.applyEdit("base")
        XCTAssertEqual(buf.state, .clean(content: "base"))
    }

    func test_applyEdit_dirtyToDirtyWithNewContent() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("v1")
        buf.applyEdit("v2")
        XCTAssertEqual(buf.state, .dirty(content: "v2", baseline: "base"))
    }

    func test_applyEdit_loadingIsNoop() {
        let buf = makeBuffer()
        buf.applyEdit("ignored")
        XCTAssertEqual(buf.state, .loading)
    }

    // MARK: - Save Transitions

    func test_beginSave_dirtyToSaving() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("dirty")
        let token = buf.beginSave()
        XCTAssertNotNil(token)
        XCTAssertEqual(token?.content, "dirty")
        XCTAssertEqual(buf.state, .saving(content: "dirty", baseline: "base", token: token!))
    }

    func test_beginSave_returnsNilWhenNotDirty() {
        let buf = makeBuffer()
        // still loading
        XCTAssertNil(buf.beginSave())
        buf.didLoad(content: "clean")
        // clean state
        XCTAssertNil(buf.beginSave())
    }

    func test_didSave_savingToClean() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("saved")
        let token = buf.beginSave()!
        buf.didSave(token: token)
        XCTAssertEqual(buf.state, .clean(content: "saved"))
        XCTAssertNil(buf.activeSaveToken)
    }

    func test_didSave_editDuringSaveUpdatesBaseline() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("v1")
        let token = buf.beginSave()!
        // edit arrives during save
        buf.applyEdit("v2")
        XCTAssertTrue(buf.isDirty)
        buf.didSave(token: token)
        // baseline updated to saved content, still dirty with v2
        XCTAssertEqual(buf.state, .dirty(content: "v2", baseline: "v1"))
    }

    func test_didFailSave_savingToDirty() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("dirty")
        let token = buf.beginSave()!
        buf.didFailSave(token: token)
        XCTAssertEqual(buf.state, .dirty(content: "dirty", baseline: "base"))
        XCTAssertNil(buf.activeSaveToken)
    }

    func test_didSave_staleTokenIgnored() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("dirty")
        let token = buf.beginSave()!
        let stale = SaveToken(id: UUID(), content: "stale")
        buf.didSave(token: stale)
        // state unchanged — still saving
        XCTAssertEqual(buf.state, .saving(content: "dirty", baseline: "base", token: token))
    }

    // MARK: - External

    func test_externalContentChanged_updatesClean() {
        let buf = makeBuffer()
        buf.didLoad(content: "old")
        buf.externalContentChanged("new")
        XCTAssertEqual(buf.state, .clean(content: "new"))
    }

    func test_externalContentChanged_rejectedWhenDirty() {
        let buf = makeBuffer()
        buf.didLoad(content: "base")
        buf.applyEdit("dirty")
        buf.externalContentChanged("external")
        XCTAssertEqual(buf.state, .dirty(content: "dirty", baseline: "base"))
    }

    // MARK: - Reload

    func test_beginReload_cancelsAndRestarts() async {
        let buf = makeBuffer()
        buf.didLoad(content: "old")

        let expectation = XCTestExpectation(description: "reload completes")
        buf.beginReload { [expectation] in
            expectation.fulfill()
            return "reloaded"
        }
        XCTAssertEqual(buf.state, .loading)
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(buf.state, .clean(content: "reloaded"))
    }

    // MARK: - Computed Properties

    func test_displayContent_perState() {
        let buf = makeBuffer()
        // loading
        XCTAssertEqual(buf.displayContent, "")

        buf.didLoad(content: "clean")
        XCTAssertEqual(buf.displayContent, "clean")

        buf.applyEdit("dirty")
        XCTAssertEqual(buf.displayContent, "dirty")

        let token = buf.beginSave()!
        XCTAssertEqual(buf.displayContent, "dirty")

        buf.didFailSave(token: token)
        buf.didLoad(content: "ignored") // no-op, not loading
        // still dirty
        XCTAssertEqual(buf.displayContent, "dirty")
    }

    func test_displayContent_failedReturnsEmpty() {
        let buf = makeBuffer()
        buf.didFailLoad(message: "err")
        XCTAssertEqual(buf.displayContent, "")
    }

    func test_isDirty() {
        let buf = makeBuffer()
        XCTAssertFalse(buf.isDirty)
        buf.didLoad(content: "c")
        XCTAssertFalse(buf.isDirty)
        buf.applyEdit("d")
        XCTAssertTrue(buf.isDirty)
    }

    func test_isLoading() {
        let buf = makeBuffer()
        XCTAssertTrue(buf.isLoading)
        buf.didLoad(content: "c")
        XCTAssertFalse(buf.isLoading)
    }

    func test_isFailed() {
        let buf = makeBuffer()
        XCTAssertFalse(buf.isFailed)
        buf.didFailLoad(message: "e")
        XCTAssertTrue(buf.isFailed)
    }

    func test_baseline() {
        let buf = makeBuffer()
        XCTAssertNil(buf.baseline)
        buf.didLoad(content: "base")
        XCTAssertNil(buf.baseline) // clean has no baseline property
        buf.applyEdit("dirty")
        XCTAssertEqual(buf.baseline, "base")
        let token = buf.beginSave()!
        XCTAssertEqual(buf.baseline, "base")
        buf.didSave(token: token)
        XCTAssertNil(buf.baseline) // back to clean
    }
}
