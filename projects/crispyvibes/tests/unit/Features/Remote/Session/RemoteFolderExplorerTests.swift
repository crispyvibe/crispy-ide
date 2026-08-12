import XCTest
@testable import CrispyVibes

@MainActor
final class RemoteFolderExplorerTests: XCTestCase {
    func testRefreshUsesLatestResponseWhenEarlierRequestFinishesLater() async throws {
        let fileSystem = ControlledFileSystemProvider()
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { await fileSystem.requestCount == 1 }

        explorer.refreshTree(trigger: .manual)
        try await waitUntil { await fileSystem.requestCount == 2 }

        await fileSystem.finishNext(
            with: [FileItemDescriptor(
                name: "stale.txt",
                path: "/remote/stale.txt",
                isDirectory: false,
                isHidden: false,
                size: nil,
                modificationDate: nil
            )]
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(explorer.rootItems.isEmpty)

        await fileSystem.finishNext(
            with: [FileItemDescriptor(
                name: "fresh.txt",
                path: "/remote/fresh.txt",
                isDirectory: false,
                isHidden: false,
                size: nil,
                modificationDate: nil
            )]
        )
        try await waitUntil { explorer.rootItems.map(\.displayName) == ["fresh.txt"] }

        XCTAssertEqual(explorer.rootItems.map(\.displayName), ["fresh.txt"])
        XCTAssertEqual(watcher.watchedPaths, ["/remote"])
    }

    func testStopWatchingCancelsInFlightRefreshAndResetsWorkerState() async throws {
        let fileSystem = ControlledFileSystemProvider()
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { await fileSystem.requestCount == 1 }

        explorer.stopWatching()
        XCTAssertEqual(watcher.stopCallCount, 1)
        XCTAssertEqual(explorer.workerStatus, .ready)

        await fileSystem.finishNext(
            with: [FileItemDescriptor(
                name: "ignored.txt",
                path: "/remote/ignored.txt",
                isDirectory: false,
                isHidden: false,
                size: nil,
                modificationDate: nil
            )]
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(explorer.rootItems.isEmpty)
        XCTAssertEqual(explorer.workerStatus, .ready)
    }

    func testEnhancedNestedCreateRefreshesExpandedFolderAndStartsRename() async throws {
        let fileSystem = InMemoryRemoteFileSystem(directories: [
            "/remote": [descriptor("src", at: "/remote/src", isDirectory: true)],
            "/remote/src": [descriptor("old.txt", at: "/remote/src/old.txt")]
        ])
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher,
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        XCTAssertFalse(explorer.supportsFileTransfers)
        try await waitUntil { explorer.rootItems.map(\.displayName) == ["src"] }
        let src = try XCTUnwrap(explorer.rootItems.first)
        explorer.toggleExpansion(for: src)
        try await waitUntil { explorer.rootItems.first?.children?.map(\.displayName) == ["old.txt"] }

        explorer.createNewFile(in: src)
        try await waitUntil {
            explorer.rootItems.first?.children?.map(\.displayName) == ["old.txt", "untitled"]
                && explorer.renamingItemID == "/remote/src/untitled"
                && explorer.workerStatus == .ready
        }

        XCTAssertEqual(explorer.selectedFileURL?.path, "/remote/src/untitled")
        XCTAssertEqual(explorer.selectedFolderURL?.path, "/remote/src")
        XCTAssertEqual(watcher.watchedPaths, ["/remote", "/remote/src"])
    }

    func testEnhancedManualRefreshReloadsExpandedDirectory() async throws {
        let fileSystem = InMemoryRemoteFileSystem(directories: [
            "/remote": [descriptor("src", at: "/remote/src", isDirectory: true)],
            "/remote/src": [descriptor("before.txt", at: "/remote/src/before.txt")]
        ])
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: TestDirectoryWatcher(),
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        explorer.toggleExpansion(for: try XCTUnwrap(explorer.rootItems.first))
        try await waitUntil { explorer.rootItems.first?.children?.map(\.displayName) == ["before.txt"] }

        await fileSystem.setDirectory(
            "/remote/src",
            descriptors: [descriptor("after.txt", at: "/remote/src/after.txt")]
        )
        explorer.refreshTree(trigger: .manual)

        try await waitUntil { explorer.rootItems.first?.children?.map(\.displayName) == ["after.txt"] }
    }

    func testEnhancedCreateAtSelectionUsesSelectedFolderAndGeneratesUniqueName() async throws {
        let fileSystem = InMemoryRemoteFileSystem(directories: [
            "/remote": [descriptor("src", at: "/remote/src", isDirectory: true)],
            "/remote/src": [descriptor("untitled", at: "/remote/src/untitled")]
        ])
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: TestDirectoryWatcher(),
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        let src = try XCTUnwrap(explorer.rootItems.first)
        explorer.select(src)
        explorer.toggleExpansion(for: src)
        try await waitUntil { explorer.rootItems.first?.children != nil }

        explorer.createNewFileAtSelection()
        try await waitUntil { explorer.renamingItemID == "/remote/src/untitled 1" }

        let createdPaths = await fileSystem.createdPaths
        XCTAssertEqual(createdPaths, ["/remote/src/untitled 1"])
    }

    func testEnhancedSelectionPreviewsFileAndClearsStaleFileForFolder() async throws {
        let fileSystem = InMemoryRemoteFileSystem(directories: [
            "/remote": [
                descriptor("src", at: "/remote/src", isDirectory: true),
                descriptor("README.md", at: "/remote/README.md")
            ],
            "/remote/src": []
        ])
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: TestDirectoryWatcher(),
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 2 }
        XCTAssertEqual(explorer.rootItems.map(\.displayName), ["src", "README.md"])

        let file = try XCTUnwrap(explorer.rootItems.first(where: { !$0.isDirectory }))
        explorer.select(file)
        XCTAssertEqual(explorer.selectedFolderURL?.path, "/remote")
        XCTAssertEqual(explorer.openRequest?.action, .preview)

        let folder = try XCTUnwrap(explorer.rootItems.first(where: \.isDirectory))
        explorer.select(folder)
        XCTAssertNil(explorer.selectedFileURL)
        XCTAssertEqual(explorer.selectedFolderURL?.path, "/remote/src")
    }

    func testEnhancedDeleteFinishesReadyAfterNestedRefresh() async throws {
        let fileSystem = InMemoryRemoteFileSystem(directories: [
            "/remote": [descriptor("src", at: "/remote/src", isDirectory: true)],
            "/remote/src": [descriptor("old.txt", at: "/remote/src/old.txt")]
        ])
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: TestDirectoryWatcher(),
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        explorer.toggleExpansion(for: try XCTUnwrap(explorer.rootItems.first))
        try await waitUntil { explorer.rootItems.first?.children?.count == 1 }

        explorer.deleteItem(try XCTUnwrap(explorer.rootItems.first?.children?.first))
        try await waitUntil {
            explorer.rootItems.first?.children?.isEmpty == true
                && explorer.workerStatus == .ready
        }
    }

    func testEnhancedDirectoryRenamePreservesExpandedDescendantSelection() async throws {
        let fileSystem = InMemoryRemoteFileSystem(directories: [
            "/remote": [descriptor("src", at: "/remote/src", isDirectory: true)],
            "/remote/src": [descriptor("nested", at: "/remote/src/nested", isDirectory: true)],
            "/remote/src/nested": [descriptor("file.txt", at: "/remote/src/nested/file.txt")]
        ])
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher,
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        let src = try XCTUnwrap(explorer.rootItems.first)
        explorer.toggleExpansion(for: src)
        try await waitUntil { explorer.rootItems.first?.children?.count == 1 }
        let nested = try XCTUnwrap(explorer.rootItems.first?.children?.first)
        explorer.toggleExpansion(for: nested)
        try await waitUntil { explorer.rootItems.first?.children?.first?.children?.count == 1 }
        let file = try XCTUnwrap(explorer.rootItems.first?.children?.first?.children?.first)
        explorer.select(file)

        explorer.startRenaming(item: src)
        explorer.renameText = "lib"
        explorer.commitRename()

        try await waitUntil {
            explorer.rootItems.first?.id == "/remote/lib"
                && explorer.rootItems.first?.children?.first?.id == "/remote/lib/nested"
                && explorer.rootItems.first?.children?.first?.children?.first?.id
                    == "/remote/lib/nested/file.txt"
                && explorer.workerStatus == .ready
        }

        XCTAssertEqual(explorer.selectedItemID, "/remote/lib/nested/file.txt")
        XCTAssertEqual(explorer.selectedFileURL?.path, "/remote/lib/nested/file.txt")
        XCTAssertEqual(explorer.selectedFolderURL?.path, "/remote/lib/nested")
        XCTAssertTrue(explorer.expandedDirectoryIDs.contains("/remote/lib"))
        XCTAssertTrue(explorer.expandedDirectoryIDs.contains("/remote/lib/nested"))
        XCTAssertFalse(explorer.expandedDirectoryIDs.contains("/remote/src"))
        XCTAssertEqual(watcher.watchedPaths, ["/remote", "/remote/lib", "/remote/lib/nested"])
    }

    func testEnhancedCreateCompletionAfterStopDoesNotMutateUIOrRestartWatcher() async throws {
        let fileSystem = SuspendingMutationFileSystem(
            directories: ["/remote": []],
            suspendedOperation: .create
        )
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher,
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { await fileSystem.contentsRequestCount >= 1 }
        explorer.createNewFileAtSelection()
        try await waitUntil { await fileSystem.hasSuspendedMutation }
        let watchCallCount = watcher.watchCallCount

        explorer.stopWatching()
        await fileSystem.resumeMutation()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(explorer.rootItems.isEmpty)
        XCTAssertNil(explorer.selectedItemID)
        XCTAssertNil(explorer.renamingItemID)
        XCTAssertEqual(explorer.workerStatus, .ready)
        XCTAssertEqual(watcher.watchCallCount, watchCallCount)
    }

    func testEnhancedDeleteCompletionAfterStopDoesNotMutateUIOrRestartWatcher() async throws {
        let fileSystem = SuspendingMutationFileSystem(
            directories: [
                "/remote": [descriptor("file.txt", at: "/remote/file.txt")]
            ],
            suspendedOperation: .remove
        )
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher,
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        explorer.deleteItem(try XCTUnwrap(explorer.rootItems.first))
        try await waitUntil { await fileSystem.hasSuspendedMutation }
        let watchCallCount = watcher.watchCallCount

        explorer.stopWatching()
        await fileSystem.resumeMutation()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(explorer.rootItems.map(\.id), ["/remote/file.txt"])
        XCTAssertEqual(explorer.workerStatus, .ready)
        XCTAssertEqual(watcher.watchCallCount, watchCallCount)
    }

    func testEnhancedRenameCompletionAfterStopDoesNotMutateUIOrRestartWatcher() async throws {
        let fileSystem = SuspendingMutationFileSystem(
            directories: [
                "/remote": [descriptor("old.txt", at: "/remote/old.txt")]
            ],
            suspendedOperation: .move
        )
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher,
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        explorer.startRenaming(item: try XCTUnwrap(explorer.rootItems.first))
        explorer.renameText = "new.txt"
        explorer.commitRename()
        try await waitUntil { await fileSystem.hasSuspendedMutation }
        let watchCallCount = watcher.watchCallCount

        explorer.stopWatching()
        await fileSystem.resumeMutation()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(explorer.rootItems.map(\.id), ["/remote/old.txt"])
        XCTAssertEqual(explorer.workerStatus, .ready)
        XCTAssertEqual(watcher.watchCallCount, watchCallCount)
    }

    func testLegacyCreateCompletionAfterStopDoesNotRestartRefresh() async throws {
        let fileSystem = SuspendingMutationFileSystem(
            directories: ["/remote": []],
            suspendedOperation: .create
        )
        let watcher = TestDirectoryWatcher()
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: watcher
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { await fileSystem.contentsRequestCount >= 1 }
        explorer.createNewFileAtSelection()
        try await waitUntil { await fileSystem.hasSuspendedMutation }
        let contentsRequestCount = await fileSystem.contentsRequestCount

        explorer.stopWatching()
        await fileSystem.resumeMutation()
        try await Task.sleep(nanoseconds: 50_000_000)

        let finalContentsRequestCount = await fileSystem.contentsRequestCount
        XCTAssertEqual(finalContentsRequestCount, contentsRequestCount)
        XCTAssertTrue(explorer.rootItems.isEmpty)
        XCTAssertEqual(explorer.workerStatus, .ready)
    }

    func testLegacyDeleteCompletionAfterStopDoesNotRestartRefresh() async throws {
        let fileSystem = SuspendingMutationFileSystem(
            directories: [
                "/remote": [descriptor("file.txt", at: "/remote/file.txt")]
            ],
            suspendedOperation: .remove
        )
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: TestDirectoryWatcher()
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        explorer.deleteItem(try XCTUnwrap(explorer.rootItems.first))
        try await waitUntil { await fileSystem.hasSuspendedMutation }
        let contentsRequestCount = await fileSystem.contentsRequestCount

        explorer.stopWatching()
        await fileSystem.resumeMutation()
        try await Task.sleep(nanoseconds: 50_000_000)

        let finalContentsRequestCount = await fileSystem.contentsRequestCount
        XCTAssertEqual(finalContentsRequestCount, contentsRequestCount)
        XCTAssertEqual(explorer.rootItems.map(\.id), ["/remote/file.txt"])
        XCTAssertEqual(explorer.workerStatus, .ready)
    }

    func testLegacyRenameCompletionAfterStopDoesNotPublishOrRestartRefresh() async throws {
        let fileSystem = SuspendingMutationFileSystem(
            directories: [
                "/remote": [descriptor("old.txt", at: "/remote/old.txt")]
            ],
            suspendedOperation: .move
        )
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: TestDirectoryWatcher()
        )
        var renameEvents: [ExplorerRenameEvent] = []
        let subscription = explorer.renameEvents.sink { renameEvents.append($0) }
        defer { subscription.cancel() }

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        explorer.startRenaming(item: try XCTUnwrap(explorer.rootItems.first))
        explorer.renameText = "new.txt"
        explorer.commitRename()
        try await waitUntil { await fileSystem.hasSuspendedMutation }
        let contentsRequestCount = await fileSystem.contentsRequestCount

        explorer.stopWatching()
        await fileSystem.resumeMutation()
        try await Task.sleep(nanoseconds: 50_000_000)

        let finalContentsRequestCount = await fileSystem.contentsRequestCount
        XCTAssertEqual(finalContentsRequestCount, contentsRequestCount)
        XCTAssertTrue(renameEvents.isEmpty)
        XCTAssertEqual(explorer.rootItems.map(\.id), ["/remote/old.txt"])
        XCTAssertEqual(explorer.workerStatus, .ready)
    }

    func testEnhancedRenameRejectsPathTraversal() async throws {
        let fileSystem = InMemoryRemoteFileSystem(directories: [
            "/remote": [descriptor("file.txt", at: "/remote/file.txt")]
        ])
        let explorer = RemoteFolderExplorer(
            remotePath: "/remote",
            fileSystem: fileSystem,
            watcher: TestDirectoryWatcher(),
            enhancedMode: true
        )

        explorer.setRootFolder(URL(fileURLWithPath: "/remote"))
        try await waitUntil { explorer.rootItems.count == 1 }
        explorer.startRenaming(item: try XCTUnwrap(explorer.rootItems.first))
        explorer.renameText = "../outside.txt"
        explorer.commitRename()

        XCTAssertNotNil(explorer.userFacingError)
        let moves = await fileSystem.moves
        XCTAssertTrue(moves.isEmpty)
        XCTAssertEqual(explorer.renamingItemID, "/remote/file.txt")
    }

    private static func descriptor(
        _ name: String,
        at path: String,
        isDirectory: Bool = false,
        size: UInt64? = nil,
        modificationDate: Date? = nil
    ) -> FileItemDescriptor {
        FileItemDescriptor(
            name: name,
            path: path,
            isDirectory: isDirectory,
            isHidden: name.hasPrefix("."),
            size: size,
            modificationDate: modificationDate
        )
    }

    private func descriptor(
        _ name: String,
        at path: String,
        isDirectory: Bool = false,
        size: UInt64? = nil,
        modificationDate: Date? = nil
    ) -> FileItemDescriptor {
        Self.descriptor(
            name,
            at: path,
            isDirectory: isDirectory,
            size: size,
            modificationDate: modificationDate
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor ControlledFileSystemProvider: FileSystemProviding {
    private var continuations: [CheckedContinuation<[FileItemDescriptor], Error>] = []
    private(set) var requestCount = 0

    func contentsOfDirectory(at path: String) async throws -> [FileItemDescriptor] {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func createDirectory(at path: String) async throws {}
    func createFile(at path: String, contents: Data?) async throws {}
    func removeItem(at path: String) async throws {}
    func moveItem(from source: String, to destination: String) async throws {}

    func finishNext(with descriptors: [FileItemDescriptor]) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: descriptors)
    }
}

private actor InMemoryRemoteFileSystem: FileSystemProviding {
    private var directories: [String: [FileItemDescriptor]]
    private(set) var createdPaths: [String] = []
    private(set) var moves: [(source: String, destination: String)] = []

    init(directories: [String: [FileItemDescriptor]]) {
        self.directories = directories
    }

    func contentsOfDirectory(at path: String) async throws -> [FileItemDescriptor] {
        directories[path] ?? []
    }

    func createDirectory(at path: String) async throws {
        createdPaths.append(path)
        directories[path] = []
        insertDescriptor(path: path, isDirectory: true)
    }

    func createFile(at path: String, contents: Data?) async throws {
        createdPaths.append(path)
        insertDescriptor(path: path, isDirectory: false)
    }

    func removeItem(at path: String) async throws {
        let parent = (path as NSString).deletingLastPathComponent
        directories[parent]?.removeAll { $0.path == path }
        directories = directories.filter { key, _ in
            key != path && !key.hasPrefix(path + "/")
        }
    }

    func moveItem(from source: String, to destination: String) async throws {
        moves.append((source, destination))
        let sourceParent = (source as NSString).deletingLastPathComponent
        let destinationParent = (destination as NSString).deletingLastPathComponent
        guard let index = directories[sourceParent]?.firstIndex(where: { $0.path == source }) else {
            return
        }
        let existing = directories[sourceParent]!.remove(at: index)
        directories[destinationParent, default: []].append(
            descriptor(
                remapping: existing,
                from: source,
                to: destination
            )
        )

        guard existing.isDirectory else { return }
        let movedDirectories = directories.filter { key, _ in
            key == source || key.hasPrefix(source + "/")
        }
        for key in movedDirectories.keys {
            directories.removeValue(forKey: key)
        }
        for (path, descriptors) in movedDirectories {
            let remappedPath = Self.remapPath(path, from: source, to: destination)
            directories[remappedPath] = descriptors.map {
                descriptor(remapping: $0, from: source, to: destination)
            }
        }
    }

    private func descriptor(
        remapping descriptor: FileItemDescriptor,
        from source: String,
        to destination: String
    ) -> FileItemDescriptor {
        let path = Self.remapPath(descriptor.path, from: source, to: destination)
        let name = (path as NSString).lastPathComponent
        return FileItemDescriptor(
            name: name,
            path: path,
            isDirectory: descriptor.isDirectory,
            isHidden: name.hasPrefix("."),
            size: descriptor.size,
            modificationDate: descriptor.modificationDate
        )
    }

    private static func remapPath(_ path: String, from source: String, to destination: String) -> String {
        path == source ? destination : destination + String(path.dropFirst(source.count))
    }

    func setDirectory(_ path: String, descriptors: [FileItemDescriptor]) {
        directories[path] = descriptors
    }

    private func insertDescriptor(path: String, isDirectory: Bool) {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        directories[parent, default: []].append(
            FileItemDescriptor(
                name: name,
                path: path,
                isDirectory: isDirectory,
                isHidden: name.hasPrefix("."),
                size: isDirectory ? nil : 0,
                modificationDate: Date()
            )
        )
    }
}

private actor SuspendingMutationFileSystem: FileSystemProviding {
    enum Operation {
        case create
        case remove
        case move
    }

    private var directories: [String: [FileItemDescriptor]]
    private let suspendedOperation: Operation
    private var mutationContinuation: CheckedContinuation<Void, Never>?
    private(set) var contentsRequestCount = 0

    var hasSuspendedMutation: Bool {
        mutationContinuation != nil
    }

    init(
        directories: [String: [FileItemDescriptor]],
        suspendedOperation: Operation
    ) {
        self.directories = directories
        self.suspendedOperation = suspendedOperation
    }

    func contentsOfDirectory(at path: String) async throws -> [FileItemDescriptor] {
        contentsRequestCount += 1
        return directories[path] ?? []
    }

    func createDirectory(at path: String) async throws {
        await suspendIfNeeded(.create)
        directories[path] = []
        insertDescriptor(path: path, isDirectory: true)
    }

    func createFile(at path: String, contents: Data?) async throws {
        await suspendIfNeeded(.create)
        insertDescriptor(path: path, isDirectory: false)
    }

    func removeItem(at path: String) async throws {
        await suspendIfNeeded(.remove)
        let parent = (path as NSString).deletingLastPathComponent
        directories[parent]?.removeAll { $0.path == path }
    }

    func moveItem(from source: String, to destination: String) async throws {
        await suspendIfNeeded(.move)
        let parent = (source as NSString).deletingLastPathComponent
        guard let index = directories[parent]?.firstIndex(where: { $0.path == source }) else { return }
        let existing = directories[parent]!.remove(at: index)
        let name = (destination as NSString).lastPathComponent
        directories[parent, default: []].append(
            FileItemDescriptor(
                name: name,
                path: destination,
                isDirectory: existing.isDirectory,
                isHidden: name.hasPrefix("."),
                size: existing.size,
                modificationDate: existing.modificationDate
            )
        )
    }

    func resumeMutation() {
        mutationContinuation?.resume()
        mutationContinuation = nil
    }

    private func suspendIfNeeded(_ operation: Operation) async {
        guard operation == suspendedOperation else { return }
        await withCheckedContinuation { continuation in
            mutationContinuation = continuation
        }
    }

    private func insertDescriptor(path: String, isDirectory: Bool) {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        directories[parent, default: []].append(
            FileItemDescriptor(
                name: name,
                path: path,
                isDirectory: isDirectory,
                isHidden: name.hasPrefix("."),
                size: isDirectory ? nil : 0,
                modificationDate: Date()
            )
        )
    }
}

@MainActor
private final class TestDirectoryWatcher: DirectoryWatching {
    var onPathsChanged: ((Set<String>) -> Void)?
    private(set) var watchedPaths: [String] = []
    private(set) var stopCallCount = 0
    private(set) var watchCallCount = 0

    func watch(paths: [String]) {
        watchCallCount += 1
        watchedPaths = paths
    }

    func stop() {
        stopCallCount += 1
    }
}


@MainActor
final class ExperimentalFeaturesServiceTests: XCTestCase {
    func testEnhancedRemoteExplorerPreferencePropagatesFromUserDefaultsNotification() async throws {
        let suiteName = "ExperimentalFeaturesServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = ExperimentalFeaturesService(defaults: defaults)
        XCTAssertFalse(service.isEnhancedRemoteExplorerEnabled)

        defaults.set(true, forKey: AppPreferences.enhancedRemoteExplorerKey)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)

        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while !service.isEnhancedRemoteExplorerEnabled,
              DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(service.isEnhancedRemoteExplorerEnabled)
    }
}

@MainActor
final class PollingDirectoryWatcherTests: XCTestCase {
    func testMetadataModeDetectsSameNameFileModificationAfterImmediateBaseline() async throws {
        let fileSystem = PollingTestFileSystem(
            descriptors: [
                FileItemDescriptor(
                    name: "file.txt",
                    path: "/remote/file.txt",
                    isDirectory: false,
                    isHidden: false,
                    size: 1,
                    modificationDate: Date(timeIntervalSince1970: 1)
                )
            ]
        )
        let watcher = PollingDirectoryWatcher(
            fileSystem: fileSystem,
            interval: 0.05,
            snapshotMode: .metadata
        )
        var reportedPaths = Set<String>()
        watcher.onPathsChanged = { reportedPaths.formUnion($0) }

        watcher.watch(paths: ["/remote"])
        try await waitUntil { await fileSystem.requestCount >= 1 }
        XCTAssertTrue(reportedPaths.isEmpty)

        await fileSystem.setDescriptors([
            FileItemDescriptor(
                name: "file.txt",
                path: "/remote/file.txt",
                isDirectory: false,
                isHidden: false,
                size: 2,
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        ])

        try await waitUntil { reportedPaths == ["/remote"] }
        watcher.stop()
    }

    func testNamesOnlyModeIgnoresMetadataOnlyModification() async throws {
        let fileSystem = PollingTestFileSystem(
            descriptors: [
                FileItemDescriptor(
                    name: "file.txt",
                    path: "/remote/file.txt",
                    isDirectory: false,
                    isHidden: false,
                    size: 1,
                    modificationDate: Date(timeIntervalSince1970: 1)
                )
            ]
        )
        let watcher = PollingDirectoryWatcher(
            fileSystem: fileSystem,
            interval: 0.05,
            snapshotMode: .namesOnly
        )
        var reportedPaths = Set<String>()
        watcher.onPathsChanged = { reportedPaths.formUnion($0) }

        watcher.watch(paths: ["/remote"])
        try await waitUntil { await fileSystem.requestCount >= 1 }
        await fileSystem.setDescriptors([
            FileItemDescriptor(
                name: "file.txt",
                path: "/remote/file.txt",
                isDirectory: false,
                isHidden: false,
                size: 2,
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        ])
        try await Task.sleep(nanoseconds: 140_000_000)

        XCTAssertTrue(reportedPaths.isEmpty)
        watcher.stop()
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor PollingTestFileSystem: FileSystemProviding {
    private var descriptors: [FileItemDescriptor]
    private(set) var requestCount = 0

    init(descriptors: [FileItemDescriptor]) {
        self.descriptors = descriptors
    }

    func contentsOfDirectory(at path: String) async throws -> [FileItemDescriptor] {
        requestCount += 1
        return descriptors
    }

    func createDirectory(at path: String) async throws {}
    func createFile(at path: String, contents: Data?) async throws {}
    func removeItem(at path: String) async throws {}
    func moveItem(from source: String, to destination: String) async throws {}

    func setDescriptors(_ descriptors: [FileItemDescriptor]) {
        self.descriptors = descriptors
    }
}
