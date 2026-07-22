import AppKit
import SwiftUI

struct ContentViewerTabItemView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale

    let tab: ContentViewerTab
    let isActive: Bool
    let projectColor: Color?
    let compact: Bool
    let browserViewModel: BrowserPanelViewModel?
    var acpChatViewModel: ACPChatViewModel?
    let onClose: () -> Void
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        if let acpChatViewModel {
            ObservedACPActivity(viewModel: acpChatViewModel) { isStreaming in
                tabContent(hasActivity: isStreaming)
            }
        } else {
            tabContent(hasActivity: false)
        }
    }

    @ViewBuilder
    func tabContent(hasActivity: Bool) -> some View {
        Group {
            if compact {
                compactChip(hasActivity: hasActivity)
            } else {
                regularTab(hasActivity: hasActivity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onDrag { ContentViewerTabDragSupport.makeItemProvider(for: tab) }
        .accessibilityIdentifier("content-viewer.tab.\(tab.id)")
    }

    /// Editor-style tab for the main strip: the active tab reads as a card
    /// connected to the canvas below; inactive tabs stay quiet until hovered,
    /// and the close button only appears on the active or hovered tab.
    private func regularTab(hasActivity: Bool) -> some View {
        let cornerRadius = crispyvibesTheme.radius(6)
        let showsClose = isActive || isHovering
        return HStack(spacing: uiScale.spacing(6)) {
            tabIcon(font: AppTypographyTokens.captionSemibold)
            Text(tab.title).font(AppTypographyTokens.caption).lineLimit(1)
                .foregroundStyle(isActive ? palette.primaryTextColor : palette.secondaryTextColor)
            CrispyVibesIconButton(systemName: "xmark", size: 9, padding: 4,
                            color: isActive ? palette.primaryTextColor : palette.secondaryTextColor,
                            accessibilityLabel: "Close \(tab.title)",
                            action: onClose)
                .opacity(showsClose ? 1 : 0)
                .allowsHitTesting(showsClose)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: uiScale.chromeSize(29))
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(regularTabFill)
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.borderColorValue.opacity(0.75), lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if hasActivity, let projectColor {
                Capsule()
                    .fill(projectColor)
                    .frame(height: 2)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 2)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var regularTabFill: Color {
        if isActive { return palette.canvasBackgroundColor }
        if isHovering { return palette.primaryTextColor.opacity(0.06) }
        return .clear
    }

    private func compactChip(hasActivity: Bool) -> some View {
        let chipStyle = TerminalTabChipStyle(
            activeBackground: palette.selectionBackgroundColor.opacity(0.25),
            inactiveBackground: .clear,
            activeBorderColor: .clear,
            inactiveBorderColor: .clear,
            selectedTextColor: palette.primaryTextColor,
            inactiveTextColor: palette.secondaryTextColor
        )
        let accent = projectColor.map {
            TerminalTabChipAccent(isActive: hasActivity, color: $0, width: 3)
        }

        return TerminalTabChipChrome(
            isSelected: isActive,
            style: chipStyle,
            showsBorder: false,
            accent: accent,
            leadingPaddingWithoutAccent: 6,
            leadingPaddingWithAccent: 9,
            trailingPadding: 6,
            verticalPadding: 3,
            accentInset: 1,
            cornerRadiusToken: 5
        ) {
            HStack(spacing: uiScale.spacing(4)) {
                tabIcon(font: AppTypographyTokens.scaledIcon(9, weight: .semibold))
                Text(tab.title).font(AppTypographyTokens.caption2).lineLimit(1)
                    .foregroundStyle(isActive ? palette.primaryTextColor : palette.secondaryTextColor)
                CrispyVibesIconButton(systemName: "xmark", size: 8, padding: 3,
                                color: palette.secondaryTextColor,
                                accessibilityLabel: "Close \(tab.title)",
                                action: onClose)
            }
        }
    }

    @ViewBuilder
    private func tabIcon(font: Font) -> some View {
        if let browserViewModel {
            BrowserTabIconView(viewModel: browserViewModel, compact: compact, fallbackIconName: tab.iconName, tint: projectColor ?? (isActive ? palette.primaryTextColor : palette.secondaryTextColor), font: font)
        } else {
            Image(systemName: tab.iconName)
                .font(font)
                .foregroundStyle(projectColor ?? (isActive ? palette.primaryTextColor : palette.secondaryTextColor))
        }
    }
}

private struct ObservedACPActivity<Content: View>: View {
    @ObservedObject var viewModel: ACPChatViewModel
    let content: (Bool) -> Content

    var body: some View {
        content(viewModel.isStreaming)
    }
}

private struct BrowserTabIconView: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    @ObservedObject var viewModel: BrowserPanelViewModel
    let compact: Bool
    let fallbackIconName: String
    let tint: Color
    let font: Font

    var body: some View {
        if let faviconData = viewModel.faviconData,
           let image = NSImage(data: faviconData) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: uiScale.iconSize(compact ? 12 : 14),
                    height: uiScale.iconSize(compact ? 12 : 14)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: fallbackIconName)
                .font(font)
                .foregroundStyle(tint)
        }
    }
}
