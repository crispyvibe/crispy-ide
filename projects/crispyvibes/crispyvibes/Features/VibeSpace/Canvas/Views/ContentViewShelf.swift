import AppKit
import OSLog
import SwiftUI

/// F052: pasteboard type used when dragging a Shelf item into a project's file
/// tree to move it there. Distinct from `VibeSpaceDragPayload` so the explorer
/// can treat a shelf drop as a move-with-retarget instead of a plain copy.
enum ShelfItemDrag {
    static let identifier = "com.crispyvibe.app.shelf-item"
    static let pasteboardType = NSPasteboard.PasteboardType(identifier)
    /// The path of the item currently being dragged from the Shelf. In-app drags
    /// carry the type marker on the pasteboard (for drop validation) but the path
    /// is read from here — reading custom-type data back from a SwiftUI `.onDrag`
    /// provider in an AppKit drop is unreliable. Main-actor isolated; set at drag
    /// start and read on drop (both on the main thread). It is overwritten by
    /// every drag start, so a value left over from a cancelled drag is harmless.
    @MainActor static var draggingPath: String?
    static let logger = Logger(subsystem: "com.crispyvibe.app", category: "shelf.drag")
}

struct ShelfSidebarSectionView: View {
    private struct ShelfEntry: Identifiable, Equatable {
        let path: String

        var id: String { path }
        var fileURL: URL { URL(fileURLWithPath: path).standardizedFileURL }
        var title: String {
            let name = fileURL.lastPathComponent
            return name.isEmpty ? fileURL.path : name
        }
        var directoryURL: URL {
            fileURL.deletingLastPathComponent()
        }
        var exists: Bool {
            FileManager.default.fileExists(atPath: fileURL.path)
        }
        var isDirectory: Bool {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) && isDir.boolValue
        }
        var setiIconName: String? {
            FileIconProvider.iconName(for: fileURL.pathExtension)
        }

        var children: [ShelfEntry] {
            guard isDirectory else { return [] }
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) else { return [] }
            return contents
                .sorted { a, b in
                    let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if aDir != bDir { return aDir }
                    return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
                }
                .map { ShelfEntry(path: $0.path) }
        }
    }

    @Environment(\.appThemePalette) private var activeThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @AppStorage(AppPreferences.vibespaceShelfExpandedKey) private var isExpanded = true
    @ObservedObject var shelfStore: ShelfStore

    let onOpenFile: (String) -> Void
    let onRevealInFinder: (String) -> Void
    let onOpenDirectoryInTerminal: (String) -> Void
    let onRenameFile: (String, String) throws -> Void
    let onDeleteFile: (String) throws -> Void
    let onRemoveFile: (String) -> Void
    let onClear: () -> Void

    @State private var renamingPath: String?
    @State private var renameText = ""
    @State private var pendingDeletionPath: String?
    @State private var errorMessage: String?
    @State private var expandedFolders = Set<String>()
    @FocusState private var focusedRenamePath: String?

    private var entries: [ShelfEntry] {
        shelfStore.filePaths.map(ShelfEntry.init(path:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledSystem(10, weight: .semibold))
                        .foregroundStyle(activeThemePalette.secondaryTextColor)

                    Image(systemName: "books.vertical")
                        .foregroundStyle(activeThemePalette.accentColor)

                    Text(AppStrings.Shelf.title)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(activeThemePalette.primaryTextColor)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button(isExpanded ? "Collapse Shelf" : "Expand Shelf") {
                    isExpanded.toggle()
                }
                Divider()
                Button(AppStrings.Common.clear, role: .destructive) {
                    onClear()
                }
            }
            .accessibilityIdentifier("vibespace.sidebar.shelf")

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        shelfRow(for: entry)
                    }
                }
                .padding(.leading, 10)
            }
        }
        .alert(
            AppStrings.Explorer.deleteItemTitle,
            isPresented: Binding(
                get: { pendingDeletionPath != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionPath = nil
                    }
                }
            ),
            presenting: pendingDeletionPath
        ) { path in
            Button(AppStrings.Common.delete, role: .destructive) {
                do {
                    try onDeleteFile(path)
                } catch {
                    errorMessage = error.localizedDescription
                }
                pendingDeletionPath = nil
            }
            Button(AppStrings.Common.cancel, role: .cancel) {
                pendingDeletionPath = nil
            }
        } message: { path in
            Text("Are you sure you want to delete \"\(ShelfEntry(path: path).title)\"?")
        }
        .alert(
            AppStrings.Explorer.errorTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(AppStrings.Common.ok, role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func shelfRow(for entry: ShelfEntry) -> some View {
        if entry.isDirectory {
            AnyView(shelfFolderRow(for: entry, depth: 0))
        } else {
            AnyView(shelfFileRow(for: entry, depth: 0, isTopLevel: true))
        }
    }

    private func shelfFolderRow(for entry: ShelfEntry, depth: Int) -> some View {
        let isExpanded = expandedFolders.contains(entry.path)
        return VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    if isExpanded { expandedFolders.remove(entry.path) }
                    else { expandedFolders.insert(entry.path) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTypographyTokens.scaledIcon(8, weight: .semibold))
                        .foregroundStyle(activeThemePalette.secondaryTextColor)
                        .frame(width: uiScale.iconSize(10))
                    Image(systemName: "folder.fill")
                        .font(AppTypographyTokens.scaledIcon(13))
                        .foregroundStyle(activeThemePalette.accentColor)
                        .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
                    Text(entry.title)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(activeThemePalette.primaryTextColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .padding(.leading, CGFloat(depth * 16) + 10)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { shelfEntryContextMenu(for: entry, isTopLevel: depth == 0) }

            if isExpanded {
                ForEach(entry.children) { child in
                    if child.isDirectory {
                        AnyView(shelfFolderRow(for: child, depth: depth + 1))
                    } else {
                        AnyView(shelfFileRow(for: child, depth: depth + 1, isTopLevel: false))
                    }
                }
            }
        }
    }

    private func shelfFileRow(for entry: ShelfEntry, depth: Int, isTopLevel: Bool) -> some View {
        let isSelected = shelfStore.selectedFilePath == entry.path
        let isRenaming = renamingPath == entry.path

        return Group {
            if isRenaming {
                HStack(spacing: 6) {
                    entryIcon(for: entry)
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(AppTypographyTokens.caption)
                            .focused($focusedRenamePath, equals: entry.path)
                        .onSubmit { commitRename(for: entry) }
                        .onExitCommand { cancelRename() }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .padding(.leading, CGFloat(depth * 16) + (isTopLevel ? 10 : 26))
                .padding(.trailing, 4)
                .background(isSelected ? activeThemePalette.selectionBackgroundColor.opacity(0.24) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(4), style: .continuous))
            } else {
                Button { onOpenFile(entry.path) } label: {
                    HStack(spacing: 6) {
                        entryIcon(for: entry)
                        Text(entry.title)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(activeThemePalette.primaryTextColor)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                    .padding(.leading, CGFloat(depth * 16) + (isTopLevel ? 10 : 26))
                    .padding(.trailing, 4)
                    .background(isSelected ? activeThemePalette.selectionBackgroundColor.opacity(0.24) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(4), style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(entry.exists ? 1 : 0.68)
                .contextMenu { shelfEntryContextMenu(for: entry, isTopLevel: isTopLevel) }
                .onDrag {
                    let provider = NSItemProvider()
                    let path = entry.path
                    ShelfItemDrag.draggingPath = path
                    ShelfItemDrag.logger.info("shelf onDrag begin: \(path, privacy: .public)")
                    provider.registerDataRepresentation(
                        forTypeIdentifier: ShelfItemDrag.identifier,
                        visibility: .ownProcess
                    ) { completion in
                        completion(Data(path.utf8), nil)
                        return nil
                    }
                    return provider
                }
            }
        }
        .help(entry.fileURL.path)
        .accessibilityIdentifier("vibespace.sidebar.shelf.file.\(entry.id)")
    }

    @ViewBuilder
    private func shelfEntryContextMenu(for entry: ShelfEntry, isTopLevel: Bool) -> some View {
        Button("Open") { onOpenFile(entry.path) }
        Button(AppStrings.Explorer.openInTerminal) { onOpenDirectoryInTerminal(entry.path) }
        Button(AppStrings.Explorer.revealInFinder) { onRevealInFinder(entry.path) }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.fileURL.path, forType: .string)
        }
        Divider()
        if !entry.isDirectory {
            Button(AppStrings.Common.rename) { beginRenaming(entry) }
                .disabled(!entry.exists)
        }
        if isTopLevel {
            Button("Remove from Shelf") { onRemoveFile(entry.path) }
        }
        Divider()
        Button(AppStrings.Common.delete, role: .destructive) { pendingDeletionPath = entry.path }
            .disabled(!entry.exists)
    }

    @ViewBuilder
    private func entryIcon(for entry: ShelfEntry) -> some View {
        if !entry.exists {
            Image(systemName: "exclamationmark.triangle")
                .font(AppTypographyTokens.scaledIcon(13))
                .foregroundStyle(activeThemePalette.warningColor)
                .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
        } else if entry.fileURL.hasDirectoryPath {
            Image(systemName: "folder.fill")
                .font(AppTypographyTokens.scaledIcon(13))
                .foregroundStyle(activeThemePalette.accentColor)
                .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
        } else if let iconName = entry.setiIconName {
            SetiIconView(iconName: iconName, size: 16)
                .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
        } else {
            Image(systemName: "doc.fill")
                .font(AppTypographyTokens.scaledIcon(13))
                .foregroundStyle(activeThemePalette.secondaryTextColor)
                .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
        }
    }

    private func beginRenaming(_ entry: ShelfEntry) {
        renamingPath = entry.path
        renameText = entry.title
        DispatchQueue.main.async {
            focusedRenamePath = entry.path
        }
    }

    private func commitRename(for entry: ShelfEntry) {
        do {
            try onRenameFile(entry.path, renameText)
            cancelRename()
        } catch {
            errorMessage = error.localizedDescription
            DispatchQueue.main.async {
                focusedRenamePath = entry.path
            }
        }
    }

    private func cancelRename() {
        renamingPath = nil
        renameText = ""
        focusedRenamePath = nil
    }
}
