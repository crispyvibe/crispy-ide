import Foundation

extension FolderExplorerViewModel {
    enum SidebarTab: String, CaseIterable, Identifiable {
        case files
        case git
        case sessions
        case conversations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .files:
                return "Files"
            case .git:
                return "Git"
            case .sessions:
                return AppStrings.Sidebar.sessionsTab
            case .conversations:
                return "Conversations"
            }
        }
    }

    enum GitState {
        case idle
        case loading
        case ready
        case gitUnavailable
        case notRepository
        case error
    }
}

struct GitStatusItem: Identifiable {
    let code: String
    let indexStatus: String
    let workTreeStatus: String
    let relativePath: String
    let url: URL

    var id: String { "\(relativePath)|\(code)" }

    var isUntracked: Bool {
        code == "??" || indexStatus == "?" || workTreeStatus == "?"
    }

    var isStaged: Bool {
        guard !isUntracked else { return false }
        return indexStatus != " "
    }

    var hasUnstagedChanges: Bool {
        if isUntracked { return true }
        return workTreeStatus != " "
    }

    var isDeleted: Bool { code.contains("D") }
    var canStage: Bool { hasUnstagedChanges || isUntracked }
    var canUnstage: Bool { isStaged }
}

struct GitBranchOption: Identifiable, Equatable {
    let name: String
    let displayName: String
    let isCurrent: Bool
    let isRemote: Bool

    var id: String { "\(isRemote ? "remote" : "local")|\(name)" }
}

struct GitCommitEntry: Identifiable, Equatable {
    let hash: String
    let shortHash: String
    let authorName: String
    let authoredDate: String
    let subject: String

    var id: String { hash }
}

enum GitHistoryScope: Equatable, Identifiable {
    case repository
    case file(relativePath: String)

    var id: String {
        switch self {
        case .repository:
            return "repository"
        case let .file(relativePath):
            return "file|\(relativePath)"
        }
    }

    var title: String {
        switch self {
        case .repository:
            return "Commit History"
        case let .file(relativePath):
            return "File History: \(relativePath)"
        }
    }
}

enum ExplorerOpenAction: Equatable {
    case preview
    case openTab
    case openWindow
    case openInSplitHorizontal
    case openInSplitVertical
    case compareGitStatus(code: String, relativePath: String)
}

struct ExplorerOpenRequest: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    let action: ExplorerOpenAction
}

struct ExplorerRenameEvent: Equatable {
    let oldURL: URL
    let newURL: URL
}
