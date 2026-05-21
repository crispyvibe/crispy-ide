import AppKit
import SwiftUI

struct VibeSpaceSidebarConversationsPane: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: AgentConversationStore

    let externalSessionService: ExternalAgentSessionService
    let vibespaceID: UUID?
    let vibespaceName: String?
    let projectColorTagsByPath: [String: ProjectColorTag]
    let onOpenThread: (ConversationThreadSummary) -> Void
    let onDeleteThread: (String) async -> Void
    let onExportMarkdown: (String) async -> Void
    let onExportJSON: (String) async -> Void
    let onPreviewExternalSession: (ExternalAgentTranscript) -> Void

    @State private var threads: [ConversationThreadSummary] = []
    @State private var otherThreads: [ConversationThreadSummary] = []
    @State private var searchText = ""
    @State private var searchResults: [FTSSearchResult] = []
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var isRefreshVisible = false
    @State private var searchTask: Task<Void, Never>?
    @State private var editingThreadId: String?
    @State private var editingTitle: String = ""
    @State private var expandedSections: Set<String> = ["vibespace"]
    @State private var pendingDeleteId: String?
    @State private var selectedTab: ConversationSidebarTab = .crispyvibes

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text(AppStrings.Sidebar.Conversations.crispyvibes).tag(ConversationSidebarTab.crispyvibes)
                Text(AppStrings.Sidebar.Conversations.external).tag(ConversationSidebarTab.external)
            }
            .pickerStyle(.segmented)
            .font(AppTypographyTokens.captionSemibold)
            .controlSize(uiScale.controlSize)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if selectedTab == .crispyvibes {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        toolbarRow

                        if !searchText.isEmpty {
                            searchResultsSection
                        } else if !isLoading, threads.isEmpty {
                            emptyState
                        } else {
                            vibespaceSection
                            if !otherThreads.isEmpty {
                                otherVibeSpacesSection
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VibeSpaceSidebarExternalSessionsPane(
                    service: externalSessionService,
                    onPreviewSession: onPreviewExternalSession
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("vibespace.sidebar.conversations")
        .transaction { $0.animation = nil }
        .task { await loadThreads() }
        .onChange(of: store.state) { _, _ in Task { await loadThreads() } }
        .onChange(of: store.threadChangeCounter) { _, _ in Task { await loadThreads() } }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty { searchResults = []; isSearching = false; return }
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                let result = await store.send(method: "search.keyword", params: ["query": query, "limit": 30])
                guard !Task.isCancelled,
                      let matches = result?.value?["matches"] as? [[String: Any]] else {
                    isSearching = false
                    return
                }
                searchResults = matches.compactMap { FTSSearchResult(json: $0) }
                isSearching = false
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTypographyTokens.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(palette.canvasBackgroundColor.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(palette.borderColorValue.opacity(0.35), lineWidth: 1)
            )

            Spacer(minLength: 4)

            ProgressView()
                .controlSize(uiScale.controlSize)
                .opacity(isRefreshVisible ? 1 : 0)
                .frame(width: uiScale.iconSize(14))

            Button { refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh conversations")
            .accessibilityIdentifier("vibespace.sidebar.conversations.refresh")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refresh() {
        isRefreshVisible = true
        Task {
            await loadThreads()
            try? await Task.sleep(nanoseconds: 300_000_000)
            isRefreshVisible = false
        }
    }

    // MARK: - VibeSpace Section (top level, like sessions pane)

    private var vibespaceSection: some View {
        DisclosureGroup(
            isExpanded: sectionBinding("vibespace")
        ) {
            VStack(alignment: .leading, spacing: 4) {
                let projectGroups = Dictionary(grouping: threads) { $0.projectPath }
                    .map { path, items in
                        (path: path,
                         name: path.isEmpty ? "General" : (path as NSString).lastPathComponent,
                         threads: items.sorted { $0.updatedAt > $1.updatedAt })
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                ForEach(projectGroups, id: \.path) { group in
                    projectSection(group: group)
                }
            }
            .padding(.leading, 8)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text(vibespaceName ?? "VibeSpace")
                    .font(AppTypographyTokens.calloutSemibold)
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)

                Text("Current VibeSpace")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(palette.secondaryTextColor)
    }

    // MARK: - Project Section (nested under vibespace)

    private func projectSection(group: (path: String, name: String, threads: [ConversationThreadSummary])) -> some View {
        let sectionId = "project.\(group.path)"
        let grouped = timeGrouped(group.threads)
        return DisclosureGroup(
            isExpanded: sectionBinding(sectionId)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(grouped, id: \.label) { bucket in
                    if grouped.count > 1 {
                        Text(bucket.label)
                            .font(AppTypographyTokens.caption2Semibold)
                            .foregroundStyle(palette.secondaryTextColor.opacity(0.6))
                            .padding(.leading, 24)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    ForEach(Array(bucket.threads.enumerated()), id: \.element.id) { index, thread in
                        threadRow(thread)
                        if index < bucket.threads.count - 1 {
                            Divider().padding(.leading, 24)
                        }
                    }
                }
            }
            .padding(.leading, 6)
        } label: {
            HStack(spacing: 8) {
                if let tag = projectColorTagsByPath[group.path] {
                    Circle().fill(tag.color).frame(width: uiScale.iconSize(8), height: uiScale.iconSize(8))
                } else {
                    Image(systemName: "folder.fill")
                        .font(AppTypographyTokens.scaledIcon(12, weight: .semibold))
                        .foregroundStyle(palette.secondaryTextColor)
                        .frame(width: uiScale.iconSize(14))
                }
                Text(group.name)
                    .font(AppTypographyTokens.calloutSemibold)
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(group.threads.count)")
                    .font(AppTypographyTokens.caption2MonospacedDigit)
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(palette.secondaryTextColor)
        .onAppear { expandedSections.insert(sectionId) }
    }

    // MARK: - Thread Row

    private func threadRow(_ thread: ConversationThreadSummary) -> some View {
        VStack(spacing: 0) {
            if pendingDeleteId == thread.id {
                // Inline delete confirmation
                HStack(spacing: 8) {
                    Text("Delete this conversation?")
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Cancel") { pendingDeleteId = nil }
                        .font(AppTypographyTokens.caption2)
                        .buttonStyle(.plain)
                    Button("Delete") {
                        pendingDeleteId = nil
                        Task { await onDeleteThread(thread.id) }
                    }
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 24)
            } else {
                HStack(spacing: 8) {
                    Button { onOpenThread(thread) } label: {
                        HStack(alignment: .center, spacing: 8) {
                            // Agent icon
                            agentIcon(for: thread.agentId)

                            if editingThreadId == thread.id {
                                TextField("Title", text: $editingTitle, onCommit: {
                                    let t = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !t.isEmpty { Task { await store.updateThreadTitle(id: thread.id, title: t) } }
                                    editingThreadId = nil
                                })
                                .font(AppTypographyTokens.caption)
                                .textFieldStyle(.plain)
                            } else {
                                Text(thread.title)
                                    .font(AppTypographyTokens.caption)
                                    .foregroundStyle(palette.primaryTextColor)
                                    .lineLimit(1)
                                    .onTapGesture(count: 2) {
                                        editingThreadId = thread.id
                                        editingTitle = thread.title
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Text(thread.relativeTime)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor.opacity(0.6))
                        .lineLimit(1)

                    HStack(spacing: 2) {
                        SidebarActionButton(icon: "play.rectangle", help: "Open") { onOpenThread(thread) }
                        SidebarActionButton(icon: "doc.on.doc", help: "Export") { Task { await onExportMarkdown(thread.id) } }
                        SidebarActionButton(icon: "xmark.circle", help: "Delete") { pendingDeleteId = thread.id }
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 24)
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Open") { onOpenThread(thread) }
            Divider()
            Button("Rename") { editingThreadId = thread.id; editingTitle = thread.title }
            Divider()
            Button("Export as Markdown…") { Task { await onExportMarkdown(thread.id) } }
            Button("Export as JSON…") { Task { await onExportJSON(thread.id) } }
            Divider()
            Button("Delete", role: .destructive) { pendingDeleteId = thread.id }
        }
        .accessibilityIdentifier("vibespace.sidebar.conversations.thread.\(thread.id)")
    }

    // MARK: - Agent Icon

    @ViewBuilder
    private func agentIcon(for agentId: String) -> some View {
        if let nsImage = ACPAgentRegistry.agentIconImage(for: agentId, size: 14) {
            Image(nsImage: nsImage)
                .frame(width: uiScale.iconSize(14), height: uiScale.iconSize(14))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            Circle()
                .fill(Color.orange)
                .frame(width: uiScale.iconSize(6), height: uiScale.iconSize(6))
        }
    }

    // MARK: - Time Grouping

    private struct TimeBucket {
        let label: String
        let threads: [ConversationThreadSummary]
    }

    private func timeGrouped(_ threads: [ConversationThreadSummary]) -> [TimeBucket] {
        let now = Date()
        let calendar = Calendar.current
        var recent: [ConversationThreadSummary] = []
        var older: [ConversationThreadSummary] = []
        for thread in threads {
            if let date = ISO8601DateFormatter().date(from: thread.updatedAt),
               calendar.dateComponents([.day], from: date, to: now).day ?? 99 < 7 {
                recent.append(thread)
            } else {
                older.append(thread)
            }
        }
        var buckets: [TimeBucket] = []
        if !recent.isEmpty { buckets.append(TimeBucket(label: "Recent", threads: recent)) }
        if !older.isEmpty { buckets.append(TimeBucket(label: "Older", threads: older)) }
        return buckets.isEmpty ? [TimeBucket(label: "Recent", threads: threads)] : buckets
    }

    // MARK: - Other VibeSpaces Section

    private var otherVibeSpacesSection: some View {
        DisclosureGroup(isExpanded: sectionBinding("other")) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(otherThreads.enumerated()), id: \.element.id) { index, thread in
                    threadRow(thread)
                    if index < otherThreads.count - 1 {
                        Divider().padding(.leading, 24)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text("Other VibeSpaces")
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                Spacer()
                Text("\(otherThreads.count)")
                    .font(AppTypographyTokens.caption2MonospacedDigit)
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(palette.secondaryTextColor)
    }

    // MARK: - Helpers

    private func sectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(id) },
            set: { if $0 { expandedSections.insert(id) } else { expandedSections.remove(id) } }
        )
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if isSearching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Searching…").font(AppTypographyTokens.caption2).foregroundStyle(palette.secondaryTextColor)
            }
            .padding(.top, 12)
        } else if searchResults.isEmpty {
            Text("No results").font(AppTypographyTokens.caption).foregroundStyle(palette.secondaryTextColor).padding(.top, 12)
        } else {
            Text("\(searchResults.count) results")
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(palette.secondaryTextColor)
                .padding(.bottom, 2)
            ForEach(searchResults) { result in
                Button { onOpenThread(ConversationThreadSummary(searchResult: result)) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        agentIcon(for: result.agentId)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(result.threadTitle)
                                    .font(AppTypographyTokens.captionSemibold)
                                    .foregroundStyle(palette.primaryTextColor)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if !result.projectName.isEmpty {
                                    Text(result.projectName)
                                        .font(AppTypographyTokens.scaledSystem(9))
                                        .foregroundStyle(palette.secondaryTextColor.opacity(0.6))
                                        .lineLimit(1)
                                }
                                Text(result.relativeTime)
                                    .font(AppTypographyTokens.scaledSystem(9))
                                    .foregroundStyle(palette.secondaryTextColor.opacity(0.5))
                                    .lineLimit(1)
                            }
                            highlightedSnippet(result.snippet)
                                .font(AppTypographyTokens.caption2)
                                .foregroundStyle(palette.secondaryTextColor)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Renders FTS5 snippet with `<b>` tags as bold highlights.
    private func highlightedSnippet(_ html: String) -> Text {
        let parts = FTSSnippetParser.parse(html)
        var result = Text("")
        for part in parts {
            if part.isBold {
                result = result + Text(part.text).bold().foregroundColor(palette.primaryTextColor)
            } else {
                result = result + Text(part.text)
            }
        }
        return result
    }

    private var emptyState: some View {
        ContentUnavailableView("No Conversations", systemImage: "bubble.left.and.bubble.right",
                               description: Text("Agent conversations will appear here."))
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - Data

    private func loadThreads() async {
        guard case .ready = store.state else { threads = []; otherThreads = []; return }
        isLoading = threads.isEmpty
        // Load current vibespace threads
        var params: [String: Any] = ["limit": 200]
        if let vibespaceID { params["vibespaceId"] = vibespaceID.uuidString }
        let result = await store.send(method: "thread.list", params: params)
        // Load all threads to find other vibespaces
        let allResult = await store.send(method: "thread.list", params: ["limit": 200])
        isLoading = false

        let currentIDs: Set<String>
        if let result, result.ok,
           let list = result.value?["threads"] as? [[String: Any]] {
            let current = list.compactMap { ConversationThreadSummary(json: $0) }
                .sorted { $0.updatedAt > $1.updatedAt }
            threads = current
            currentIDs = Set(current.map(\.id))
        } else {
            threads = []
            currentIDs = []
        }

        if let allResult, allResult.ok,
           let allList = allResult.value?["threads"] as? [[String: Any]] {
            otherThreads = allList.compactMap { ConversationThreadSummary(json: $0) }
                .filter { !currentIDs.contains($0.id) }
                .sorted { $0.updatedAt > $1.updatedAt }
        } else {
            otherThreads = []
        }
    }
}

private enum ConversationSidebarTab {
    case crispyvibes
    case external
}

// MARK: - Sidebar Action Button with hover

private struct SidebarActionButton: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    @State private var isHovered = false
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppTypographyTokens.scaledIcon(11))
                .frame(width: uiScale.iconSize(20), height: uiScale.iconSize(20))
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - Models

struct ConversationThreadSummary: Identifiable {
    let id: String
    let title: String
    let agentId: String
    let transportKind: String
    let projectPath: String
    let updatedAt: String
    let hasActiveSession: Bool

    var projectDisplayName: String {
        projectPath.isEmpty ? "General" : (projectPath as NSString).lastPathComponent
    }

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: updatedAt) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String,
              let agentId = json["agentId"] as? String else { return nil }
        self.id = id; self.title = title; self.agentId = agentId
        self.transportKind = json["transportKind"] as? String ?? ""
        self.projectPath = json["projectPath"] as? String ?? ""
        self.updatedAt = json["updatedAt"] as? String ?? ""
        self.hasActiveSession = false
    }

    init(searchResult: FTSSearchResult) {
        self.id = searchResult.threadId; self.title = searchResult.threadTitle
        self.agentId = searchResult.agentId; self.transportKind = ""
        self.projectPath = searchResult.projectPath; self.updatedAt = searchResult.updatedAt
        self.hasActiveSession = false
    }
}

struct FTSSearchResult: Identifiable {
    let id: String
    let threadId: String
    let threadTitle: String
    let snippet: String
    let agentId: String
    let projectPath: String
    let updatedAt: String
    let messageId: String

    var projectName: String {
        projectPath.isEmpty ? "" : (projectPath as NSString).lastPathComponent
    }

    var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: updatedAt) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    init?(json: [String: Any]) {
        guard let messageId = json["messageId"] as? String, let threadId = json["threadId"] as? String,
              let threadTitle = json["threadTitle"] as? String, let snippet = json["snippet"] as? String else { return nil }
        self.id = messageId; self.messageId = messageId; self.threadId = threadId
        self.threadTitle = threadTitle; self.snippet = snippet
        self.agentId = json["agentId"] as? String ?? ""
        self.projectPath = json["projectPath"] as? String ?? ""
        self.updatedAt = json["updatedAt"] as? String ?? ""
    }
}

/// Parses FTS5 snippet HTML (`<b>` tags) into structured parts for rendering.
enum FTSSnippetParser {
    struct Part {
        let text: String
        let isBold: Bool
    }

    static func parse(_ html: String) -> [Part] {
        guard !html.isEmpty else { return [] }
        var parts: [Part] = []
        var remaining = html[...]
        while let openRange = remaining.range(of: "<b>") {
            let before = remaining[remaining.startIndex..<openRange.lowerBound]
            if !before.isEmpty { parts.append(Part(text: String(before), isBold: false)) }
            remaining = remaining[openRange.upperBound...]
            if let closeRange = remaining.range(of: "</b>") {
                let bold = remaining[remaining.startIndex..<closeRange.lowerBound]
                parts.append(Part(text: String(bold), isBold: true))
                remaining = remaining[closeRange.upperBound...]
            }
        }
        if !remaining.isEmpty { parts.append(Part(text: String(remaining), isBold: false)) }
        return parts
    }
}
