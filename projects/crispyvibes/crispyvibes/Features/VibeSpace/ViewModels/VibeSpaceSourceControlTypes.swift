import Foundation

typealias PaneWorkerFactory = @Sendable (PaneWorkerKind) -> any PaneWorkerExecuting

struct VibeSpaceSourceControlProjectReference: Identifiable {
    let rootURL: URL
    let title: String
    let orderIndex: Int
    let projectIdentifier: String
    let usesProjectGitBackend: Bool
    let gitExplorer: AnyGitExplorer?

    var id: String { projectIdentifier }

    static func == (lhs: VibeSpaceSourceControlProjectReference, rhs: VibeSpaceSourceControlProjectReference) -> Bool {
        lhs.rootURL == rhs.rootURL
            && lhs.title == rhs.title
            && lhs.orderIndex == rhs.orderIndex
            && lhs.projectIdentifier == rhs.projectIdentifier
            && lhs.usesProjectGitBackend == rhs.usesProjectGitBackend
    }

    func repositoryIdentifier(for repositoryRootURL: URL) -> String {
        let normalizedRepositoryPath = repositoryRootURL.standardizedFileURL.path
        if usesProjectGitBackend {
            return "\(projectIdentifier)|\(normalizedRepositoryPath)"
        }
        return normalizedRepositoryPath
    }
}

struct VibeSpaceSourceControlStatusItem: Identifiable, Equatable {
    let repositoryRootURL: URL
    let code: String
    let indexStatus: String
    let workTreeStatus: String
    let relativePath: String
    let url: URL

    var id: String { "\(relativePath)|\(code)" }
    var fileName: String { url.lastPathComponent }

    var parentRelativePath: String? {
        let directoryPath = (relativePath as NSString).deletingLastPathComponent
        return directoryPath == "." || directoryPath.isEmpty ? nil : directoryPath
    }

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

    var lacksCommittedHistory: Bool {
        isUntracked || indexStatus == "A"
    }

    var isDeleted: Bool {
        code.contains("D")
    }

    var canStage: Bool { hasUnstagedChanges || isUntracked }
    var canUnstage: Bool { isStaged }
    var canDiscardChanges: Bool { hasUnstagedChanges && !isUntracked }
}

enum VibeSpaceSourceControlHistoryScope: Equatable, Identifiable {
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
