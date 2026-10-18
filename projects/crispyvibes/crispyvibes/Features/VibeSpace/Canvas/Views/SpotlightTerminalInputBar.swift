import AppKit
import SwiftUI

private struct SpotlightTerminalPastedImage: Identifiable {
    let id = UUID()
    let image: NSImage
    let escapedPath: String
}

struct SpotlightTerminalInputBar: View {
    @Environment(\.appThemePalette) private var palette
    @Environment(\.boardInlinePickerOverlayController) private var boardInlinePickerOverlayController
    @Environment(\.composeHistoryStore) private var composeHistoryStore
    @Environment(\.crispyvibesUIScale) private var uiScale
    let spotlight: TerminalSpotlightState
    let vibespaceProjects: [AnyProjectSession]
    let requestsInitialFocus: Bool
    let onActivate: () -> Void

    init(
        spotlight: TerminalSpotlightState,
        vibespaceProjects: [AnyProjectSession],
        requestsInitialFocus: Bool = true,
        onActivate: @escaping () -> Void = {}
    ) {
        self.spotlight = spotlight
        self.vibespaceProjects = vibespaceProjects
        self.requestsInitialFocus = requestsInitialFocus
        self.onActivate = onActivate
    }

    @AppStorage(AppPreferences.terminalComposeInlineTriggerKey)
    private var configuredInlineTrigger = AppPreferences.defaultTerminalComposeInlineTrigger
    @State private var inputText = ""
    @State private var pendingSelectionLocation: Int?
    @State private var isRephrasing = false
    @State private var drafts: [SpotlightComposeIdentity: String] = [:]
    @State private var imageDrafts: [SpotlightComposeIdentity: [SpotlightTerminalPastedImage]] = [:]
    @State private var pastedImages: [SpotlightTerminalPastedImage] = []
    @State private var focusTrigger = false
    @StateObject private var inlineTrigger = TerminalInlineTriggerController()
    @State private var historyNavigator: ComposeHistoryNavigator?

    private var session: TerminalSession? {
        switch spotlight.source {
        case let .persistent(terminalViewModel, tabID):
            return terminalViewModel.session(for: tabID)
        case let .transient(session):
            return session
        case .vibeCast, .vibeLanes, .todos, .acp, .filePreview, .file, .browserPreview, .browser:
            return nil
        }
    }

    var body: some View {
        if session != nil {
            // Fixed reserved space — compose bar floats as overlay, growing upward
            Color.clear
                .frame(height: uiScale.chromeSize(ComposeLayoutTokens.compactBarHeight + 20))
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        if !pastedImages.isEmpty {
                            pastedImageStrip
                        }
                        TerminalComposeInputView(
                            text: $inputText,
                            pendingSelectionLocation: $pendingSelectionLocation,
                            isRephrasing: isRephrasing,
                            requestFocus: focusTrigger,
                            canSendOverride: canSendInputPayload,
                    onSend: { sendInput() },
                    onRephrase: { rephrase() },
                    inlineOverlayActive: inlineTrigger.isPresented,
                    onInlineMoveUp: { _ = inlineTrigger.handleCommand(.moveUp) },
                    onInlineMoveDown: { _ = inlineTrigger.handleCommand(.moveDown) },
                    onInlineMoveRight: { _ = inlineTrigger.handleCommand(.moveRight) },
                    onInlineConfirm: { _ = inlineTrigger.handleCommand(.confirm) },
                    onInlineDismiss: dismissInlineTrigger,
                    onPasteImage: { image in appendPastedImage(image) },
                    onHistoryBack: {
                        guard let historyNavigator else { return }
                        let nav = historyNavigator.navigateBack(currentText: inputText)
                        if case let .replace(text) = nav {
                            historyNavigator.isApplyingNavigation = true
                            inputText = text
                        }
                    },
                    onHistoryForward: {
                        guard let historyNavigator else { return }
                        let nav = historyNavigator.navigateForward(currentText: inputText)
                        if case let .replace(text) = nav {
                            historyNavigator.isApplyingNavigation = true
                            inputText = text
                        }
                    }
                )
            }
            }
            .onAppear {
                if let composeHistoryStore {
                    historyNavigator = ComposeHistoryNavigator(store: composeHistoryStore)
                }
                historyNavigator?.attach(toStableKey: terminalIdentity?.historyKey)
                focusTrigger = requestsInitialFocus
                syncInlineTriggerConfiguration()
                inlineTrigger.reconcileBufferText(inputText)
                syncBoardInlinePickerOverlay()
            }
            .onChange(of: terminalIdentity) { oldID, newID in
                guard oldID != newID else { return }
                if let oldID {
                    drafts[oldID] = inputText
                    imageDrafts[oldID] = pastedImages
                }
                if let newID {
                    inputText = drafts[newID] ?? ""
                    pastedImages = imageDrafts[newID] ?? []
                } else {
                    inputText = ""
                    pastedImages = []
                }
                historyNavigator?.attach(toStableKey: newID?.historyKey)
                syncInlineTriggerConfiguration()
                inlineTrigger.reconcileBufferText(inputText)
                syncBoardInlinePickerOverlay()
                focusTrigger = false
                guard requestsInitialFocus, let expectedID = newID else { return }
                DispatchQueue.main.async {
                    guard requestsInitialFocus, terminalIdentity == expectedID else { return }
                    focusTrigger = true
                }
            }
            .onChange(of: requestsInitialFocus) { _, shouldFocus in
                focusTrigger = false
                guard shouldFocus, let expectedID = terminalIdentity else { return }
                DispatchQueue.main.async {
                    guard requestsInitialFocus, terminalIdentity == expectedID else { return }
                    focusTrigger = true
                }
            }
            .onChange(of: inputText) { _, _ in
                if historyNavigator?.isApplyingNavigation == true {
                    historyNavigator?.isApplyingNavigation = false
                } else {
                    historyNavigator?.resetOnUnrelatedEdit()
                }
                syncInlineTriggerBuffer()
            }
            .onChange(of: configuredInlineTrigger) { _, _ in
                syncInlineTriggerConfiguration()
                inlineTrigger.reconcileBufferText(inputText)
                syncBoardInlinePickerOverlay()
            }
            .onChange(of: spotlight.title) { _, _ in
                syncInlineTriggerConfiguration()
            }
            .onChange(of: spotlight.shortcutDefinitions.map { "\($0.id.uuidString):\($0.name):\($0.command)" }) { _, _ in
                syncInlineTriggerConfiguration()
            }
            .onChange(of: vibespaceProjectRootPaths) { _, _ in
                syncInlineTriggerConfiguration()
            }
            .onChange(of: currentSessionSearchDirectoryPath) { _, _ in
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
    }

    private var pastedImageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pastedImages) { pastedImage in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: pastedImage.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: uiScale.iconSize(52), height: uiScale.iconSize(52))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(palette.borderColorValue.opacity(0.35), lineWidth: 1)
                            )

                        Button {
                            pastedImages.removeAll { $0.id == pastedImage.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypographyTokens.caption)
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                    .help(AppStrings.Spotlight.pastedImage)
                }
            }
            .padding(.horizontal, ComposeLayoutTokens.contentHorizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .background(palette.canvasSecondaryBackgroundColor.opacity(ComposeLayoutTokens.backgroundOpacity))
    }

    private var terminalIdentity: SpotlightComposeIdentity? {
        spotlight.composeIdentity
    }

    private var inlinePathSearchRoots: [URL] {
        var orderedRoots: [URL] = []
        if let currentSessionDirectoryURL = currentSessionSearchDirectoryURL {
            orderedRoots.append(currentSessionDirectoryURL)
        }
        if let owningProjectRootURL = spotlight.owningProjectRootURL, owningProjectRootURL.isFileURL {
            orderedRoots.append(owningProjectRootURL)
        }
        orderedRoots.append(contentsOf: vibespaceProjects.compactMap { project in
            guard project.projectSession != nil else { return nil }
            let rootURL = project.rootURL.standardizedFileURL
            return rootURL.isFileURL ? rootURL : nil
        })
        if spotlight.workingDirectoryURL.isFileURL {
            orderedRoots.append(spotlight.workingDirectoryURL)
        }

        var seen = Set<String>()
        return orderedRoots.compactMap { rootURL in
            let normalized = rootURL.standardizedFileURL
            let path = normalized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return normalized
        }
    }

    private var vibespaceProjectRootPaths: [String] {
        inlinePathSearchRoots.map(\.path)
    }

    private var currentSessionSearchDirectoryPath: String? {
        currentSessionSearchDirectoryURL?.path
    }

    private var currentSessionSearchDirectoryURL: URL? {
        guard let directoryURL = session?.currentWorkingDirectory.standardizedFileURL,
              directoryURL.isFileURL else {
            return nil
        }
        return directoryURL
    }

    private var parsedInlineTrigger: SpotlightComposeInlineTrigger? {
        SpotlightComposeInlineTrigger.parse(
            inputText,
            triggerToken: AppPreferences.normalizedTerminalComposeInlineTrigger(configuredInlineTrigger)
        )
    }

    private var inputPayloadText: String {
        let typedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagePaths = pastedImages.map(\.escapedPath)
        guard !typedText.isEmpty else {
            return imagePaths.joined(separator: " ")
        }
        guard !imagePaths.isEmpty else {
            return typedText
        }
        return ([typedText] + imagePaths).joined(separator: " ")
    }

    private var canSendInputPayload: Bool {
        !inputPayloadText.isEmpty
    }

    private func sendInput() {
        let text = inputPayloadText
        guard !text.isEmpty, let expectedIdentity = terminalIdentity else { return }
        onActivate()
        guard terminalIdentity == expectedIdentity, let targetSession = session else { return }
        targetSession.sendRawTextWithEnter(text)
        historyNavigator?.append(text)
        inputText = ""
        pastedImages = []
        if let terminalIdentity {
            drafts[terminalIdentity] = ""
            imageDrafts[terminalIdentity] = []
        }
        syncInlineTriggerBuffer()
    }

    private func appendPastedImage(_ image: NSImage) {
        guard let escapedPath = savePastedImage(image) else { return }
        pastedImages.append(SpotlightTerminalPastedImage(image: image, escapedPath: escapedPath))
        requestComposeFocus()
    }

    private func savePastedImage(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "crispyvibes-terminal-paste",
            isDirectory: true
        )
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "clipboard-\(timestamp)-\(UUID().uuidString.prefix(8)).png"
        let fileURL = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: fileURL, options: .atomic)
            return ShellEscaping.singleQuote(fileURL.path)
        } catch {
            return nil
        }
    }

    private func rephrase() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRephrasing else { return }
        isRephrasing = true
        Task.detached {
            let result = VibeCastRephraseService.rephrase(text)
            await MainActor.run {
                if let result { inputText = result }
                isRephrasing = false
            }
        }
    }

    private func dismissInlineTrigger() {
        _ = inlineTrigger.handleCommand(.dismiss)
        requestComposeFocus()
        syncBoardInlinePickerOverlay()
    }

    private func requestComposeFocus() {
        let expectedIdentity = terminalIdentity
        onActivate()
        focusTrigger = false
        guard requestsInitialFocus, expectedIdentity != nil else { return }
        DispatchQueue.main.async {
            guard requestsInitialFocus, terminalIdentity == expectedIdentity else { return }
            focusTrigger = true
        }
    }

    private func replaceInlineTrigger(with replacement: String) {
        guard let trigger = parsedInlineTrigger else {
            return
        }
        let newText = trigger.prefixText + replacement
        inputText = newText
        pendingSelectionLocation = (newText as NSString).length
    }

    private func syncInlineTriggerConfiguration() {
        let sessionRef = session
        inlineTrigger.configure(
            triggerToken: configuredInlineTrigger,
            searchRoots: inlinePathSearchRoots,
            shortcuts: spotlight.shortcutDefinitions,
            terminalTitle: spotlight.title,
            currentDirectoryProvider: { [weak sessionRef] in
                sessionRef?.currentWorkingDirectory ?? spotlight.workingDirectoryURL
            },
            insertionHandler: { replacement in
                replaceInlineTrigger(with: replacement)
            },
            focusHandler: requestComposeFocus,
            manageShortcutsHandler: spotlight.onManageShortcutsRequested
        )
        syncBoardInlinePickerOverlay()
    }

    private func syncInlineTriggerBuffer() {
        inlineTrigger.syncBufferText(inputText)
        syncBoardInlinePickerOverlay()
    }

    private var boardInlinePickerOverlayOwnerID: String {
        "terminal-spotlight:\(terminalIdentity?.historyKey ?? spotlight.id.uuidString)"
    }

    private var manageShortcutsAction: (() -> Void)? {
        guard spotlight.onManageShortcutsRequested != nil else { return nil }
        let inlineTriggerRef = inlineTrigger
        return { [weak inlineTriggerRef] in
            inlineTriggerRef?.runManageShortcutsAction()
        }
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
                onAction: manageShortcutsAction,
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
