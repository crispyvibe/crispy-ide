import SwiftUI

/// F053 — a single todo card. Reads as a card (surface fill + hairline border),
/// carries its sticky color as a leading edge, shows a relative timestamp, and
/// offers complete/color/delete from a context menu; delete also reveals on
/// hover. Selection = accent border + tint.
struct TodoCardView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var theme
    @Environment(\.crispyvibesUIScale) private var uiScale
    let todo: Todo
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onColor: (TodoStickyColor?) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(10)) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: uiScale.iconSize(16)))
                    .foregroundStyle(todo.isCompleted ? palette.accentColor : palette.tertiaryTextColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(AppStrings.Todos.complete)

            VStack(alignment: .leading, spacing: uiScale.spacing(2)) {
                Text(todo.title)
                    .font(.system(size: uiScale.textSize(13), weight: .medium))
                    .strikethrough(todo.isCompleted, color: palette.tertiaryTextColor)
                    .foregroundStyle(todo.isCompleted ? palette.tertiaryTextColor : palette.primaryTextColor)
                    .lineLimit(2)
                if let body = todo.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.tertiaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: uiScale.spacing(3)) {
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: uiScale.iconSize(11)))
                            .foregroundStyle(palette.tertiaryTextColor)
                    }
                    .buttonStyle(.plain)
                    .help(AppStrings.Todos.delete)
                    .transition(.opacity)
                } else {
                    Text(TodoTime.relative(todo.isCompleted ? (todo.completedAt ?? todo.updatedAt) : todo.createdAt))
                        .font(.system(size: uiScale.textSize(10)))
                        .foregroundStyle(palette.tertiaryTextColor)
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, uiScale.spacing(9))
        .padding(.leading, uiScale.spacing(12))
        .padding(.trailing, uiScale.spacing(10))
        .background(cardFill, in: RoundedRectangle(cornerRadius: theme.radius(8)))
        .overlay(alignment: .leading) {
            if let sticky = todo.stickyColor {
                UnevenRoundedRectangle(
                    topLeadingRadius: theme.radius(8), bottomLeadingRadius: theme.radius(8),
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
                .fill(sticky.color.opacity(todo.isCompleted ? 0.35 : 0.9))
                .frame(width: uiScale.spacing(3))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(8))
                .stroke(
                    isSelected ? palette.accentColor.opacity(0.55) : palette.borderColorValue.opacity(0.35),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .contextMenu { contextMenu }
    }

    private var cardFill: Color {
        if isSelected { return palette.accentColor.opacity(0.10) }
        if isHovering { return palette.canvasSecondaryBackgroundColor }
        return palette.canvasSecondaryBackgroundColor.opacity(0.55)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(action: onToggle) {
            Label(
                todo.isCompleted ? AppStrings.Todos.reopen : AppStrings.Todos.complete,
                systemImage: todo.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
            )
        }
        Menu(AppStrings.Todos.colorLabel) {
            ForEach(TodoStickyColor.allCases, id: \.self) { color in
                Button {
                    onColor(color)
                } label: {
                    Label {
                        Text(color.displayName)
                    } icon: {
                        Image(systemName: todo.stickyColor == color ? "circle.inset.filled" : "circle.fill")
                    }
                }
                .tint(color.color)
            }
            Divider()
            Button(AppStrings.Todos.colorNone) { onColor(nil) }
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label(AppStrings.Todos.delete, systemImage: "trash")
        }
    }
}

/// Shared ISO-second timestamp parsing + relative display for todo UI.
enum TodoTime {
    static let iso = ISO8601DateFormatter()
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func date(_ string: String) -> Date? { iso.date(from: string) }

    static func relative(_ string: String) -> String {
        guard let date = iso.date(from: string) else { return "" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
