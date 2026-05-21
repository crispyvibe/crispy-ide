import SwiftUI

struct TmuxSessionManagerView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [TmuxService.SessionInfo] = []

    private var activeSessions: [TmuxService.SessionInfo] {
        sessions.filter(\.isAttached)
    }

    private var orphanedSessions: [TmuxService.SessionInfo] {
        sessions.filter { !$0.isAttached }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
            footer
        }
        .padding(16)
        .frame(width: 480, alignment: .leading)
        .background(palette.canvasBackgroundColor)
        .onAppear { reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(AppStrings.Settings.Experimental.tmuxManagerTitle)
                .font(AppTypographyTokens.settingsHeaderTitle)
            Spacer()
            Button { reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("tmux.manager.refresh")
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        Text(AppStrings.Settings.Experimental.tmuxManagerEmpty)
            .font(AppTypographyTokens.caption)
            .foregroundStyle(palette.secondaryTextColor)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
    }

    // MARK: - List

    private var sessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !activeSessions.isEmpty {
                    sectionHeader(AppStrings.Settings.Experimental.tmuxManagerActive, count: activeSessions.count)
                    ForEach(activeSessions) { session in
                        sessionRow(session, isOrphaned: false)
                    }
                }
                if !orphanedSessions.isEmpty {
                    sectionHeader(AppStrings.Settings.Experimental.tmuxManagerOrphaned, count: orphanedSessions.count)
                    ForEach(orphanedSessions) { session in
                        sessionRow(session, isOrphaned: true)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(AppTypographyTokens.settingsCardTitle)
            Text("(\(count))")
                .font(AppTypographyTokens.caption)
                .foregroundStyle(palette.secondaryTextColor)
        }
        .padding(.top, 4)
    }

    private func sessionRow(_ session: TmuxService.SessionInfo, isOrphaned: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isOrphaned ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.workingDirectory)
                    .font(AppTypographyTokens.settingsFieldTitle)
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack(spacing: 6) {
                    Text(session.currentCommand)
                        .font(AppTypographyTokens.monospacedCaption)
                    Text("·")
                        .foregroundStyle(palette.secondaryTextColor)
                    Text(session.lastActivity, style: .relative)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }

            Spacer()

            if isOrphaned {
                Button(AppStrings.Settings.Experimental.tmuxManagerKill, role: .destructive) {
                    TmuxService.killSessionAsync(session.name)
                    withAnimation { sessions.removeAll { $0.id == session.id } }
                }
                .buttonStyle(.borderless)
                .font(AppTypographyTokens.caption)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                .fill(palette.canvasSecondaryBackgroundColor.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                .stroke(palette.borderColorValue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !orphanedSessions.isEmpty {
                Button(AppStrings.Settings.Experimental.tmuxManagerKillAllOrphans, role: .destructive) {
                    for session in orphanedSessions {
                        TmuxService.killSessionAsync(session.name)
                    }
                    withAnimation { sessions.removeAll { !$0.isAttached } }
                }
                .font(AppTypographyTokens.caption)
            }
            Spacer()
            Text("\(sessions.count) \(AppStrings.Settings.Experimental.tmuxManagerSessionCount)")
                .font(AppTypographyTokens.caption)
                .foregroundStyle(palette.secondaryTextColor)
        }
    }

    private func reload() {
        sessions = TmuxService.listSessionDetails()
    }
}
