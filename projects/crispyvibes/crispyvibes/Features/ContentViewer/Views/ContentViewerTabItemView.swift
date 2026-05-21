import AppKit
import SwiftUI

struct ContentViewerTabItemView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let tab: ContentViewerTab
    let isActive: Bool
    let projectColor: Color?
    let compact: Bool
    let browserViewModel: BrowserPanelViewModel?
    var acpChatViewModel: ACPChatViewModel?
    let onClose: () -> Void
    let onSelect: () -> Void

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
        let iconFont: Font = compact ? AppTypographyTokens.scaledIcon(9, weight: .semibold) : AppTypographyTokens.captionSemibold
        let titleFont: Font = compact ? AppTypographyTokens.caption2 : AppTypographyTokens.caption
        let innerSpacing: CGFloat = uiScale.spacing(compact ? 4 : 5)
        let closeSize: CGFloat = compact ? 8 : 10
        let closePadding: CGFloat = compact ? 3 : 4
        let chipStyle = compact
            ? TerminalTabChipStyle(
                activeBackground: palette.selectionBackgroundColor.opacity(0.25),
                inactiveBackground: .clear,
                activeBorderColor: .clear,
                inactiveBorderColor: .clear,
                selectedTextColor: palette.primaryTextColor,
                inactiveTextColor: palette.secondaryTextColor
            )
            : TerminalTabChipStyle(palette: palette)
        let accent = projectColor.map {
            TerminalTabChipAccent(isActive: hasActivity, color: $0, width: compact ? 3 : 4)
        }

        TerminalTabChipChrome(
            isSelected: isActive,
            style: chipStyle,
            showsBorder: !compact,
            accent: accent,
            leadingPaddingWithoutAccent: compact ? 6 : 10,
            leadingPaddingWithAccent: compact ? 9 : 13,
            trailingPadding: compact ? 6 : 10,
            verticalPadding: compact ? 3 : 0,
            accentInset: 1,
            cornerRadiusToken: compact ? 5 : 6
        ) {
            HStack(spacing: innerSpacing) {
                tabIcon(font: iconFont)
                Text(tab.title).font(titleFont).lineLimit(1)
                    .foregroundStyle(isActive ? palette.primaryTextColor : palette.secondaryTextColor)
                CrispyVibesIconButton(systemName: "xmark", size: closeSize, padding: closePadding,
                                color: compact ? palette.secondaryTextColor : (isActive ? palette.primaryTextColor : palette.secondaryTextColor),
                                accessibilityLabel: "Close \(tab.title)",
                                action: onClose)
            }
        }
        .frame(height: compact ? nil : uiScale.chromeSize(29))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onDrag { ContentViewerTabDragSupport.makeItemProvider(for: tab) }
        .accessibilityIdentifier("content-viewer.tab.\(tab.id)")
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
