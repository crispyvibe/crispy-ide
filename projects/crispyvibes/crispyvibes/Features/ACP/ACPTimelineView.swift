import SwiftUI

struct ACPTimelineView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    let timeline: [ACPTimelineEntry]
    let agentName: String
    let agentID: String?
    let onResend: (UUID) -> Void
    var displayMode: ACPDisplayMode = .detail

    @State private var expandedTurnDiffIDs = Set<String>()

    private var initials: String {
        NSFullUserName().prefix(1).uppercased().isEmpty ? "U" : String(NSFullUserName().prefix(1).uppercased())
    }
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    var vibespaceRoot: String?
    var onViewDiff: (([ACPDiffSummaryRow], String) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: displayMode.timelineSpacing) {
                    if timeline.count >= 2000 {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(AppTypographyTokens.caption2)
                            Text("Showing latest 2,000 messages. Older messages are available via search and export.")
                                .font(AppTypographyTokens.caption2)
                        }
                        .foregroundStyle(palette.secondaryTextColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.secondaryTextColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    ForEach(timeline) { entry in
                        timelineRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(displayMode.timelinePadding)
            }
            .onAppear { scrollToBottom(using: proxy) }
            .onChange(of: timeline.map(\.id)) { _, _ in scrollToBottom(using: proxy) }
        }
    }

    @ViewBuilder
    private func timelineRow(_ entry: ACPTimelineEntry) -> some View {
        switch entry.kind {
        case .userMessage(let text):
            userMessageRow(text: text, entryID: entry.id)
        case .assistantMessage(let text, let streaming):
            assistantMessageRow(text: text, streaming: streaming)
        case .thought(let text):
            thoughtRow(text: text)
        case .toolCallGroup(let calls):
            ACPToolCallGroupView(
                calls: calls,
                vibespaceRoot: vibespaceRoot,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
        case .turn(let turn):
            turnRow(turn: turn)
        }
    }

    // MARK: - User Message

    private func userMessageRow(text: String, entryID: UUID) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: displayMode.isCompact ? 36 : 60)
            ACPSelectableText(
                text: text,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            .padding(.horizontal, displayMode.isCompact ? 12 : 14)
            .padding(.vertical, displayMode.isCompact ? 8 : 10)
            .background(palette.secondaryTextColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(displayMode.isCompact ? 10 : 16), style: .continuous))
            if !displayMode.isCompact {
                Text(initials)
                    .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(width: uiScale.iconSize(24), height: uiScale.iconSize(24))
                    .background(palette.secondaryTextColor.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contextMenu {
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button { onResend(entryID) } label: {
                Label("Resend", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: - Assistant Message

    private func assistantMessageRow(text: String, streaming: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ACPAvatar(agentID: agentID, role: .agent)
            VStack(alignment: .leading, spacing: 6) {
                ACPSelectableText(
                    text: text,
                    onLinkTargetActivated: onLinkTargetActivated,
                    onFileSystemTargetActivated: onFileSystemTargetActivated
                )
                if streaming {
                    ACPStreamingIndicator()
                } else if !displayMode.isCompact, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Copy button — only on completed responses (#10)
                    AssistantCopyButton(text: text)
                }
            }
            Spacer(minLength: displayMode.isCompact ? 24 : 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    /// Renders response text split around approval pauses (#21).
    @ViewBuilder
    private func assistantMessageSegments(turn: ACPTurnEntry) -> some View {
        let segments = turn.responseSegments
        if segments.count <= 1 {
            assistantMessageRow(text: turn.responseText, streaming: turn.isStreaming)
        } else {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                assistantMessageRow(text: segment, streaming: index == segments.count - 1 && turn.isStreaming)
                if index < segments.count - 1 {
                    HStack(spacing: 8) {
                        Rectangle().fill(palette.secondaryTextColor.opacity(0.15)).frame(height: 1)
                        Text("Approval")
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor.opacity(0.5))
                            .fixedSize()
                        Rectangle().fill(palette.secondaryTextColor.opacity(0.15)).frame(height: 1)
                    }
                    .padding(.vertical, displayMode.isCompact ? 0 : 2)
                }
            }
        }
    }

    // MARK: - Thought

    private func thoughtRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ACPAvatar(agentID: nil, role: .thought)
            ACPSelectableText(
                text: text,
                font: .callout,
                foregroundColor: palette.secondaryTextColor,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.secondaryTextColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Turn (grouped)

    private func turnRow(turn: ACPTurnEntry) -> some View {
        VStack(alignment: .leading, spacing: displayMode.isCompact ? 10 : 12) {
            // User message
            userMessageRow(text: turn.userMessage, entryID: turn.id)

            // Thinking (collapsed by default)
            if !turn.thinking.isEmpty {
                ACPCollapsibleSection(title: "Thinking", icon: "brain", collapsed: true) {
                    ACPSelectableText(
                        text: turn.thinking,
                        font: .callout,
                        foregroundColor: palette.secondaryTextColor,
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated
                    )
                }
            }

            // Tool calls (collapsed work log)
            if !turn.toolCalls.isEmpty {
                ACPCollapsibleSection(
                    title: "Work (\(turn.toolCalls.count))",
                    icon: "wrench",
                    collapsed: !turn.isStreaming
                ) {
                    let visibleCalls = turn.toolCalls.count <= 6 ? turn.toolCalls : Array(turn.toolCalls.suffix(6))
                    ACPToolCallGroupView(
                        calls: visibleCalls,
                        vibespaceRoot: vibespaceRoot,
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated
                    )
                    if turn.toolCalls.count > 6 {
                        ACPShowAllToolCallsButton(
                            allCalls: turn.toolCalls,
                            vibespaceRoot: vibespaceRoot,
                            onLinkTargetActivated: onLinkTargetActivated,
                            onFileSystemTargetActivated: onFileSystemTargetActivated
                        )
                    }
                }
            }

            // Response
            if !turn.responseText.isEmpty {
                // Completion divider with elapsed time (#9)
                if !displayMode.isCompact, !turn.isStreaming, let completedAt = turn.completedAt {
                    let elapsed = completedAt.timeIntervalSince(turn.timestamp)
                    HStack(spacing: 8) {
                        Rectangle().fill(palette.secondaryTextColor.opacity(0.15)).frame(height: 1)
                        Text("Response • \(ACPDurationFormatter.format(elapsed))")
                            .font(AppTypographyTokens.caption2)
                            .foregroundStyle(palette.secondaryTextColor.opacity(0.5))
                            .fixedSize()
                        Rectangle().fill(palette.secondaryTextColor.opacity(0.15)).frame(height: 1)
                    }
                    .padding(.vertical, 2)
                }
                assistantMessageSegments(turn: turn)
            } else if turn.isStreaming {
                HStack(spacing: 8) {
                    ACPAvatar(agentID: agentID, role: .agent)
                    ACPStreamingIndicator()
                }
            }

            // Error message
            if let errorText = turn.errorText {
                HStack(alignment: .top, spacing: 8) {
                    ACPAvatar(agentID: agentID, role: .agent)
                    Text(errorText)
                        .font(AppTypographyTokens.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Changed files summary
            if !turn.changedFiles.isEmpty {
                ACPChangedFilesSummaryView(
                    rows: turn.changedFiles,
                    vibespaceRoot: vibespaceRoot,
                    expandedDiffIDs: $expandedTurnDiffIDs,
                    onLinkTargetActivated: onLinkTargetActivated,
                    onFileSystemTargetActivated: onFileSystemTargetActivated,
                    onViewDiff: onViewDiff != nil ? {
                        onViewDiff?(turn.changedFiles, "Turn \(turnIndex(for: turn))")
                    } : nil
                )
            }
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard let lastID = timeline.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func turnIndex(for turn: ACPTurnEntry) -> Int {
        var index = 0
        for entry in timeline {
            if case .turn = entry.kind { index += 1 }
            if entry.id == turn.id { return index }
        }
        return index
    }

}

/// "Show all N tool calls" button for work log collapsing (#19).
private struct ACPShowAllToolCallsButton: View {
    let allCalls: [ACPToolCallState]
    var vibespaceRoot: String?
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    @State private var showAll = false

    var body: some View {
        if showAll {
            ACPToolCallGroupView(
                calls: allCalls,
                vibespaceRoot: vibespaceRoot,
                onLinkTargetActivated: onLinkTargetActivated,
                onFileSystemTargetActivated: onFileSystemTargetActivated
            )
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAll = true }
            } label: {
                Text("Show all \(allCalls.count) tool calls")
                    .font(AppTypographyTokens.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
}

/// Copy button that appears on hover for completed assistant messages.
private struct AssistantCopyButton: View {
    let text: String
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(AppTypographyTokens.caption2)
                if copied { Text("Copied").font(AppTypographyTokens.caption2) }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.secondary.opacity(isHovered ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: copied)
    }
}

// MARK: - Avatar

struct ACPAvatar: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    let agentID: String?
    let role: Role

    enum Role {
        case agent
        case user
        case thought
    }

    private var iconImage: NSImage? {
        guard let agentID else { return nil }
        return ACPAgentRegistry.agentIconImage(for: agentID, size: 16)
    }

    var body: some View {
        Group {
            switch role {
            case .agent:
                if let iconImage {
                    Image(nsImage: iconImage)
                        .frame(width: uiScale.iconSize(24), height: uiScale.iconSize(24))
                        .clipShape(Circle())
                } else {
                    sfSymbolAvatar(systemName: "sparkles", color: palette.accentColor)
                }
            case .user:
                sfSymbolAvatar(systemName: "person.fill", color: palette.accentColor)
            case .thought:
                sfSymbolAvatar(systemName: "brain", color: palette.secondaryTextColor)
            }
        }
        .frame(width: uiScale.iconSize(24), height: uiScale.iconSize(24))
        .fixedSize()
    }

    private func sfSymbolAvatar(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(AppTypographyTokens.scaledIcon(10, weight: .semibold))
            .foregroundStyle(palette.canvasBackgroundColor)
            .frame(width: uiScale.iconSize(24), height: uiScale.iconSize(24))
            .background(color.gradient)
            .clipShape(Circle())
    }
}

// MARK: - Collapsible Section

struct ACPCollapsibleSection<Content: View>: View {
    @Environment(\.appThemePalette) private var palette
    let title: String
    let icon: String
    let collapsed: Bool
    @ViewBuilder let content: () -> Content
    @State private var isCollapsed: Bool

    init(title: String, icon: String, collapsed: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.collapsed = collapsed
        self.content = content
        _isCollapsed = State(initialValue: collapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(AppTypographyTokens.caption2Semibold)
                    Image(systemName: icon)
                        .font(AppTypographyTokens.caption)
                    Text(title)
                        .font(AppTypographyTokens.captionSemibold)
                }
                .foregroundStyle(palette.secondaryTextColor)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                content()
                    .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Streaming Indicator

struct ACPStreamingIndicator: View {
    @Environment(\.appThemePalette) private var palette
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(palette.accentColor)
                    .frame(width: 5, height: 5)
                    .opacity(i <= dotCount ? 1.0 : 0.3)
            }
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
    }
}
