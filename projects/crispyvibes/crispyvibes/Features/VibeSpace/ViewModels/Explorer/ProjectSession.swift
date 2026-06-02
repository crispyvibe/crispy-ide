import Combine
import Foundation
import AppKit
import SwiftUI

@MainActor
protocol EditorDetachedWindowManaging: AnyObject {
    func openWindow(for fileURL: URL)
}

struct ProjectSessionDependencies {
    var layoutPersistence: LayoutPersistenceService
    var vibespaceManagement: VibeSpaceManagementService
    var vibespaceID: UUID?
    var folderExplorerViewModelFactory: @MainActor () -> FolderExplorerViewModel
    var terminalViewModelFactory: @MainActor () -> TerminalViewModel
    var detachedWindowManager: EditorDetachedWindowManaging
    var directoryWatcher: any FileSystemEventWatching
}

struct ProjectPaneLayoutState: Codable, Equatable {
    var explorerFraction: Double
    var terminalFraction: Double
    var explorerPoints: Double?
    var terminalPoints: Double?

    static let `default` = ProjectPaneLayoutState(
        explorerFraction: 0.30,
        terminalFraction: 0.36,
        explorerPoints: nil,
        terminalPoints: nil
    )

    func normalized() -> ProjectPaneLayoutState {
        ProjectPaneLayoutState(
            explorerFraction: Self.clamp(explorerFraction, min: 0.18, max: 0.72),
            terminalFraction: Self.clamp(terminalFraction, min: 0.20, max: 0.72),
            explorerPoints: Self.clampOptional(explorerPoints, min: 190),
            terminalPoints: Self.clampOptional(terminalPoints, min: 160)
        )
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(value, upper))
    }

    private static func clampOptional(_ value: Double?, min lower: Double) -> Double? {
        guard let value else { return nil }
        return Swift.max(lower, value)
    }
}

@MainActor
final class ProjectSession: ObservableObject, Identifiable, ProjectProviding {
    let id = UUID()
    let rootURL: URL
    let folderExplorerViewModel: FolderExplorerViewModel
    let terminalViewModel: TerminalViewModel
    @Published var paneLayout: ProjectPaneLayoutState = .default

    var onFileOpenRequested: ((ExplorerOpenRequest) -> Void)?
    var onFileRenamed: ((ExplorerRenameEvent) -> Void)?

    // MARK: - ProjectProviding conformance

    lazy var metadata: any ProjectMetadata = LocalProjectMetadata(rootURL: rootURL)
    var folderExplorer: any FolderExploring { folderExplorerViewModel }
    lazy var gitExplorer: any GitExploring = LocalGitExplorer(explorer: folderExplorerViewModel)
    var terminal: any TerminalProviding { terminalViewModel }
    let fileContent: any FileContentProviding = LocalFileContentProvider()

    func activate() { activateIfNeeded() }
    func ensureExplorerLoaded() { ensureExplorerLoadedIfNeeded() }

    // MARK: - Private

    private let layoutPersistence: LayoutPersistenceService
    private let vibespaceManagement: VibeSpaceManagementService
    private let vibespaceID: UUID?
    private let detachedWindowManager: EditorDetachedWindowManaging
    private let directoryWatcher: any FileSystemEventWatching
    private var cancellables = Set<AnyCancellable>()
    private var hasActivatedCore = false
    private var hasLoadedExplorer = false
    private var hasShutdown = false

    init(
        rootURL: URL,
        dependencies: ProjectSessionDependencies
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.layoutPersistence = dependencies.layoutPersistence
        self.vibespaceManagement = dependencies.vibespaceManagement
        self.vibespaceID = dependencies.vibespaceID
        self.detachedWindowManager = dependencies.detachedWindowManager
        self.directoryWatcher = dependencies.directoryWatcher
        self.folderExplorerViewModel = dependencies.folderExplorerViewModelFactory()
        self.terminalViewModel = dependencies.terminalViewModelFactory()
    }

    var title: String {
        let name = rootURL.lastPathComponent
        return name.isEmpty ? rootURL.path : name
    }

    func activateIfNeeded() {
        guard !hasShutdown else { return }
        guard !hasActivatedCore else { return }
        hasActivatedCore = true

        wireViewModels()
        restoreLocalSessionState()
        wireLocalPersistence()
        startWatchingProjectRoot()
    }

    /// Filesystem watching is a project-session lifecycle resource, not an
    /// explorer-view concern. Started here at activation (vibespace hydration)
    /// so external edits — e.g. by an agent — reload open editors and docked
    /// file tiles in any canvas mode, even when the explorer is never shown.
    /// Stopped in `shutdown()`. The explorer is one consumer of the events.
    private func startWatchingProjectRoot() {
        directoryWatcher.setOnEvent { [weak self] event in
            Task { @MainActor [weak self] in
                self?.folderExplorerViewModel.ingestFileSystemEvent(event)
            }
        }
        directoryWatcher.updateWatchedPaths([rootURL.standardizedFileURL.path])
    }

    func ensureExplorerLoadedIfNeeded() {
        activateIfNeeded()
        guard !hasShutdown else { return }
        guard !hasLoadedExplorer else { return }
        hasLoadedExplorer = true
        folderExplorerViewModel.setRootFolder(self.rootURL)
    }

    func shutdown() {
        guard !hasShutdown else { return }
        hasShutdown = true
        persistLocalSessionState()
        onFileOpenRequested = nil
        onFileRenamed = nil
        cancellables.removeAll()
        terminalViewModel.shutdown()
        // The session owns the filesystem `DirectoryWatcher` (started in
        // `activate()`); stop it here. Per coding-guidelines "explicit
        // shutdown() for long-lived resources", also shut down the explorer,
        // which still owns pending main-actor refresh work items.
        directoryWatcher.invalidate()
        folderExplorerViewModel.shutdown()
    }

    private func wireViewModels() {
        // F044-R04: stamp the vibespace ID onto every terminal session this
        // project's view model creates, so spawned shells get
        // `CRISPY_VIBESPACE=vibespace.<uuid>` in their env. Composes with any
        // existing configurator by wrapping it.
        let vibespaceID = self.vibespaceID
        let existingConfigurator = terminalViewModel.sessionConfigurator
        terminalViewModel.sessionConfigurator = { session in
            session.vibespaceID = vibespaceID
            existingConfigurator?(session)
        }

        folderExplorerViewModel.$openRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                guard let self, let request else { return }
                self.folderExplorerViewModel.openRequest = nil
                if request.action == .openWindow {
                    self.detachedWindowManager.openWindow(for: request.fileURL)
                } else if let handler = self.onFileOpenRequested {
                    handler(request)
                }
            }
            .store(in: &cancellables)

        folderExplorerViewModel.renameEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                self?.onFileRenamed?(event)
            }
            .store(in: &cancellables)
    }

    private func wireLocalPersistence() {
        terminalViewModel.tabsPublisher
            .combineLatest(terminalViewModel.activeTabIDPublisher)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.persistLocalSessionState()
            }
            .store(in: &cancellables)

        $paneLayout
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] paneLayout in
                guard let self else { return }
                self.layoutPersistence.setPaneLayout(paneLayout, for: self.rootURL)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.layoutPersistence.setPaneLayout(self.paneLayout, for: self.rootURL)
                self.persistLocalSessionState()
                self.terminalViewModel.shutdown()
            }
            .store(in: &cancellables)
    }

    private func restoreLocalSessionState() {
        paneLayout = layoutPersistence.paneLayout(for: rootURL)
        ProjectTerminalSessionPersistence.restore(
            into: terminalViewModel,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID,
            projectIdentifier: metadata.identifier,
            defaultDirectory: rootURL,
            pathMapper: { [self] rawPath in
                normalizedPersistedPath(rawPath)
            }
        )
    }

    private func persistLocalSessionState() {
        ProjectTerminalSessionPersistence.persist(
            from: terminalViewModel,
            vibespaceManagement: vibespaceManagement,
            vibespaceID: vibespaceID,
            projectIdentifier: metadata.identifier
        )
    }

    private func normalizedPersistedPath(_ rawPath: String) -> String {
        let cleanedPath = rawPath.replacingOccurrences(of: "\\/", with: "/")
        return URL(fileURLWithPath: cleanedPath).standardizedFileURL.path
    }
}

@MainActor
final class EditorDetachedWindowManager {
    private var windowsByPath: [String: NSWindow] = [:]
    private var closeObserversByPath: [String: NSObjectProtocol] = [:]
    private let markdownViewModelFactory: @MainActor () -> MarkdownViewModel

    init(markdownViewModelFactory: @escaping @MainActor () -> MarkdownViewModel) {
        self.markdownViewModelFactory = markdownViewModelFactory
    }

    func openWindow(for fileURL: URL) {
        let normalizedURL = fileURL.standardizedFileURL
        let key = normalizedURL.path

        if let existingWindow = windowsByPath[key] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DetachedEditorWindowView(
            fileURL: normalizedURL,
            markdownViewModelFactory: markdownViewModelFactory
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.setContentSize(NSSize(width: 980, height: 680))
        window.minSize = NSSize(width: 760, height: 520)
        window.title = normalizedURL.lastPathComponent

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.teardownWindow(forPath: key)
            }
        }

        closeObserversByPath[key] = observer
        windowsByPath[key] = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func teardownWindow(forPath path: String) {
        if let observer = closeObserversByPath.removeValue(forKey: path) {
            NotificationCenter.default.removeObserver(observer)
        }
        windowsByPath.removeValue(forKey: path)
    }

    deinit {
        for observer in closeObserversByPath.values {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

extension EditorDetachedWindowManager: EditorDetachedWindowManaging {}

private struct DetachedEditorWindowView: View {
    let fileURL: URL
    @StateObject private var viewModel: MarkdownViewModel

    init(
        fileURL: URL,
        markdownViewModelFactory: @escaping @MainActor () -> MarkdownViewModel
    ) {
        let normalizedURL = fileURL.standardizedFileURL
        self.fileURL = normalizedURL
        _viewModel = StateObject(
            wrappedValue: {
                let model = markdownViewModelFactory()
                model.openFileInTab(at: normalizedURL)
                return model
            }()
        )
    }

    var body: some View {
        MarkdownEditorView(viewModel: viewModel)
            .frame(minWidth: 760, minHeight: 520)
            .accessibilityIdentifier("editor.window.detached")
    }
}
