@testable import CrispyVibes
import XCTest

@MainActor
final class DocumentBufferStoreTests: XCTestCase {

    private func makeRef(_ path: String = "/tmp/test.md") -> FileDocumentReference {
        FileDocumentReference(url: URL(fileURLWithPath: path))
    }

    func test_openBuffer_createsNewBuffer() {
        let store = DocumentBufferStore()
        let buf = store.openBuffer(for: makeRef())
        XCTAssertNotNil(store.buffer(for: buf.id))
    }

    func test_openBuffer_reusesExistingAndIncrementsRefCount() {
        let store = DocumentBufferStore()
        let ref = makeRef()
        let buf1 = store.openBuffer(for: ref)
        let buf2 = store.openBuffer(for: ref)
        XCTAssertTrue(buf1 === buf2)
    }

    func test_closeBuffer_decrementsRefCount_bufferSurvives() {
        let store = DocumentBufferStore()
        let ref = makeRef()
        let buf = store.openBuffer(for: ref)
        _ = store.openBuffer(for: ref) // refCount = 2
        store.closeBuffer(id: buf.id)
        XCTAssertNotNil(store.buffer(for: buf.id))
    }

    func test_closeBuffer_removesBufferWhenRefCountReachesZero() {
        let store = DocumentBufferStore()
        let ref = makeRef()
        let buf = store.openBuffer(for: ref)
        store.closeBuffer(id: buf.id)
        XCTAssertNil(store.buffer(for: buf.id))
    }

    func test_closeBuffer_flushesDirtyBufferViaWriter() async {
        let store = DocumentBufferStore()
        let ref = makeRef()
        let buf = store.openBuffer(for: ref)
        buf.didLoad(content: "base")
        buf.applyEdit("dirty")

        let wrote = XCTestExpectation(description: "writer called")
        let task = store.closeBuffer(id: buf.id) { _, _ in
            wrote.fulfill()
        }
        XCTAssertNotNil(task)
        await fulfillment(of: [wrote], timeout: 1)
    }

    func test_closeBuffer_cancelsLoadTaskOnDisposal() {
        let store = DocumentBufferStore()
        let ref = makeRef()
        let buf = store.openBuffer(for: ref)
        // Buffer is still in .loading state — cancelLoad should be called
        store.closeBuffer(id: buf.id)
        XCTAssertNil(store.buffer(for: buf.id))
    }

    func test_bufferFor_returnsCorrectBufferOrNil() {
        let store = DocumentBufferStore()
        XCTAssertNil(store.buffer(for: "nonexistent"))
        let ref = makeRef()
        let buf = store.openBuffer(for: ref)
        XCTAssertTrue(store.buffer(for: buf.id) === buf)
    }

    func test_migrateBuffer_rekeysLiveDirtyBufferWithoutLosingState() {
        let store = DocumentBufferStore()
        let oldReference = makeRef("/tmp/migrate.md")
        let newReference = FileDocumentReference(
            url: oldReference.url,
            projectIdentifier: "/tmp"
        )
        let buffer = store.openBuffer(for: oldReference)
        buffer.didLoad(content: "base")
        buffer.applyEdit("dirty")

        let migrated = store.migrateBuffer(from: oldReference.documentIdentity, to: newReference)

        XCTAssertTrue(migrated === buffer)
        XCTAssertNil(store.buffer(for: oldReference.documentIdentity))
        XCTAssertTrue(store.buffer(for: newReference.documentIdentity) === buffer)
        XCTAssertEqual(buffer.id, newReference.documentIdentity)
        XCTAssertEqual(buffer.displayContent, "dirty")
        XCTAssertTrue(buffer.isDirty)
    }

    func test_migrateBuffer_collisionRemovesOldIdentityAndPreservesUnsavedSource() {
        let store = DocumentBufferStore()
        let oldReference = makeRef("/tmp/collision.md")
        let newReference = FileDocumentReference(
            url: oldReference.url,
            projectIdentifier: "/tmp"
        )
        let oldBuffer = store.openBuffer(for: oldReference)
        oldBuffer.didLoad(content: "base")
        oldBuffer.applyEdit("unsaved source")
        let destinationBuffer = store.openBuffer(for: newReference)
        destinationBuffer.didLoad(content: "base")

        let migrated = store.migrateBuffer(from: oldReference.documentIdentity, to: newReference)

        XCTAssertTrue(migrated === destinationBuffer)
        XCTAssertNil(store.buffer(for: oldReference.documentIdentity))
        XCTAssertEqual(destinationBuffer.displayContent, "unsaved source")
        XCTAssertTrue(destinationBuffer.isDirty)
    }

    func test_migrateBuffer_returnsInFlightSaveToDirtyStateUnderNewIdentity() {
        let store = DocumentBufferStore()
        let oldReference = makeRef("/tmp/saving-migration.md")
        let newReference = FileDocumentReference(
            url: URL(fileURLWithPath: "/tmp/renamed-saving-migration.md")
        )
        let buffer = store.openBuffer(for: oldReference)
        buffer.didLoad(content: "base")
        buffer.applyEdit("saving content")
        XCTAssertNotNil(buffer.beginSave())
        XCTAssertTrue(buffer.isSaving)

        store.migrateBuffer(from: oldReference.documentIdentity, to: newReference)

        XCTAssertNil(buffer.activeSaveToken)
        XCTAssertTrue(buffer.isDirty)
        XCTAssertEqual(buffer.displayContent, "saving content")
        XCTAssertEqual(buffer.id, newReference.documentIdentity)
        XCTAssertEqual(buffer.fileURL, newReference.url)
    }

}
