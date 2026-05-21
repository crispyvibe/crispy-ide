import SwiftUI

struct VibeSpaceSettingsSheetView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    let vibespaceName: String
    @Binding var selectedCategory: VibeSpaceSettingsCategory
    let projects: [VibeSpaceSettingsProjectItem]
    let availableTerminalPresets: [TerminalPresetDefinition]
    let availableACPAgents: [ACPDiscoveredAgent]
    @Binding var startupSettings: VibeSpaceStartupSettings
    @Binding var vibespaceDefaultTerminalShell: TerminalShellPreference?
    @Binding var sourceControlSettings: VibeSpaceSourceControlSettings
    let startupOverrideForPath: (String) -> VibeSpaceProjectStartupOverride?
    let setStartupOverride: (String, VibeSpaceProjectStartupOverride?) -> Void
    let projectACPAgentOverrideIDForPath: (String) -> String?
    let setProjectACPAgentOverrideID: (String, String?) -> Void
    let setProjectShortcut: (String, Int?) -> Void
    let projectColorTagForPath: (String) -> ProjectColorTag?
    let setProjectColorTag: (String, ProjectColorTag?) -> Void
    let projectTerminalShellOverrideForPath: (String) -> TerminalShellPreference?
    let setProjectTerminalShellOverride: (String, TerminalShellPreference?) -> Void
    let onAddProjects: () -> Void
    let onAddRemoteProject: () -> Void
    let onRemoveProject: (UUID) -> Void
    let onMoveProjects: (IndexSet, Int) -> Void
    let onRenameVibeSpace: (String) -> Void
    let onReindexProjects: () -> Void
    let onClose: () -> Void
    let vibespaceShortcuts: [TerminalShortcutDefinition]
    let setVibeSpaceShortcuts: ([TerminalShortcutDefinition]) -> Void
    let projectShortcutsForPath: (String) -> [TerminalShortcutDefinition]
    let setProjectShortcutsForPath: (String, [TerminalShortcutDefinition]) -> Void

    @State private var vibespaceNameDraft = ""
    @State private var selectedProjectPath: String?

    private var categoryItems: [SettingsCategoryItem] {
        VibeSpaceSettingsCategory.allCases.map(\.categoryItem)
    }

    private var selectedCategoryIDBinding: Binding<String> {
        Binding(
            get: { selectedCategory.rawValue },
            set: { rawValue in
                selectedCategory = VibeSpaceSettingsCategory(rawValue: rawValue) ?? .vibespace
            }
        )
    }

    private var normalizedStartupSettings: VibeSpaceStartupSettings {
        startupSettings.normalized()
    }

    private var trimmedVibeSpaceNameDraft: String {
        vibespaceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveVibeSpaceRename: Bool {
        let trimmedCurrentName = vibespaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedVibeSpaceNameDraft.isEmpty && trimmedVibeSpaceNameDraft != trimmedCurrentName
    }

    private var startupTerminalCountBinding: Binding<Int> {
        Binding(
            get: { normalizedStartupSettings.startupTerminalCount },
            set: { newCount in
                let clampedCount = Swift.max(
                    VibeSpaceStartupSettings.minimumTerminalCount,
                    Swift.min(newCount, VibeSpaceStartupSettings.maximumTerminalCount)
                )
                startupSettings.startupTerminalCount = clampedCount
                ensureStartupProfileCount(clampedCount)
            }
        )
    }

    private var vibespaceDefaultTerminalShellSelectionBinding: Binding<TerminalShellSelection> {
        Binding(
            get: { TerminalShellSelection(shellPreference: vibespaceDefaultTerminalShell) },
            set: { selection in
                vibespaceDefaultTerminalShell = selection.shellPreference
            }
        )
    }

    var body: some View {
        SettingsSplitView(
            title: AppStrings.VibeSpaceSettings.title,
            subtitle: vibespaceName,
            doneAccessibilityIdentifier: "vibespace.settings.done",
            categories: categoryItems,
            selectedCategoryID: selectedCategoryIDBinding,
            onClose: onClose
        ) {
            SettingsDetailPanel {
                SettingsCategoryHeader(
                    title: selectedCategory.title,
                    description: selectedCategory.subtitle
                )

                selectedCategoryContent
            }
        }
        .buttonBorderShape(crispyvibesTheme.borderShape.buttonBorderShape)
        .onAppear {
            ensureStartupProfileCount(normalizedStartupSettings.startupTerminalCount)
            vibespaceNameDraft = vibespaceName
            if selectedProjectPath == nil {
                selectedProjectPath = projects.first?.path
            }
        }
        .onChange(of: vibespaceName) { _, newValue in
            vibespaceNameDraft = newValue
        }
        .onChange(of: projects.map(\.path)) { _, updatedPaths in
            if let selectedProjectPath, updatedPaths.contains(selectedProjectPath) {
                return
            }
            self.selectedProjectPath = updatedPaths.first
        }
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
        switch selectedCategory {
        case .vibespace:
            vibespaceCategoryContent
        case .projects:
            projectsCategoryContent
        case .shortcuts:
            shortcutsCategoryContent
        }
    }

    private var vibespaceCategoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(
                title: "VibeSpace Identity",
                description: "Use a short descriptive vibespace name."
            ) {
                SettingsFieldRow(title: "VibeSpace name", detail: nil) {
                    HStack(spacing: 8) {
                        TextField("VibeSpace", text: $vibespaceNameDraft)
                            .textFieldStyle(SquareBorderTextFieldStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("vibespace.settings.name.field")
                            .onSubmit {
                                commitVibeSpaceRename()
                            }

                        Button(AppStrings.Common.save) {
                            commitVibeSpaceRename()
                        }
                        .buttonStyle(.crispyvibesPrimary)
                        .disabled(!canSaveVibeSpaceRename)
                        .accessibilityIdentifier("vibespace.settings.name.save")
                    }
                }
            }

            SettingsCard(
                title: "VibeSpace Defaults",
                description: "Each startup terminal can run one preset or one custom command."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsFieldRow(
                        title: "Default terminal shell",
                        detail: "Applies to all folders unless a folder override is set."
                    ) {
                        Picker("VibeSpace default shell", selection: vibespaceDefaultTerminalShellSelectionBinding) {
                            ForEach(TerminalShellSelection.allCases) { selection in
                                Text(selection.title(for: .appDefault)).tag(selection)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("vibespace.settings.default-terminal-shell")
                    }

                    SettingsFieldRow(title: "Startup terminals", detail: nil) {
                        HStack(spacing: 8) {
                            Text("\(normalizedStartupSettings.startupTerminalCount)")
                                .font(AppTypographyTokens.scaledChromeSystem(13, design: .monospaced).monospacedDigit())
                                .frame(minWidth: 28, alignment: .trailing)
                            Stepper(
                                "",
                                value: startupTerminalCountBinding,
                                in: VibeSpaceStartupSettings.minimumTerminalCount...VibeSpaceStartupSettings.maximumTerminalCount
                            )
                            .labelsHidden()
                        }
                        .accessibilityIdentifier("vibespace.settings.startup-terminal-count")
                    }

                    ForEach(Array(0..<normalizedStartupSettings.startupTerminalCount), id: \.self) { terminalIndex in
                        VibeSpaceStartupProfileRow(
                            terminalIndex: terminalIndex,
                            availableTerminalPresets: availableTerminalPresets,
                            profile: startupProfileBinding(for: terminalIndex)
                        )
                    }

                    Toggle("Focus terminal when switching projects", isOn: $startupSettings.focusTerminalOnProjectSwitch)
                        .accessibilityIdentifier("vibespace.settings.focus-on-switch")
                }
            }

            SettingsCard(
                title: "VibeSpace Maintenance",
                description: "Reindex refreshes available and missing project paths for this vibespace."
            ) {
                Button {
                    onReindexProjects()
                } label: {
                    Label("Reindex Project Folders", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("vibespace.settings.reindex-projects")
            }

            VibeSpaceSourceControlSettingsCard(settings: $sourceControlSettings)
        }
    }

    private var projectsCategoryContent: some View {
        SettingsCard(
            title: "Projects",
            description: AppStrings.VibeSpaceSettings.shortcutProjectsDescription
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        onAddProjects()
                    } label: {
                        Label("Add Project Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.crispyvibesPrimary)
                    .accessibilityIdentifier("vibespace.settings.projects.add")

                    Button {
                        onAddRemoteProject()
                    } label: {
                        Label("Add Remote Project", systemImage: "server.rack")
                    }
                    .buttonStyle(.crispyvibesPrimary)
                    .accessibilityIdentifier("vibespace.settings.projects.add-remote")

                    Button {
                        onReindexProjects()
                    } label: {
                        Label("Refresh Availability", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.crispyvibesText)
                    .accessibilityIdentifier("vibespace.settings.projects.reindex")
                }

                Text(AppStrings.VibeSpaceSettings.dragToReorder)
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)

                if projects.isEmpty {
                    Text(AppStrings.VibeSpaceSettings.noProjectVibeSpace)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        List(selection: $selectedProjectPath) {
                            ForEach(projects, id: \.path) { project in
                                VibeSpaceProjectListRow(project: project)
                                    .tag(project.path)
                            }
                            .onMove { sourceOffsets, destinationOffset in
                                let movingPath: String?
                                if let index = sourceOffsets.first, projects.indices.contains(index) {
                                    movingPath = projects[index].path
                                } else {
                                    movingPath = nil
                                }
                                onMoveProjects(sourceOffsets, destinationOffset)
                                if let movingPath {
                                    selectedProjectPath = movingPath
                                }
                            }
                        }
                        .frame(minWidth: 280, maxWidth: 360)
                        .frame(minHeight: 360)
                        .scrollContentBackground(.hidden)
                        .background(appThemePalette.canvasBackgroundColor)

                        if let selectedProject = selectedProject {
                            VStack(alignment: .leading, spacing: 12) {
                                VibeSpaceProjectStartupOverrideRow(
                                    project: selectedProject,
                                    availableTerminalPresets: availableTerminalPresets,
                                    availableACPAgents: availableACPAgents,
                                    colorTag: projectColorTagBinding(for: selectedProject.path),
                                    acpAgentOverrideID: projectACPAgentOverrideBinding(for: selectedProject.path),
                                    terminalShellOverride: projectTerminalShellOverrideBinding(for: selectedProject.path),
                                    shortcutIndex: projectShortcutBinding(for: selectedProject.path),
                                    startupOverride: startupOverrideBinding(for: selectedProject.path),
                                    onRemove: {
                                        removeSelectedProject(selectedProject)
                                    }
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ContentUnavailableView(
                                "Select a Project",
                                systemImage: "folder",
                                description: Text(AppStrings.VibeSpaceSettings.chooseProject)
                            )
                            .frame(maxWidth: .infinity, minHeight: 360)
                        }
                    }
                }
            }
        }
    }

    private var selectedProject: VibeSpaceSettingsProjectItem? {
        if let selectedProjectPath,
           let matchingProject = projects.first(where: { $0.path == selectedProjectPath }) {
            return matchingProject
        }
        return projects.first
    }

    private var shortcutsCategoryContent: some View {
        VibeSpaceShortcutCommandsSettingsView(
            vibespaceName: vibespaceName,
            vibespaceShortcuts: vibespaceShortcuts,
            setVibeSpaceShortcuts: setVibeSpaceShortcuts,
            projects: projects,
            projectShortcutsForPath: projectShortcutsForPath,
            setProjectShortcutsForPath: setProjectShortcutsForPath
        )
    }

    private func startupProfileBinding(for terminalIndex: Int) -> Binding<VibeSpaceTerminalStartupProfile> {
        Binding(
            get: {
                normalizedStartupSettings.profile(at: terminalIndex)
            },
            set: { updatedProfile in
                var updatedSettings = startupSettings
                updatedSettings.setProfile(updatedProfile, at: terminalIndex)
                startupSettings = updatedSettings
            }
        )
    }

    private func startupOverrideBinding(for projectPath: String) -> Binding<VibeSpaceProjectStartupOverride?> {
        Binding(
            get: { startupOverrideForPath(projectPath) },
            set: { updatedOverride in
                setStartupOverride(projectPath, updatedOverride)
            }
        )
    }

    private func projectShortcutBinding(for projectPath: String) -> Binding<Int?> {
        Binding(
            get: { projects.first(where: { $0.path == projectPath })?.shortcutIndex },
            set: { updatedShortcut in
                setProjectShortcut(projectPath, updatedShortcut)
            }
        )
    }

    private func projectACPAgentOverrideBinding(for projectPath: String) -> Binding<String?> {
        Binding(
            get: { projectACPAgentOverrideIDForPath(projectPath) },
            set: { updatedAgentID in
                setProjectACPAgentOverrideID(projectPath, updatedAgentID)
            }
        )
    }

    private func projectColorTagBinding(for projectPath: String) -> Binding<ProjectColorTag?> {
        Binding(
            get: { projectColorTagForPath(projectPath) },
            set: { updatedColorTag in
                setProjectColorTag(projectPath, updatedColorTag)
            }
        )
    }

    private func projectTerminalShellOverrideBinding(
        for projectPath: String
    ) -> Binding<TerminalShellPreference?> {
        Binding(
            get: { projectTerminalShellOverrideForPath(projectPath) },
            set: { updatedShellPreference in
                setProjectTerminalShellOverride(projectPath, updatedShellPreference)
            }
        )
    }

    private func ensureStartupProfileCount(_ requiredCount: Int) {
        var updatedSettings = startupSettings
        let clampedCount = Swift.max(
            VibeSpaceStartupSettings.minimumTerminalCount,
            Swift.min(requiredCount, VibeSpaceStartupSettings.maximumTerminalCount)
        )
        for index in 0..<clampedCount {
            updatedSettings.setProfile(updatedSettings.profile(at: index), at: index)
        }
        startupSettings = updatedSettings
    }

    private func commitVibeSpaceRename() {
        let trimmedName = trimmedVibeSpaceNameDraft
        guard !trimmedName.isEmpty else {
            vibespaceNameDraft = vibespaceName
            return
        }
        onRenameVibeSpace(trimmedName)
    }

    private func removeSelectedProject(_ project: VibeSpaceSettingsProjectItem) {
        let currentIndex = projects.firstIndex(where: { $0.id == project.id })
        let remainingProjects = projects.filter { $0.id != project.id }
        let nextSelectionPath: String?
        if let index = currentIndex, !remainingProjects.isEmpty {
            if remainingProjects.indices.contains(index) {
                nextSelectionPath = remainingProjects[index].path
            } else {
                nextSelectionPath = remainingProjects.last?.path
            }
        } else {
            nextSelectionPath = nil
        }
        onRemoveProject(project.id)
        selectedProjectPath = nextSelectionPath
    }
}

private struct VibeSpaceSourceControlSettingsCard: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Binding var settings: VibeSpaceSourceControlSettings

    private var normalizedSettings: VibeSpaceSourceControlSettings {
        settings.normalized()
    }

    private var ignoredFoldersBinding: Binding<String> {
        Binding(
            get: { normalizedSettings.ignoredDirectoryNames.joined(separator: ", ") },
            set: { newValue in
                settings.ignoredDirectoryNames = newValue
                    .split(whereSeparator: { $0 == "," || $0 == "\n" })
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        )
    }

    private var scanDepthBinding: Binding<Int> {
        Binding(
            get: { normalizedSettings.scanMaxDepth },
            set: { settings.scanMaxDepth = $0 }
        )
    }

    private var scanRepositoryLimitBinding: Binding<Int> {
        Binding(
            get: { normalizedSettings.scanMaxRepositories },
            set: { newValue in
                settings.scanMaxRepositories = newValue
                if settings.autoPresentedRepositoryLimit > newValue {
                    settings.autoPresentedRepositoryLimit = newValue
                }
            }
        )
    }

    private var presentedRepositoryLimitBinding: Binding<Int> {
        Binding(
            get: { normalizedSettings.autoPresentedRepositoryLimit },
            set: { settings.autoPresentedRepositoryLimit = $0 }
        )
    }

    var body: some View {
        SettingsCard(
            title: "Source Control",
            description: "Protect responsiveness by limiting discovery and rendering, and by ignoring generated or tool-managed folders."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(
                    title: "Ignored folders",
                    detail: "Comma-separated directory names to skip while scanning for repositories."
                ) {
                    TextField(
                        "DerivedData, SourcePackages, checkouts, node_modules",
                        text: ignoredFoldersBinding,
                        axis: .vertical
                    )
                    .textFieldStyle(SquareBorderTextFieldStyle())
                    .lineLimit(2...4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("vibespace.settings.source-control.ignored-folders")
                }

                SettingsFieldRow(title: "Scan depth", detail: nil) {
                    HStack(spacing: 8) {
                        Text("\(normalizedSettings.scanMaxDepth)")
                            .font(AppTypographyTokens.scaledChromeSystem(13, design: .monospaced).monospacedDigit())
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper(
                            "",
                            value: scanDepthBinding,
                            in: VibeSpaceSourceControlSettings.minimumScanDepth...VibeSpaceSourceControlSettings.maximumScanDepth
                        )
                        .labelsHidden()
                    }
                    .accessibilityIdentifier("vibespace.settings.source-control.scan-depth")
                }

                SettingsFieldRow(title: "Max discovered repos", detail: nil) {
                    HStack(spacing: 8) {
                        Text("\(normalizedSettings.scanMaxRepositories)")
                            .font(AppTypographyTokens.scaledChromeSystem(13, design: .monospaced).monospacedDigit())
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper(
                            "",
                            value: scanRepositoryLimitBinding,
                            in: VibeSpaceSourceControlSettings.minimumRepositoryCount...VibeSpaceSourceControlSettings.maximumRepositoryCount
                        )
                        .labelsHidden()
                    }
                    .accessibilityIdentifier("vibespace.settings.source-control.max-repos")
                }

                SettingsFieldRow(
                    title: "Rendered repos",
                    detail: "Repositories above this limit remain discovered but are not eagerly loaded into the UI."
                ) {
                    HStack(spacing: 8) {
                        Text("\(normalizedSettings.autoPresentedRepositoryLimit)")
                            .font(AppTypographyTokens.scaledChromeSystem(13, design: .monospaced).monospacedDigit())
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper(
                            "",
                            value: presentedRepositoryLimitBinding,
                            in: VibeSpaceSourceControlSettings.minimumPresentedRepositoryCount...max(
                                VibeSpaceSourceControlSettings.minimumPresentedRepositoryCount,
                                normalizedSettings.scanMaxRepositories
                            )
                        )
                        .labelsHidden()
                    }
                    .accessibilityIdentifier("vibespace.settings.source-control.rendered-repos")
                }

                Text(AppStrings.VibeSpaceSettings.scanLimitsHint)
                    .font(AppTypographyTokens.settingsFieldDetail)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
            }
        }
    }
}

struct VibeSpaceShortcutCommandsSettingsView: View {
    @Environment(\.appThemePalette) private var appThemePalette

    let vibespaceName: String
    let vibespaceShortcuts: [TerminalShortcutDefinition]
    let setVibeSpaceShortcuts: ([TerminalShortcutDefinition]) -> Void
    let projects: [VibeSpaceSettingsProjectItem]
    let projectShortcutsForPath: (String) -> [TerminalShortcutDefinition]
    let setProjectShortcutsForPath: (String, [TerminalShortcutDefinition]) -> Void

    @State private var draftRows: [ShortcutCommandDraftRow] = []

    private var sortedProjects: [VibeSpaceSettingsProjectItem] {
        projects.sorted { lhs, rhs in
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private var sourceRows: [ShortcutCommandDraftRow] {
        var rows = vibespaceShortcuts.map {
            ShortcutCommandDraftRow(
                id: $0.id,
                name: $0.name,
                command: $0.command,
                launchBehavior: $0.launchBehavior,
                scope: .vibespace
            )
        }
        for project in sortedProjects {
            rows.append(
                contentsOf: projectShortcutsForPath(project.path).map {
                    ShortcutCommandDraftRow(
                        id: $0.id,
                        name: $0.name,
                        command: $0.command,
                        launchBehavior: $0.launchBehavior,
                        scope: .project(project.path)
                    )
                }
            )
        }
        return rows
    }

    private var projectOptions: [ShortcutProjectOption] {
        sortedProjects.map { ShortcutProjectOption(path: $0.path, title: $0.title) }
    }

    private var validProjectPaths: Set<String> {
        Set(projectOptions.map(\.path))
    }

    private var targetOptions: [VibeSpaceShortcutTargetOption] {
        VibeSpaceShortcutSettingsSupport.targetOptions(
            vibespaceName: vibespaceName,
            projects: sortedProjects
        )
    }

    var body: some View {
        SettingsCard(
            title: AppStrings.VibeSpaceSettings.shortcutCommandsCardTitle,
            description: AppStrings.VibeSpaceSettings.shortcutCommandsCardDescription
        ) {
            VStack(alignment: .leading, spacing: 12) {
                shortcutHeaderRow

                if draftRows.isEmpty {
                    Text(AppStrings.TerminalShortcuts.noShortcuts)
                        .font(AppTypographyTokens.settingsFieldDetail)
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(draftRows) { row in
                            ShortcutCommandEditableRow(
                                row: binding(for: row.id),
                                targetOptions: targetOptions,
                                onDelete: {
                                    draftRows.removeAll { $0.id == row.id }
                                    commitChanges()
                                },
                                onCommit: commitChanges
                            )
                        }
                    }
                }

                Button {
                    draftRows.append(
                        ShortcutCommandDraftRow(
                            name: "",
                            command: "",
                            launchBehavior: .currentTerminal,
                            scope: .vibespace,
                            isTransientDraft: true
                        )
                    )
                } label: {
                    Label(AppStrings.VibeSpaceSettings.addShortcut, systemImage: "plus")
                }
                .buttonStyle(.crispyvibesText)
                .accessibilityIdentifier("vibespace.settings.shortcuts.add")
            }
        }
        .accessibilityIdentifier("vibespace.settings.shortcuts.card")
        .onAppear {
            draftRows = sourceRows
        }
        .onChange(of: sourceRows) { _, newValue in
            guard !draftRows.contains(where: \.isTransientDraft) else { return }
            draftRows = newValue
        }
        .onChange(of: validProjectPaths) { _, newValue in
            let filteredRows = draftRows.filter { row in
                switch row.scope {
                case .vibespace:
                    return true
                case let .project(path):
                    return newValue.contains(path)
                }
            }
            guard filteredRows != draftRows else { return }
            draftRows = filteredRows
            commitChanges()
        }
        .onDisappear {
            commitChanges()
        }
    }

    private var shortcutHeaderRow: some View {
        HStack(spacing: 8) {
            Text(AppStrings.VibeSpaceSettings.shortcutColumnName)
                .frame(width: 170, alignment: .leading)
            Text(AppStrings.VibeSpaceSettings.shortcutColumnCommand)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(AppStrings.VibeSpaceSettings.shortcutColumnOpenIn)
                .frame(width: 170, alignment: .leading)
            Text(AppStrings.VibeSpaceSettings.shortcutColumnTarget)
                .frame(width: 240, alignment: .leading)
            Spacer(minLength: 20)
        }
        .font(AppTypographyTokens.settingsFieldDetail)
        .foregroundStyle(appThemePalette.secondaryTextColor)
    }

    private func commitChanges() {
        let rows = draftRows
            .filter { !$0.isEmpty }
            .map {
                VibeSpaceShortcutPersistedRow(
                    definition: $0.shortcutDefinition,
                    target: $0.scope
                )
            }
        let plan = VibeSpaceShortcutSettingsSupport.buildPersistencePlan(
            rows: rows,
            orderedProjectPaths: sortedProjects.map(\.path)
        )
        setVibeSpaceShortcuts(plan.vibespaceShortcuts)

        for project in sortedProjects {
            setProjectShortcutsForPath(
                project.path,
                plan.projectShortcutsByPath[project.path] ?? []
            )
        }
    }

    private func binding(for rowID: UUID) -> Binding<ShortcutCommandDraftRow> {
        Binding(
            get: {
                draftRows.first(where: { $0.id == rowID }) ?? ShortcutCommandDraftRow(
                    id: rowID,
                    name: "",
                    command: "",
                    launchBehavior: .currentTerminal,
                    scope: .vibespace
                )
            },
            set: { updatedValue in
                guard let index = draftRows.firstIndex(where: { $0.id == rowID }) else { return }
                draftRows[index] = updatedValue
            }
        )
    }
}

private struct ShortcutCommandEditableRow: View {
    @FocusState private var focusedField: EditableField?

    @Binding var row: ShortcutCommandDraftRow
    let targetOptions: [VibeSpaceShortcutTargetOption]
    let onDelete: () -> Void
    let onCommit: () -> Void

    private enum EditableField: Hashable {
        case name
        case command
    }

    private var targetSelectionBinding: Binding<String> {
        Binding(
            get: { row.scope.storageID },
            set: { newValue in
                guard let targetOption = targetOptions.first(where: { $0.id == newValue }) else { return }
                row.scope = targetOption.scope
                row.isTransientDraft = false
                onCommit()
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(AppStrings.TerminalShortcuts.shortcutName, text: $row.name)
                .textFieldStyle(SquareBorderTextFieldStyle())
                .frame(width: 170)
                .accessibilityIdentifier("vibespace.settings.shortcuts.name")
                .focused($focusedField, equals: .name)
                .onChange(of: row.name) { _, _ in
                    row.isTransientDraft = false
                }
                .onSubmit(onCommit)

            TextField(AppStrings.TerminalShortcuts.command, text: $row.command)
                .textFieldStyle(SquareBorderTextFieldStyle())
                .accessibilityIdentifier("vibespace.settings.shortcuts.command")
                .focused($focusedField, equals: .command)
                .onChange(of: row.command) { _, _ in
                    row.isTransientDraft = false
                }
                .onSubmit(onCommit)

            Picker(AppStrings.VibeSpaceSettings.shortcutColumnOpenIn, selection: $row.launchBehavior) {
                ForEach(TerminalShortcutLaunchBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 170, alignment: .leading)
            .accessibilityIdentifier("vibespace.settings.shortcuts.launch-behavior")
            .onChange(of: row.launchBehavior) { _, _ in
                row.isTransientDraft = false
                onCommit()
            }

            Picker(AppStrings.VibeSpaceSettings.shortcutColumnTarget, selection: targetSelectionBinding) {
                ForEach(targetOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 240, alignment: .leading)
            .accessibilityIdentifier("vibespace.settings.shortcuts.target")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.crispyvibesText)
            .accessibilityIdentifier("vibespace.settings.shortcuts.delete")
        }
        .accessibilityIdentifier("vibespace.settings.shortcuts.row")
        .onChange(of: focusedField) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            onCommit()
        }
    }
}

private struct ShortcutProjectOption: Identifiable, Equatable {
    let path: String
    let title: String

    var id: String { path }
}

private struct ShortcutCommandDraftRow: Identifiable, Equatable {
    let id: UUID
    var name: String
    var command: String
    var launchBehavior: TerminalShortcutLaunchBehavior
    var scope: VibeSpaceShortcutTargetScope
    var isTransientDraft: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        launchBehavior: TerminalShortcutLaunchBehavior,
        scope: VibeSpaceShortcutTargetScope,
        isTransientDraft: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.launchBehavior = launchBehavior
        self.scope = scope
        self.isTransientDraft = isTransientDraft
    }

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shortcutDefinition: TerminalShortcutDefinition {
        TerminalShortcutDefinition(
            id: id,
            name: name,
            command: command,
            launchBehavior: launchBehavior
        )
    }
}
