// AnyProjectSession.swift — SSH Remote Development
// Type-erased wrapper for ProjectProviding. This is the ONLY project type views see.
// Forwards objectWillChange from all sub-components for SwiftUI observation.

import Combine
import Foundation

@MainActor
final class AnyProjectSession: ObservableObject, Identifiable {
    let id: UUID
    let metadata: any ProjectMetadata
    let folderExplorer: AnyFolderExplorer
    let gitExplorer: AnyGitExplorer
    let terminal: AnyTerminalProvider
    let fileContent: any FileContentProviding

    let _wrapped: any ProjectProviding
    private var cancellables = Set<AnyCancellable>()

    init<T: ProjectProviding>(_ project: T) {
        self._wrapped = project
        self.id = project.id
        self.metadata = project.metadata
        self.folderExplorer = AnyFolderExplorer(project.folderExplorer)
        self.gitExplorer = AnyGitExplorer(project.gitExplorer)
        self.terminal = AnyTerminalProvider(project.terminal)
        self.fileContent = project.fileContent

        // Bubble up objectWillChange from sub-components
        folderExplorer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        gitExplorer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        terminal.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var paneLayout: ProjectPaneLayoutState {
        get { _wrapped.paneLayout }
        set { _wrapped.paneLayout = newValue }
    }

    var onFileOpenRequested: ((ExplorerOpenRequest) -> Void)? {
        get { _wrapped.onFileOpenRequested }
        set { _wrapped.onFileOpenRequested = newValue }
    }

    var onFileRenamed: ((ExplorerRenameEvent) -> Void)? {
        get { _wrapped.onFileRenamed }
        set { _wrapped.onFileRenamed = newValue }
    }

    func activate() { _wrapped.activate() }
    func ensureExplorerLoaded() { _wrapped.ensureExplorerLoaded() }
    func shutdown() { _wrapped.shutdown() }
}
