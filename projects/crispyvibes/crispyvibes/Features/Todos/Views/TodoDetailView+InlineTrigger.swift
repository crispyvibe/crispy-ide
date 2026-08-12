import SwiftUI

// F060 — the terminal inline file-search trigger (F038), embedded in the todo
// notes editor and thread composer: the third consumer of the shared
// `TerminalInlineTriggerController` after VibeCast and the ACP chat. Picking a
// file inserts its path into the text AND attaches it as a file link.

extension TodoDetailView {

    func configureInlineTrigger() {
        let root = todo.projectPath ?? focusedProjectPath
        guard let root else {
            _ = inlineTrigger.handleCommand(.dismiss)
            return
        }
        let rootURL = URL(fileURLWithPath: root)
        inlineTrigger.configure(
            triggerToken: configuredInlineTrigger,
            searchRoots: [rootURL],
            shortcuts: [],
            terminalTitle: todo.title,
            currentDirectoryProvider: { rootURL },
            insertionHandler: { [weak store] text in
                applyInlineInsertion(text)
                // Inserted paths become links too (the pipeline's whole point).
                let parsed = TodoFileLink.parsePathToken(text)
                let absolute = parsed.path.hasPrefix("/")
                    ? parsed.path
                    : rootURL.appendingPathComponent(parsed.path).standardizedFileURL.path
                let todoID = todo.id
                Task { @MainActor in
                    _ = await store?.addFileLink(todoID: todoID, path: absolute, line: parsed.line)
                }
            },
            focusHandler: nil,
            manageShortcutsHandler: nil
        )
    }

    /// Replace the trigger token + query in whichever field is being edited.
    private func applyInlineInsertion(_ replacement: String) {
        let token = AppPreferences.normalizedTerminalComposeInlineTrigger(configuredInlineTrigger)
        if isEditingBody {
            if let trigger = SpotlightComposeInlineTrigger.parse(draftBody, triggerToken: token) {
                draftBody = trigger.prefixText + replacement
            }
        } else if let trigger = SpotlightComposeInlineTrigger.parse(composerText, triggerToken: token) {
            composerText = trigger.prefixText + replacement
        }
    }

    /// The floating results panel, anchored above the composer / below the editor.
    @ViewBuilder var inlineTriggerPanel: some View {
        if inlineTrigger.isPresented {
            SpotlightComposeInlinePanel(
                title: AppStrings.Terminal.ComposeTriggers.pickerTitle,
                queryText: inlineTrigger.queryText,
                featuredAction: inlineTrigger.featuredPanelAction,
                rows: inlineTrigger.panelRows,
                statusText: inlineTrigger.footerText,
                hintText: inlineTrigger.hintText,
                actionTitle: nil,
                onAction: nil,
                onFeaturedAction: { inlineTrigger.applyFeaturedAction() },
                onSelect: { inlineTrigger.applyResult(id: $0) }
            )
            .frame(maxWidth: 420)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// Keyboard routing while the panel is up: arrows navigate, return
    /// confirms, escape dismisses. Attach to the editing fields.
    func inlineTriggerKeyHandler(_ press: KeyPress) -> KeyPress.Result {
        guard inlineTrigger.isPresented else { return .ignored }
        switch press.key {
        case .upArrow: return inlineTrigger.handleCommand(.moveUp) ? .handled : .ignored
        case .downArrow: return inlineTrigger.handleCommand(.moveDown) ? .handled : .ignored
        case .return: return inlineTrigger.handleCommand(.confirm) ? .handled : .ignored
        case .escape: return inlineTrigger.handleCommand(.dismiss) ? .handled : .ignored
        default: return .ignored
        }
    }
}
