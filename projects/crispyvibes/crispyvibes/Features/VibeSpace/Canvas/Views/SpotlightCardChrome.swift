import SwiftUI
import AppKit

@MainActor
struct SpotlightMemberInteractionContext {
    let isFocused: Bool
    private let onFocusRequested: () -> Void

    init(isFocused: Bool, onFocusRequested: @escaping () -> Void) {
        self.isFocused = isFocused
        self.onFocusRequested = onFocusRequested
    }

    func handleTerminalSelection(activateFocusedTerminal: () -> Void) {
        if isFocused {
            activateFocusedTerminal()
        } else {
            onFocusRequested()
        }
    }

    func requestFocus() {
        guard !isFocused else { return }
        onFocusRequested()
    }
}

struct TerminalSpotlightCardView<SpotlightContent: View, InputBarContent: View>: View {
    @Environment(\.appThemePalette) private var activeThemePalette
    @EnvironmentObject private var themeManager: CrispyVibesThemeManager

    let spotlight: TerminalSpotlightState
    let onDismiss: () -> Void
    let onPin: (() -> Void)?
    let pinAccessibilityLabel: String?
    let shortcutDefinitions: [TerminalShortcutDefinition]
    let onShortcutSelected: ((TerminalShortcutDefinition) -> Void)?
    let onManageShortcutsRequested: (() -> Void)?
    let onSendSignal: ((String) -> Void)?
    let onRenamePersistentTab: (TerminalViewModel, UUID, String) -> Void
    let comboMembers: [TerminalSpotlightState]
    let comboOrientation: SpotlightComboOrientation
    let onFocusMember: ((SpotlightNavigationIdentity) -> Void)?
    let onToggleComboOrientation: (() -> Void)?
    let spotlightContent: (TerminalSpotlightState, SpotlightMemberInteractionContext) -> SpotlightContent
    let inputBarContent: (TerminalSpotlightState, Bool, @escaping () -> Void) -> InputBarContent

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var comboPrimarySize: CGFloat = 560
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: spotlight.headerIconName)
                    .foregroundStyle(spotlight.accentColor ?? activeThemePalette.accentColor)

                HStack(spacing: 6) {
                    if isRenaming, case let .persistent(vm, tabID) = spotlight.source {
                        TextField("", text: $renameText, onCommit: {
                            let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                            onRenamePersistentTab(vm, tabID, trimmed)
                            isRenaming = false
                        })
                        .textFieldStyle(.plain)
                        .font(AppTypographyTokens.subheadlineSemibold)
                        .foregroundStyle(activeThemePalette.primaryTextColor)
                        .frame(maxWidth: 200)
                        .focused($isRenameFieldFocused)
                        .onExitCommand { isRenaming = false }
                        .onAppear { isRenameFieldFocused = true }
                    } else {
                        spotlightHeaderTitle
                            .font(AppTypographyTokens.subheadlineSemibold)
                            .lineLimit(1)
                            .foregroundStyle(activeThemePalette.primaryTextColor)
                            .accessibilityIdentifier("spotlight.header.title")
                            .accessibilityValue(spotlight.navigationIdentity?.diagnosticToken ?? "")
                    }

                    if spotlight.showsTemporaryBadge {
                        Text(AppStrings.Terminal.temporary)
                            .font(AppTypographyTokens.caption2Semibold)
                            .foregroundStyle(activeThemePalette.secondaryTextColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(activeThemePalette.selectionBackgroundColor.opacity(0.22))
                            .clipShape(Capsule())
                    }
                }

                Spacer(minLength: 8)

                spotlightHeaderDirectory
                    .font(AppTypographyTokens.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(activeThemePalette.secondaryTextColor)

                if let onSendSignal {
                    TerminalCommandsMenu(
                        textColor: activeThemePalette.secondaryTextColor,
                        shortcuts: shortcutDefinitions,
                        agentPresets: spotlight.agentPresets,
                        showsAgentCLIMenu: spotlight.onAgentPresetSelected != nil,
                        onRunShortcut: { shortcut in
                            onShortcutSelected?(shortcut)
                        },
                        onManageShortcutsRequested: onManageShortcutsRequested,
                        onSendSignal: onSendSignal,
                        onLaunchAgent: { preset, mode in
                            spotlight.onAgentPresetSelected?(preset, mode)
                        }
                    )
                    .accessibilityIdentifier("terminal.spotlight.commands")
                }

                if let onSplitTerminalRequested = spotlight.onSplitTerminalRequested {
                    CrispyVibesIconButton(systemName: "square.split.2x1", size: 12, padding: 4, color: activeThemePalette.secondaryTextColor, accessibilityLabel: AppStrings.Terminal.splitTerminal) {
                        onSplitTerminalRequested()
                    }
                    .help(AppStrings.Terminal.splitTerminal)
                }

                if let onTemporaryTerminalRequested = spotlight.onTemporaryTerminalRequested {
                    CrispyVibesIconButton(systemName: "scope", size: 12, padding: 4, color: activeThemePalette.secondaryTextColor, accessibilityLabel: AppStrings.Terminal.newTemporaryTerminal) {
                        onTemporaryTerminalRequested()
                    }
                    .help(AppStrings.Terminal.newTemporaryTerminal)
                }

                if let onPin, let pinAccessibilityLabel {
                    CrispyVibesIconButton(systemName: "pin", size: 12, padding: 4, color: activeThemePalette.secondaryTextColor, accessibilityLabel: pinAccessibilityLabel) {
                        onPin()
                    }
                    .help(pinAccessibilityLabel)
                    .accessibilityIdentifier("terminal.spotlight.pin")
                }

                if comboMembers.count == 2, let onToggleComboOrientation {
                    CrispyVibesIconButton(
                        systemName: comboOrientation == .sideBySide ? "rectangle.split.2x1" : "rectangle.split.1x2",
                        size: 12,
                        padding: 7,
                        color: activeThemePalette.secondaryTextColor,
                        accessibilityLabel: AppStrings.Spotlight.toggleOrientation
                    ) {
                        onToggleComboOrientation()
                    }
                    .help(AppStrings.Spotlight.toggleOrientation)
                    .accessibilityIdentifier("spotlight.combo.orientation")
                }

                CrispyVibesIconButton(systemName: "xmark.circle.fill", size: 12, padding: 7, color: activeThemePalette.secondaryTextColor, accessibilityLabel: AppStrings.Spotlight.close) {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(activeThemePalette.canvasSecondaryBackgroundColor)

            Divider()

            spotlightBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if comboMembers.count != 2, spotlight.source.showsComposeInputBar {
                inputBarContent(spotlight, true, {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(activeThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: themeManager.theme.radius(11), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: themeManager.theme.radius(11), style: .continuous)
                .stroke(activeThemePalette.borderColorValue.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 26, x: 0, y: 15)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal.spotlight.overlay")
        .onTapGesture(count: 2) {
            onDismiss()
        }
    }

    @ViewBuilder
    private var spotlightBody: some View {
        if comboMembers.count == 2 {
            NativeSplitView(
                isVerticalSplit: comboOrientation == .sideBySide,
                primaryAtEnd: false,
                primarySize: $comboPrimarySize,
                minPrimary: 220,
                maxPrimary: 10_000,
                minSecondary: 220,
                accessibilityIdentifier: "spotlight.combo.split"
            ) {
                comboMember(comboMembers[0])
            } secondary: {
                comboMember(comboMembers[1])
            }
        } else {
            spotlightContent(
                spotlight,
                SpotlightMemberInteractionContext(isFocused: true, onFocusRequested: {})
            )
        }
    }

    @ViewBuilder
    private func comboMember(_ member: TerminalSpotlightState) -> some View {
        let isFocused = member.navigationIdentity == spotlight.navigationIdentity
        let interaction = SpotlightMemberInteractionContext(
            isFocused: isFocused,
            onFocusRequested: {
                guard let identity = member.navigationIdentity else { return }
                onFocusMember?(identity)
            }
        )

        VStack(spacing: 0) {
            spotlightContent(member, interaction)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { interaction.requestFocus() }
                )

            if member.source.showsComposeInputBar {
                inputBarContent(member, isFocused, interaction.requestFocus)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            interaction.requestFocus()
                        }
                    )
            }
        }
            .overlay(alignment: .topLeading) {
                if isFocused {
                    Rectangle()
                        .fill(member.accentColor ?? activeThemePalette.accentColor)
                        .frame(width: 3, height: 28)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue(
                isFocused
                    ? AppStrings.Spotlight.focused
                    : AppStrings.Spotlight.combo
            )
    }

    @ViewBuilder
    private var spotlightHeaderTitle: some View {
        switch spotlight.source {
        case let .filePreview(target, group):
            TerminalSpotlightFileMetadataText(
                group: group,
                rootURL: target.url,
                component: .title
            )
        case let .file(_, fileURL, group):

            TerminalSpotlightFileMetadataText(
                group: group,
                rootURL: fileURL,
                component: .title
            )
        case .persistent:
            Text(spotlight.title)
                .onTapGesture(count: 2) {
                    renameText = spotlight.title
                    isRenaming = true
                }
        case .transient, .vibeCast, .vibeLanes, .todos, .acp, .browserPreview, .browser:
            Text(spotlight.title)
        }
    }

    @ViewBuilder
    private var spotlightHeaderDirectory: some View {
        switch spotlight.source {
        case let .filePreview(target, group):
            TerminalSpotlightFileMetadataText(
                group: group,
                rootURL: target.url,
                component: .directory
            )
        case let .file(_, fileURL, group):
            TerminalSpotlightFileMetadataText(
                group: group,
                rootURL: fileURL,
                component: .directory
            )
        case .persistent, .transient:
            Text(spotlight.workingDirectoryURL.lastPathComponent)
        case let .browserPreview(snapshot):
            Text(snapshot.urlString.flatMap(URL.init(string:)).map { SpotlightSafeMetadata.browserLocation($0).display } ?? AppStrings.Spotlight.web)
        case let .browser(_, url):
            Text(SpotlightSafeMetadata.browserLocation(url).display)
        case .vibeCast, .vibeLanes, .todos, .acp:
            Text(spotlight.owningProjectRootURL?.lastPathComponent ?? AppStrings.Spotlight.vibeSpace)
        }
    }
}

@MainActor
private struct TerminalSpotlightFileMetadataText: View {
    enum Component {
        case title
        case directory
    }

    @ObservedObject var group: EditorGroupStore
    let rootURL: URL
    let component: Component

    var body: some View {
        let activeURL = group.activeFileDocumentReference?.url ?? rootURL
        switch component {
        case .title:
            Text(activeURL.lastPathComponent)
        case .directory:
            Text(activeURL.deletingLastPathComponent().lastPathComponent)
        }
    }
}


private extension TerminalSpotlightState {
    var isPersistentTerminal: Bool {
        if case .persistent = source { return true }
        return false
    }
}
