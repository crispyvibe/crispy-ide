import SwiftUI

enum VibeLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case ready
    case needsSetup
    case inLanes
    case unused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.VibeLanes.vibeLibraryAnyStatus
        case .ready: AppStrings.VibeLanes.ready
        case .needsSetup: AppStrings.VibeLanes.laneNeedsSetup
        case .inLanes: AppStrings.VibeLanes.vibeLibraryInLanes
        case .unused: AppStrings.VibeLanes.vibeLibraryUnused
        }
    }

    var systemImage: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case .ready: "checkmark.circle"
        case .needsSetup: "exclamationmark.circle"
        case .inLanes: "rectangle.stack"
        case .unused: "tray"
        }
    }

    func includes(_ vibe: VibeDefinition, usageCount: Int) -> Bool {
        switch self {
        case .all: true
        case .ready: vibe.isReady
        case .needsSetup: !vibe.isReady
        case .inLanes: usageCount > 0
        case .unused: usageCount == 0
        }
    }
}

@MainActor
struct VibeCategoryLabel: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let category: VibeCategory
    var isEmphasized = false

    var body: some View {
        Label(
            AppStrings.VibeLanes.vibeCategoryName(category),
            systemImage: category.systemImage
        )
        .font(.system(size: uiScale.textSize(10), weight: isEmphasized ? .semibold : .medium))
        .foregroundStyle(isEmphasized ? palette.accentColor : palette.tertiaryTextColor)
        .lineLimit(1)
    }
}

@MainActor
struct VibeLibraryRow: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let vibe: VibeDefinition
    let usageCount: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: uiScale.spacing(10)) {
                Image(systemName: "scope")
                    .font(.system(size: uiScale.iconSize(13), weight: .semibold))
                    .foregroundStyle(isSelected ? palette.accentColor : palette.tertiaryTextColor)
                    .frame(width: uiScale.chromeSize(28), height: uiScale.chromeSize(28))
                    .background(
                        RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                            .fill(
                                isSelected
                                    ? palette.accentColor.opacity(0.14)
                                    : palette.canvasSecondaryBackgroundColor
                            )
                    )

                VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
                    HStack(spacing: uiScale.spacing(6)) {
                        Text(vibe.name)
                            .font(.system(size: uiScale.textSize(13), weight: .semibold))
                            .foregroundStyle(palette.primaryTextColor)
                            .lineLimit(1)
                        if !vibe.isReady {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: uiScale.iconSize(10), weight: .semibold))
                                .foregroundStyle(palette.warningColor)
                                .accessibilityLabel(AppStrings.VibeLanes.laneNeedsSetup)
                        }
                    }
                    Text(vibe.detail ?? vibe.work.goal)
                        .font(.system(size: uiScale.textSize(11)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(2)
                    HStack(spacing: uiScale.spacing(8)) {
                        VibeCategoryLabel(category: vibe.category)
                        Text(AppStrings.VibeLanes.vibeVersion(vibe.version))
                        Text(AppStrings.VibeLanes.vibeUsage(usageCount))
                    }
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
                }
                Spacer(minLength: uiScale.spacing(4))
            }
            .padding(.horizontal, uiScale.spacing(10))
            .padding(.vertical, uiScale.spacing(9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                    .fill(isSelected ? palette.selectionBackgroundColor.opacity(0.22) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                    .strokeBorder(
                        isSelected ? palette.accentColor.opacity(0.32) : .clear,
                        lineWidth: uiScale.chromeSize(1)
                    )
            )
        }
        .buttonStyle(.plain)
        .vibeLaneHoverable(cornerRadius: uiScale.chromeSize(6))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
struct VibeCategoryPicker: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    @Binding var selection: VibeCategory
    let categories: [VibeCategory]

    @State private var showsCreator = false

    private var availableCategories: [VibeCategory] {
        var values = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        values[selection.id] = selection
        return values.values.sorted(by: VibeCategory.sort)
    }

    var body: some View {
        HStack(spacing: uiScale.spacing(6)) {
            Picker(AppStrings.VibeLanes.vibeCategory, selection: $selection) {
                ForEach(availableCategories) { category in
                    Label(
                        AppStrings.VibeLanes.vibeCategoryName(category),
                        systemImage: category.systemImage
                    )
                    .tag(category)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(uiScale.controlSize)
            .frame(width: uiScale.chromeSize(178))

            Button {
                showsCreator = true
            } label: {
                Image(systemName: "plus")
                    .frame(
                        width: uiScale.chromeSize(20),
                        height: uiScale.chromeSize(20)
                    )
            }
            .buttonStyle(.bordered)
            .controlSize(uiScale.controlSize)
            .help(AppStrings.VibeLanes.newVibeCategory)
            .popover(isPresented: $showsCreator, arrowEdge: .bottom) {
                VibeCategoryCreatorView(
                    categories: availableCategories,
                    onCancel: { showsCreator = false },
                    onCreate: { category in
                        selection = category
                        showsCreator = false
                    }
                )
            }
        }
    }
}

@MainActor
private struct VibeCategoryCreatorView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    let categories: [VibeCategory]
    let onCancel: () -> Void
    let onCreate: (VibeCategory) -> Void

    @State private var name = ""
    @State private var systemImage = "tag"

    private static let symbols = [
        "tag", "hammer", "wrench.and.screwdriver", "curlybraces",
        "checkmark.seal", "shield.checkered", "bolt.trianglebadge.exclamationmark",
        "ladybug", "shippingbox", "archivebox", "megaphone", "paperplane",
        "chart.line.uptrend.xyaxis", "target", "lightbulb", "brain",
        "doc.text.magnifyingglass", "books.vertical", "person.2", "briefcase",
        "paintbrush", "photo", "globe", "network",
        "lock.shield", "heart.text.square", "leaf", "sparkles",
        "calendar", "clock", "tray.full", "square.grid.2x2",
    ]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(16)) {
            HStack(spacing: uiScale.spacing(10)) {
                VibeLaneIconBadge(
                    systemImage: systemImage,
                    color: palette.accentColor,
                    side: 36,
                    iconSize: 14
                )
                VStack(alignment: .leading, spacing: uiScale.spacing(2)) {
                    Text(AppStrings.VibeLanes.newVibeCategory)
                        .font(.system(size: uiScale.textSize(15), weight: .bold))
                        .foregroundStyle(palette.primaryTextColor)
                    Text(AppStrings.VibeLanes.newVibeCategoryDetail)
                        .font(.system(size: uiScale.textSize(10)))
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }

            VStack(alignment: .leading, spacing: uiScale.spacing(7)) {
                Text(AppStrings.VibeLanes.categoryName)
                    .font(.system(size: uiScale.textSize(10), weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                TextField(AppStrings.VibeLanes.categoryNamePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                Text(AppStrings.VibeLanes.categoryIcon)
                    .font(.system(size: uiScale.textSize(10), weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(uiScale.chromeSize(30)), spacing: uiScale.spacing(6)),
                        count: 8
                    ),
                    spacing: uiScale.spacing(6)
                ) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            systemImage = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: uiScale.iconSize(12), weight: .semibold))
                                .foregroundStyle(
                                    systemImage == symbol
                                        ? palette.accentColor
                                        : palette.secondaryTextColor
                                )
                                .frame(
                                    width: uiScale.chromeSize(30),
                                    height: uiScale.chromeSize(30)
                                )
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: uiScale.chromeSize(6),
                                        style: .continuous
                                    )
                                    .fill(
                                        systemImage == symbol
                                            ? palette.accentColor.opacity(0.14)
                                            : palette.canvasSecondaryBackgroundColor
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: uiScale.chromeSize(6),
                                        style: .continuous
                                    )
                                    .strokeBorder(
                                        systemImage == symbol
                                            ? palette.accentColor.opacity(0.55)
                                            : palette.borderColorValue.opacity(0.42),
                                        lineWidth: uiScale.chromeSize(1)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(systemImage == symbol ? .isSelected : [])
                    }
                }
            }

            HStack {
                Spacer()
                Button(AppStrings.VibeLanes.cancel, action: onCancel)
                Button(AppStrings.VibeLanes.addCategory, action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
            .controlSize(uiScale.controlSize)
        }
        .padding(uiScale.spacing(18))
        .frame(width: uiScale.chromeSize(340))
        .background(palette.canvasBackgroundColor)
    }

    private func create() {
        if let existing = categories.first(where: {
            AppStrings.VibeLanes.vibeCategoryName($0)
                .localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            onCreate(existing)
            return
        }
        onCreate(VibeCategory.custom(name: trimmedName, systemImage: systemImage))
    }
}
