import SwiftUI

struct VibeSpaceTerminalCreateSheet: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let projects: [AnyProjectSession]
    let initialProjectPath: String?
    let onCreate: (String?, URL) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var browseEntries: [BrowseEntry] = []
    @State private var selectedIndex = 0
    @State private var isLoading = false
    @FocusState private var isSearchFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            resultsList
            Divider()
            footer
        }
        .frame(minWidth: 520, maxWidth: 520, minHeight: 300, maxHeight: 460)
        .scrollAssistGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 6)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: query) { _, newValue in
            selectedIndex = 0
            refreshBrowse(for: newValue)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.magnifyingglass")
                .font(AppTypographyTokens.scaledSystem(13, weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)

            TextField(
                isBrowsing ? "Filter or type path\u{2026}" : "Type a path or pick a project\u{2026}",
                text: $query
            )
            .textFieldStyle(.plain)
            .font(AppTypographyTokens.body)
            .focused($isSearchFocused)
            .onKeyPress(.upArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.return) {
                createTerminal()
                return .handled
            }
            .onKeyPress(.tab) {
                if let entry = selectedEntry, entry.isDirectory {
                    navigateInto(entry)
                }
                return .handled
            }
            .onKeyPress(.delete) {
                if query.isEmpty { return .ignored }
                if isBrowsing, filterSegment.isEmpty {
                    navigateUp()
                    return .handled
                }
                return .ignored
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    browseEntries = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.tertiaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Results

    private var displayedItems: [DisplayItem] {
        if isBrowsing {
            return browseDisplayItems
        }
        return projectPickerItems
    }

    private var projectPickerItems: [DisplayItem] {
        let filterText = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return projects
            .map { project -> DisplayItem in
                let url = project.rootURL.standardizedFileURL
                return DisplayItem(
                    id: url.path,
                    name: url.lastPathComponent,
                    displayPath: VibeSpaceDirectoryCandidate.formatDisplayPath(for: url.path),
                    path: url.path,
                    isDirectory: true,
                    isProjectRoot: true
                )
            }
            .filter { filterText.isEmpty || $0.name.lowercased().contains(filterText) || $0.displayPath.lowercased().contains(filterText) }
    }

    private var browseDisplayItems: [DisplayItem] {
        let filter = filterSegment.lowercased()
        let showHidden = filterSegment.hasPrefix(".")

        var items: [DisplayItem] = []

        // Parent navigation
        if canNavigateUp {
            items.append(DisplayItem(
                id: "..",
                name: "..",
                displayPath: parentDirectoryDisplayPath,
                path: "",
                isDirectory: true,
                isProjectRoot: false
            ))
        }

        let filtered = browseEntries.filter { entry in
            let nameMatch = filter.isEmpty || entry.name.lowercased().hasPrefix(filter)
            let hiddenMatch = showHidden || !entry.name.hasPrefix(".")
            return nameMatch && hiddenMatch
        }

        for entry in filtered {
            items.append(DisplayItem(
                id: entry.path,
                name: entry.name,
                displayPath: entry.name + (entry.isDirectory ? "/" : ""),
                path: entry.path,
                isDirectory: entry.isDirectory,
                isProjectRoot: false
            ))
        }

        return items
    }

    private var selectedEntry: DisplayItem? {
        let items = displayedItems
        guard !items.isEmpty else { return nil }
        let idx = min(selectedIndex, items.count - 1)
        return items[idx]
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                        itemRow(item, isSelected: index == selectedIndex)
                            .id(item.id)
                            .onTapGesture(count: 2) {
                                selectedIndex = index
                                if item.id == ".." {
                                    navigateUp()
                                } else if item.isDirectory && isBrowsing {
                                    navigateInto(item)
                                }
                            }
                            .onTapGesture {
                                selectedIndex = index
                                createTerminal()
                            }
                    }

                    if displayedItems.isEmpty {
                        emptyState
                    }
                }
                .padding(6)
            }
            .onChange(of: selectedIndex) { _, _ in
                if let id = selectedEntry?.id {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: DisplayItem, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: itemIcon(for: item))
                .font(AppTypographyTokens.scaledIcon(11))
                .foregroundStyle(itemIconColor(for: item))
                .frame(width: uiScale.iconSize(14))

            Text(item.displayPath)
                .font(item.isProjectRoot ? AppTypographyTokens.captionSemibold : AppTypographyTokens.caption)
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if isSelected && item.isDirectory && item.id != ".." {
                Text("tab \u{21E5}")
                    .font(AppTypographyTokens.scaledSystem(9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.tertiaryTextColor)
            }

            if isSelected {
                Text("\u{21A9}")
                    .font(AppTypographyTokens.scaledSystem(11, weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous)
                .fill(isSelected ? palette.selectionBackgroundColor.opacity(0.24) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func itemIcon(for item: DisplayItem) -> String {
        if item.id == ".." { return "arrow.turn.up.left" }
        if item.isProjectRoot { return "folder.fill" }
        if item.isDirectory { return "folder" }
        return "doc"
    }

    private func itemIconColor(for item: DisplayItem) -> Color {
        if item.isProjectRoot { return palette.accentColor }
        return palette.secondaryTextColor
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 4) {
            if isLoading {
                Text("Loading\u{2026}")
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            } else {
                Text(isBrowsing ? "No matching entries" : "No matching projects")
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if isBrowsing {
                Image(systemName: "folder")
                    .font(AppTypographyTokens.scaledSystem(10))
                    .foregroundStyle(palette.tertiaryTextColor)
                Text(currentBrowseDirectory)
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else if let entry = selectedEntry {
                Image(systemName: "terminal")
                    .font(AppTypographyTokens.scaledSystem(10))
                    .foregroundStyle(palette.tertiaryTextColor)
                Text(entry.displayPath)
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text("⇥ browse  ⏎ create")
                .font(AppTypographyTokens.scaledSystem(10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.tertiaryTextColor)

            Button(AppStrings.Common.cancel) {
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button(AppStrings.Terminal.createTerminal) {
                createTerminal()
            }
            .buttonStyle(.crispyvibesPrimary)
            .disabled(resolvedDirectoryURL == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Browse State

    private var isBrowsing: Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.hasPrefix("/") || q.hasPrefix("~/")
    }

    private var currentBrowseDirectory: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastSlash = q.lastIndex(of: "/") else { return q }
        return String(q[...lastSlash])
    }

    private var filterSegment: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastSlash = q.lastIndex(of: "/") else { return q }
        return String(q[q.index(after: lastSlash)...])
    }

    private var canNavigateUp: Bool {
        let dir = currentBrowseDirectory
        let expanded = expandPath(dir)
        return expanded != "/" && !expanded.isEmpty
    }

    private var parentDirectoryDisplayPath: String {
        let dir = currentBrowseDirectory
        let trimmed = dir.hasSuffix("/") && dir.count > 1 ? String(dir.dropLast()) : dir
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return "/" }
        let parent = String(trimmed[...lastSlash])
        return parent.isEmpty ? "/" : parent
    }

    private var resolvedDirectoryURL: URL? {
        if let entry = selectedEntry {
            if entry.id == ".." { return nil }
            if entry.isDirectory {
                return URL(fileURLWithPath: entry.path).standardizedFileURL
            }
        }
        if isBrowsing {
            let expanded = expandPath(currentBrowseDirectory)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded).standardizedFileURL
            }
        }
        return nil
    }

    // MARK: - Actions

    private func createTerminal() {
        guard let directoryURL = resolvedDirectoryURL else { return }
        let projectPath = inferredProjectPath(for: directoryURL)
        onCreate(projectPath, directoryURL)
        onDismiss()
    }

    private func navigateInto(_ item: DisplayItem) {
        guard item.isDirectory else { return }
        let displayPath = VibeSpaceDirectoryCandidate.formatDisplayPath(for: item.path)
        query = displayPath.hasSuffix("/") ? displayPath : displayPath + "/"
    }

    private func navigateUp() {
        let parent = parentDirectoryDisplayPath
        query = parent
    }

    private func moveSelection(by offset: Int) {
        let count = displayedItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + offset + count) % count
    }

    private func refreshBrowse(for newQuery: String) {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") else {
            browseEntries = []
            return
        }

        let dirPath = currentBrowseDirectory
        let expanded = expandPath(dirPath)

        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = listDirectory(at: expanded)
            DispatchQueue.main.async {
                self.browseEntries = entries
                self.isLoading = false
                self.clampSelection()
            }
        }
    }

    private func clampSelection() {
        let count = displayedItems.count
        if count == 0 {
            selectedIndex = 0
        } else if selectedIndex >= count {
            selectedIndex = count - 1
        }
    }

    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + path.dropFirst(1)
        }
        return path
    }

    private func inferredProjectPath(for directoryURL: URL) -> String? {
        let dirPath = directoryURL.standardizedFileURL.path
        return projects
            .map { $0.rootURL.standardizedFileURL.path }
            .filter { dirPath == $0 || dirPath.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }
}

// MARK: - Directory Listing

private func listDirectory(at path: String) -> [BrowseEntry] {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsPackageDescendants]
    ) else {
        return []
    }

    let skipped: Set<String> = [
        "node_modules", ".build", "DerivedData", ".git", ".svn", ".hg",
        "Pods", "Carthage", ".swiftpm", "__pycache__", ".tox", ".venv",
        "dist", "build", ".next", ".nuxt", "SourcePackages"
    ]

    var entries: [BrowseEntry] = []
    for itemURL in contents {
        let name = itemURL.lastPathComponent
        let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDir = values?.isDirectory ?? false
        if isDir && skipped.contains(name) { continue }
        entries.append(BrowseEntry(
            name: name,
            path: itemURL.standardizedFileURL.path,
            isDirectory: isDir
        ))
    }

    return entries.sorted { lhs, rhs in
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - Models

private struct BrowseEntry: Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    var id: String { path }
}

private struct DisplayItem: Identifiable {
    let id: String
    let name: String
    let displayPath: String
    let path: String
    let isDirectory: Bool
    let isProjectRoot: Bool
}
