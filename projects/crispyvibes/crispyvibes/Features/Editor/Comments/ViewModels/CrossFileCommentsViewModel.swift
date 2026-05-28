import Combine
import Foundation

/// F049-R15: view model for the workspace-wide "All Comments" view.
///
/// Owns the filter/group/sort pipeline so the SwiftUI view only renders the
/// computed result. Re-runs the pipeline whenever the underlying store
/// emits a change, the status filter changes, or the search query changes.
@MainActor
final class CrossFileCommentsViewModel: ObservableObject {

    /// One file (or browser URL)'s worth of threads, grouped under a label
    /// for display.
    struct FileGroup: Identifiable, Equatable {
        let surfaceKind: CommentSurfaceKind
        let filePath: String
        let fileLabel: String
        let threads: [CommentThread]
        var id: String { "\(surfaceKind.rawValue)::\(filePath)" }
    }

    /// Top-level section grouping (Files vs Browsers).
    struct Section: Identifiable, Equatable {
        let surfaceKind: CommentSurfaceKind
        let title: String
        let groups: [FileGroup]
        var id: String { surfaceKind.rawValue }
    }

    @Published private(set) var sections: [Section] = []

    @Published var statusFilter: CommentStatusFilter = .active {
        didSet { recompute() }
    }
    @Published var searchQuery: String = "" {
        didSet { recompute() }
    }

    private let store: VibeSpaceCommentStore
    private var subscriptions: Set<AnyCancellable> = []

    init(store: VibeSpaceCommentStore) {
        self.store = store
        store.$threadsByFile
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &subscriptions)
        recompute()
    }

    func refresh() async {
        await store.refreshAll()
    }

    private func recompute() {
        let raw = store.threadsByFile
        var groupsByKind: [CommentSurfaceKind: [FileGroup]] = [:]
        for (key, threads) in raw {
            let filtered = CommentsPanelStore.filter(
                threads,
                status: statusFilter,
                query: searchQuery
            )
            guard !filtered.isEmpty else { continue }
            let kind = filtered.first?.root.surfaceKind ?? .file
            let label: String
            switch kind {
            case .file:
                label = AppStrings.Comments.crossFileFileLabel(
                    name: URL(fileURLWithPath: key.filePath).lastPathComponent,
                    path: key.filePath
                )
            case .browser:
                label = key.filePath
            }
            groupsByKind[kind, default: []].append(
                FileGroup(
                    surfaceKind: kind,
                    filePath: key.filePath,
                    fileLabel: label,
                    threads: filtered
                )
            )
        }

        var out: [Section] = []
        if let fileGroups = groupsByKind[.file] {
            out.append(Section(
                surfaceKind: .file,
                title: AppStrings.Comments.crossFileSectionFiles,
                groups: fileGroups.sorted { $0.fileLabel < $1.fileLabel }
            ))
        }
        if let browserGroups = groupsByKind[.browser] {
            out.append(Section(
                surfaceKind: .browser,
                title: AppStrings.Comments.crossFileSectionBrowsers,
                groups: browserGroups.sorted { $0.fileLabel < $1.fileLabel }
            ))
        }
        sections = out
    }
}
