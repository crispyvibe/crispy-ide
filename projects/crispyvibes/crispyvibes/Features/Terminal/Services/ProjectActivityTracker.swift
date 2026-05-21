import Combine
import Foundation

@MainActor
final class ProjectActivityTracker: ObservableObject {
    @Published private(set) var activeProjectPaths: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    func track(projects: [AnyProjectSession]) {
        cancellables.removeAll()
        guard !projects.isEmpty else {
            activeProjectPaths = []
            return
        }
        for project in projects {
            let path = project.rootURL.standardizedFileURL.path
            project.terminal.tabActivitySummary.$hasAnyActivity
                .removeDuplicates()
                .sink { [weak self] hasActivity in
                    guard let self else { return }
                    if hasActivity {
                        self.activeProjectPaths.insert(path)
                    } else {
                        self.activeProjectPaths.remove(path)
                    }
                }
                .store(in: &cancellables)
        }
    }
}
