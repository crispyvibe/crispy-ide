import SwiftUI

@MainActor
struct VibeLibraryView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var manager: VibeLaneTaskManager
    let onEdit: (UUID) -> Void
    let onNew: () -> Void

    @State private var searchText = ""
    @State private var filter: VibeLibraryFilter = .all
    @State private var selectedCategory: VibeCategory?
    @State private var selectedVibeID: UUID?

    private var categories: [VibeCategory] {
        VibeCategory.available(in: manager.vibes)
    }

    private var filteredVibes: [VibeDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.vibes
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .filter { filter.includes($0, usageCount: manager.vibeUsageCount(id: $0.id)) }
            .filter {
                query.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.detail?.localizedCaseInsensitiveContains(query) == true)
                    || $0.work.goal.localizedCaseInsensitiveContains(query)
                    || $0.work.skills.contains { $0.localizedCaseInsensitiveContains(query) }
                    || $0.verify.definition.localizedCaseInsensitiveContains(query)
                    || $0.verify.reviewSkills.contains { $0.localizedCaseInsensitiveContains(query) }
                    || AppStrings.VibeLanes.vibeCategoryName($0.category)
                        .localizedCaseInsensitiveContains(query)
            }
            .sorted {
                if $0.category != $1.category {
                    return VibeCategory.sort($0.category, $1.category)
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var selectedVibe: VibeDefinition? {
        guard let selectedVibeID else { return nil }
        return manager.vibes.first { $0.id == selectedVibeID }
    }

    private var filteredVibeIDs: [UUID] {
        filteredVibes.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            horizontalSeparator
            GeometryReader { proxy in
                if proxy.size.width >= uiScale.chromeSize(940) {
                    wideCatalog
                } else {
                    compactCatalog
                }
            }
        }
        .background(palette.canvasBackgroundColor)
        .onAppear(perform: reconcileSelection)
        .onChange(of: filteredVibeIDs) { _, _ in reconcileSelection() }
    }

    private var header: some View {
        HStack(spacing: uiScale.spacing(12)) {
            VibeLaneIconBadge(
                systemImage: "sparkles.rectangle.stack",
                color: palette.accentColor,
                side: 36,
                iconSize: 15
            )
            VStack(alignment: .leading, spacing: uiScale.spacing(1)) {
                Text(AppStrings.VibeLanes.yourVibes)
                    .font(.system(size: uiScale.textSize(18), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                Text("\(manager.vibes.count)")
                    .font(.system(size: uiScale.textSize(11), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .monospacedDigit()
            }
            Spacer(minLength: uiScale.spacing(16))
            TextField(AppStrings.VibeLanes.searchVibes, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: uiScale.chromeSize(240))
                .controlSize(uiScale.controlSize)
            Button(action: onNew) {
                Label(AppStrings.VibeLanes.newVibe, systemImage: "plus")
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(uiScale.controlSize)
        }
        .padding(.horizontal, uiScale.spacing(22))
        .padding(.vertical, uiScale.spacing(14))
        .background(palette.canvasSecondaryBackgroundColor)
    }

    private var wideCatalog: some View {
        HStack(spacing: 0) {
            filterRail
                .frame(width: uiScale.chromeSize(210))
            verticalSeparator
            vibeList
                .frame(
                    minWidth: uiScale.chromeSize(330),
                    idealWidth: uiScale.chromeSize(390),
                    maxWidth: uiScale.chromeSize(460)
                )
            verticalSeparator
            inspector
        }
    }

    private var compactCatalog: some View {
        VStack(spacing: 0) {
            compactFilter
            horizontalSeparator
            HStack(spacing: 0) {
                vibeList
                    .frame(
                        minWidth: uiScale.chromeSize(300),
                        idealWidth: uiScale.chromeSize(350),
                        maxWidth: uiScale.chromeSize(410)
                    )
                verticalSeparator
                inspector
            }
        }
    }

    private var filterRail: some View {
        VStack(alignment: .leading, spacing: uiScale.spacing(5)) {
            railTitle(AppStrings.VibeLanes.vibeCategories)

            categoryButton(nil)
            ForEach(categories) { category in
                categoryButton(category)
            }

            railTitle(AppStrings.VibeLanes.vibeStatus)
                .padding(.top, uiScale.spacing(12))

            ForEach(VibeLibraryFilter.allCases) { option in
                statusFilterButton(option)
            }
            Spacer()
        }
        .padding(uiScale.spacing(10))
        .background(palette.canvasSecondaryBackgroundColor)
    }

    private func railTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: uiScale.textSize(10), weight: .bold))
            .foregroundStyle(palette.tertiaryTextColor)
            .textCase(.uppercase)
            .padding(.horizontal, uiScale.spacing(12))
            .padding(.bottom, uiScale.spacing(4))
    }

    private var compactFilter: some View {
        HStack(spacing: uiScale.spacing(10)) {
            Picker(AppStrings.VibeLanes.vibeCategories, selection: $selectedCategory) {
                Text(AppStrings.VibeLanes.vibeCategoryAll).tag(nil as VibeCategory?)
                ForEach(categories) { category in
                    Label(
                        AppStrings.VibeLanes.vibeCategoryName(category),
                        systemImage: category.systemImage
                    )
                    .tag(category as VibeCategory?)
                }
            }
            .pickerStyle(.menu)
            .controlSize(uiScale.controlSize)

            Picker(AppStrings.VibeLanes.vibeStatus, selection: $filter) {
                ForEach(VibeLibraryFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .controlSize(uiScale.controlSize)
            Spacer()
            Text(AppStrings.VibeLanes.vibeLibraryResultCount(filteredVibes.count))
                .font(.system(size: uiScale.textSize(11), weight: .medium))
                .foregroundStyle(palette.tertiaryTextColor)
                .monospacedDigit()
        }
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(8))
        .background(palette.canvasSecondaryBackgroundColor)
    }

    private func categoryButton(_ category: VibeCategory?) -> some View {
        let isSelected = selectedCategory == category
        let title = category.map(AppStrings.VibeLanes.vibeCategoryName)
            ?? AppStrings.VibeLanes.vibeCategoryAll
        let systemImage = category?.systemImage ?? "square.grid.2x2"
        return Button {
            selectedCategory = category
        } label: {
            railButtonLabel(
                title: title,
                systemImage: systemImage,
                count: count(for: category),
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .vibeLaneHoverable(cornerRadius: uiScale.chromeSize(6))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func statusFilterButton(_ option: VibeLibraryFilter) -> some View {
        let isSelected = filter == option
        return Button {
            filter = option
        } label: {
            railButtonLabel(
                title: option.title,
                systemImage: option.systemImage,
                count: count(for: option),
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .vibeLaneHoverable(cornerRadius: uiScale.chromeSize(6))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func railButtonLabel(
        title: String,
        systemImage: String,
        count: Int,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: uiScale.spacing(8)) {
            Image(systemName: systemImage)
                .font(.system(size: uiScale.iconSize(12), weight: .semibold))
                .frame(width: uiScale.chromeSize(16))
            Text(title)
                .font(.system(size: uiScale.textSize(11), weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.system(size: uiScale.textSize(10), weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(isSelected ? palette.primaryTextColor : palette.secondaryTextColor)
        .padding(.horizontal, uiScale.spacing(10))
        .frame(height: uiScale.chromeSize(30))
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: uiScale.chromeSize(6), style: .continuous)
                .fill(isSelected ? palette.selectionBackgroundColor.opacity(0.28) : .clear)
        )
    }

    private var vibeList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    selectedCategory.map(AppStrings.VibeLanes.vibeCategoryName)
                        ?? AppStrings.VibeLanes.vibeLibraryAll
                )
                    .font(.system(size: uiScale.textSize(13), weight: .semibold))
                    .foregroundStyle(palette.primaryTextColor)
                Spacer()
                if filter != .all {
                    Text(filter.title)
                        .font(.system(size: uiScale.textSize(10), weight: .medium))
                        .foregroundStyle(palette.secondaryTextColor)
                }
                Text("\(filteredVibes.count)")
                    .font(.system(size: uiScale.textSize(11), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
                    .monospacedDigit()
            }
            .padding(.horizontal, uiScale.spacing(14))
            .frame(height: uiScale.chromeSize(42))

            horizontalSeparator

            if filteredVibes.isEmpty {
                ContentUnavailableView(
                    AppStrings.VibeLanes.noVibes,
                    systemImage: "sparkles.rectangle.stack"
                )
                .foregroundStyle(palette.secondaryTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: uiScale.spacing(4), pinnedViews: [.sectionHeaders]) {
                        ForEach(categories) { category in
                            let categoryVibes = filteredVibes.filter { $0.category == category }
                            if !categoryVibes.isEmpty {
                                Section {
                                    ForEach(categoryVibes) { vibe in
                                        VibeLibraryRow(
                                            vibe: vibe,
                                            usageCount: manager.vibeUsageCount(id: vibe.id),
                                            isSelected: selectedVibeID == vibe.id,
                                            onSelect: { selectedVibeID = vibe.id }
                                        )
                                    }
                                } header: {
                                    categoryHeader(category, count: categoryVibes.count)
                                }
                            }
                        }
                    }
                    .padding(uiScale.spacing(8))
                }
            }
        }
        .background(palette.canvasBackgroundColor)
    }

    private func categoryHeader(_ category: VibeCategory, count: Int) -> some View {
        HStack(spacing: uiScale.spacing(7)) {
            VibeCategoryLabel(category: category, isEmphasized: true)
            Spacer()
            Text("\(count)")
                .font(.system(size: uiScale.textSize(10), weight: .medium))
                .foregroundStyle(palette.tertiaryTextColor)
                .monospacedDigit()
        }
        .padding(.horizontal, uiScale.spacing(10))
        .frame(height: uiScale.chromeSize(28))
        .background(palette.canvasBackgroundColor)
    }

    @ViewBuilder
    private var inspector: some View {
        if let selectedVibe {
            VibeLibraryInspectorView(
                vibe: selectedVibe,
                usageCount: manager.vibeUsageCount(id: selectedVibe.id),
                onEdit: { onEdit(selectedVibe.id) }
            )
        } else {
            Color.clear
                .background(palette.canvasBackgroundColor)
        }
    }

    private var horizontalSeparator: some View {
        Rectangle()
            .fill(palette.borderColorValue.opacity(0.42))
            .frame(maxWidth: .infinity)
            .frame(height: uiScale.chromeSize(1))
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(palette.borderColorValue.opacity(0.42))
            .frame(width: uiScale.chromeSize(1))
            .frame(maxHeight: .infinity)
    }

    private func count(for option: VibeLibraryFilter) -> Int {
        manager.vibes.filter {
            (selectedCategory == nil || $0.category == selectedCategory)
                && option.includes($0, usageCount: manager.vibeUsageCount(id: $0.id))
        }.count
    }

    private func count(for category: VibeCategory?) -> Int {
        manager.vibes.filter {
            (category == nil || $0.category == category)
                && filter.includes($0, usageCount: manager.vibeUsageCount(id: $0.id))
        }.count
    }

    private func reconcileSelection() {
        guard !filteredVibeIDs.isEmpty else {
            selectedVibeID = nil
            return
        }
        if let selectedVibeID, filteredVibeIDs.contains(selectedVibeID) {
            return
        }
        selectedVibeID = filteredVibeIDs.first
    }
}
