import SwiftUI

struct ACPChatView: View {
    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesUIScale) private var uiScale
    @Environment(\.boardInlinePickerOverlayController) private var boardInlinePickerOverlayController
    @Environment(\.composeHistoryStore) private var composeHistoryStore
    @AppStorage(AppPreferences.terminalComposeInlineTriggerKey)
    private var configuredInlineTrigger = AppPreferences.defaultTerminalComposeInlineTrigger
    @ObservedObject var viewModel: ACPChatViewModel
    @StateObject private var inlineTrigger = TerminalInlineTriggerController()
    @State private var pendingSelectionLocation: Int?
    @State private var diffSpotlightRows: [ACPDiffSummaryRow]?
    @State private var diffSpotlightLabel = ""
    @State private var showDiffSpotlight = false
    @State private var historyNavigator: ComposeHistoryNavigator?
    let title: String
    let subtitle: String?
    var showsHeader: Bool = true
    let showsHeaderSessionControls: Bool
    var showsDebugSessionIdentity: Bool = false
    var displayMode: ACPDisplayMode = .detail
    var historyKey: UUID? = nil
    var isExternallyManaged: Bool = false
    let isConnecting: Bool
    let connectionError: String?
    let onReconnect: (() -> Void)?
    let onLinkTargetActivated: ((URL) -> Void)?
    let onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
            }
            // Debug: session identity info
            #if DEBUG
            if showsDebugSessionIdentity, let ctx = viewModel.persistenceContext {
                HStack(spacing: 4) {
                    Text("thread:\(ctx.threadID.prefix(8))")
                    if let session = viewModel.activeSession, let pid = session.providerSessionID {
                        Text("\(session.transportKind):\(pid.prefix(8))")
                    }
                }
                .font(.system(size: uiScale.textSize(9), design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
            #endif
            if showsHeader || showsDebugSessionIdentity {
                Divider()
            }
            if viewModel.isConnected || !viewModel.timeline.isEmpty {
                // Provider status banner (#17) — shows connection errors with retry
                if let connectionError, !viewModel.isConnected {
                    ProviderStatusBanner(
                        error: connectionError,
                        onRetry: onReconnect
                    )
                }
                if viewModel.timeline.isEmpty {
                    connectedEmptyTimelineState
                } else {
                    ACPTimelineView(
                        timeline: viewModel.timeline,
                        agentName: viewModel.agentName,
                        agentID: viewModel.agentID,
                        onResend: viewModel.resend(from:),
                        displayMode: displayMode,
                        onLinkTargetActivated: onLinkTargetActivated,
                        onFileSystemTargetActivated: onFileSystemTargetActivated,
                        vibespaceRoot: viewModel.activeSession?.projectPath.path,
                        onViewDiff: { rows, label in
                            diffSpotlightRows = rows
                            diffSpotlightLabel = label
                            showDiffSpotlight = true
                        }
                    )
                }
                permissionCardOverlay
                userInputRequestCard
                Divider()
                composeBar
            } else {
                disconnectedState
                Divider()
                composeBar
            }
        }
        .sheet(isPresented: $showDiffSpotlight) {
            if let rows = diffSpotlightRows, !rows.isEmpty {
                ACPDiffSpotlightPanel(
                    rows: rows,
                    turnLabel: diffSpotlightLabel,
                    vibespaceRoot: viewModel.activeSession?.projectPath.path,
                    onDismiss: { showDiffSpotlight = false }
                )
                .frame(minWidth: 700, minHeight: 500)
            }
        }
        .onAppear {
            syncInlineTriggerConfiguration()
            syncBoardInlinePickerOverlay()
        }
        .onChange(of: viewModel.isConnected) { _, _ in
            syncInlineTriggerConfiguration()
        }
        .onChange(of: viewModel.activeSession?.projectPath.path) { _, _ in
            syncInlineTriggerConfiguration()
        }
        .onChange(of: configuredInlineTrigger) { _, _ in
            syncInlineTriggerConfiguration()
        }
        .onDisappear {
            clearBoardInlinePickerOverlay()
            inlineTrigger.shutdown()
        }
        .onReceive(inlineTrigger.objectWillChange) { _ in
            guard boardInlinePickerOverlayController != nil else { return }
            DispatchQueue.main.async {
                syncBoardInlinePickerOverlay()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Connection status dot
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            // Agent name
            Text(title)
                .font(AppTypographyTokens.subheadlineSemibold)
                .lineLimit(1)

            // Project name
            if let subtitle {
                Text("·")
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                Text(subtitle)
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsHeaderSessionControls, viewModel.isConnected {
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
                    .frame(maxWidth: uiScale.chromeSize(140))
                }

                // Model picker (if agent supports multiple models)
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
                        .foregroundStyle(appThemePalette.secondaryTextColor)
                        .lineLimit(1)
                }
            }

            if isConnecting {
                ProgressView()
                    .controlSize(uiScale.controlSize)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectedEmptyTimelineState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(uiScale.controlSize)
                Text(AppStrings.ACP.connectedEmptyTimelineTitle)
                    .font(AppTypographyTokens.headline)
                Text(AppStrings.ACP.connectedEmptyTimelineDescription)
                    .font(AppTypographyTokens.callout)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disconnectedState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(appThemePalette.accentColor.opacity(0.1))
                        .frame(width: uiScale.iconSize(64), height: uiScale.iconSize(64))
                    Image(systemName: "sparkles")
                        .font(AppTypographyTokens.scaledIcon(28))
                        .foregroundStyle(appThemePalette.accentColor)
                }

                // Title + description
                VStack(spacing: 8) {
                    if isExternallyManaged {
                        Text(AppStrings.ACP.managedSessionPendingTitle)
                            .font(AppTypographyTokens.headline)
                        Text(AppStrings.ACP.managedSessionPendingDescription)
                            .font(AppTypographyTokens.callout)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                            .multilineTextAlignment(.center)
                    } else if subtitle == nil {
                        Text("No Project Selected")
                            .font(AppTypographyTokens.headline)
                        Text("Select a project above to start a conversation with an AI agent.")
                            .font(AppTypographyTokens.callout)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                            .multilineTextAlignment(.center)
                    } else if title == AppStrings.ACP.agentContentTitle {
                        Text("No Agent Configured")
                            .font(AppTypographyTokens.headline)
                        Text("Set a default agent in Settings → ACP, or select one from the picker above.")
                            .font(AppTypographyTokens.callout)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Ready to Connect")
                            .font(AppTypographyTokens.headline)
                        Text("Start a conversation with \(title) on this project.")
                            .font(AppTypographyTokens.callout)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 360)

                // Error
                if let connectionError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(connectionError)
                            .font(AppTypographyTokens.caption)
                            .foregroundStyle(appThemePalette.secondaryTextColor)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: 400)
                }

                // Connect button
                if subtitle != nil, title != AppStrings.ACP.agentContentTitle {
                    if let onReconnect {
                        Button {
                            onReconnect()
                        } label: {
                            HStack(spacing: 6) {
                                if isConnecting {
                                    ProgressView().controlSize(.small)
                                }
                                Text(isConnecting ? "Connecting…" : "Connect")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(isConnecting)
                    }
                }

                // Quick tips
                if subtitle != nil, title != AppStrings.ACP.agentContentTitle, connectionError == nil, !isConnecting {
                    VStack(alignment: .leading, spacing: 8) {
                        quickTip(icon: "text.bubble", text: "Ask questions about your code")
                        quickTip(icon: "hammer", text: "Generate, edit, and refactor files")
                        quickTip(icon: "terminal", text: "Run commands in the terminal")
                        quickTip(icon: "shield.lefthalf.filled", text: "Review changes before they're applied")
                    }
                    .padding(.top, 8)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func quickTip(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppTypographyTokens.scaledIcon(12))
                .foregroundStyle(appThemePalette.accentColor)
                .frame(width: uiScale.iconSize(20))
            Text(text)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(appThemePalette.secondaryTextColor)
        }
    }

    @ViewBuilder
    private var permissionCardOverlay: some View {
        if let handler = viewModel.permissionHandler,
           let request = handler.pendingRequest {
            ACPPermissionCard(request: request) { outcome in
                handler.resolve(outcome)
            } onAcceptForSession: {
                handler.allowAll = true
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Structured question card from the agent (#4).
    @ViewBuilder
    private var userInputRequestCard: some View {
        if let request = viewModel.pendingUserInputRequest {
            VStack(alignment: .leading, spacing: 10) {
                Text(request.question)
                    .font(AppTypographyTokens.calloutSemibold)
                    .foregroundStyle(appThemePalette.primaryTextColor)
                ForEach(request.options) { option in
                    Button {
                        viewModel.respondToUserInput(requestId: request.id, answer: option.label)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(AppTypographyTokens.calloutSemibold)
                            if let desc = option.description {
                                Text(desc)
                                    .font(AppTypographyTokens.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(appThemePalette.accentColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if request.allowCustom {
                    Text("Or type a custom answer below")
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(appThemePalette.secondaryTextColor.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var composeBar: some View {
        VStack(spacing: 0) {
            if !viewModel.filteredCommands.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.filteredCommands) { command in
                        Button {
                            viewModel.composeText = command.name + " "
                        } label: {
                            HStack(spacing: 8) {
                                Text(command.name)
                                    .font(AppTypographyTokens.captionSemibold)
                                Text(command.description)
                                    .font(AppTypographyTokens.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                Divider()
            }

            if viewModel.isStreaming {
                HStack(spacing: 10) {
                    Text("Thinking…")
                        .font(AppTypographyTokens.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        viewModel.cancelPrompt()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, ComposeLayoutTokens.contentHorizontalPadding)
                .padding(.vertical, 12)
            } else {
                // Context window meter (#6)
                if let usage = viewModel.contextWindowUsage, usage.usedTokens > 0 {
                    ContextWindowMeterView(usage: usage)
                }
                // Image attachments strip (#5)
                if !viewModel.composeImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(viewModel.composeImages.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: uiScale.iconSize(56), height: uiScale.iconSize(56))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    Button {
                                        viewModel.composeImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(AppTypographyTokens.caption)
                                            .foregroundStyle(.white)
                                            .shadow(radius: 1)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .padding(.horizontal, ComposeLayoutTokens.contentHorizontalPadding)
                        .padding(.top, 4)
                    }
                }
                TerminalComposeInputView(
                    text: $viewModel.composeText,
                    pendingSelectionLocation: $pendingSelectionLocation,
                    initialHeight: displayMode.composeInitialHeight,
                    isRephrasing: false,
                    showBroadcast: false,
                    requestFocus: !viewModel.isStreaming,
                    showsResizeHandle: !displayMode.isCompact,
                    showsBackground: false,
                    verticalPadding: ComposeLayoutTokens.contentVerticalPadding,
                    onSend: {
                        historyNavigator?.append(viewModel.composeText.trimmingCharacters(in: .whitespacesAndNewlines))
                        DispatchQueue.main.async {
                            viewModel.send()
                        }
                    },
                    onRephrase: {},
                    inlineOverlayActive: inlineTrigger.isPresented,
                    onInlineMoveUp: { _ = inlineTrigger.handleCommand(.moveUp) },
                    onInlineMoveDown: { _ = inlineTrigger.handleCommand(.moveDown) },
                    onInlineMoveRight: { _ = inlineTrigger.handleCommand(.moveRight) },
                    onInlineConfirm: { _ = inlineTrigger.handleCommand(.confirm) },
                    onInlineDismiss: { _ = inlineTrigger.handleCommand(.dismiss) },
                    onPasteImage: { image in viewModel.composeImages.append(image) },
                    onHistoryBack: {
                        guard let historyNavigator else { return }
                        let nav = historyNavigator.navigateBack(currentText: viewModel.composeText)
                        if case let .replace(text) = nav {
                            historyNavigator.isApplyingNavigation = true
                            viewModel.composeText = text
                        }
                    },
                    onHistoryForward: {
                        guard let historyNavigator else { return }
                        let nav = historyNavigator.navigateForward(currentText: viewModel.composeText)
                        if case let .replace(text) = nav {
                            historyNavigator.isApplyingNavigation = true
                            viewModel.composeText = text
                        }
                    }
                )
                .onAppear {
                    if let composeHistoryStore {
                        historyNavigator = ComposeHistoryNavigator(store: composeHistoryStore)
                    }
                    historyNavigator?.attach(to: historyKey)
                }
                .onChange(of: viewModel.composeText) { _, newValue in
                    if historyNavigator?.isApplyingNavigation == true {
                        historyNavigator?.isApplyingNavigation = false
                    } else {
                        historyNavigator?.resetOnUnrelatedEdit()
                    }
                    inlineTrigger.syncBufferText(newValue)
                    syncBoardInlinePickerOverlay()
                }
            }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        DispatchQueue.main.async { viewModel.composeImages.append(image) }
                    }
                }
            }
            return true
        }
    }

    private var boardInlinePickerOverlayOwnerID: String {
        "acp-chat:\(ObjectIdentifier(viewModel).hashValue)"
    }

    private func syncInlineTriggerConfiguration() {
        guard viewModel.isConnected, let path = viewModel.activeSession?.projectPath else {
            _ = inlineTrigger.handleCommand(.dismiss)
            syncBoardInlinePickerOverlay()
            return
        }

        inlineTrigger.configure(
            triggerToken: configuredInlineTrigger,
            searchRoots: [path],
            shortcuts: [],
            terminalTitle: title,
            currentDirectoryProvider: { [weak viewModel] in
                viewModel?.activeSession?.projectPath ?? path
            },
            insertionHandler: { [weak viewModel] text in
                guard let viewModel else { return }
                let newText = replaceInlineTrigger(
                    in: viewModel.composeText,
                    replacement: text
                )
                viewModel.composeText = newText
                pendingSelectionLocation = (newText as NSString).length
            },
            focusHandler: nil,
            manageShortcutsHandler: nil
        )
        inlineTrigger.reconcileBufferText(viewModel.composeText)
        syncBoardInlinePickerOverlay()
    }

    private func replaceInlineTrigger(in text: String, replacement: String) -> String {
        let triggerToken = AppPreferences.normalizedTerminalComposeInlineTrigger(configuredInlineTrigger)
        guard let trigger = SpotlightComposeInlineTrigger.parse(text, triggerToken: triggerToken) else {
            return text
        }
        return trigger.prefixText + replacement
    }

    private func syncBoardInlinePickerOverlay() {
        guard let boardInlinePickerOverlayController else { return }
        guard inlineTrigger.isPresented else {
            boardInlinePickerOverlayController.clear(ownerID: boardInlinePickerOverlayOwnerID)
            return
        }
        let inlineTriggerRef = inlineTrigger

        boardInlinePickerOverlayController.update(
            ownerID: boardInlinePickerOverlayOwnerID,
            presentation: BoardInlinePickerOverlayPresentation(
                title: AppStrings.Terminal.ComposeTriggers.pickerTitle,
                queryText: inlineTrigger.queryText,
                featuredAction: inlineTrigger.featuredPanelAction,
                rows: inlineTrigger.panelRows,
                statusText: inlineTrigger.footerText,
                hintText: inlineTrigger.hintText,
                actionTitle: inlineTrigger.manageShortcutsActionTitle,
                onAction: nil,
                onFeaturedAction: { [weak inlineTriggerRef] in
                    inlineTriggerRef?.applyFeaturedAction()
                },
                onDismiss: { [weak inlineTriggerRef] in
                    _ = inlineTriggerRef?.handleCommand(.dismiss)
                },
                onSelect: { [weak inlineTriggerRef] rowID in
                    inlineTriggerRef?.applyResult(id: rowID)
                }
            )
        )
    }

    private func clearBoardInlinePickerOverlay() {
        boardInlinePickerOverlayController?.clear(ownerID: boardInlinePickerOverlayOwnerID)
    }
}

/// Provider status banner showing connection errors with retry (#17).
private struct ProviderStatusBanner: View {
    @Environment(\.appThemePalette) private var palette
    let error: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppTypographyTokens.caption)
                .foregroundStyle(.orange)
            Text(error)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(2)
            Spacer()
            if let onRetry {
                Button("Retry") { onRetry() }
                    .font(AppTypographyTokens.captionSemibold)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

/// Thin progress bar showing context window token usage (#6).
private struct ContextWindowMeterView: View {
    let usage: ACPContextWindowUsage
    @Environment(\.appThemePalette) private var palette
    @Environment(\.crispyvibesUIScale) private var uiScale

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.secondaryTextColor.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: geo.size.width * CGFloat(min(usage.fraction, 1.0)))
                }
            }
            .frame(height: 4)

            Text(label)
                .font(.system(size: uiScale.textSize(9), weight: .medium).monospacedDigit())
                .foregroundStyle(palette.secondaryTextColor.opacity(0.6))
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var label: String {
        let used = formatTokenCount(usage.usedTokens)
        if let max = usage.maxTokens {
            return "\(used) / \(formatTokenCount(max))"
        }
        return "\(used) tokens"
    }

    private var fillColor: Color {
        if usage.fraction > 0.9 { return .red }
        if usage.fraction > 0.7 { return .orange }
        return palette.accentColor
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
