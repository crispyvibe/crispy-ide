import AppKit
import Foundation
import GhosttyKit

@MainActor
extension GhosttyTerminalView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Terminal")

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyAction(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteAction(_:)), keyEquivalent: "")
        pasteItem.target = self
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let signalMenu = NSMenu(title: "Send Signal")
        for (title, byte) in Self.signalMenuItems {
            let item = NSMenuItem(title: title, action: #selector(sendSignalAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(byte)
            signalMenu.addItem(item)
        }
        signalMenu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Screen (Ctrl+L)", action: #selector(sendSignalAction(_:)), keyEquivalent: "")
        clearItem.target = self
        clearItem.tag = 0x0C
        signalMenu.addItem(clearItem)

        let signalSubmenu = NSMenuItem(title: "Send Signal", action: nil, keyEquivalent: "")
        signalSubmenu.submenu = signalMenu
        menu.addItem(signalSubmenu)

        if engine?.actionHandlers.onSplitTerminalRequested != nil
            || engine?.actionHandlers.onTemporaryTerminalRequested != nil
            || engine?.actionHandlers.onOpenInEditorPaneRequested != nil {
            menu.addItem(.separator())
        }

        if engine?.actionHandlers.onOpenInEditorPaneRequested != nil {
            let editorItem = NSMenuItem(title: "Open in Editor Pane", action: #selector(openInEditorPaneAction(_:)), keyEquivalent: "")
            editorItem.target = self
            menu.addItem(editorItem)
        }

        if engine?.actionHandlers.onSplitTerminalRequested != nil {
            let splitItem = NSMenuItem(title: "Split Terminal", action: #selector(splitTerminalAction(_:)), keyEquivalent: "")
            splitItem.target = self
            menu.addItem(splitItem)
        }

        if engine?.actionHandlers.onTemporaryTerminalRequested != nil {
            let temporaryItem = NSMenuItem(title: "New Temporary Terminal", action: #selector(temporaryTerminalAction(_:)), keyEquivalent: "")
            temporaryItem.target = self
            menu.addItem(temporaryItem)
        }

        return menu
    }

    @objc fileprivate func copyAction(_ sender: Any?) {
        engine?.copySelection()
    }

    @objc fileprivate func pasteAction(_ sender: Any?) {
        engine?.pasteFromClipboard()
    }

    @objc fileprivate func sendSignalAction(_ sender: NSMenuItem) {
        guard let surface else { return }
        guard let command = Self.signalCommand(for: UInt8(sender.tag)) else { return }
        engine?.sendControlKey(
            to: surface,
            keycode: command.keycode,
            mods: command.mods,
            text: command.text,
            unshiftedCodepoint: command.codepoint
        )
    }

    @objc fileprivate func splitTerminalAction(_ sender: Any?) {
        engine?.actionHandlers.onSplitTerminalRequested?()
    }

    @objc fileprivate func temporaryTerminalAction(_ sender: Any?) {
        engine?.actionHandlers.onTemporaryTerminalRequested?()
    }

    @objc fileprivate func openInEditorPaneAction(_ sender: Any?) {
        engine?.actionHandlers.onOpenInEditorPaneRequested?()
    }

    private static let signalMenuItems: [(String, UInt8)] = [
        ("Interrupt (Ctrl+C)", 0x03),
        ("EOF (Ctrl+D)", 0x04),
        ("Suspend (Ctrl+Z)", 0x1A),
        ("Quit (Ctrl+\\\\)", 0x1C),
        ("Escape", 0x1B),
    ]

    private static func signalCommand(for byte: UInt8) -> (
        keycode: UInt32,
        text: String,
        codepoint: UInt32,
        mods: ghostty_input_mods_e
    )? {
        switch byte {
        case 0x03: return (8, "c", 0x63, GHOSTTY_MODS_CTRL)
        case 0x04: return (2, "d", 0x64, GHOSTTY_MODS_CTRL)
        case 0x1A: return (6, "z", 0x7A, GHOSTTY_MODS_CTRL)
        case 0x1C: return (42, "\\", 0x5C, GHOSTTY_MODS_CTRL)
        case 0x0C: return (37, "l", 0x6C, GHOSTTY_MODS_CTRL)
        case 0x1B: return (53, "", 0x1B, GHOSTTY_MODS_NONE)
        default: return nil
        }
    }
}
