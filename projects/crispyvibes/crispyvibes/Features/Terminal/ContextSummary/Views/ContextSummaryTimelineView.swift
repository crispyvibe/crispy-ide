import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Expanded timeline view showing recent terminal commands and agent activity.
/// Supports switching between AI-generated summaries and original commands.
struct ContextSummaryTimelineView: View {
    @Environment(\.crispyvibesUIScale) private var uiScale

    let entries: [TimelineEntry]
    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            viewToggle
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)

            Divider().padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        timelineRow(entry)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 220)
        }
    }

    private var viewToggle: some View {
        HStack(spacing: 0) {
            toggleTab("Summary", isSelected: !showOriginal) {
                showOriginal = false
            }
            toggleTab("Original", isSelected: showOriginal) {
                showOriginal = true
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func toggleTab(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(isSelected ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { action() } }
    }

    private func timelineRow(_ entry: TimelineEntry) -> some View {
        let displayText = showOriginal
            ? (entry.originalText ?? entry.text)
            : (entry.generatedText ?? entry.text)

        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName(for: entry.kind))
                .font(AppTypographyTokens.scaledIcon(11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: uiScale.iconSize(14))
                .padding(.top, 2)

            Text(displayText)
                .font(AppTypographyTokens.captionMonospaced)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            CopyButton(text: displayText)
        }
    }

    private func iconName(for kind: TimelineEntry.Kind) -> String {
        switch kind {
        case .command: return "chevron.right"
        case .toolCall: return "wrench"
        case .message: return "bubble.left"
        case .status: return "circle.fill"
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}

/// Small copy button with hover highlight and brief checkmark feedback.
private struct CopyButton: View {
    let text: String
    @State private var isHovered = false
    @State private var isCopied = false

    var body: some View {
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 10))
            .foregroundStyle(isCopied ? .green : (isHovered ? .primary : .secondary))
            .frame(width: 20, height: 20)
            .background(isHovered ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif
                withAnimation(.easeOut(duration: 0.15)) { isCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.15)) { isCopied = false }
                }
            }
            .help(AppStrings.Terminal.ContextSummary.copySummary)
            .accessibilityLabel(AppStrings.Terminal.ContextSummary.copySummary)
    }
}
