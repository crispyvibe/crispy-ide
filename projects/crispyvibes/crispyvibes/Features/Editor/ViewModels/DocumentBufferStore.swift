import Foundation

/// Reference-counted store of open document buffers.
///
/// Multiple tabs can share the same buffer. The buffer is created on first
/// open and removed when the last reference closes.
@MainActor
final class DocumentBufferStore: ObservableObject {

    /// All currently open buffers keyed by document identity.
    @Published private(set) var buffers: [String: DocumentBuffer] = [:]

    private var refCounts: [String: Int] = [:]

    /// Opens (or reuses) a buffer for the given document reference. Increments the reference count.
    func openBuffer(for reference: FileDocumentReference) -> DocumentBuffer {
        let id = reference.documentIdentity
        if let existing = buffers[id] {
            refCounts[id, default: 0] += 1
            return existing
        }
        let buffer = DocumentBuffer(id: id, fileURL: reference.url)
        buffers[id] = buffer
        refCounts[id] = 1
        return buffer
    }

    /// Decrements the reference count for a buffer. When it reaches zero the buffer is removed.
    ///
    /// If the buffer is dirty and a `writer` is provided, returns a `Task` that flushes
    /// the content to disk before removal. Otherwise removes immediately and returns `nil`.
    @discardableResult
    func closeBuffer(id: String, writer: ((URL, SaveToken) async throws -> Void)? = nil) -> Task<Error?, Never>? {
        guard let count = refCounts[id] else { return nil }
        let newCount = count - 1
        if newCount > 0 {
            refCounts[id] = newCount
            return nil
        }

        guard let buffer = buffers[id] else {
            refCounts.removeValue(forKey: id)
            return nil
        }

        buffer.cancelLoad()

        if let writer, buffer.isDirty || buffer.activeSaveToken != nil {
            refCounts[id] = 0
            return Task { [weak self] in
                let activeSaveDeadline = Date().addingTimeInterval(30)
                while buffer.activeSaveToken != nil, Date() < activeSaveDeadline {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                guard buffer.activeSaveToken == nil else {
                    return URLError(.timedOut)
                }

                guard buffer.isDirty else {
                    self?.removeBufferIfUnreferenced(id: id)
                    return nil
                }
                guard let token = buffer.beginSave() else {
                    return CocoaError(.fileWriteUnknown)
                }
                do {
                    try await writer(buffer.fileURL, token)
                    buffer.didSave(token: token)
                    self?.removeBufferIfUnreferenced(id: id)
                    return nil
                } catch {
                    buffer.didFailSave(token: token)
                    return error
                }
            }
        }

        removeBuffer(id: id)
        return nil
    }

    /// Re-keys a live buffer under a replacement document identity without closing it.
    /// If the destination is already open, its buffer absorbs unsaved source edits.
    @discardableResult
    func migrateBuffer(
        from oldID: String,
        to reference: FileDocumentReference
    ) -> DocumentBuffer? {
        let newID = reference.documentIdentity
        guard oldID != newID else { return buffers[oldID] }
        guard let buffer = buffers.removeValue(forKey: oldID) else {
            return buffers[newID]
        }
        buffer.prepareForIdentityMigration()
        let referenceCount = refCounts.removeValue(forKey: oldID) ?? 1
        if let existing = buffers[newID] {
            existing.absorbUnsavedEdits(from: buffer)
            buffer.cancelLoad()
            refCounts[newID, default: 0] += referenceCount
            return existing
        }
        buffer.retarget(to: reference)
        buffers[newID] = buffer
        refCounts[newID] = referenceCount
        return buffer
    }

    /// Returns the buffer for the given identity, if open.
    func buffer(for id: String) -> DocumentBuffer? {
        buffers[id]
    }

    // MARK: - Private

    private func removeBufferIfUnreferenced(id: String) {
        guard refCounts[id] == 0 else { return }
        removeBuffer(id: id)
    }

    private func removeBuffer(id: String) {
        buffers.removeValue(forKey: id)
        refCounts.removeValue(forKey: id)
    }
}
