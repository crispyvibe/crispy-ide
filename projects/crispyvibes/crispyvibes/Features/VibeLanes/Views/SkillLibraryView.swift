import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SkillLibraryView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: VibeLaneSkillStore
    @ObservedObject var manager: VibeLaneTaskManager

    @State private var searchText = ""
    @State private var selectedSource: VibeLaneSkillSource?
    @State private var selectedCategory: String?
    @State private var selectedReference: String?
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var categories: [String] {
        Array(Set(store.skills.map(\.category))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var filteredSkills: [VibeLaneSkillDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.skills.filter { skill in
            (selectedSource == nil || skill.source == selectedSource)
                && (selectedCategory == nil || skill.category == selectedCategory)
                && (query.isEmpty
                    || skill.name.localizedCaseInsensitiveContains(query)
                    || skill.detail.localizedCaseInsensitiveContains(query)
                    || skill.category.localizedCaseInsensitiveContains(query)
                    || skill.resources.contains {
                        $0.relativePath.localizedCaseInsensitiveContains(query)
                    })
        }
    }

    private var selectedSkill: VibeLaneSkillDefinition? {
        guard let selectedReference else { return nil }
        return store.skills.first { $0.reference == selectedReference }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.borderColorValue.opacity(0.5))
            filterBar
            Divider().overlay(palette.borderColorValue.opacity(0.5))
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    skillList
                        .frame(width: listWidth(for: proxy.size.width))
                    Divider().overlay(palette.borderColorValue.opacity(0.5))
                    detail
                }
            }
        }
        .background(palette.canvasBackgroundColor)
        .onAppear(perform: reconcileSelection)
        .onChange(of: filteredSkills.map(\.id)) { _, _ in reconcileSelection() }
        .alert(
            AppStrings.Skills.errorTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(AppStrings.Common.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: uiScale.spacing(12)) {
                title
                Spacer(minLength: uiScale.spacing(12))
                search
                importButton
                newButton
            }
            VStack(alignment: .leading, spacing: uiScale.spacing(10)) {
                HStack {
                    title
                    Spacer()
                    importButton
                    newButton
                }
                search
            }
        }
        .controlSize(uiScale.controlSize)
        .padding(.horizontal, uiScale.spacing(22))
        .padding(.vertical, uiScale.spacing(14))
        .background(palette.canvasSecondaryBackgroundColor)
    }

    private var title: some View {
        HStack(spacing: uiScale.spacing(10)) {
            VibeLaneIconBadge(
                systemImage: "books.vertical.fill",
                color: palette.accentColor,
                side: 36,
                iconSize: 15
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(AppStrings.Skills.title)
                    .font(.system(size: uiScale.textSize(18), weight: .bold))
                    .foregroundStyle(palette.primaryTextColor)
                Text(AppStrings.Skills.skillCount(store.skills.count))
                    .font(.system(size: uiScale.textSize(10), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
            }
        }
    }

    private var search: some View {
        TextField(AppStrings.Skills.search, text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: uiScale.chromeSize(280))
    }

    private var importButton: some View {
        Button(action: chooseSkillCollection) {
            Label(AppStrings.Skills.importSkills, systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.bordered)
    }

    private var newButton: some View {
        Button {
            isCreating = true
            selectedReference = nil
        } label: {
            Label(AppStrings.Skills.newSkill, systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
    }

    private var filterBar: some View {
        HStack(spacing: uiScale.spacing(12)) {
            Picker(AppStrings.Skills.source, selection: $selectedSource) {
                Text(AppStrings.Skills.allSources).tag(nil as VibeLaneSkillSource?)
                ForEach(VibeLaneSkillSource.allCases) { source in
                    Text(AppStrings.Skills.sourceName(source))
                        .tag(source as VibeLaneSkillSource?)
                }
            }
            .pickerStyle(.menu)
            Picker(AppStrings.Skills.category, selection: $selectedCategory) {
                Text(AppStrings.Skills.allCategories).tag(nil as String?)
                ForEach(categories, id: \.self) { value in
                    Text(value).tag(value as String?)
                }
            }
            .pickerStyle(.menu)
            Spacer()
            readinessSummary
        }
        .controlSize(uiScale.controlSize)
        .padding(.horizontal, uiScale.spacing(14))
        .padding(.vertical, uiScale.spacing(8))
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.72))
    }

    private var readinessSummary: some View {
        let ready = store.skills.filter { $0.validationState == .ready }.count
        return Label("\(ready)/\(store.skills.count)", systemImage: "checkmark.seal")
            .font(.system(size: uiScale.textSize(10), weight: .semibold))
            .foregroundStyle(palette.tertiaryTextColor)
            .help(AppStrings.Skills.compatible)
    }

    private var skillList: some View {
        ScrollView {
            LazyVStack(spacing: uiScale.spacing(3)) {
                ForEach(filteredSkills) { skill in
                    skillRow(skill)
                }
                if filteredSkills.isEmpty {
                    ContentUnavailableView(
                        AppStrings.Skills.noMatches,
                        systemImage: "magnifyingglass"
                    )
                    .padding(.top, uiScale.spacing(34))
                }
            }
            .padding(uiScale.spacing(9))
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.45))
    }

    private func skillRow(_ skill: VibeLaneSkillDefinition) -> some View {
        let isSelected = !isCreating && selectedReference == skill.reference
        return Button {
            selectedReference = skill.reference
            isCreating = false
        } label: {
            HStack(alignment: .top, spacing: uiScale.spacing(10)) {
                ZStack(alignment: .bottomTrailing) {
                    VibeLaneIconBadge(
                        systemImage: skill.source.systemImage,
                        color: sourceColor(skill.source),
                        side: 32,
                        iconSize: 12
                    )
                    Circle()
                        .fill(validationColor(skill.validationState))
                        .frame(
                            width: uiScale.chromeSize(8),
                            height: uiScale.chromeSize(8)
                        )
                        .overlay(Circle().stroke(palette.canvasBackgroundColor, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: uiScale.spacing(4)) {
                    Text(skill.name)
                        .font(.system(size: uiScale.textSize(12), weight: .semibold))
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)
                    Text(skill.detail)
                        .font(.system(size: uiScale.textSize(10)))
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(2)
                    HStack(spacing: uiScale.spacing(8)) {
                        Text(skill.category)
                        Label(
                            AppStrings.Skills.resourceCount(skill.resources.count),
                            systemImage: "folder"
                        )
                        HStack(spacing: 3) {
                            ForEach(skill.roles) { role in
                                Image(systemName: role == .work ? "hammer" : "checkmark.seal")
                            }
                        }
                    }
                    .font(.system(size: uiScale.textSize(9), weight: .medium))
                    .foregroundStyle(palette.tertiaryTextColor)
                }
                Spacer(minLength: 0)
            }
            .padding(uiScale.spacing(9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(6))
                    .fill(isSelected ? palette.accentColor.opacity(0.10) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: uiScale.chromeSize(6))
                    .strokeBorder(
                        isSelected ? palette.accentColor.opacity(0.55) : .clear,
                        lineWidth: uiScale.chromeSize(1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if isCreating {
            SkillLibraryDetailView(
                skill: nil,
                usageCount: 0,
                onCreate: create,
                onUpdate: { _, _ in },
                onDuplicate: { _ in },
                onRemove: { _ in },
                onCancel: {
                    isCreating = false
                    reconcileSelection()
                }
            )
            .id("new-skill")
        } else if let selectedSkill {
            SkillLibraryDetailView(
                skill: selectedSkill,
                usageCount: usageCount(for: selectedSkill),
                onCreate: { _ in },
                onUpdate: update,
                onDuplicate: duplicate,
                onRemove: remove,
                onCancel: {}
            )
            .id(selectedSkill.id)
        } else {
            ContentUnavailableView(AppStrings.Skills.noSkills, systemImage: "books.vertical")
        }
    }

    private func usageCount(for skill: VibeLaneSkillDefinition) -> Int {
        manager.vibes.filter { vibe in
            vibe.work.skills.contains(skill.reference)
                || vibe.verify.reviewSkills.contains(skill.reference)
        }.count
    }

    private func reconcileSelection() {
        guard !isCreating else { return }
        let ids = Set(filteredSkills.map(\.reference))
        if let selectedReference, ids.contains(selectedReference) { return }
        selectedReference = filteredSkills.first?.reference
    }

    private func create(_ draft: VibeLaneSkillDraft) {
        perform {
            let skill = try store.create(draft)
            selectedSource = .personal
            selectedCategory = skill.category
            selectedReference = skill.reference
            isCreating = false
        }
    }

    private func update(_ skill: VibeLaneSkillDefinition, _ draft: VibeLaneSkillDraft) {
        perform {
            let updated = try store.update(skill, draft: draft)
            selectedReference = updated.reference
        }
    }

    private func duplicate(_ skill: VibeLaneSkillDefinition) {
        perform {
            let copy = try store.duplicate(skill)
            selectedSource = .personal
            selectedCategory = copy.category
            selectedReference = copy.reference
        }
    }

    private func remove(_ skill: VibeLaneSkillDefinition) {
        performAsync {
            try await store.remove(skill)
            selectedReference = nil
            reconcileSelection()
        }
    }

    private func chooseSkillCollection() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .plainText]
        panel.prompt = AppStrings.Skills.importSkills
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performAsync {
            let imported = try await store.linkCollection(url)
            selectedSource = .linked
            selectedCategory = nil
            selectedReference = imported.first?.reference
            isCreating = false
        }
    }

    private func listWidth(for totalWidth: CGFloat) -> CGFloat {
        min(
            uiScale.chromeSize(400),
            max(uiScale.chromeSize(290), totalWidth * 0.34)
        )
    }

    private func sourceColor(_ source: VibeLaneSkillSource) -> Color {
        switch source {
        case .bundled: palette.accentColor
        case .personal: palette.successColor
        case .linked: palette.secondaryTextColor
        }
    }

    private func validationColor(_ state: VibeLaneSkillValidationState) -> Color {
        switch state {
        case .ready: palette.successColor
        case .attention: palette.warningColor
        case .unavailable: palette.errorColor
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performAsync(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
