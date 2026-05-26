import XCTest
@testable import CrispyVibes

@MainActor
final class ManageVibeSpacesViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempService() -> (VibeSpaceManagementService, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppPersistenceDataStore(appDirectoryURL: tempDir)
        let persistenceStore = VibeSpacePersistenceStore(store: store)
        let service = VibeSpaceManagementService(persistenceStore: persistenceStore)
        return (service, tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Builds a view model with the test-only synchronous load mode so
    /// `entries` is populated before the test makes assertions.
    private func makeViewModel(
        service: VibeSpaceManagementService,
        onOpen: @escaping (VibeSpaceConfigFile) -> Void = { _ in },
        onDelete: ((Set<UUID>) -> Void)? = nil
    ) -> ManageVibeSpacesViewModel {
        let viewModel = ManageVibeSpacesViewModel(
            vibespaceManagement: service,
            onOpenVibeSpace: onOpen,
            onDeleteVibeSpaces: { ids in
                if let onDelete {
                    onDelete(ids)
                } else {
                    for id in ids { service.deleteVibeSpace(id: id) }
                }
            }
        )
        viewModel.loadSynchronouslyForTesting = true
        viewModel.load()
        return viewModel
    }

    // MARK: - Loading

    func test_load_emptyState_hasNoEntries() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let viewModel = makeViewModel(service: service)

        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_load_listsAllVibeSpacesIncludingNonRecent() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let alpha = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        let beta = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])
        service.removeFromRecent(beta.id)

        let viewModel = makeViewModel(service: service)

        let ids = viewModel.entries.map(\.id)
        XCTAssertTrue(ids.contains(alpha.id))
        XCTAssertTrue(ids.contains(beta.id))
    }

    func test_load_putsRecentEntriesFirstInRecencyOrder() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let first = service.createVibeSpace(name: "First", projectURLs: [URL(fileURLWithPath: "/tmp/1")])
        let second = service.createVibeSpace(name: "Second", projectURLs: [URL(fileURLWithPath: "/tmp/2")])
        let third = service.createVibeSpace(name: "Third", projectURLs: [URL(fileURLWithPath: "/tmp/3")])
        service.touchRecent(first.id)

        let viewModel = makeViewModel(service: service)

        XCTAssertEqual(viewModel.entries.prefix(3).map(\.id), [first.id, third.id, second.id])
        for entry in viewModel.entries.prefix(3) {
            XCTAssertTrue(entry.isRecent)
        }
    }

    func test_load_sortsNonRecentEntriesAlphabetically() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let zeta = service.createVibeSpace(name: "Zeta", projectURLs: [URL(fileURLWithPath: "/tmp/z")])
        let alpha = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        let beta = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])
        service.removeFromRecent(zeta.id)
        service.removeFromRecent(alpha.id)
        service.removeFromRecent(beta.id)

        let viewModel = makeViewModel(service: service)

        XCTAssertEqual(viewModel.entries.map(\.name), ["Alpha", "Beta", "Zeta"])
        for entry in viewModel.entries {
            XCTAssertFalse(entry.isRecent)
        }
    }

    func test_entry_capturesProjectPaths() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(
            name: "Multi",
            projectURLs: [
                URL(fileURLWithPath: "/tmp/one"),
                URL(fileURLWithPath: "/tmp/two")
            ]
        )

        let viewModel = makeViewModel(service: service)
        let entry = try! XCTUnwrap(viewModel.entries.first(where: { $0.id == config.id }))

        XCTAssertEqual(entry.projectPaths, ["/tmp/one", "/tmp/two"])
    }

    func test_filteredEntries_byNonFirstPath_matches() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(
            name: "Multi",
            projectURLs: [
                URL(fileURLWithPath: "/tmp/first"),
                URL(fileURLWithPath: "/tmp/specialsecond")
            ]
        )
        _ = service.createVibeSpace(name: "Other", projectURLs: [URL(fileURLWithPath: "/tmp/other")])

        let viewModel = makeViewModel(service: service)
        viewModel.searchQuery = "specialsecond"

        XCTAssertEqual(viewModel.filteredEntries.map(\.name), ["Multi"])
    }

    // MARK: - Open

    func test_open_invokesOnOpenWithEntryConfig() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let config = service.createVibeSpace(name: "Pickme", projectURLs: [URL(fileURLWithPath: "/tmp/p")])

        var openedConfig: VibeSpaceConfigFile?
        let viewModel = makeViewModel(
            service: service,
            onOpen: { openedConfig = $0 }
        )

        let entry = try! XCTUnwrap(viewModel.entries.first(where: { $0.id == config.id }))
        viewModel.open(entry)

        XCTAssertEqual(openedConfig?.id, config.id)
    }

    func test_openSelected_singleSelection_invokesOnOpen() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let alpha = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        _ = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])

        var openedConfig: VibeSpaceConfigFile?
        let viewModel = makeViewModel(
            service: service,
            onOpen: { openedConfig = $0 }
        )

        viewModel.selection = [alpha.id]
        viewModel.openSelected()

        XCTAssertEqual(openedConfig?.id, alpha.id)
    }

    func test_openSelected_noSelection_doesNotInvokeOnOpen() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])

        var openedConfig: VibeSpaceConfigFile?
        let viewModel = makeViewModel(
            service: service,
            onOpen: { openedConfig = $0 }
        )

        viewModel.openSelected()

        XCTAssertNil(openedConfig)
    }

    func test_openSelected_multipleSelected_doesNotInvokeOnOpen() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let alpha = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        let beta = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])

        var openedConfig: VibeSpaceConfigFile?
        let viewModel = makeViewModel(
            service: service,
            onOpen: { openedConfig = $0 }
        )

        viewModel.selection = [alpha.id, beta.id]
        viewModel.openSelected()

        XCTAssertNil(openedConfig)
    }

    // MARK: - Delete

    func test_deleteSelected_singleSelection() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let alpha = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        _ = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])

        var deletedIDs: Set<UUID> = []
        let viewModel = makeViewModel(
            service: service,
            onDelete: { ids in
                deletedIDs = ids
                for id in ids { service.deleteVibeSpace(id: id) }
            }
        )

        viewModel.selection = [alpha.id]
        viewModel.deleteSelected()

        XCTAssertEqual(deletedIDs, [alpha.id])
        XCTAssertTrue(viewModel.selection.isEmpty)
        XCTAssertFalse(viewModel.entries.contains(where: { $0.id == alpha.id }))
    }

    func test_deleteSelected_bulkSelection() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let alpha = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        let beta = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])
        let gamma = service.createVibeSpace(name: "Gamma", projectURLs: [URL(fileURLWithPath: "/tmp/g")])

        var deletedIDs: Set<UUID> = []
        let viewModel = makeViewModel(
            service: service,
            onDelete: { ids in
                deletedIDs = ids
                for id in ids { service.deleteVibeSpace(id: id) }
            }
        )

        viewModel.selection = [alpha.id, gamma.id]
        viewModel.deleteSelected()

        XCTAssertEqual(deletedIDs, [alpha.id, gamma.id])
        XCTAssertTrue(viewModel.selection.isEmpty)
        let remaining = viewModel.entries.map(\.id)
        XCTAssertFalse(remaining.contains(alpha.id))
        XCTAssertFalse(remaining.contains(gamma.id))
        XCTAssertTrue(remaining.contains(beta.id))
    }

    func test_deleteSelected_emptySelection_isNoOp() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])

        var hookCalled = false
        let viewModel = makeViewModel(
            service: service,
            onDelete: { _ in hookCalled = true }
        )

        viewModel.deleteSelected()

        XCTAssertFalse(hookCalled)
        XCTAssertEqual(viewModel.entries.count, 1)
    }

    func test_deleteIDs_singleID_convenience() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        let alpha = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])

        var deletedIDs: Set<UUID> = []
        let viewModel = makeViewModel(
            service: service,
            onDelete: { ids in
                deletedIDs = ids
                for id in ids { service.deleteVibeSpace(id: id) }
            }
        )

        viewModel.deleteIDs([alpha.id])

        XCTAssertEqual(deletedIDs, [alpha.id])
        XCTAssertTrue(viewModel.entries.isEmpty)
    }

    // MARK: - Search

    func test_filteredEntries_emptyQuery_returnsAll() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        _ = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])

        let viewModel = makeViewModel(service: service)
        XCTAssertEqual(viewModel.filteredEntries.count, 2)
    }

    func test_filteredEntries_byName_caseInsensitive() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        _ = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])

        let viewModel = makeViewModel(service: service)
        viewModel.searchQuery = "alp"

        XCTAssertEqual(viewModel.filteredEntries.map(\.name), ["Alpha"])
    }

    func test_filteredEntries_byPath() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(name: "First", projectURLs: [URL(fileURLWithPath: "/tmp/specialpath")])
        _ = service.createVibeSpace(name: "Second", projectURLs: [URL(fileURLWithPath: "/tmp/other")])

        let viewModel = makeViewModel(service: service)
        viewModel.searchQuery = "specialpath"

        XCTAssertEqual(viewModel.filteredEntries.map(\.name), ["First"])
    }

    func test_filteredEntries_whitespaceQuery_returnsAll() {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        _ = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])

        let viewModel = makeViewModel(service: service)
        viewModel.searchQuery = "   "
        XCTAssertEqual(viewModel.filteredEntries.count, 2)
    }

    // MARK: - Async load smoke

    func test_load_async_eventuallyPopulates() async {
        let (service, tempDir) = makeTempService()
        defer { cleanup(tempDir) }

        _ = service.createVibeSpace(name: "Alpha", projectURLs: [URL(fileURLWithPath: "/tmp/a")])
        _ = service.createVibeSpace(name: "Beta", projectURLs: [URL(fileURLWithPath: "/tmp/b")])

        // Default async path (loadSynchronouslyForTesting = false).
        let viewModel = ManageVibeSpacesViewModel(
            vibespaceManagement: service,
            onOpenVibeSpace: { _ in },
            onDeleteVibeSpaces: { _ in },
            batchSize: 1
        )

        // Spin a few runloop ticks; entries fill in across batches.
        for _ in 0..<10 {
            if viewModel.entries.count == 2 && !viewModel.isLoading { break }
            await Task.yield()
        }

        XCTAssertEqual(viewModel.entries.count, 2)
        XCTAssertFalse(viewModel.isLoading)
    }
}
