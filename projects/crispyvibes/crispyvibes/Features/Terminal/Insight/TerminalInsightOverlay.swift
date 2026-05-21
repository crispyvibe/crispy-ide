// TerminalInsightOverlay.swift — Terminal Insight (Phase 18)
// Traceability: REQ-P18-INS-017 through REQ-P18-INS-028

import SwiftUI

/// Floating pill overlay showing the last submitted command at the top of a terminal tile.
/// Appears on hover; shows last command or "not-started" if no command has been run.
struct TerminalInsightOverlay: View {
    @ObservedObject var observer: TerminalInsightObserver
    let isHovering: Bool

    var body: some View {
        Group {
            if isHovering {
                HStack(spacing: 4) {
                    if let input = observer.lastInput {
                        Text("⏎")
                        Text(formattedInput(input))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("not-started")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(AppTypographyTokens.captionMonospaced)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isHovering)
    }

    private func formattedInput(_ input: String) -> String {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1 {
            return "\(lines[0]) +\(lines.count - 1) more lines"
        }
        return input
    }
}
