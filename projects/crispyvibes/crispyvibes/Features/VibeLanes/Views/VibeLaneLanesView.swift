import SwiftUI

private enum VibeLaneCatalogFilter: String, CaseIterable, Identifiable {
    case all
    case ready
    case needsSetup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.VibeLanes.allLanes
        case .ready: AppStrings.VibeLanes.ready
        case .needsSetup: AppStrings.VibeLanes.laneNeedsSetup
        }
    }

    func includes(_ lane: VibeLaneDefinition) -> Bool {
        switch self {
        case .all: true
        case .ready: lane.isRunnable
        case .needsSetup: !lane.isRunnable
        }
    }
}

@MainActor
struct VibeLaneLanesView: View {
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.appThemePalette) private var palette
    @ObservedObject var manager: VibeLaneTaskManager
    let onEdit: (UUID) -> Void
    let onNew: () -> Void

    @State private var searchText = ""
    @State private var filter: VibeLaneCatalogFilter = .all

    private var filteredLanes: [VibeLaneDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.lanes.filter { lane in
            filter.includes(lane)
                && (
                    query.isEmpty
                        || lane.name.localizedCaseInsensitiveContains(query)
                        || (lane.detail?.localizedCaseInsensitiveContains(query) == true)
                        || lane.orderedCheckpoints.contains {
                            $0.displayTitle.localizedCaseInsensitiveContains(query)
                        }
                        || categories(for: lane).contains {
                            AppStrings.VibeLanes.vibeCategoryName($0)
                                .localizedCaseInsensitiveContains(query)
                        }
                )
        }
    }

    private var readyCount: Int {
        manager.lanes.lazy.filter { $0.isRunnable }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: uiScale.spacing(14)) {
                    catalogTitle
                    if filteredLanes.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: uiScale.spacing(14)) {
                            ForEach(filteredLanes) { lane in
                                VibeLaneCatalogCard(
                                    lane: lane,
                                    categories: categories(for: lane),
                                    onOpen: { onEdit(lane.id) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, uiScale.spacing(22))
                .padding(.vertical, uiScale.spacing(18))
                .frame(maxWidth: uiScale.chromeSize(1240), alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(palette.canvasBackgroundColor)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(13)) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: uiScale.spacing(14)) {
                    identity
                    Spacer(minLength: uiScale.spacing(20))
                    actions
                }
                VStack(alignment: .leading, spacing: uiScale.spacing(12)) {
                    identity
                    actions
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: uiScale.spacing(14)) {
                    summary
                    Spacer(minLength: uiScale.spacing(20))
                    searchAndFilter
                }
                VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
                    summary
                    searchAndFilter
                }
            }
        }
        .padding(.horizontal, uiScale.spacing(22))
        .padding(.vertical, uiScale.spacing(16))
        .background(palette.canvasSecondaryBackgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderColorValue.opacity(0.42))
                .frame(height: uiScale.chromeSize(1))
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: uiScale.spacing(12)) {
            VibeLaneIconBadge(
                systemImage: "point.3.connected.trianglepath.dotted",
                color: palette.warningColor,
                side: 40,
                iconSize: 16
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(3)) {
                Text(AppStrings.VibeLanes.yourLanes)
                    .font(.system(size: uiScale.textSize(20), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                Text(AppStrings.VibeLanes.laneCatalogSubtitle)
                    .font(.system(size: uiScale.textSize(12)))
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: uiScale.spacing(8)) {
            Button(action: { Task { await manager.restoreStarterLanes() } }) {
                Label(AppStrings.VibeLanes.restoreStarterLanes, systemImage: "arrow.counterclockwise")
                    .font(.system(size: uiScale.textSize(12), weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(uiScale.controlSize)
            .help(AppStrings.VibeLanes.restoreStarterLanesHelp)

            Button(action: onNew) {
                Label(AppStrings.VibeLanes.newLane, systemImage: "plus")
                    .font(.system(size: uiScale.textSize(12), weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(uiScale.controlSize)
        }
    }

    private var summary: some View {
        HStack(spacing: uiScale.spacing(14)) {
            summaryItem(
                value: AppStrings.VibeLanes.vibeUsage(manager.lanes.count),
                systemImage: "rectangle.stack"
            )
            summaryItem(
                value: "\(readyCount) \(AppStrings.VibeLanes.ready)",
                systemImage: "checkmark.seal"
            )
            summaryItem(
                value: AppStrings.VibeLanes.vibeLibraryResultCount(manager.vibes.count),
                systemImage: "sparkles.rectangle.stack"
            )
        }
    }

    private func summaryItem(value: String, systemImage: String) -> some View {
        Label(value, systemImage: systemImage)
            .font(.system(size: uiScale.textSize(10), weight: .semibold))
            .foregroundStyle(palette.secondaryTextColor)
            .lineLimit(1)
    }

    private var searchAndFilter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: uiScale.spacing(10)) {
                searchField
                filterPicker
            }
            VStack(alignment: .leading, spacing: uiScale.spacing(8)) {
                searchField
                filterPicker
            }
        }
    }

    private var searchField: some View {
        TextField(AppStrings.VibeLanes.searchLanes, text: $searchText)
            .textFieldStyle(.roundedBorder)
            .controlSize(uiScale.controlSize)
            .frame(minWidth: uiScale.chromeSize(190), idealWidth: uiScale.chromeSize(230))
    }

    private var filterPicker: some View {
        Picker(AppStrings.VibeLanes.vibeStatus, selection: $filter) {
            ForEach(VibeLaneCatalogFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(uiScale.controlSize)
        .frame(width: uiScale.chromeSize(250))
    }

    private var catalogTitle: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AppStrings.VibeLanes.laneRecipes)
                .font(.system(size: uiScale.textSize(13), weight: .bold))
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            Text(AppStrings.VibeLanes.vibeUsage(filteredLanes.count))
                .font(.system(size: uiScale.textSize(10), weight: .medium))
                .foregroundStyle(palette.tertiaryTextColor)
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty ? AppStrings.VibeLanes.noLanes : AppStrings.VibeLanes.noMatchingLanes,
            systemImage: "point.3.connected.trianglepath.dotted"
        )
        .foregroundStyle(palette.secondaryTextColor)
        .frame(maxWidth: .infinity, minHeight: uiScale.chromeSize(280))
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: uiScale.chromeSize(300),
                    maximum: uiScale.chromeSize(480)
                ),
                spacing: uiScale.spacing(14),
                alignment: .top
            )
        ]
    }

    private func categories(for lane: VibeLaneDefinition) -> [VibeCategory] {
        let categorySet: Set<VibeCategory> = Set(
            lane.checkpoints.compactMap { checkpoint -> VibeCategory? in
                guard let vibeID = checkpoint.vibeID else { return nil }
                return manager.vibe(withID: vibeID)?.category
            }
        )
        return categorySet.sorted(by: VibeCategory.sort)
    }
}
