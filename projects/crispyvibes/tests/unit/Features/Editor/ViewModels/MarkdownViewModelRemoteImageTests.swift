import Foundation
import XCTest
@testable import CrispyVibes

/// Remote provider whose content and modification token the test can change.
private actor MutableRemoteImageProvider: FileContentProviding {
    enum TokenMode { case normal, unsupported, failing }

    private var data: Data
    private var token: String
    private var tokenMode: TokenMode
    private(set) var writes: [Data] = []

    nonisolated var requiresMaterializedLocalPreview: Bool { true }

    init(data: Data, token: String, tokenMode: TokenMode = .normal) {
        self.data = data
        self.token = token
        self.tokenMode = tokenMode
    }

    func readFile(at path: String) async throws -> Data { data }

    func writeFile(at path: String, contents: Data) async throws {
        writes.append(contents)
        data = contents
        token = "saved-\(writes.count)"
    }

    func modificationToken(at path: String) async throws -> String? {
        switch tokenMode {
        case .normal: return token
        case .unsupported: return nil
        case .failing: throw CocoaError(.fileReadUnknown)
        }
    }

    func simulateRemoteEdit(_ newData: Data, token newToken: String) {
        data = newData
        token = newToken
    }

    func setTokenMode(_ mode: TokenMode) { tokenMode = mode }

    func recordedWrites() -> [Data] { writes }
}

/// F009: remote (SSH) images must not silently overwrite changes made on the remote host.
@MainActor
final class MarkdownViewModelRemoteImageTests: XCTestCase {
    private var container: AppContainer!
    private var viewModel: MarkdownViewModel!
    private let remoteURL = URL(fileURLWithPath: "/remote/assets/shot.png")

    override func setUp() {
        super.setUp()
        container = AppContainer.makeDefault()
        viewModel = container.makeMarkdownViewModel(bufferStore: DocumentBufferStore())
    }

    override func tearDown() {
        viewModel = nil
        container = nil
        super.tearDown()
    }

    private func openRemoteImage(_ provider: MutableRemoteImageProvider) async throws -> URL {
        viewModel.fileContentProvider = provider
        viewModel.openFile(at: remoteURL)
        let opened = await waitForCondition(timeout: 8) {
            self.viewModel.workerStatus == .ready && self.viewModel.imageFileURL != nil
        }
        XCTAssertTrue(opened)
        return try XCTUnwrap(viewModel.imageFileURL)
    }

    private func save(_ data: Data, from stagedURL: URL) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            viewModel.saveImagePreviewData(data, from: stagedURL) { continuation.resume(returning: $0) }
        }
    }

    private func assertRemoteChanged(_ result: Result<Void, Error>, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = result, case RasterImageSaveError.remoteChanged = error else {
            return XCTFail("expected remoteChanged, got \(result)", file: file, line: line)
        }
    }

    func test_openCapturesBaseline_soImmediateSaveSucceeds_andTracksOwnWrite() async throws {
        let provider = MutableRemoteImageProvider(data: Data([1, 2, 3]), token: "v1")
        let stagedURL = try await openRemoteImage(provider)
        XCTAssertEqual(viewModel.remoteImageBaselineToken, "v1", "baseline is captured at materialization")

        let result = await save(Data([4, 5, 6]), from: stagedURL)
        if case .failure(let error) = result { XCTFail("unexpected failure \(error)") }
        XCTAssertEqual(viewModel.remoteImageBaselineToken, "saved-1", "our own write must not look like a remote change")

        let second = await save(Data([7, 8, 9]), from: stagedURL)
        if case .failure(let error) = second { XCTFail("unexpected failure \(error)") }
        let writes = await provider.recordedWrites()
        XCTAssertEqual(writes, [Data([4, 5, 6]), Data([7, 8, 9])])
        XCTAssertEqual(try Data(contentsOf: stagedURL), Data([7, 8, 9]))
    }

    func test_remoteChangeAfterStaging_blocksSave_andRefreshesStagedFile() async throws {
        let provider = MutableRemoteImageProvider(data: Data([1, 2, 3]), token: "v1")
        let stagedURL = try await openRemoteImage(provider)

        await provider.simulateRemoteEdit(Data([9, 9, 9]), token: "v2")
        assertRemoteChanged(await save(Data([4, 5, 6]), from: stagedURL))

        let writes = await provider.recordedWrites()
        XCTAssertTrue(writes.isEmpty, "remote edit must not be overwritten")
        let refreshed = await waitForCondition(timeout: 4) {
            (try? Data(contentsOf: stagedURL)) == Data([9, 9, 9]) && self.viewModel.remoteImageBaselineToken == "v2"
        }
        XCTAssertTrue(refreshed, "staged preview mirrors the remote change so the editor can raise a conflict")

        // After the user has seen (or kept edits over) the refreshed version, saving succeeds.
        let retry = await save(Data([4, 5, 6]), from: stagedURL)
        if case .failure(let error) = retry { XCTFail("unexpected failure \(error)") }
    }

    func test_versionLookupFailure_failsClosed() async throws {
        let provider = MutableRemoteImageProvider(data: Data([1, 2, 3]), token: "v1")
        let stagedURL = try await openRemoteImage(provider)
        await provider.setTokenMode(.failing)
        assertRemoteChanged(await save(Data([4, 5, 6]), from: stagedURL))
        let writes = await provider.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    func test_missingBaseline_withVersionedProvider_failsClosed() async throws {
        let provider = MutableRemoteImageProvider(data: Data([1, 2, 3]), token: "v1")
        let stagedURL = try await openRemoteImage(provider)
        viewModel.remoteImageBaselineToken = nil
        assertRemoteChanged(await save(Data([4, 5, 6]), from: stagedURL))
        let writes = await provider.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    func test_providerWithoutVersions_isTrusted() async throws {
        let provider = MutableRemoteImageProvider(data: Data([1, 2, 3]), token: "v1", tokenMode: .unsupported)
        let stagedURL = try await openRemoteImage(provider)
        let result = await save(Data([4, 5, 6]), from: stagedURL)
        if case .failure(let error) = result { XCTFail("unexpected failure \(error)") }
        let writes = await provider.recordedWrites()
        XCTAssertEqual(writes, [Data([4, 5, 6])])
    }
}
