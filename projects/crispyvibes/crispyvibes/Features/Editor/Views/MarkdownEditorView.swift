import PDFKit
import SwiftUI
import WebKit

struct MarkdownEditorView: View {
    enum HeaderLayout: Equatable {
        case floating
        case embedded
    }

    @Environment(\.appThemePalette) private var appThemePalette
    @Environment(\.crispyvibesTheme) private var crispyvibesTheme
    @ObservedObject var viewModel: MarkdownViewModel
    var showsTopBar: Bool = true
    var headerLayout: HeaderLayout = .floating
    var embeddedHeaderCornerRadii: RectangleCornerRadii? = nil
    var embeddedDropBridge: ContentViewerEmbeddedDropBridge? = nil
    @State var isFindBarVisible = false
    @State var isReplaceModeVisible = false
    @State var findQuery = ""
    @State var replaceQuery = ""
    @State var findMatchCount = 0
    @State var selectedMatchIndex: Int?
    @State var findStatusMessage = ""
    @State var cachedFindSource = ""
    @State var cachedFindQuery = ""
    @State var cachedFindRanges: [Range<String.Index>] = []
    @State private var commandRequest: EditorCommandRequest?
    @FocusState var isFindFieldFocused: Bool

    /// F049: per-editor-instance bridge to the underlying `NSTextView`.
    /// Owning the bridge here means each MarkdownEditorView mount (regular
    /// content viewer, split pane, file spotlight, detached window, etc.)
    /// has its own bridge tied to its own NSTextView — no cross-surface
    /// contention over a shared bridge.
    ///
    /// Uses `@State` (not `@StateObject`) so SwiftUI preserves the same
    /// bridge instance across re-renders WITHOUT subscribing to its
    /// `@Published` changes. The bridge increments `geometryTick` on every
    /// scroll event; subscribing here would re-render the whole editor on
    /// every scroll. Only the inner `CommentsCodeEditorOverlay` needs to
    /// observe the bridge — and it already does via `@ObservedObject`.
    @State private var commentBridge = CodeEditorCommentBridge()

    /// F049: comment chrome — these env values, when all non-nil, drive the
    /// overlay (gutter dots + content highlights) and the floating "Add
    /// Comment" glass button on top of the editor. Set by the surrounding
    /// view (content viewer, spotlight, etc.).
    @Environment(\.vibespaceCommentStoreEnvironment) private var commentStore: VibeSpaceCommentStore?
    @Environment(\.commentsPanelEnvironment) private var commentsPanel: CommentsPanelStore?
    @Environment(\.commentsFilePathEnvironment) private var commentsFilePath: String?

    private var windowBackgroundColor: Color {
        appThemePalette.windowBackgroundColor
    }

    private var headerBackgroundColor: Color {
        appThemePalette.canvasSecondaryBackgroundColor
    }

    private var activeFileName: String {
        guard let fileURL = viewModel.fileURL else { return "No File Selected" }
        let fileName = fileURL.lastPathComponent
        return fileName.isEmpty ? fileURL.path : fileName
    }

    private var activeFileIconName: String {
        switch viewModel.documentType {
        case .none:
            return "doc"
        case .markdown, .html:
            return "doc.richtext"
        case .plainText, .python, .json, .r:
            return "doc.text"
        case .image:
            return "photo"
        case .pdf:
            return "doc.text.image"
        case .office:
            let ext = viewModel.fileURL?.pathExtension.lowercased() ?? ""
            if ["doc", "docx"].contains(ext) { return "doc.text.fill" }
            if ["ppt", "pptx"].contains(ext) { return "rectangle.stack.fill" }
            if ["xls", "xlsx"].contains(ext) { return "tablecells.fill" }
            return "doc.text.fill"
        case .gitDiff:
            return "arrow.left.arrow.right"
        case .unsupported:
            return "doc.badge.questionmark"
        }
    }

    private var resolvedActiveEditorTabID: String? {
        if let activeEditorTabID = viewModel.activeEditorTabID {
            return activeEditorTabID
        }
        return viewModel.currentDocumentID
    }

    private func iconName(for tab: MarkdownViewModel.EditorTab) -> String {
        let fileExtension = tab.fileURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff"].contains(fileExtension) {
            return "photo"
        }
        if fileExtension == "pdf" {
            return "doc.text.image"
        }
        if ["md", "markdown", "html", "htm"].contains(fileExtension) {
            return "doc.richtext"
        }
        if ["doc", "docx"].contains(fileExtension) {
            return "doc.text.fill"
        }
        if ["ppt", "pptx"].contains(fileExtension) {
            return "rectangle.stack.fill"
        }
        if ["xls", "xlsx"].contains(fileExtension) {
            return "tablecells.fill"
        }
        return "doc.text"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsTopBar {
                topBar
                Divider()
            }
            if isFindBarVisible {
                findReplaceBar
                Divider()
            }
            if supportsMarkupToolbar {
                markupToolbar
                Divider()
            }
            commentDecoratedContent
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveCurrentMarkdown)) { _ in
            viewModel.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFindInDocument)) { _ in
            activateFind(replaceMode: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showReplaceInDocument)) { _ in
            activateFind(replaceMode: true)
        }
        .onChange(of: findQuery) { _, _ in
            invalidateFindCache()
            refreshFindState(resetSelection: true)
        }
        .onChange(of: viewModel.displayContent) { _, _ in
            invalidateFindCache()
            if isFindBarVisible {
                refreshFindState(resetSelection: false)
            }
        }
        .onChange(of: viewModel.fileURL) { _, _ in
            resetFindUI()
            commandRequest = nil
        }
        .alert(
            "Document Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.errorMessage = nil }
                }
            )
        ) {
            Button(AppStrings.Common.ok, role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var topBarContent: some View {
        HStack(spacing: 10) {
            if viewModel.editorTabs.isEmpty {
                Label {
                    Text(activeFileName)
                        .font(AppTypographyTokens.subheadlineSemibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: activeFileIconName)
                        .font(AppTypographyTokens.captionSemibold)
                }
                .foregroundStyle(appThemePalette.primaryTextColor)
                .layoutPriority(1)
                .accessibilityIdentifier("editor.title")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(viewModel.editorTabs.enumerated()), id: \.element.id) { index, tab in
                            editorTabView(tab)

                            if index < viewModel.editorTabs.count - 1 {
                                Rectangle()
                                    .fill(appThemePalette.borderColorValue.opacity(0.48))
                                    .frame(width: 1, height: 20)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("editor.tab.strip")
            }

            Spacer(minLength: 6)

            if shouldShowUnsavedIndicator {
                Text(AppStrings.Editor.unsaved)
                    .font(AppTypographyTokens.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(appThemePalette.warningColor.opacity(0.22))
                    .clipShape(Capsule())
            }

            if viewModel.activeEditorTabID == nil, viewModel.fileURL != nil {
                Text(AppStrings.Common.preview)
                    .font(AppTypographyTokens.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(appThemePalette.selectionBackgroundColor.opacity(0.22))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("editor.preview.badge")
            }
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if headerLayout == .embedded {
            let embeddedBar = topBarContent
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(headerBackgroundColor)

            if let embeddedHeaderCornerRadii {
                embeddedBar
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: embeddedHeaderCornerRadii,
                            style: .continuous
                        )
                    )
            } else {
                embeddedBar
            }
        } else {
            topBarContent
                .padding(.horizontal, viewModel.editorTabs.isEmpty ? 8 : 6)
                .padding(.vertical, viewModel.editorTabs.isEmpty ? 6 : 2)
                .background(
                    RoundedRectangle(cornerRadius: crispyvibesTheme.radius(8), style: .continuous)
                        .fill(headerBackgroundColor)
                )
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
    }

    private func editorTabView(_ tab: MarkdownViewModel.EditorTab) -> some View {
        let isActive = resolvedActiveEditorTabID == tab.id
        return HStack(spacing: 8) {
            Button {
                viewModel.activateEditorTab(withID: tab.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: tab))
                        .font(AppTypographyTokens.captionSemibold)
                        .foregroundStyle(
                            isActive
                                ? appThemePalette.primaryTextColor
                                : appThemePalette.secondaryTextColor
                        )

                    Text(tab.title)
                        .lineLimit(1)
                        .foregroundStyle(
                            isActive
                                ? appThemePalette.primaryTextColor
                                : appThemePalette.secondaryTextColor
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.tab.select.\(tab.id)")

            if isActive {
                CrispyVibesIconButton(systemName: "xmark", size: 12, padding: 4, color: appThemePalette.primaryTextColor, accessibilityLabel: "Close \(tab.title)") {
                    viewModel.closeEditorTab(withID: tab.id)
                }
                .accessibilityIdentifier("editor.tab.close.\(tab.id)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            ZStack(alignment: .bottom) {
                (isActive
                    ? appThemePalette.selectionBackgroundColor.opacity(0.22)
                    : appThemePalette.canvasSecondaryBackgroundColor.opacity(0.18))

                Rectangle()
                    .fill(isActive ? appThemePalette.selectionBackgroundColor.opacity(0.9) : Color.clear)
                    .frame(height: 2)
            }
        )
        .contextMenu {
            Button(AppStrings.Common.close) {
                viewModel.closeEditorTab(withID: tab.id)
            }
        }
        .accessibilityIdentifier("editor.tab.\(tab.id)")
        .accessibilityLabel(tab.title)
    }

    private var findReplaceBar: some View {
        HStack(spacing: 8) {
            TextField(AppStrings.Editor.find, text: $findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 260)
                .focused($isFindFieldFocused)
                .onSubmit(findNext)
                .accessibilityIdentifier("editor.find.query")

            Button(AppStrings.Common.next) {
                findNext()
            }
            .disabled(findQuery.isEmpty || findMatchCount == 0)

            if isReplaceModeVisible {
                TextField(AppStrings.Editor.replace, text: $replaceQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: 260)
                    .accessibilityIdentifier("editor.find.replace")

                Button(AppStrings.Editor.replaceNext) {
                    replaceNext()
                }
                .disabled(findQuery.isEmpty || findMatchCount == 0)

                Button(AppStrings.Editor.replaceAll) {
                    replaceAll()
                }
                .disabled(findQuery.isEmpty || findMatchCount == 0)
            }

            Spacer(minLength: 8)

            Text(findStatusText)
                .font(AppTypographyTokens.caption)
                .foregroundStyle(appThemePalette.secondaryTextColor)
                .lineLimit(1)

            Button(AppStrings.Common.done) {
                resetFindUI()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(windowBackgroundColor.opacity(0.92))
    }

    /// F049: wraps the underlying editor `content` with the comments
    /// overlay (gutter + highlights), floating toggle button, and the
    /// per-editor `codeEditorCommentBridge` env value. Pure no-op when no
    /// comment env is set.
    @ViewBuilder
    private var commentDecoratedContent: some View {
        let path = viewModel.fileURL?.standardizedFileURL.path ?? commentsFilePath
        let isAvailable = (commentStore != nil) && (commentsPanel != nil) && (path != nil)
        ZStack(alignment: .topLeading) {
            content
                .environment(\.codeEditorCommentBridge, commentBridge)
                .environment(\.commentsFilePathEnvironment, path)

            if isAvailable, let store = commentStore, let panel = commentsPanel, let path {
                CommentsCodeEditorOverlay(
                    bridge: commentBridge,
                    commentStore: store,
                    panel: panel,
                    filePath: path
                )
                .allowsHitTesting(panel.isOpen)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isAvailable, let panel = commentsPanel, let path {
                CommentsFloatingButton(
                    panel: panel,
                    activeCount: commentStore?.activeCount(forFile: path) ?? 0,
                    isAvailable: true
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commentsNavigateToThread)) { note in
            handleCommentsNavigate(note)
        }
        .onChange(of: commentsPanel?.selectedThreadID) { _, newID in
            // F049-R06 bidirectional linking: panel-selection → editor-scroll.
            // The bridge owns the lookup + scroll; this view only forwards.
            guard let newID, let store = commentStore, let path else { return }
            commentBridge.scrollToThread(id: newID, in: store, filePath: path)
        }
        .task(id: commentRefreshTaskID) {
            // Auto-load this file's comments on first appear so highlights
            // show immediately without requiring the panel to be opened.
            guard let store = commentStore, let path else { return }
            guard let vsID = store.currentVibeSpaceID() else { return }
            await store.refreshFile(vibespaceID: vsID, filePath: path)
        }
    }

    private var commentRefreshTaskID: String {
        viewModel.fileURL?.standardizedFileURL.path ?? "(none)"
    }

    /// Handle a cross-window thread-navigation notification by routing it
    /// to the bridge once we've confirmed the file path matches this view.
    private func handleCommentsNavigate(_ note: Notification) {
        guard let info = note.userInfo as? [String: String],
              let path = info["filePath"],
              let threadID = info["threadID"] else { return }
        let myPath = viewModel.fileURL?.standardizedFileURL.path ?? commentsFilePath
        guard path == myPath, let store = commentStore else { return }
        commentsPanel?.reveal(threadID: threadID)
        commentBridge.scrollToThread(id: threadID, in: store, filePath: path)
    }

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.unsupportedFileMessage {            ContentUnavailableView(
                "Unsupported File Type",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.fileURL == nil {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc.text",
                description: Text(
                    "Choose a file from the explorer to preview or edit it here.\n\nMarkdown stays fast in context with direct preview editing, so you can work across projects without losing your place."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            if let pluginView = EditorPluginRegistry.render(
                for: viewModel.documentType,
                context: EditorPluginContext(
                    viewModel: viewModel,
                    commandRequest: $commandRequest,
                    embeddedDropBridge: embeddedDropBridge
                )
            ) {
                pluginView
            } else {
                unsupportedState
            }
        }
    }

    private var findStatusText: String {
        if !findStatusMessage.isEmpty {
            return findStatusMessage
        }
        guard !findQuery.isEmpty else { return "" }
        guard findMatchCount > 0 else { return "No matches" }
        if let selectedMatchIndex {
            return "\(selectedMatchIndex + 1) of \(findMatchCount)"
        }
        return "\(findMatchCount) matches"
    }

    private var unsupportedState: some View {
        ContentUnavailableView(
            "Preview Unavailable",
            systemImage: "eye.slash",
            description: Text(AppStrings.Editor.cannotPreview)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var supportsMarkupToolbar: Bool {
        viewModel.supportsMarkupViewModeToggle
    }

    private var shouldShowUnsavedIndicator: Bool {
        if viewModel.documentType == .image {
            return viewModel.hasUnsavedImageEdits
        }
        return viewModel.canEditCurrentDocument && viewModel.hasUnsavedTextChanges
    }

    private var markupToolbar: some View {
        HStack(spacing: 10) {
            if viewModel.currentMarkupViewMode == .rich {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        formattingButton(AppStrings.Editor.bold, systemImage: "bold", command: .bold)
                        formattingButton(AppStrings.Editor.italic, systemImage: "italic", command: .italic)
                        Divider().frame(height: 18)
                        formattingButton(AppStrings.Editor.h1, systemImage: "textformat.size.larger", command: .heading1)
                        formattingButton(AppStrings.Editor.h2, systemImage: "textformat.size", command: .heading2)
                        Divider().frame(height: 18)
                        formattingButton(AppStrings.Editor.bulletList, systemImage: "list.bullet", command: .unorderedList)
                        formattingButton(AppStrings.Editor.numberedList, systemImage: "list.number", command: .orderedList)
                        formattingButton(AppStrings.Editor.quote, systemImage: "text.quote", command: .blockQuote)
                        formattingButton(AppStrings.Editor.codeBlock, systemImage: "curlybraces.square", command: .codeBlock)
                        Divider().frame(height: 18)
                        formattingButton(AppStrings.Editor.link, systemImage: "link", command: .link)
                        formattingButton(AppStrings.Editor.image, systemImage: "photo", command: .image)
                        formattingButton(AppStrings.Editor.table, systemImage: "tablecells", command: .table)
                        formattingButton(AppStrings.Editor.rule, systemImage: "minus", command: .horizontalRule)
                    }
                    .buttonStyle(.crispyvibesText)
                    .controlSize(.small)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(viewModel.documentType == .html ? "HTML Source" : "Markdown Source")
                    .font(AppTypographyTokens.caption)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }

            markupViewModeToggle
        }
        .padding(.horizontal, 12)
        .background(headerBackgroundColor)
    }

    private func formattingButton(_ title: String, systemImage: String, command: EditorFormattingCommand) -> some View {
        Button {
            commandRequest = EditorCommandRequest(command: command)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityIdentifier("editor.format.command.\(command.rawValue)")
    }

    private var markupViewModeToggle: some View {
        Picker(
            "Editor Mode",
            selection: Binding(
                get: { viewModel.currentMarkupViewMode },
                set: { newMode in
                    Task { @MainActor in
                        viewModel.setCurrentMarkupViewMode(newMode)
                    }
                }
            )
        ) {
            Text("Rich").tag(MarkdownViewModel.MarkupViewMode.rich)
            Text("Source").tag(MarkdownViewModel.MarkupViewMode.source)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 132)
        .accessibilityIdentifier("editor.mode.toggle")
    }
}
