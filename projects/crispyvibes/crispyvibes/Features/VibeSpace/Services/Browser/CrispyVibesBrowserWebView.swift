import AppKit
import WebKit

final class CrispyVibesBrowserWebView: WKWebView {
    var allowsFirstResponderAcquisition: Bool = true
    var onOpenInNewTab: ((URL) -> Void)?
    private var pointerFocusAllowanceDepth: Int = 0
    private var middleClickTimestamp: Date?

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard allowsFirstResponderAcquisition || pointerFocusAllowanceDepth > 0 else { return false }
        let result = super.becomeFirstResponder()
        if result {
            NotificationCenter.default.post(name: .browserDidBecomeFirstResponderWebView, object: self)
        }
        return result
    }

    // MARK: - Keyboard

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Skip custom handling during IME composition
        if let ic = inputContext, ic.handleEvent(event) { return true }

        // Return/Enter: let WebKit handle for form submission
        if event.keyCode == 36 || event.keyCode == 76, flags.isEmpty {
            return super.performKeyEquivalent(with: event)
        }

        // Non-Cmd keys go straight to WebKit
        guard flags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // Cmd+Shift+V: paste as plain text
        if flags == [.command, .shift], event.charactersIgnoringModifiers == "v" {
            if let text = NSPasteboard.general.string(forType: .string) {
                evaluateJavaScript("document.execCommand('insertText', false, \(quoteJS(text)))")
                return true
            }
        }

        // Route Cmd shortcuts through main menu first
        if let menu = NSApp.mainMenu, menu.performKeyEquivalent(with: event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        pointerFocusAllowanceDepth += 1
        defer { pointerFocusAllowanceDepth -= 1 }
        NotificationCenter.default.post(name: .webViewDidReceiveClick, object: self)
        super.mouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        switch event.buttonNumber {
        case 2: // Middle click — track for new-tab intent
            middleClickTimestamp = Date()
        case 3: // Back
            goBack()
            return
        case 4: // Forward
            goForward()
            return
        default:
            break
        }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            // Middle-click on a link opens in new tab — handled via navigation delegate
            // checking hasRecentMiddleClickIntent
        }
        super.otherMouseUp(with: event)
    }

    var hasRecentMiddleClickIntent: Bool {
        guard let ts = middleClickTimestamp else { return false }
        return Date().timeIntervalSince(ts) < 0.8
    }

    // MARK: - Context Menu

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for item in menu.items {
            if item.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" {
                item.title = AppStrings.Browser.openInNewTab
                let url = item.representedObject as? URL
                item.target = self
                item.representedObject = url
                item.action = #selector(contextMenuOpenInNewTab(_:))
            }
        }

        if let newTabIndex = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" }) {
            let openExternal = NSMenuItem(title: AppStrings.Browser.openInDefaultBrowser, action: #selector(contextMenuOpenInDefaultBrowser(_:)), keyEquivalent: "")
            openExternal.target = self
            openExternal.representedObject = menu.items[newTabIndex].representedObject
            menu.insertItem(openExternal, at: newTabIndex + 1)
        }

        // Retarget Copy Image to use pasteboard pipeline
        for item in menu.items where item.identifier?.rawValue == "WKMenuItemIdentifierCopyImage" {
            let original = item
            original.target = self
            original.action = #selector(contextMenuCopyImage(_:))
        }

        // Retarget Download Linked File
        for item in menu.items where item.identifier?.rawValue == "WKMenuItemIdentifierDownloadLinkedFile" {
            let original = item
            original.target = self
            original.action = #selector(contextMenuDownloadLinkedFile(_:))
        }

        super.willOpenMenu(menu, with: event)
    }

    @objc private func contextMenuOpenInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpenInNewTab?(url)
    }

    @objc private func contextMenuOpenInDefaultBrowser(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func contextMenuCopyImage(_ sender: NSMenuItem) {
        evaluateJavaScript("""
        (() => {
            const el = document.elementFromPoint(\(lastContextMenuPoint.x), \(lastContextMenuPoint.y));
            return el?.tagName === 'IMG' ? el.src : null;
        })();
        """) { result, _ in
            guard let src = result as? String, let url = URL(string: src) else { return }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data) else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
            }
        }
    }

    @objc private func contextMenuDownloadLinkedFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        load(URLRequest(url: url))
    }

    private var lastContextMenuPoint: NSPoint = .zero

    override func menu(for event: NSEvent) -> NSMenu? {
        let locationInView = convert(event.locationInWindow, from: nil)
        // Convert to web coordinates (flip Y)
        lastContextMenuPoint = NSPoint(x: locationInView.x, y: bounds.height - locationInView.y)
        return super.menu(for: event)
    }

    // MARK: - Drag Filtering

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let validTypes: [NSPasteboard.PasteboardType] = [.URL, .fileURL, .string]
        let pb = sender.draggingPasteboard
        guard pb.types?.contains(where: { validTypes.contains($0) }) == true else { return [] }
        return super.draggingEntered(sender)
    }

    // MARK: - Helpers

    private func quoteJS(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "'\(escaped)'"
    }
}

extension Notification.Name {
    static let webViewDidReceiveClick = Notification.Name("webViewDidReceiveClick")
    static let browserDidBecomeFirstResponderWebView = Notification.Name("browserDidBecomeFirstResponderWebView")
}
