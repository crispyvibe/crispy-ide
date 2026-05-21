import AppKit

extension AppKitTreeView.Coordinator {
    func buildContextMenu(for item: FileItem) -> NSMenu {
        let menu = NSMenu()
        let action = onAction
        let dirURL = item.isDirectory ? item.url : item.url.deletingLastPathComponent()

        if item.isDirectory {
            addMenuItem(to: menu, title: "New File", action: .createNewFile(item))
            addMenuItem(to: menu, title: "New Folder", action: .createNewFolder(item))
            menu.addItem(.separator())
        }

        addMenuItem(to: menu, title: "Open in Terminal", action: .openInTerminal(dirURL))
        addMenuItem(to: menu, title: "Reveal in Finder", action: .openInFinder(item.url))

        if !item.isDirectory {
            menu.addItem(.separator())
            addMenuItem(to: menu, title: "Open in Tab", action: .openInTab(item))
        }

        menu.addItem(.separator())

        let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(AppKitMenuTarget.copyPathAction(_:)), keyEquivalent: "")
        copyPathItem.representedObject = item.url.path
        copyPathItem.target = AppKitMenuTarget.shared
        menu.addItem(copyPathItem)

        if let rootURL {
            let relativePath = item.url.path.replacingOccurrences(
                of: rootURL.standardizedFileURL.path + "/",
                with: ""
            )
            let copyRelativeItem = NSMenuItem(title: "Copy Relative Path", action: #selector(AppKitMenuTarget.copyPathAction(_:)), keyEquivalent: "")
            copyRelativeItem.representedObject = relativePath
            copyRelativeItem.target = AppKitMenuTarget.shared
            menu.addItem(copyRelativeItem)
        }

        menu.addItem(.separator())
        addMenuItem(to: menu, title: "Rename", action: .startRenaming(item))
        menu.addItem(.separator())
        addMenuItem(to: menu, title: "Delete", action: .requestDelete(item))

        AppKitMenuTarget.shared.handler = action
        return menu
    }

    func buildRootContextMenu() -> NSMenu {
        let menu = NSMenu()
        addMenuItem(to: menu, title: "New File", action: .createNewFile(nil))
        addMenuItem(to: menu, title: "New Folder", action: .createNewFolder(nil))

        AppKitMenuTarget.shared.handler = onAction
        return menu
    }

    func addMenuItem(to menu: NSMenu, title: String, action: FileTreeAction) {
        let item = NSMenuItem(title: title, action: #selector(AppKitMenuTarget.menuAction(_:)), keyEquivalent: "")
        item.representedObject = action
        item.target = AppKitMenuTarget.shared
        menu.addItem(item)
    }
}
