import AppKit

final class TreeNode: NSObject {
    var item: FileItem
    var childNodes: [TreeNode]?

    init(item: FileItem) {
        self.item = item
    }
}

final class LoadingNode: NSObject {
    let parentDirectoryID: String

    init(parentDirectoryID: String) {
        self.parentDirectoryID = parentDirectoryID
    }
}
