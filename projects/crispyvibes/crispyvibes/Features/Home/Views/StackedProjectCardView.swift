import SwiftUI

struct StackedTerminalCardView: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.appThemePalette) private var appThemePalette
    @AppStorage(AppPreferences.codeFontSizeKey) private var codeFontSize = AppPreferences.defaultCodeFontSize
    @ObservedObject private var tabActivityState: TerminalTabActivityState
    let title: String
    let projectTitle: String?
    let showsProjectTitle: Bool
    let visibleTerminalCount: Int
    let showsStackAffordance: Bool
    let session: TerminalSession?
    let preferredHeight: CGFloat
    let preferredWidth: CGFloat?
    let accentColor: Color
    let shortcutIndex: Int?
    let onFocus: () -> Void
    let onClose: () -> Void
    let onHide: () -> Void
    let onRestart: () -> Void
    let onRename: (String) -> Void
    let onSpotlight: () -> Void

    @FocusState private var isRenameFieldFocused: Bool
    @State private var isRenaming = false
    @State private var renameText = ""

    init(
        title: String,
        projectTitle: String? = nil,
        showsProjectTitle: Bool = true,
        visibleTerminalCount: Int = 1,
        showsStackAffordance: Bool = false,
        tabActivityState: TerminalTabActivityState,
        session: TerminalSession?,
        preferredHeight: CGFloat,
        preferredWidth: CGFloat?,
        accentColor: Color,
        shortcutIndex: Int?,
        onFocus: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onRestart: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onSpotlight: @escaping () -> Void
    ) {
        self.title = title
        self.projectTitle = projectTitle
        self.showsProjectTitle = showsProjectTitle
        self.visibleTerminalCount = visibleTerminalCount
        self.showsStackAffordance = showsStackAffordance
        self._tabActivityState = ObservedObject(wrappedValue: tabActivityState)
        self.session = session
        self.preferredHeight = preferredHeight
        self.preferredWidth = preferredWidth
        self.accentColor = accentColor
        self.shortcutIndex = shortcutIndex
        self.onFocus = onFocus
        self.onClose = onClose
        self.onHide = onHide
        self.onRestart = onRestart
        self.onRename = onRename
        self.onSpotlight = onSpotlight
    }

    private var hasActivity: Bool {
        tabActivityState.isActive
    }

    private var chromeScale: CGFloat {
        AppPreferences.chromeScale(forCodeFontSize: codeFontSize)
    }

    private var shouldShowProjectSubtitle: Bool {
        guard showsProjectTitle, let projectTitle, !projectTitle.isEmpty else { return false }
        return projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(title.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
    }

    var body: some View {
        VStack(spacing: 0) {
            CrispyVibesHeaderChrome(style: .card) {
                TerminalActivityBar(isActive: hasActivity, color: accentColor)
                    .frame(width: 4, height: 28)

                if isRenaming {
                    TextField("", text: $renameText, onCommit: commitRename)
                        .textFieldStyle(.plain)
                        .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                        .foregroundStyle(appThemePalette.primaryTextColor)
                        .focused($isRenameFieldFocused)
                        .onExitCommand {
                            isRenaming = false
                        }
                        .onAppear {
                            isRenameFieldFocused = true
                        }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        if shouldShowProjectSubtitle, let projectTitle {
                            Text(projectTitle)
                                .font(AppTypographyTokens.caption2)
                                .lineLimit(1)
                                .foregroundStyle(appThemePalette.secondaryTextColor)
                        }

                        Text(title)
                            .font(CrispyVibesHeaderStyle.panel.titleFont(scale: chromeScale))
                            .lineLimit(1)
                            .foregroundStyle(appThemePalette.primaryTextColor)
                            .accessibilityIdentifier("project.stacked.title")
                    }
                }

                if showsStackAffordance, visibleTerminalCount > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                        Text("\(visibleTerminalCount)")
                    }
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.28), lineWidth: 1)
                    )
                    .accessibilityIdentifier("project.stacked.count")
                }

                if let shortcutIndex {
                    HStack(spacing: 3) {
                        Image(systemName: "command")
                        Text("\(shortcutIndex)")
                    }
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.28), lineWidth: 1)
                    )
                    .accessibilityIdentifier("project.stacked.shortcut")
                }

                Spacer(minLength: 8)

                CrispyVibesIconButton(
                    systemName: "xmark.circle.fill",
                    variant: .card,
                    color: appThemePalette.secondaryTextColor,
                    accessibilityLabel: "Close Terminal"
                ) {
                    onClose()
                }
                .accessibilityIdentifier("project.stacked.close")
            }

            Rectangle()
                .fill(appThemePalette.primaryTextColor.opacity(0.10))
                .frame(height: 1)

            Group {
                if let session {
                    TerminalSessionHostView(
                        session: session,
                        displayDensity: .compact,
                        isActive: true,
                        accessibilityIdentifier: "project.stacked.terminal.host"
                    )
                    .id(session.viewIdentity)
                    .allowsHitTesting(false)
                } else {
                    ContentUnavailableView(
                        "Terminal Unavailable",
                        systemImage: "terminal",
                        description: Text("This terminal session is no longer available.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: preferredWidth, height: preferredHeight, alignment: .topLeading)
        .background(appThemePalette.canvasBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(10), style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(
            color: appThemePalette.canvasBackgroundColor.opacity(hasActivity ? 0.34 : 0.22),
            radius: hasActivity ? 16 : 10,
            x: 0,
            y: hasActivity ? 10 : 6
        )
        .shadow(
            color: accentColor.opacity(hasActivity ? 0.12 : 0.06),
            radius: hasActivity ? 14 : 8,
            x: 0,
            y: 0
        )
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityValue(hasActivity ? "active" : "idle")
        .accessibilityIdentifier("project.stacked.card")
        .contextMenu {
            Button("Hide Terminal") {
                onHide()
            }
            Button("Rename Terminal") {
                beginRename()
            }
            Button("Restart Terminal") {
                onRestart()
            }
        }
        .onTapGesture(count: 2) {
            onSpotlight()
        }
        .onTapGesture {
            onFocus()
        }
    }

    private func beginRename() {
        renameText = title
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        onRename(trimmed)
        isRenaming = false
    }
}

typealias StackedProjectCardView = StackedTerminalCardView
