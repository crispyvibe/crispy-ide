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

private final class TestDirectoryWatcher: DirectoryWatching {
    var onPathsChanged: ((Set<String>) -> Void)?
    private(set) var watchedPaths: [String] = []
    private(set) var stopCallCount = 0

    func watch(paths: [String]) {
        watchedPaths = paths
    }

    func stop() {
        stopCallCount += 1
    }
}
