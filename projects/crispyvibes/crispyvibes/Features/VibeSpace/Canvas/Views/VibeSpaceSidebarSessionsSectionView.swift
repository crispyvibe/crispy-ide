import AppKit
import SwiftUI

struct VibeSpaceSidebarSessionsVibeSpaceGroupView: View {
    @Environment(\.appThemePalette) private var palette

    let group: VibeSpaceSidebarTmuxVibeSpaceGroup
    @Binding var expandedVibeSpaceIDs: Set<UUID>
    @Binding var expandedSectionIDs: Set<String>
    let onPreviewSession: (VibeSpaceSidebarTmuxSession) -> Void
    let onSendSessionToProject: (VibeSpaceSidebarTmuxSession, UUID) -> Void
    let onTerminateSession: (VibeSpaceSidebarTmuxSession) async -> Void
    let onRefreshRequested: () -> Void

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedVibeSpaceIDs.contains(group.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedVibeSpaceIDs.insert(group.id)
                    } else {
                        expandedVibeSpaceIDs.remove(group.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(group.sections) { section in
                    VibeSpaceSidebarSessionsSectionView(
                        section: section,
                        expandedSectionIDs: $expandedSectionIDs,
                        onPreviewSession: onPreviewSession,
                        onSendSessionToProject: onSendSessionToProject,
                        onTerminateSession: onTerminateSession,
                        onRefreshRequested: onRefreshRequested
                    )
                }
            }
            .padding(.leading, 8)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(AppTypographyTokens.calloutSemibold)
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)

                if group.isCurrentVibeSpace {
                    Text(AppStrings.Sidebar.Sessions.currentVibeSpace)
                        .font(AppTypographyTokens.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(palette.secondaryTextColor)
    }
}

struct VibeSpaceSidebarSessionsSectionView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let section: VibeSpaceSidebarTmuxSessionSection
    @Binding var expandedSectionIDs: Set<String>
    let onPreviewSession: (VibeSpaceSidebarTmuxSession) -> Void
    let onSendSessionToProject: (VibeSpaceSidebarTmuxSession, UUID) -> Void
    let onTerminateSession: (VibeSpaceSidebarTmuxSession) async -> Void
    let onRefreshRequested: () -> Void

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSectionIDs.contains(section.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedSectionIDs.insert(section.id)
                    } else {
                        expandedSectionIDs.remove(section.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 0) {
                switch section.availability {
                case .ready:
                    ForEach(section.sessions) { session in
                        VibeSpaceSidebarSessionRowView(
                            session: session,
                            defaultProjectID: section.projectID,
                            onPreviewSession: onPreviewSession,
                            onSendSessionToProject: onSendSessionToProject,
                            onTerminateSession: onTerminateSession,
                            onRefreshRequested: onRefreshRequested
                        )

                        if session.id != section.sessions.last?.id {
                            Divider()
                                .padding(.leading, 24)
                        }
                    }
                case .message(let message):
                    Text(message)
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                        .padding(.leading, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                }
            }
            .padding(.leading, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.iconName)
                    .font(AppTypographyTokens.scaledIcon(12, weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(width: uiScale.iconSize(14))

                Text(section.title)
                    .font(AppTypographyTokens.calloutSemibold)
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if case .ready = section.availability {
                    Text("\(section.sessions.count)")
                        .font(AppTypographyTokens.caption2MonospacedDigit)
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(palette.secondaryTextColor)
    }
}

private struct VibeSpaceSidebarSessionRowView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let session: VibeSpaceSidebarTmuxSession
    let defaultProjectID: UUID?
    let onPreviewSession: (VibeSpaceSidebarTmuxSession) -> Void
    let onSendSessionToProject: (VibeSpaceSidebarTmuxSession, UUID) -> Void
    let onTerminateSession: (VibeSpaceSidebarTmuxSession) async -> Void
    let onRefreshRequested: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            previewButton

            Spacer(minLength: 8)

            Button {
                onPreviewSession(session)
            } label: {
                Image(systemName: "play.rectangle")
                    .font(AppTypographyTokens.scaledIcon(12))
            }
            .buttonStyle(.plain)
            .help(AppStrings.Sidebar.Sessions.preview)

            projectButton

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(session.attachCommand, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(AppTypographyTokens.scaledIcon(12))
            }
            .buttonStyle(.plain)
            .help(AppStrings.Sidebar.Sessions.copyAttachCommand)

            Button(role: .destructive) {
                Task {
                    await onTerminateSession(session)
                    onRefreshRequested()
                }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(AppTypographyTokens.scaledIcon(12))
            }
            .buttonStyle(.plain)
            .help(AppStrings.Sidebar.Sessions.terminate)
        }
        .padding(.vertical, 4)
        .padding(.leading, 24)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("vibespace.sidebar.sessions.row.\(session.sessionName)")
    }

    private var previewButton: some View {
        Button {
            onPreviewSession(session)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(session.isAttached ? Color.green : Color.orange)
                    .frame(width: uiScale.iconSize(6), height: uiScale.iconSize(6))

                Text(session.displayTitle)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(palette.primaryTextColor)
                    .lineLimit(1)

                if !session.isCrispyVibesManaged {
                    Text(session.sessionName)
                        .font(AppTypographyTokens.caption2Monospaced)
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(AppStrings.Sidebar.Sessions.preview)
    }

    @ViewBuilder
    private var projectButton: some View {
        if let targetProjectID = session.owningProjectID ?? defaultProjectID ?? session.launchContextProjectID {
            Button {
                onSendSessionToProject(session, targetProjectID)
            } label: {
                Image(systemName: "arrowshape.right")
                    .font(AppTypographyTokens.scaledIcon(12))
            }
            .buttonStyle(.plain)
            .help(AppStrings.Sidebar.Sessions.openInProject)
        } else {
            Image(systemName: "arrowshape.right")
                .font(AppTypographyTokens.scaledIcon(12))
                .foregroundStyle(palette.secondaryTextColor.opacity(0.35))
                .frame(width: uiScale.iconSize(16))
                .help(AppStrings.Sidebar.Sessions.openInProject)
        }
    }
}
