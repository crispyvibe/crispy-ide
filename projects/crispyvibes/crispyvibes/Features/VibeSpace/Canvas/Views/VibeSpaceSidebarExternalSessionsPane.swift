import AppKit
import SwiftUI

struct VibeSpaceSidebarExternalSessionsPane: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let service: ExternalAgentSessionService
    let onPreviewSession: (ExternalAgentTranscript) -> Void

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
                        ForEach(groupedSessions) { bucket in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(bucket.title)
                                        .font(AppTypographyTokens.captionSemibold)
                                        .foregroundStyle(palette.secondaryTextColor)
                                    Text("\(bucket.sessions.count)")
                                        .font(AppTypographyTokens.caption2MonospacedDigit)
                                        .foregroundStyle(palette.secondaryTextColor.opacity(0.7))
                                    Spacer(minLength: 6)
                                }

                                ForEach(bucket.sessions) { session in
                                    externalSessionRow(session)
                                }
                            }
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

    private func externalSessionRow(_ session: ExternalAgentSessionSummary) -> some View {
        Button {
            select(session)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    providerIcon(session.provider)
                    Text(session.title)
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    if session.parseStatus != "ok" {
                        Image(systemName: "exclamationmark.triangle")
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.accentColor)
                    }
                }

                HStack(spacing: 5) {
                    Text(session.providerName)
                    Text("-")
                    Text(session.projectDisplayName)
                    if !session.relativeTime.isEmpty {
                        Text("-")
                        Text(session.relativeTime)
                    }
                    if !session.shortSessionId.isEmpty {
                        Text("-")
                        Text(session.shortSessionId)
                            .monospacedDigit()
                    }
                    if session.matchCount > 0 {
                        Text("-")
                        Text(session.matchCountLabel)
                    }
                }
                .font(AppTypographyTokens.caption2)
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)

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
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedSession?.id == session.id
                        ? palette.canvasSecondaryBackgroundColor.opacity(0.9)
                        : palette.canvasSecondaryBackgroundColor.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selectedSession?.id == session.id
                        ? palette.accentColor.opacity(0.6)
                        : palette.borderColorValue.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(AppStrings.Sidebar.ExternalSessions.copyResumeCommand) {
                copy(session.resumeCommand)
            }
            Button(AppStrings.Sidebar.ExternalSessions.copySourcePath) {
                copy(session.sourcePath)
            }
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: ExternalAgentSessionProvider) -> some View {
        let symbol: String = switch provider {
        case .codex: "sparkles"
        case .claude: "c.circle"
        case .kiro: "ghost.fill"
        }
        Image(systemName: symbol)
            .font(AppTypographyTokens.scaledIcon(12))
            .foregroundStyle(palette.accentColor)
            .frame(width: uiScale.iconSize(14))
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

    private struct ExternalSessionTimeBucket: Identifiable {
        let id: String
        let title: String
        let sessions: [ExternalAgentSessionSummary]
    }

    private var groupedSessions: [ExternalSessionTimeBucket] {
        let now = Date()
        let calendar = Calendar.current
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        var thisWeek: [ExternalAgentSessionSummary] = []
        var previousWeek: [ExternalAgentSessionSummary] = []
        var earlier: [ExternalAgentSessionSummary] = []

        for session in sessions.sorted(by: compareSessionsByActivity) {
            guard let date = session.lastActivityDate else {
                earlier.append(session)
                continue
            }
            if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                thisWeek.append(session)
            } else if calendar.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) {
                previousWeek.append(session)
            } else {
                earlier.append(session)
            }
        }

        return [
            ExternalSessionTimeBucket(id: "this-week", title: AppStrings.Sidebar.ExternalSessions.thisWeek, sessions: thisWeek),
            ExternalSessionTimeBucket(id: "last-week", title: AppStrings.Sidebar.ExternalSessions.lastWeek, sessions: previousWeek),
            ExternalSessionTimeBucket(id: "earlier", title: AppStrings.Sidebar.ExternalSessions.earlier, sessions: earlier),
        ]
        .filter { !$0.sessions.isEmpty }
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
