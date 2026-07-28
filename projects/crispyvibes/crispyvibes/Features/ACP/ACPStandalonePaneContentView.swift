import SwiftUI

enum ACPDisplayMode {
    case board
    case detail
    case spotlight
    case preview

    var isCompact: Bool {
        switch self {
        case .board, .spotlight, .preview:
            return true
        case .detail:
            return false
        }
    }

    var showsStandaloneModelPicker: Bool {
        switch self {
        case .detail, .preview:
            return true
        case .board, .spotlight:
            return false
        }
    }

    var showsTrustModeInHeader: Bool {
        self == .detail
    }

    var timelineSpacing: CGFloat {
        isCompact ? 12 : 16
    }

    var timelinePadding: CGFloat {
        isCompact ? 12 : 16
    }

    var composeInitialHeight: CGFloat {
        isCompact ? 64 : 80
    }
}

struct ACPStandalonePaneContentView: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var store: ACPStandaloneSessionStore
    let projects: [AnyProjectSession]
    let displayMode: ACPDisplayMode
    private let externalShowingSettings: Binding<Bool>?
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?

    @State private var discoveredAgents: [ACPDiscoveredAgent] = []
    @State private var showingAddAgent = false
    @State private var localShowingSettings = false
    @State private var newAgentTitle = ""
    @State private var newAgentCommand = ""

    private var selectedProjectTitle: String? {
        store.selectedProject(from: projects)?.title
    }

    private var canConnect: Bool {
        store.selectedAgentID != nil
            && store.selectedProject(from: projects) != nil
            && !store.isConnecting
    }

    private var isShowingSettings: Bool {
        externalShowingSettings?.wrappedValue ?? localShowingSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            if displayMode != .board {
                setupStrip
                Divider()
            }

            if isShowingSettings {
                settingsPanel
            } else {
                ACPChatView(
                    viewModel: store.chatViewModel,
                    title: store.agentTitle,
                    subtitle: selectedProjectTitle,
                    showsHeader: false,
                    showsHeaderSessionControls: false,
                    displayMode: displayMode,
                    historyKey: store.id,
                    isExternallyManaged: store.isExternallyManaged,
                    managedSessionEnded: store.managedSessionEnded,
                    isConnecting: store.isConnecting,
                    connectionError: store.connectionError,
                    onReconnect: store.isExternallyManaged ? nil : { Task { await store.connect(projects: projects) } },
                    onLinkTargetActivated: onLinkTargetActivated,
                    onFileSystemTargetActivated: onFileSystemTargetActivated
                )
            }
        }
        .background(palette.canvasBackgroundColor)
        .onAppear(perform: prepareDefaults)
        .alert(
            "Session Resume Failed",
            isPresented: Binding(
                get: { store.pendingResumeFailure != nil },
                set: { if !$0 { store.dismissResumeFailure() } }
            )
        ) {
            Button("Start Fresh") { store.confirmStartFreshSession(projects: projects) }
            Button("Cancel", role: .cancel) { store.dismissResumeFailure() }
        } message: {
            Text(store.pendingResumeFailure ?? "")
        }
        .sheet(isPresented: $showingAddAgent) {
            addAgentSheet
        }
    }

    init(
        store: ACPStandaloneSessionStore,
        projects: [AnyProjectSession],
        displayMode: ACPDisplayMode = .detail,
        showingSettings: Binding<Bool>? = nil,
        onLinkTargetActivated: ((URL) -> Void)?,
        onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?
    ) {
        self.store = store
        self.projects = projects
        self.displayMode = displayMode
        self.externalShowingSettings = showingSettings
        self.onLinkTargetActivated = onLinkTargetActivated
        self.onFileSystemTargetActivated = onFileSystemTargetActivated
    }

    private var addAgentSheet: some View {
        VStack(spacing: 16) {
            Text("Add Custom Agent")
                .font(AppTypographyTokens.headline)
            TextField("Name", text: $newAgentTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Command (e.g. my-agent --acp)", text: $newAgentCommand)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showingAddAgent = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Add") {
                    let parts = CLICommandLineParser.splitArguments(newAgentCommand)
                    guard let executable = parts.first, !newAgentTitle.isEmpty else { return }
                    let args = Array(parts.dropFirst())
                    var agents = AppPreferences.customACPAgents()
                    agents.append(CustomACPAgent(title: newAgentTitle, executable: executable, arguments: args))
                    AppPreferences.setCustomACPAgents(agents)
                    discoveredAgents = ACPAgentRegistry.discoverInstalledAgents()
                    newAgentTitle = ""
                    newAgentCommand = ""
                    showingAddAgent = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newAgentTitle.isEmpty || newAgentCommand.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    // MARK: - Setup Strip

    private var setupStrip: some View {
        HStack(spacing: 10) {
            if isShowingSettings {
                Button {
                    setShowingSettings(false)
                } label: {
                    Label("Chat", systemImage: "chevron.left")
                        .font(AppTypographyTokens.captionSemibold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.primaryTextColor)
                Text("Settings")
                    .font(AppTypographyTokens.captionSemibold)
                    .foregroundStyle(palette.secondaryTextColor)
            } else {
                agentMenu(showsTitle: true)
                projectMenu
            }

            Spacer(minLength: 0)

            if store.isConnecting {
                ProgressView()
                    .controlSize(uiScale.controlSize)
            } else if store.isExternallyManaged, !store.isConnected {
                HStack(spacing: 6) {
                    if store.managedSessionEnded {
                        // The engine finished with this session; a spinner here
                        // would imply a reconnect that will never happen.
                        Image(systemName: "checkmark.circle")
                            .font(AppTypographyTokens.scaledSystem(10))
                            .foregroundStyle(palette.secondaryTextColor)
                        Text(AppStrings.ACP.managedSessionEnded)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                    } else {
                        ProgressView()
                            .controlSize(uiScale.controlSize)
                        Text(AppStrings.ACP.managedSessionWaiting)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                }
            } else if !store.isConnected {
                Button {
                    Task { await store.connect(projects: projects) }
                } label: {
                    Text("Connect")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(uiScale.controlSize)
                .disabled(!canConnect)
            } else {
                Image(systemName: "circle.fill")
                    .font(AppTypographyTokens.scaledSystem(7))
                    .foregroundStyle(palette.successColor)
                    .help("Connected")
            }

            Button {
                setShowingSettings(!isShowingSettings)
            } label: {
                Image(systemName: isShowingSettings ? "xmark" : "line.3.horizontal.decrease.circle")
                    .font(AppTypographyTokens.scaledIcon(13, weight: .semibold))
                    .frame(width: uiScale.iconSize(22), height: uiScale.iconSize(22))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isShowingSettings ? palette.primaryTextColor : palette.secondaryTextColor)
            .help(isShowingSettings ? "Hide settings" : "Show settings")
        }
        .padding(.horizontal, displayMode.isCompact ? 10 : 12)
        .padding(.vertical, displayMode.isCompact ? 7 : 8)
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.72))
    }

    private func setShowingSettings(_ value: Bool) {
        if let externalShowingSettings {
            externalShowingSettings.wrappedValue = value
        } else {
            localShowingSettings = value
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsSection(title: "Session") {
                    HStack(spacing: 8) {
                        agentMenu(showsTitle: true)
                        projectMenu
                    }
                    ACPStandaloneHeaderSessionControls(
                        viewModel: store.chatViewModel,
                        displayMode: .detail
                    )
                }

                settingsSection(title: "Model") {
                    standaloneModelMenu
                }

                settingsSection(title: "Trust") {
                    trustModePicker
                }

                if let connectionError = store.connectionError {
                    settingsSection(title: "Connection") {
                        Text(connectionError)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.warningColor)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(displayMode.isCompact ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvasBackgroundColor)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypographyTokens.captionSemibold)
                .foregroundStyle(palette.secondaryTextColor)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvasSecondaryBackgroundColor.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                .stroke(palette.borderColorValue.opacity(crispyvibesTheme.borderVisible ? 0.45 : 0), lineWidth: 0.7)
        )
    }

    private func agentMenu(showsTitle: Bool) -> some View {
        Menu {
            ForEach(discoveredAgents.filter(\.isAvailable)) { agent in
                Button {
                    let changed = store.selectedAgentID != agent.id
                    store.setSelectedAgentID(agent.id)
                    store.connectionError = nil
                    if changed, store.isConnected {
                        Task { await store.reconnectWithNewAgent(projects: projects) }
                    }
                } label: {
                    Label {
                        Text(agent.title)
                    } icon: {
                        agentIcon(for: agent.id)
                    }
                }
            }
            Divider()
            Button { showingAddAgent = true } label: {
                Label("Add Custom Agent…", systemImage: "plus")
            }
        } label: {
            controlChip {
                HStack(spacing: 6) {
                    if let agentID = store.selectedAgentID {
                        agentIcon(for: agentID)
                        if showsTitle {
                            Text(store.agentTitle)
                                .lineLimit(1)
                        }
                    } else {
                        Image(systemName: "sparkles")
                        if showsTitle {
                            Text("Select Agent")
                        }
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppTypographyTokens.scaledSystem(8))
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var projectMenu: some View {
        Menu {
            ForEach(projects) { project in
                Button {
                    store.setSelectedProjectIdentifier(project.projectIdentifier)
                    store.connectionError = nil
                } label: {
                    Label(project.title, systemImage: "folder")
                }
            }
        } label: {
            controlChip {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(selectedProjectTitle ?? "Project")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppTypographyTokens.scaledSystem(8))
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var standaloneModelMenu: some View {
        if !store.availableModels.isEmpty {
            Menu {
                ForEach(store.availableModels) { model in
                    Button(model.name) {
                        store.setSelectedModelID(model.modelId)
                    }
                }
            } label: {
                controlChip {
                    HStack(spacing: 4) {
                        Text(store.selectedModelName ?? "Model")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AppTypographyTokens.scaledSystem(8))
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    private var trustModePicker: some View {
        Picker("", selection: Binding(
            get: { store.trustMode },
            set: { newMode in
                Task { @MainActor in
                    store.setTrustMode(newMode)
                }
            }
        )) {
            ForEach(CLITrustMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .font(AppTypographyTokens.captionSemibold)
        .controlSize(uiScale.controlSize)
        .frame(maxWidth: uiScale.chromeSize(180))
    }

    private func controlChip<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(AppTypographyTokens.captionSemibold)
            .foregroundStyle(palette.primaryTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.secondaryTextColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous)
                    .stroke(palette.borderColorValue.opacity(crispyvibesTheme.borderVisible ? 0.35 : 0), lineWidth: 0.6)
            )
    }

    // MARK: - Agent Icon

    @ViewBuilder
    private func agentIcon(for agentID: String) -> some View {
        if let nsImage = ACPAgentRegistry.agentIconImage(for: agentID, size: 16) {
            Image(nsImage: nsImage)
                .frame(width: uiScale.iconSize(16), height: uiScale.iconSize(16))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: "sparkles")
                .font(AppTypographyTokens.caption)
                .foregroundStyle(palette.accentColor)
        }
    }

    private func prepareDefaults() {
        discoveredAgents = ACPAgentRegistry.discoverInstalledAgents()
        if store.selectedProjectIdentifier == nil, projects.count == 1 {
            store.selectedProjectIdentifier = projects.first?.projectIdentifier
        }
        store.chatViewModel.connectAndSend = { [weak store] text in
            guard let store else { return }
            Task {
                await store.connect(projects: projects)
                await MainActor.run {
                    store.chatViewModel.composeText = text
                    store.chatViewModel.send()
                }
            }
        }
        store.ensureConnected(projects: projects)
    }
}

private struct ACPStandaloneHeaderSessionControls: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @Environment(\.crispyvibesUIScale) private var uiScale
    @ObservedObject var viewModel: ACPChatViewModel
    let displayMode: ACPDisplayMode

    var body: some View {
        if viewModel.isConnected {
            HStack(spacing: 8) {
                if viewModel.availableModes.count > 1, let currentModeID = viewModel.currentModeID {
                    Picker("", selection: Binding(
                        get: { viewModel.currentModeID ?? currentModeID },
                        set: { viewModel.setMode($0) }
                    )) {
                        ForEach(viewModel.availableModes) { mode in
                            Text(mode.name).tag(mode.modeId)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(AppTypographyTokens.captionSemibold)
                    .controlSize(uiScale.controlSize)
                    .frame(maxWidth: uiScale.chromeSize(displayMode.isCompact ? 120 : 140))
                }

                if displayMode.showsStandaloneModelPicker {
                    if viewModel.availableModels.count > 1, let currentModelID = viewModel.currentModelID {
                        Picker("", selection: Binding(
                            get: { viewModel.currentModelID ?? currentModelID },
                            set: { viewModel.setModel($0) }
                        )) {
                            ForEach(viewModel.availableModels) { model in
                                Text(model.name).tag(model.modelId)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(AppTypographyTokens.captionSemibold)
                        .controlSize(uiScale.controlSize)
                        .frame(maxWidth: uiScale.chromeSize(180))
                    } else if let model = viewModel.availableModels.first(where: { $0.modelId == viewModel.currentModelID }) {
                        Text(model.name)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(palette.secondaryTextColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: crispyvibesTheme.radius(6), style: .continuous))
                    }
                }
            }
        }
    }
}
