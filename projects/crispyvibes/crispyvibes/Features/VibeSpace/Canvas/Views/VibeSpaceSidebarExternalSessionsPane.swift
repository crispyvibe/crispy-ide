import AppKit
import SwiftUI

struct VibeSpaceSidebarExternalSessionsPane: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let service: ExternalAgentSessionService
    let onPreviewSession: (ExternalAgentTranscript) -> Void
    /// Resume this terminal-agent session by running its resume command in a
    /// new terminal (old Feature C). No-op default keeps previews/tests simple.
    var onResumeInTerminal: (ExternalAgentSessionSummary) -> Void = { _ in }

    @State private var providerFilter: ExternalAgentSessionProvider?
    @State private var searchText = ""
    @State private var sessions: [ExternalAgentSessionSummary] = []
    @State private var diagnostics: [ExternalAgentSessionDiagnostic] = []
    @State private var selectedSession: ExternalAgentSessionSummary?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var loadTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if isLoading {
                        loadingRow(AppStrings.Sidebar.ExternalSessions.loading)
                    } else if let errorMessage {
                        statusRow(title: AppStrings.Sidebar.ExternalSessions.loadFailed, detail: errorMessage)
                    } else if sessions.isEmpty {
                        statusRow(
                            title: AppStrings.Sidebar.ExternalSessions.emptyTitle,
                            detail: AppStrings.Sidebar.ExternalSessions.emptyDescription
                        )
                    } else {
                        ForEach(groupedSessions) { group in
                            directorySection(group)
                        }
                    }

                    if !diagnostics.isEmpty {
                        diagnosticsSection
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await refresh() }
        .onChange(of: providerFilter) { _, _ in
            Task { await refresh() }
        }
        .onChange(of: searchText) { _, _ in
            scheduleSearch()
        }
        .onDisappear {
            loadTask?.cancel()
            searchTask?.cancel()
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                providerFilterButton(nil, title: AppStrings.Common.all)
                ForEach(ExternalAgentSessionProvider.allCases) { provider in
                    providerFilterButton(provider, title: provider.displayName)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor)
                TextField(AppStrings.Sidebar.ExternalSessions.searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTypographyTokens.caption)
                if isSearching {
                    ProgressView().controlSize(.mini)
                } else if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(AppTypographyTokens.caption2)
                }
                .buttonStyle(.plain)
                .help(AppStrings.Sidebar.ExternalSessions.refresh)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(palette.canvasBackgroundColor.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(palette.borderColorValue.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func providerFilterButton(_ provider: ExternalAgentSessionProvider?, title: String) -> some View {
        let isSelected = providerFilter == provider
        return Button {
            providerFilter = provider
        } label: {
            Text(title)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(isSelected ? .white : palette.secondaryTextColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? palette.accentColor : palette.canvasSecondaryBackgroundColor.opacity(0.65))
                )
        }
        .buttonStyle(.plain)
    }

    /// Directory disclosure section (mirrors the ACP pane's project sections):
    /// a folder header that expands to plain session rows.
    private func directorySection(_ group: ExternalSessionDirectoryGroup) -> some View {
        DisclosureGroup(isExpanded: groupBinding(group.id)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.sessions.enumerated()), id: \.element.id) { index, session in
                    externalSessionRow(session)
                    if index < group.sessions.count - 1 {
                        Divider().padding(.leading, 24)
                    }
                }
            }
            .padding(.leading, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(AppTypographyTokens.scaledIcon(12, weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(width: uiScale.iconSize(14))
                Text(group.title)
                    .font(AppTypographyTokens.calloutSemibold)
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)
                    .help(group.path)
                Spacer(minLength: 8)
                Text("\(group.sessions.count)")
                    .font(AppTypographyTokens.caption2MonospacedDigit)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            // Toggle on the whole header row, not just the chevron.
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedGroups.contains(group.id) {
                        expandedGroups.remove(group.id)
                    } else {
                        expandedGroups.insert(group.id)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(palette.secondaryTextColor)
        .onAppear { expandedGroups.insert(group.id) }
    }

    private func groupBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(id) },
            set: { if $0 { expandedGroups.insert(id) } else { expandedGroups.remove(id) } }
        )
    }

    /// A session row styled identically to the ACP pane's thread rows: brand
    /// icon + title + relative time + inline hover action buttons on one line.
    /// The provider/id/match sub-line is dropped; search snippets appear only
    /// while searching (matching the ACP search-results behavior).
    private func externalSessionRow(_ session: ExternalAgentSessionSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { select(session) } label: {
                    HStack(alignment: .center, spacing: 8) {
                        providerIcon(session.provider)
                        Text(session.title)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                        if session.parseStatus != "ok" {
                            Image(systemName: "exclamationmark.triangle")
                                .font(AppTypographyTokens.caption2)
                                .foregroundStyle(palette.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Text(session.relativeTime)
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(palette.secondaryTextColor.opacity(0.6))
                    .lineLimit(1)

                HStack(spacing: 2) {
                    SidebarActionButton(icon: "play.rectangle", help: AppStrings.Sidebar.ExternalSessions.resumeInTerminal) {
                        onResumeInTerminal(session)
                    }
                    SidebarActionButton(icon: "eye", help: AppStrings.Sidebar.ExternalSessions.preview) {
                        select(session)
                    }
                }
            }

            if !searchText.isEmpty {
                let snippets = session.displaySearchSnippets.prefix(3)
                if !snippets.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(snippets.enumerated()), id: \.offset) { _, snippet in
                            Text(snippet)
                                .font(AppTypographyTokens.caption2)
                                .foregroundStyle(palette.secondaryTextColor)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 22)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 24)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selectedSession?.id == session.id
                ? palette.selectionBackgroundColor.opacity(0.25)
                : Color.clear
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(AppStrings.Sidebar.ExternalSessions.resumeInTerminal) {
                onResumeInTerminal(session)
            }
            Divider()
            Button(AppStrings.Sidebar.ExternalSessions.copyResumeCommand) {
                copy(session.resumeCommand)
            }
            Button(AppStrings.Sidebar.ExternalSessions.copySourcePath) {
                copy(session.sourcePath)
            }
        }
    }

    /// Map an external provider to the ACP agent id so we can reuse the exact
    /// brand icons the ACP pane uses (keeps the two panes visually identical).
    private func providerAgentId(_ provider: ExternalAgentSessionProvider) -> String {
        switch provider {
        case .codex: "codex"
        case .claude: "claudeCode"
        case .kiro: "kiro"
        case .opencode: "opencode"
        case .pi: "pi"
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: ExternalAgentSessionProvider) -> some View {
        if let nsImage = ACPAgentRegistry.agentIconImage(for: providerAgentId(provider), size: 14) {
            Image(nsImage: nsImage)
                .frame(width: uiScale.iconSize(14), height: uiScale.iconSize(14))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            Circle()
                .fill(Color.orange)
                .frame(width: uiScale.iconSize(6), height: uiScale.iconSize(6))
        }
    }

    private var diagnosticsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(diagnostics.prefix(8)) { diagnostic in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.message)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.primaryTextColor)
                            .textSelection(.enabled)
                        Text(diagnostic.sourcePath)
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(AppStrings.Sidebar.ExternalSessions.parseDiagnostics)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(palette.secondaryTextColor)
        }
        .tint(palette.secondaryTextColor)
    }

    private func loadingRow(_ title: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(title)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(palette.secondaryTextColor)
        }
        .padding(.top, 12)
    }

    private func statusRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(palette.primaryTextColor)
            Text(detail)
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(palette.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private func refresh() async {
        isLoading = sessions.isEmpty
        isSearching = false
        searchTask?.cancel()
        do {
            let result = try await service.scan(provider: providerFilter)
            sessions = result.sessions
            diagnostics = result.diagnostics
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            sessions = []
            diagnostics = []
        }
        isLoading = false
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            Task { await refresh() }
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do {
                let result = try await service.search(query: query, provider: providerFilter)
                guard !Task.isCancelled else { return }
                sessions = result.sessions
                diagnostics = result.diagnostics
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func select(_ session: ExternalAgentSessionSummary) {
        selectedSession = session
        loadTask?.cancel()
        loadTask = Task {
            do {
                let loaded = try await service.load(session: session)
                guard !Task.isCancelled else { return }
                onPreviewSession(loaded)
                diagnostics = diagnostics + loaded.parseErrors
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private struct ExternalSessionDirectoryGroup: Identifiable {
        let id: String
        let title: String
        let path: String
        let sessions: [ExternalAgentSessionSummary]
    }

    /// Group sessions by their working directory (project path), mirroring how
    /// the ACP pane groups threads by project. Groups are ordered alphabetically
    /// by directory name; sessions within a group are most-recently-active first.
    private var groupedSessions: [ExternalSessionDirectoryGroup] {
        Dictionary(grouping: sessions) { $0.projectPath }
            .map { path, items in
                let name = path.isEmpty ? AppStrings.Common.all : URL(fileURLWithPath: path).lastPathComponent
                return ExternalSessionDirectoryGroup(
                    id: path.isEmpty ? "__none__" : path,
                    title: name.isEmpty ? path : name,
                    path: path,
                    sessions: items.sorted(by: compareSessionsByActivity)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func compareSessionsByActivity(_ lhs: ExternalAgentSessionSummary, _ rhs: ExternalAgentSessionSummary) -> Bool {
        switch (lhs.lastActivityDate, rhs.lastActivityDate) {
        case let (left?, right?): return left > right
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil):
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
