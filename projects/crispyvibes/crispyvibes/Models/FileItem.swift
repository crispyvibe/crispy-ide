import Foundation

struct FileItem: Identifiable, Equatable {
    let url: URL
    let isDirectory: Bool
    let isHidden: Bool
    let isGitIgnored: Bool
    var children: [FileItem]?

    init(
        url: URL,
        isDirectory: Bool,
        isHidden: Bool = false,
        isGitIgnored: Bool = false,
        children: [FileItem]? = nil
    ) {
        self.url = url
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isGitIgnored = isGitIgnored
        self.children = children
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
            && lhs.isDirectory == rhs.isDirectory
            && lhs.isHidden == rhs.isHidden
            && lhs.isGitIgnored == rhs.isGitIgnored
        // children intentionally excluded — deep tree comparison is O(n) and
        // unnecessary for view diffing since flat rows don't render children
    }

    var id: String { url.path }

    var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
    
    var setiIconName: String? {
        guard !isDirectory else { return nil }
        return FileIconProvider.iconName(for: url.pathExtension)
    }
}
