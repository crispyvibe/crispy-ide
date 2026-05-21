import AppKit
import Foundation

enum TerminalFileDropSupport {
    static func dragOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
        fileURLs(from: pasteboard).isEmpty ? [] : .copy
    }

    static func requestFocus(for view: NSView, retryCount: Int = 0) {
        guard retryCount <= 2 else { return }
        guard let window = view.window else { return }

        if !window.isKeyWindow {
            window.makeKey()
        }

        if window.firstResponder === view {
            return
        }

        if window.makeFirstResponder(view) {
            return
        }

        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            requestFocus(for: view, retryCount: retryCount + 1)
        }
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    static func droppedText(
        for urls: [URL],
        currentDirectory: URL?
    ) -> String? {
        let escapedPaths = urls.compactMap { url in
            escapedDroppedPath(for: url, currentDirectory: currentDirectory)
        }
        guard !escapedPaths.isEmpty else { return nil }
        return escapedPaths.joined(separator: " ") + " "
    }

    static func shellEscapedRelativePath(
        for url: URL,
        isDirectory: Bool,
        currentDirectory: URL?
    ) -> String? {
        guard var insertablePath = relativePath(from: currentDirectory, to: url) else {
            return nil
        }
        if isDirectory, !insertablePath.hasSuffix("/") {
            insertablePath.append("/")
        }
        return ShellEscaping.singleQuote(insertablePath)
    }

    private static func escapedDroppedPath(for url: URL, currentDirectory: URL?) -> String? {
        let filePath = url.standardizedFileURL.path
        guard !filePath.isEmpty else { return nil }

        let currentDirectoryPath = currentDirectory?.standardizedFileURL.path
        let relativePath: String
        if let currentDirectoryPath,
           filePath.hasPrefix(currentDirectoryPath + "/") {
            relativePath = String(filePath.dropFirst(currentDirectoryPath.count + 1))
        } else {
            relativePath = filePath
        }

        return ShellEscaping.singleQuote(relativePath)
    }

    private static func relativePath(from baseURL: URL?, to targetURL: URL) -> String? {
        let normalizedTargetURL = targetURL.standardizedFileURL
        let targetPath = normalizedTargetURL.path
        guard !targetPath.isEmpty else { return nil }
        guard let baseURL else { return targetPath }

        let normalizedBaseURL = baseURL.standardizedFileURL
        let baseComponents = normalizedBaseURL.pathComponents
        let targetComponents = normalizedTargetURL.pathComponents
        var commonIndex = 0

        while commonIndex < baseComponents.count,
              commonIndex < targetComponents.count,
              baseComponents[commonIndex] == targetComponents[commonIndex] {
            commonIndex += 1
        }

        guard commonIndex > 0 else { return targetPath }
        let upwardTraversal = Array(repeating: "..", count: max(baseComponents.count - commonIndex, 0))
        let downwardTraversal = Array(targetComponents.dropFirst(commonIndex))
        let components = upwardTraversal + downwardTraversal
        if components.isEmpty { return "." }
        return components.joined(separator: "/")
    }
}
