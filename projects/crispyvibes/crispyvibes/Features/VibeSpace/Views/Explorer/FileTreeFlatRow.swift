import SwiftUI
import UniformTypeIdentifiers

// MARK: - Action enum

enum FileTreeAction {
    case toggleExpansion(FileItem)
    case select(FileItem)
    case openInTab(FileItem)
    case openInFinder(URL)
    case createNewFile(FileItem?)
    case createNewFolder(FileItem?)
    case startRenaming(FileItem)
    case commitRename
    case cancelRename
    case openInTerminal(URL)
    case openInSplitHorizontal(FileItem)
    case openInSplitVertical(FileItem)
    case requestDelete(FileItem)
}

// MARK: - Row view

struct FileTreeFlatRow: Equatable, View {
    let item: FileItem
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let isRenaming: Bool
    let searchQuery: String

    var renameText: Binding<String>
    var onAction: (FileTreeAction) -> Void
    var onMoveDrop: ([NSItemProvider], URL) -> Bool

    static func == (lhs: FileTreeFlatRow, rhs: FileTreeFlatRow) -> Bool {
        lhs.item == rhs.item
            && lhs.depth == rhs.depth
            && lhs.isExpanded == rhs.isExpanded
            && lhs.isSelected == rhs.isSelected
            && lhs.isRenaming == rhs.isRenaming
            && lhs.searchQuery == rhs.searchQuery
    }

    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale

    private var ignoredOpacity: Double { item.isGitIgnored && !isSelected ? 0.48 : 1.0 }
    private var directoryURL: URL { item.isDirectory ? item.url : item.url.deletingLastPathComponent() }

    var body: some View {
        Button {
            if item.isDirectory {
                onAction(.toggleExpansion(item))
            } else {
                onAction(.select(item))
            }
        } label: {
            HStack(spacing: uiScale.spacing(6)) {
                Image(systemName: item.isDirectory ? (isExpanded ? "chevron.down" : "chevron.right") : "")
                    .font(AppTypographyTokens.scaledIcon(9, weight: .semibold))
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .frame(width: uiScale.iconSize(10), height: uiScale.iconSize(10))

                if let iconName = item.setiIconName {
                    SetiIconView(iconName: iconName, size: 16)
                        .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
                        .opacity(ignoredOpacity)
                } else {
                    Image(systemName: item.isDirectory ? "folder" : (item.isMarkdown ? "doc.richtext.fill" : "doc.fill"))
                        .font(AppTypographyTokens.scaledIcon(14))
                        .foregroundStyle(item.isDirectory ? appThemePalette.directoryIconColor : appThemePalette.secondaryTextColor)
                        .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
                        .opacity(ignoredOpacity)
                }

                if isRenaming {
                    TextField("Name", text: renameText, onCommit: { onAction(.commitRename) })
                        .textFieldStyle(.plain)
                        .font(AppTypographyTokens.caption)
                        .accessibilityIdentifier("explorer.rename.field")
                        .onExitCommand { onAction(.cancelRename) }
                } else {
                    highlightedText(name: item.displayName, query: searchQuery)
                        .font(AppTypographyTokens.caption)
                        .accessibilityIdentifier("explorer.row.label")
                        .lineLimit(1)
                        .opacity(ignoredOpacity)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, uiScale.spacing(3))
            .padding(.leading, CGFloat(depth) * uiScale.spacing(10))
            .padding(.trailing, uiScale.spacing(4))
            .background(isSelected ? appThemePalette.selectionBackgroundColor.opacity(0.24) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !item.isDirectory else { return }
                onAction(.openInTab(item))
            }
        )
        .contextMenu {
            if item.isDirectory {
                Button(AppStrings.Explorer.newFile) { onAction(.createNewFile(item)) }
                Button(AppStrings.Explorer.newFolder) { onAction(.createNewFolder(item)) }
                Divider()
            }
            Button(AppStrings.Explorer.openInTerminal) { onAction(.openInTerminal(directoryURL)) }
            if !item.isDirectory {
                Button(AppStrings.Explorer.openInSplitHorizontal) { onAction(.openInSplitHorizontal(item)) }
                Button(AppStrings.Explorer.openInSplitVertical) { onAction(.openInSplitVertical(item)) }
            }
            Divider()
            Button(AppStrings.Common.rename) { onAction(.startRenaming(item)) }
            if !item.isDirectory {
                Button(AppStrings.Explorer.revealInFinder) { onAction(.openInFinder(item.url)) }
                Divider()
            }
            Button(AppStrings.Common.delete, role: .destructive) { onAction(.requestDelete(item)) }
        }
        .onDrag { NSItemProvider(object: item.id as NSString) }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            onMoveDrop(providers, directoryURL)
        }
    }

    private func highlightedText(name: String, query: String) -> Text {
        guard !query.isEmpty,
              let range = name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        else { return Text(name) }

        let prefix = String(name[..<range.lowerBound])
        let match = String(name[range])
        let suffix = String(name[range.upperBound...])
        return Text(prefix) + Text(match).bold().foregroundColor(appThemePalette.accentColor) + Text(suffix)
    }
}
