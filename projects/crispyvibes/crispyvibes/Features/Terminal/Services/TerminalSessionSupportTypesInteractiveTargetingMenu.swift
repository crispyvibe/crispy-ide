import AppKit

extension MonitoredTerminalView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command] || modifiers == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }

        guard let sessionID = ownerSessionID,
              focusCoordinator?.currentSessionID == sessionID else {
            return false
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            copy(self)
            return true
        case "v":
            paste(self)
            return true
        default:
            return false
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Terminal")
        contextualInteractiveTarget = interactiveTarget(for: event)

        if let contextualInteractiveTarget {
            let openTargetItem = NSMenuItem(
                title: contextualInteractiveTarget.contextMenuTitle,
                action: #selector(openContextualInteractiveTarget(_:)),
                keyEquivalent: ""
            )
            openTargetItem.target = self
            menu.addItem(openTargetItem)
            menu.addItem(NSMenuItem.separator())
        }

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = (NSPasteboard.general.string(forType: .string)?.isEmpty == false)
        menu.addItem(pasteItem)

        if onSplitTerminalRequested != nil || onTemporaryTerminalRequested != nil {
            menu.addItem(NSMenuItem.separator())
        }

        if onSplitTerminalRequested != nil {
            let splitItem = NSMenuItem(
                title: "Split Terminal",
                action: #selector(requestSplitTerminal(_:)),
                keyEquivalent: ""
            )
            splitItem.target = self
            menu.addItem(splitItem)
        }

        if onTemporaryTerminalRequested != nil {
            let temporaryItem = NSMenuItem(
                title: "New Temporary Terminal",
                action: #selector(requestTemporaryTerminal(_:)),
                keyEquivalent: ""
            )
            temporaryItem.target = self
            menu.addItem(temporaryItem)
        }

        return menu
    }

    @objc func requestSplitTerminal(_ sender: Any?) {
        onSplitTerminalRequested?()
    }

    @objc func requestTemporaryTerminal(_ sender: Any?) {
        onTemporaryTerminalRequested?()
    }

    @objc func openContextualInteractiveTarget(_ sender: Any?) {
        guard let contextualInteractiveTarget else { return }
        activateInteractiveTarget(contextualInteractiveTarget)
    }
}
