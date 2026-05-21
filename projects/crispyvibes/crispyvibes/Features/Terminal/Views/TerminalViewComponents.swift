import SwiftUI

enum TerminalPresentationMode: Equatable {
    case singleActiveTab
    case stackedTabs
}

struct TerminalActivityBar: View {
    let isActive: Bool
    let color: Color
    private let animationPeriod: TimeInterval = 1.0
    private let highlightOpacity = 0.30
    private let glowOpacity = 0.18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isActive)) { context in
            GeometryReader { proxy in
                let height = max(proxy.size.height, 1)
                let segmentHeight = max(height * 0.34, 4)
                let phase = isActive
                    ? context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: animationPeriod) / animationPeriod
                    : 0

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(color)
                        .padding(.horizontal, 0.6)

                    if isActive {
                        RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                            .fill(Color.white.opacity(highlightOpacity))
                            .frame(height: segmentHeight)
                            .padding(.horizontal, 0.6)
                            .shadow(color: color.opacity(glowOpacity), radius: 3, x: 0, y: 0)
                            .offset(y: (height + segmentHeight) * phase - segmentHeight)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1.2, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct TerminalActivityUnderline: View {
    let isActive: Bool
    let color: Color
    private let animationPeriod: TimeInterval = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isActive)) { context in
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let segmentWidth = min(max(width * 0.34, 14), 34)
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: animationPeriod) / animationPeriod
                let offset = isActive ? (width + segmentWidth) * phase - segmentWidth : 0

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(color.opacity(isActive ? 0.28 : 0.16))
                        .frame(height: 2)

                    if isActive {
                        Capsule(style: .continuous)
                            .fill(color.opacity(0.90))
                            .frame(width: segmentWidth, height: 2)
                            .shadow(color: color.opacity(0.30), radius: 2, x: 0, y: 0)
                            .offset(x: offset)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TerminalActivityPulse: ViewModifier {
    let isActive: Bool
    let activeColor: Color

    // Explicit TimelineView at 8 fps replaces .repeatForever() which:
    //  • created RepeatAnimation objects in the AttributeGraph every cycle
    //  • could silently stop under SwiftUI view-identity changes
    // cos() over a 1.6 s period closely matches the original easeInOut(0.8) autoreverse.
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: !isActive)) { context in
            let pulsePhase = isActive
                ? (1.0 + cos(context.date.timeIntervalSinceReferenceDate * .pi / 0.8)) / 2.0
                : 1.0

            content
                .foregroundStyle(activeColor)
                .opacity(0.80 + 0.20 * pulsePhase)
                .shadow(color: isActive ? activeColor.opacity(0.18) : .clear, radius: 2.5, x: 0, y: 0)
                .overlay(alignment: .topTrailing) {
                    if isActive {
                        Circle()
                            .fill(activeColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: activeColor.opacity(0.34), radius: 3, x: 0, y: 0)
                            .offset(x: 3, y: -3)
                    }
                }
        }
    }
}

extension View {
    func terminalActivityPulse(isActive: Bool, color: Color) -> some View {
        modifier(TerminalActivityPulse(isActive: isActive, activeColor: color))
    }
}

struct ActivityIndicator: View {
    @Environment(\.appThemePalette) private var appThemePalette
    var color: Color?
    private let animationPeriod: TimeInterval = 0.9
    
    var body: some View {
        let resolvedColor = color ?? appThemePalette.successColor
        TimelineView(.animation(minimumInterval: 0.25, paused: false)) { context in
            let phase = Int(
                (context.date.timeIntervalSinceReferenceDate / animationPeriod * 3)
                    .rounded(.down)
            ) % 3

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(resolvedColor.opacity(index == phase ? 1.0 : 0.26))
                        .frame(width: 4, height: 4)
                        .shadow(
                            color: index == phase ? resolvedColor.opacity(0.34) : .clear,
                            radius: 2.5,
                            x: 0,
                            y: 0
                        )
                }
            }
        }
        .frame(width: 18, height: 6)
        .accessibilityHidden(true)
    }
}

struct TerminalTabChipStyle {
    let activeBackground: Color
    let inactiveBackground: Color
    let activeBorderColor: Color
    let inactiveBorderColor: Color
    let selectedTextColor: Color
    let inactiveTextColor: Color

    init(palette: AppThemePalette) {
        self.init(
            activeBackground: palette.selectionBackgroundColor.opacity(0.18),
            inactiveBackground: palette.canvasSecondaryBackgroundColor.opacity(0.90),
            activeBorderColor: palette.borderColorValue.opacity(1.0),
            inactiveBorderColor: palette.borderColorValue.opacity(0.62),
            selectedTextColor: palette.primaryTextColor,
            inactiveTextColor: palette.secondaryTextColor
        )
    }

    init(
        activeBackground: Color,
        inactiveBackground: Color,
        activeBorderColor: Color,
        inactiveBorderColor: Color,
        selectedTextColor: Color,
        inactiveTextColor: Color
    ) {
        self.activeBackground = activeBackground
        self.inactiveBackground = inactiveBackground
        self.activeBorderColor = activeBorderColor
        self.inactiveBorderColor = inactiveBorderColor
        self.selectedTextColor = selectedTextColor
        self.inactiveTextColor = inactiveTextColor
    }
}

struct TerminalTabChipAccent {
    let isActive: Bool
    let color: Color
    let width: CGFloat

    init(isActive: Bool, color: Color, width: CGFloat = 4) {
        self.isActive = isActive
        self.color = color
        self.width = width
    }
}

struct TerminalTabChipChrome<Content: View>: View {
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme

    let isSelected: Bool
    let style: TerminalTabChipStyle
    let showsBorder: Bool
    let accent: TerminalTabChipAccent?
    let leadingPaddingWithoutAccent: CGFloat
    let leadingPaddingWithAccent: CGFloat
    let trailingPadding: CGFloat
    let verticalPadding: CGFloat
    let accentInset: CGFloat
    let showsActivityUnderline: Bool
    let cornerRadiusToken: CGFloat
    let content: Content

    init(
        isSelected: Bool,
        style: TerminalTabChipStyle,
        showsBorder: Bool = true,
        accent: TerminalTabChipAccent? = nil,
        leadingPaddingWithoutAccent: CGFloat = 8,
        leadingPaddingWithAccent: CGFloat = 13,
        trailingPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4,
        accentInset: CGFloat = 1,
        showsActivityUnderline: Bool = false,
        cornerRadiusToken: CGFloat = 6,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.style = style
        self.showsBorder = showsBorder
        self.accent = accent
        self.leadingPaddingWithoutAccent = leadingPaddingWithoutAccent
        self.leadingPaddingWithAccent = leadingPaddingWithAccent
        self.trailingPadding = trailingPadding
        self.verticalPadding = verticalPadding
        self.accentInset = accentInset
        self.showsActivityUnderline = showsActivityUnderline
        self.cornerRadiusToken = cornerRadiusToken
        self.content = content()
    }

    var body: some View {
        let chipCornerRadius = crispyvibesTheme.radius(cornerRadiusToken)

        content
            .padding(.leading, accent == nil ? leadingPaddingWithoutAccent : leadingPaddingWithAccent)
            .padding(.trailing, trailingPadding)
            .padding(.vertical, verticalPadding)
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: chipCornerRadius, style: .continuous)
                            .fill(isSelected ? style.activeBackground : style.inactiveBackground)

                        if let accent, showsActivityUnderline {
                            TerminalActivityUnderline(isActive: accent.isActive, color: accent.color)
                                .frame(height: 3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .padding(.leading, accent.width + accentInset)
                                .padding(.trailing, 2)
                                .padding(.bottom, 1)
                        }

                        if let accent {
                            TerminalActivityBar(isActive: accent.isActive, color: accent.color)
                                .frame(width: accent.width, height: max(proxy.size.height - (accentInset * 2), 1))
                                .padding(.leading, accentInset)
                                .padding(.vertical, accentInset)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: chipCornerRadius, style: .continuous))
                }
            }
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: chipCornerRadius, style: .continuous)
                        .stroke(
                            isSelected ? style.activeBorderColor : style.inactiveBorderColor,
                            lineWidth: 1
                        )
                }
            }
    }
}

struct TerminalTabBarItem: View {
    let tab: TerminalTab
    @ObservedObject var activityState: TerminalTabActivityState
    let isSelected: Bool
    let style: TerminalTabChipStyle
    let showsBorder: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    var onRename: ((String) -> Void)?
    var dragItemProvider: (() -> NSItemProvider)? = nil

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        let chip = TerminalTabChipChrome(
            isSelected: isSelected,
            style: style,
            showsBorder: showsBorder,
            accent: TerminalTabChipAccent(
                isActive: activityState.isActive,
                color: isSelected ? style.selectedTextColor : style.inactiveTextColor
            )
        ) {
            HStack(spacing: 6) {
                if isEditing {
                    TextField("", text: $editText, onCommit: {
                        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onRename?(trimmed.isEmpty ? "" : trimmed)
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(style.selectedTextColor)
                    .frame(minWidth: 40, maxWidth: 120)
                    .focused($isRenameFieldFocused)
                    .onExitCommand { isEditing = false }
                    .onAppear { isRenameFieldFocused = true }
                } else {
                    Button {
                        onSelect()
                    } label: {
                        Text(tab.title)
                            .lineLimit(1)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(isSelected ? style.selectedTextColor : style.inactiveTextColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("terminal.tab.select")
                    .onTapGesture(count: 2) {
                        guard onRename != nil else { return }
                        editText = tab.title
                        isEditing = true
                    }
                }

                CrispyVibesIconButton(
                    systemName: "xmark.circle.fill",
                    size: 12,
                    padding: 4,
                    color: isSelected ? style.selectedTextColor : style.inactiveTextColor,
                    accessibilityLabel: "Close Terminal Tab"
                ) {
                    onClose()
                }
                .accessibilityIdentifier("terminal.tab.close")
            }
        }

        Group {
            if let dragItemProvider, !isEditing {
                chip.onDrag {
                    dragItemProvider()
                }
            } else {
                chip
            }
        }
        .accessibilityValue(activityState.isActive ? "active" : "idle")
        .accessibilityIdentifier("terminal.tab")
        .help(tab.workingDirectory.path)
    }
}

struct TerminalSessionView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    let tab: TerminalTab
    @ObservedObject var viewModel: TerminalViewModel
    var isActive: Bool = true
    let sessionAccessibilityIdentifier: String
    let sessionHostAccessibilityIdentifier: String
    var inlineTriggerTerminalTitle: String? = nil
    var inlineTriggerSearchRoots: [URL] = []
    var inlineTriggerShortcuts: [TerminalShortcutDefinition] = []
    var onManageInlineTriggerShortcutsRequested: (() -> Void)? = nil
    var onSessionSelected: ((UUID) -> Void)? = nil
    var onSessionDoubleClicked: ((UUID) -> Void)? = nil
    var onSplitTerminalRequested: ((TerminalTab) -> Void)? = nil
    var onTemporaryTerminalRequested: ((TerminalTab) -> Void)? = nil
    var onOpenInEditorPaneRequested: ((TerminalTab) -> Void)? = nil
    var onLinkTargetActivated: ((URL) -> Void)? = nil
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(tab.title)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .lineLimit(1)
                    .help(tab.workingDirectory.path)
                    .accessibilityIdentifier("terminal.active.path")

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            Divider()

            if let session = viewModel.session(for: tab.id) {
                TerminalSessionHostView(
                    session: session,
                    displayDensity: .regular,
                    isActive: isActive,
                    accessibilityIdentifier: sessionHostAccessibilityIdentifier,
                    inlineTriggerTerminalTitle: inlineTriggerTerminalTitle ?? tab.title,
                    inlineTriggerSearchRoots: inlineTriggerSearchRoots,
                    inlineTriggerShortcuts: inlineTriggerShortcuts,
                    onManageInlineTriggerShortcutsRequested: onManageInlineTriggerShortcutsRequested,
                    onSplitTerminalRequested: {
                        onSplitTerminalRequested?(tab)
                    },
                    onTemporaryTerminalRequested: {
                        onTemporaryTerminalRequested?(tab)
                    },
                    onOpenInEditorPaneRequested: onOpenInEditorPaneRequested != nil ? {
                        onOpenInEditorPaneRequested?(tab)
                    } : nil,
                    onLinkTargetActivated: onLinkTargetActivated,
                    onFileSystemTargetActivated: onFileSystemTargetActivated
                )
                    .id(session.viewIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Terminal Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(AppStrings.Terminal.sessionInactive)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(sessionAccessibilityIdentifier)
        .onTapGesture(count: 2) {
            onSessionDoubleClicked?(tab.id)
        }
        .onTapGesture {
            onSessionSelected?(tab.id)
        }
    }
}

struct TerminalCommandsMenu: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    let textColor: Color
    let shortcuts: [TerminalShortcutDefinition]
    let onRunShortcut: (TerminalShortcutDefinition) -> Void
    let onManageShortcutsRequested: (() -> Void)?
    let onSendSignal: (String) -> Void

    var body: some View {
        Menu {
            Section("Signals") {
                Button("Interrupt (Ctrl+C)") { onSendSignal("\u{03}") }
                Button("EOF (Ctrl+D)") { onSendSignal("\u{04}") }
                Button("Suspend (Ctrl+Z)") { onSendSignal("\u{1A}") }
                Button("Escape") { onSendSignal("\u{1B}") }
                Button("Clear Screen (Ctrl+L)") { onSendSignal("\u{0C}") }
                Button("Quit (Ctrl+\\)") { onSendSignal("\u{1C}") }
            }

            if !shortcuts.isEmpty {
                Section("Shortcuts") {
                    ForEach(shortcuts) { shortcut in
                        Button(shortcut.name) { onRunShortcut(shortcut) }
                    }
                }
            }

            if onManageShortcutsRequested != nil {
                Divider()
                Button("Manage Shortcuts…") { onManageShortcutsRequested?() }
            }
        } label: {
            Image(systemName: "terminal")
                .font(AppTypographyTokens.scaledIcon(12))
                .foregroundStyle(textColor)
                .frame(width: uiScale.iconSize(24), height: uiScale.iconSize(24))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .tint(textColor)
        .fixedSize()
        .help("Send signals or run saved shortcuts")
        .accessibilityIdentifier("terminal.commands.menu")
    }
}
