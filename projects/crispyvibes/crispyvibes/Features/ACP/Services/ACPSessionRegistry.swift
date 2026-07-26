import Combine
import Foundation

/// Central registry for all ACPStandaloneSessionStore instances.
/// Keyed by threadID so multiple views can share the same store.
/// Any view that needs a conversation gets it from here — one store, one session, one timeline.
@MainActor
final class ACPSessionRegistry: ObservableObject {
    typealias StoreFactory = @MainActor (UUID, UUID?) -> ACPStandaloneSessionStore

    private let storeFactory: StoreFactory
    private var stores: [String: ACPStandaloneSessionStore] = [:]  // threadID → store
    private var storesByID: [UUID: String] = [:]  // store.id → threadID (reverse lookup)
    private var pendingStores: [UUID: ACPStandaloneSessionStore] = [:]  // stores without threadID yet
    private var observations: [String: AnyCancellable] = [:]

    init(storeFactory: @escaping StoreFactory) {
        self.storeFactory = storeFactory
    }

    /// Get an existing store for a thread, or nil if none exists.
    func store(forThread threadID: String) -> ACPStandaloneSessionStore? {
        stores[threadID]
    }

    /// Get an existing store by its UUID.
    func store(forID id: UUID) -> ACPStandaloneSessionStore? {
        if let threadID = storesByID[id] { return stores[threadID] }
        return pendingStores[id]
    }

    /// Get or create a store for a thread. If one already exists, returns it.
    func storeForThread(
        _ threadID: String,
        agentId: String,
        projectIdentifier: String?,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        if let existing = stores[threadID] { return existing }

        let snapshot = ACPStandalonePaneSnapshot(
            id: UUID(),
            selectedAgentID: agentId,
            selectedProjectIdentifier: projectIdentifier,
            trustMode: .standard,
            reasoningLevel: .medium,
            shouldAutoConnect: true,
            threadId: threadID
        )
        let store = storeFactory(snapshot.id, vibespaceID)
        store.restore(from: snapshot)
        register(store, threadID: threadID)
        return store
    }

    /// Create a fresh store for a new conversation (no threadID yet).
    func newStore(
        focusedProject: AnyProjectSession?,
        preferredAgentID: String?,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        let store = storeFactory(UUID(), vibespaceID)
        store.applyDefaults(focusedProject: focusedProject, preferredAgentID: preferredAgentID)
        pendingStores[store.id] = store
        observeForThreadCreation(store)
        return store
    }

    /// Create or return a visible chat store for a Vibe Lane-owned ACP session.
    /// The engine owns the session lifetime; the store owns the user-visible timeline.
    func storeForVibeLaneSession(
        id: UUID,
        agentID: String,
        projectPath: String,
        modelID: String? = nil,
        trustMode: CLITrustMode? = nil,
        reasoningLevel: AgentReasoningLevel? = nil,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        if let existing = store(forID: id) {
            existing.prepareExternalVibeLaneSession(
                agentID: agentID,
                projectPath: projectPath,
                modelID: modelID,
                trustMode: trustMode,
                reasoningLevel: reasoningLevel
            )
            return existing
        }
        let store = storeFactory(id, vibespaceID)
        store.prepareExternalVibeLaneSession(
            agentID: agentID,
            projectPath: projectPath,
            modelID: modelID,
            trustMode: trustMode,
            reasoningLevel: reasoningLevel
        )
        pendingStores[store.id] = store
        observeForThreadCreation(store)
        return store
    }

    /// Restore a store from a persisted snapshot.
    func restoreStore(
        from snapshot: ACPStandalonePaneSnapshot,
        vibespaceID: UUID? = nil
    ) -> ACPStandaloneSessionStore {
        // If this thread is already registered, return existing
        if let threadID = snapshot.threadId, let existing = stores[threadID] {
            existing.restore(from: snapshot)
            return existing
        }

        let store = storeFactory(snapshot.id, vibespaceID)
        store.restore(from: snapshot)
        if let threadID = snapshot.threadId {
            register(store, threadID: threadID)
        } else {
            pendingStores[store.id] = store
            observeForThreadCreation(store)
        }
        return store
    }

    /// Remove a store and tear it down.
    func removeStore(id: UUID) {
        // Check pending stores first
        if let pending = pendingStores.removeValue(forKey: id) {
            observations.removeValue(forKey: "pending-\(id.uuidString)")
            pending.teardown()
            objectWillChange.send()
            return
        }
        guard let threadID = storesByID.removeValue(forKey: id) else { return }
        observations.removeValue(forKey: threadID)
        stores.removeValue(forKey: threadID)?.teardown()
        objectWillChange.send()
    }

    /// Tear down all stores (vibespace switch).
    func removeAll() {
        let allStores = Array(stores.values) + Array(pendingStores.values)
        stores.removeAll()
        storesByID.removeAll()
        pendingStores.removeAll()
        observations.removeAll()
        for store in allStores { store.teardown() }
        objectWillChange.send()
    }

    /// Snapshot for a store by its UUID.
    func snapshot(forID id: UUID) -> ACPStandalonePaneSnapshot? {
        store(forID: id)?.snapshot
    }

    /// All store IDs (for iteration).
    var allStoreIDs: [UUID] { Array(storesByID.keys) }

    // MARK: - Private

    private func register(_ store: ACPStandaloneSessionStore, threadID: String) {
        pendingStores.removeValue(forKey: store.id)
        observations.removeValue(forKey: "pending-\(store.id.uuidString)")
        if let previousThreadID = storesByID[store.id], previousThreadID != threadID {
            stores.removeValue(forKey: previousThreadID)
            observations.removeValue(forKey: previousThreadID)
        }
        stores[threadID] = store
        storesByID[store.id] = threadID
        observations[threadID] = store.chatViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        objectWillChange.send()
    }

    /// For new conversations that don't have a threadID yet — watch for it to appear.
    private func observeForThreadCreation(_ store: ACPStandaloneSessionStore) {
        let storeID = store.id
        let key = "pending-\(storeID.uuidString)"
        observations[key] = store.chatViewModel.objectWillChange
            .sink { [weak self, weak store] _ in
                guard let self, let store,
                      let ctx = store.chatViewModel.persistenceContext else { return }
                // Thread created — move from pending to registered
                self.observations.removeValue(forKey: key)
                self.pendingStores.removeValue(forKey: storeID)
                self.register(store, threadID: ctx.threadID)
            }
    }
}
