import SwiftUI

struct GitStatusSection: Identifiable {
    let title: String
    let items: [GitStatusItem]

    var id: String { title }
}

struct GitStatusBadgePresentation {
    let text: String
    let color: Color
}

extension FolderExplorerView {
    var gitSections: [GitStatusSection] {
        var staged: [GitStatusItem] = []
        var unstaged: [GitStatusItem] = []

        staged.reserveCapacity(viewModel.gitStatusItems.count)
        unstaged.reserveCapacity(viewModel.gitStatusItems.count)

        for item in viewModel.gitStatusItems {
            if item.isStaged {
                staged.append(item)
            }
            if item.hasUnstagedChanges || !item.isStaged {
                unstaged.append(item)
            }
        }

        var sections: [GitStatusSection] = []
        if !staged.isEmpty {
            sections.append(GitStatusSection(title: "Staged", items: staged))
        }
        if !unstaged.isEmpty {
            sections.append(GitStatusSection(title: "Changes", items: unstaged))
        }
        return sections
    }

    func gitBadgePresentation(for code: String) -> GitStatusBadgePresentation {
        if code == "??" {
            return GitStatusBadgePresentation(text: "A", color: appThemePalette.gitAddedStatusColor)
        }
        if code.contains("U") {
            return GitStatusBadgePresentation(text: "U", color: appThemePalette.gitConflictStatusColor)
        }
        if code.contains("R") || code.contains("C") {
            return GitStatusBadgePresentation(text: "R", color: appThemePalette.gitRenamedStatusColor)
        }
        if code.contains("D") {
            return GitStatusBadgePresentation(text: "D", color: appThemePalette.gitDeletedStatusColor)
        }
        if code.contains("A") {
            return GitStatusBadgePresentation(text: "A", color: appThemePalette.gitAddedStatusColor)
        }
        if code.contains("M") {
            return GitStatusBadgePresentation(text: "M", color: appThemePalette.gitModifiedStatusColor)
        }

        let trimmed = code.trimmingCharacters(in: .whitespaces)
        return GitStatusBadgePresentation(
            text: trimmed.isEmpty ? "?" : trimmed,
            color: appThemePalette.secondaryTextColor
        )
    }
}
