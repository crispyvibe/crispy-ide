import AppKit

final class AppKitMenuTarget: NSObject {
    static let shared = AppKitMenuTarget()
    var handler: ((FileTreeAction) -> Void)?

    @objc func menuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? FileTreeAction else { return }
        handler?(action)
        handler = nil
    }

    @objc func copyPathAction(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}
