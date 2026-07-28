import SwiftUI

// F059 — the visual vocabulary for Vibe Lanes: checkpoint status nodes, the
// shared card/chip/hover design kit, and the lightweight markdown renderer.
// Shared by every Vibe Lane screen so states and surfaces read identically.

// MARK: - Design kit

/// Central task-state styling so the dashboard, detail header, and chips all
/// agree on color + icon for a state.
enum VibeLaneStateStyle {
    static func color(_ state: VibeLaneTaskState) -> Color {
        switch state {
        case .running: return .accentColor
        case .needsInput: return .orange
        case .stopped: return .red
        case .done: return .green
        }
    }

    static func icon(_ state: VibeLaneTaskState) -> String {
        switch state {
        case .running: return "play.fill"
        case .needsInput: return "person.crop.circle.badge.exclamationmark"
        case .stopped: return "stop.fill"
        case .done: return "checkmark"
        }
    }
}

/// Elevated card surface — soft fill, hairline stroke, gentle shadow. The one
/// panel treatment every Vibe Lane screen uses (optionally tinted for emphasis,
/// e.g. the orange Needs-you panel).
private struct VibeLaneCardModifier: ViewModifier {
    @Environment(\.appThemePalette) private var palette
    var cornerRadius: CGFloat = 12
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.map { $0.opacity(0.08) } ?? palette.canvasSecondaryBackgroundColor)
                    .shadow(color: .black.opacity(tint == nil ? 0.07 : 0.0), radius: 5, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.map { $0.opacity(0.30) } ?? palette.tertiaryTextColor.opacity(0.13))
            )
    }
}

/// Hover affordance for interactive rows inside cards.
private struct VibeLaneHoverModifier: ViewModifier {
    @Environment(\.appThemePalette) private var palette
    var cornerRadius: CGFloat = 8
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? palette.primaryTextColor.opacity(0.045) : Color.clear)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    /// The shared Vibe Lane panel surface.
    func vibeLaneCard(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(VibeLaneCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Subtle hover highlight for tappable rows.
    func vibeLaneHoverable(cornerRadius: CGFloat = 8) -> some View {
        modifier(VibeLaneHoverModifier(cornerRadius: cornerRadius))
    }
}

/// Tinted capsule chip: dot (or icon) + label. The one way a task state is
/// written anywhere in the surface.
@MainActor
struct VibeLaneStatusChip: View {
    let text: String
    let color: Color
    var icon: String?
    var size: CGFloat = 11
    @Environment(\.crispyvibesUIScale) private var uiScale

    var body: some View {
        HStack(spacing: uiScale.spacing(5)) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: uiScale.iconSize(size * 0.82), weight: .semibold))
            } else {
                Circle().frame(width: uiScale.chromeSize(6), height: uiScale.chromeSize(6))
            }
            Text(text)
                .font(.system(size: uiScale.textSize(size), weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, uiScale.spacing(9))
        .padding(.vertical, uiScale.spacing(4))
        .background(Capsule().fill(color.opacity(0.13)))
        .overlay(Capsule().strokeBorder(color.opacity(0.22)))
    }
}

/// Icon in a soft tinted rounded square — used for headers and list leading icons.
@MainActor
struct VibeLaneIconBadge: View {
    let systemImage: String
    var color: Color = .accentColor
    var side: CGFloat = 34
    var iconSize: CGFloat = 15
    @Environment(\.crispyvibesUIScale) private var uiScale

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.22), color.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .strokeBorder(color.opacity(0.25))
            )
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: uiScale.iconSize(iconSize), weight: .semibold))
                    .foregroundStyle(color)
            )
            .frame(width: uiScale.chromeSize(side), height: uiScale.chromeSize(side))
    }
}

/// Visual state of a checkpoint node.
enum VibeLaneNodeState {
    case done
    case active
    case needsInput
    case pending
    case stopped

    /// Derive the node state for a checkpoint within a task.
    static func resolve(
        for checkpoint: VibeLaneCheckpoint,
        task: VibeLaneTask,
        lane: VibeLaneDefinition? = nil
    ) -> VibeLaneNodeState {
        if checkpoint.key == task.currentCheckpointKey, task.state == .needsInput {
            return .needsInput
        }
        let activeGroupContainsCheckpoint = task.activeLoop.flatMap { active in
            lane?.loopGroup(forKey: active.groupKey)?.members.contains(checkpoint.key)
        } == true
        let runRecord: VibeLaneCheckpointRun?
        if checkpoint.key == task.currentCheckpointKey {
            runRecord = task.currentRun
        } else if activeGroupContainsCheckpoint {
            runRecord = task.run(forKey: checkpoint.key, visit: task.currentVisit)
        } else {
            runRecord = task.run(forKey: checkpoint.key)
        }
        if let runRecord {
            switch runRecord.status {
            case .passed:
                return .done
            case .stopped:
                return .stopped
            case .needsInput:
                return .needsInput
            case .running, .pending:
                if checkpoint.key == task.currentCheckpointKey {
                    return task.state == .running ? .active : .pending
                }
                return .pending
            }
        }
        if checkpoint.key == task.currentCheckpointKey, task.state == .running {
            return .active
        }
        if checkpoint.key == task.currentCheckpointKey, task.state == .needsInput {
            return .needsInput
        }
        return .pending
    }
}

/// A single status node glyph (done ✓ / active ● with ring / stopped ✕ / pending ○).
@MainActor
struct VibeLaneStatusNode: View {
    let state: VibeLaneNodeState
    var diameter: CGFloat = 18
    /// Animates a breathing halo around the active node (live tasks).
    var pulses: Bool = false
    @Environment(\.appThemePalette) private var palette
    @State private var pulsing = false

    var body: some View {
        switch state {
        case .done:
            Circle().fill(Color.green).frame(width: diameter, height: diameter)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: diameter * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                )
        case .active:
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(pulses ? (pulsing ? 0.05 : 0.45) : 0.30), lineWidth: diameter * 0.16)
                    .frame(width: diameter * 1.45, height: diameter * 1.45)
                    .scaleEffect(pulses && pulsing ? 1.45 : 1.0)
                Circle().fill(Color.accentColor).frame(width: diameter, height: diameter)
                Circle().fill(.white).frame(width: diameter * 0.32, height: diameter * 0.32)
            }
            .frame(width: diameter, height: diameter)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
        case .needsInput:
            Circle().fill(Color.orange).frame(width: diameter, height: diameter)
                .overlay(
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: diameter * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                )
        case .stopped:
            Circle().fill(Color.red).frame(width: diameter, height: diameter)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: diameter * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                )
        case .pending:
            Circle()
                .strokeBorder(palette.tertiaryTextColor.opacity(0.5), lineWidth: 2)
                .frame(width: diameter, height: diameter)
        }
    }
}

enum VibeLaneRoute {
    /// Color of the connector segment leading into a node of `state`.
    static func connectorColor(for state: VibeLaneNodeState, tertiary: Color) -> Color {
        switch state {
        case .pending:
            return tertiary.opacity(0.28)
        case .needsInput:
            return Color.orange.opacity(0.65)
        case .stopped:
            return Color.red.opacity(0.65)
        case .done, .active:
            return Color.green
        }
    }
}

/// Thin rounded lane-progress bar: passed checkpoints fill solid, the active
/// checkpoint contributes a half segment.
@MainActor
struct VibeLaneProgressBar: View {
    let fraction: Double
    var height: CGFloat = 5
    @Environment(\.appThemePalette) private var palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tertiaryTextColor.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.75), Color.accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                    .animation(.easeInOut(duration: 0.5), value: fraction)
            }
        }
        .frame(height: height)
    }
}


// MARK: - Lightweight markdown

/// Renders the simple markdown agents emit (## headings, - bullets, inline
/// **bold** / `code`) as clean native text, so summaries/handoffs never show raw
/// syntax. Not a full markdown engine — just the shapes Vibe Lane output uses.
@MainActor
struct VibeLaneMarkdownText: View {
    let markdown: String
    /// F060: when set, file/folder paths in the text render as clickable links
    /// (absolute always; relative when they exist under this directory) — the
    /// same detection terminal boards and ACP chat use. Clicks route through
    /// the enclosing `openURL` environment.
    var linkBaseDirectory: URL? = nil
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    private var blocks: [(id: Int, line: String)] {
        Array(markdown.components(separatedBy: "\n").enumerated()).map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
            ForEach(blocks, id: \.id) { block in
                lineView(block.line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Color.clear.frame(height: uiScale.spacing(4))
        } else if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4))))
                .font(.system(size: uiScale.textSize(12), weight: .semibold))
                .foregroundStyle(palette.primaryTextColor)
                .padding(.top, uiScale.spacing(2))
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3))))
                .font(.system(size: uiScale.textSize(12), weight: .bold))
                .foregroundStyle(palette.tertiaryTextColor)
                .textCase(.uppercase)
                .padding(.top, uiScale.spacing(4))
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2))))
                .font(.system(size: uiScale.textSize(14), weight: .bold))
                .foregroundStyle(palette.primaryTextColor)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: uiScale.spacing(6)) {
                Text("•").foregroundStyle(palette.tertiaryTextColor)
                Text(inline(String(line.dropFirst(2))))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: uiScale.textSize(13)))
        } else {
            Text(inline(line))
                .font(.system(size: uiScale.textSize(13)))
                .foregroundStyle(palette.secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inline(_ string: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
        ACPTextLinking.applyDetectedLinks(
            to: &attributed,
            original: String(attributed.characters),
            baseDirectory: linkBaseDirectory
        )
        return attributed
    }
}
