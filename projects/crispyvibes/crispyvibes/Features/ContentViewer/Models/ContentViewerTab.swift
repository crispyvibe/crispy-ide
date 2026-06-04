import AppKit
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct FileDocumentReference: Codable, Equatable, Hashable {
    let filePath: String
    let projectIdentifier: String?

    init(url: URL, projectIdentifier: String? = nil) {
        self.filePath = url.standardizedFileURL.path
        self.projectIdentifier = projectIdentifier
    }

    var url: URL {
        URL(fileURLWithPath: filePath).standardizedFileURL
    }

    var documentIdentity: String {
        guard let projectIdentifier, !projectIdentifier.isEmpty else {
            return filePath
        }
        return "\(projectIdentifier)|\(filePath)"
    }

    func replacingURL(_ url: URL) -> FileDocumentReference {
        FileDocumentReference(url: url, projectIdentifier: projectIdentifier)
    }
}

struct BrowserTabReference: Codable, Equatable {
    var browserID: UUID
    var seedURLString: String?
    var projectPath: String?
    var linkedTileID: UUID?

    init(
        browserID: UUID = UUID(),
        url: URL? = nil,
        projectPath: String? = nil,
        linkedTileID: UUID? = nil
    ) {
        self.browserID = browserID
        self.seedURLString = url?.absoluteString
        self.projectPath = projectPath
        self.linkedTileID = linkedTileID
    }

    var seedURL: URL? {
        guard let seedURLString else { return nil }
        return URL(string: seedURLString)
    }
}

private enum BrowserTabDisplayNameFormatter {
    static func title(for url: URL) -> String {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return url.absoluteString
        }

        let components = host.split(separator: ".")
        guard components.count >= 2 else { return host }

        if components.count >= 3, components[components.count - 2] == "co" {
            return String(components[components.count - 3])
        }

        return String(components[components.count - 2])
    }
}

enum ContentViewerTabKind: Equatable {
    case file(FileDocumentReference)
    case vibeCast
    case todos
    case webPage(BrowserTabReference)
    case terminal(projectID: UUID, tabID: UUID)
    case acpPane(id: UUID)
}

struct ContentViewerTab: Identifiable, Equatable {
    let id: String
    let kind: ContentViewerTabKind
    var customTitle: String?

    var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        switch kind {
        case .file(let reference):
            let url = reference.url
            let name = url.lastPathComponent
            return name.isEmpty ? url.path : name
        case .vibeCast:
            return "VibeCast"
        case .todos:
            return "Todos"
        case .webPage(let reference):
            if let url = reference.seedURL {
                return BrowserTabDisplayNameFormatter.title(for: url)
            }
            return "New Tab"
        case .terminal:
            return "Terminal"
        case .acpPane:
            return "Agent"
        }
    }

    var iconName: String {
        switch kind {
        case .file(let reference):
            let url = reference.url
            let ext = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff"].contains(ext) { return "photo" }
            if ext == "pdf" { return "doc.text.image" }
            if ["md", "markdown", "html", "htm"].contains(ext) { return "doc.richtext" }
            if ["doc", "docx"].contains(ext) { return "doc.text.fill" }
            if ["ppt", "pptx"].contains(ext) { return "rectangle.stack.fill" }
            if ["xls", "xlsx"].contains(ext) { return "tablecells.fill" }
            return "doc.text"
        case .vibeCast:
            return "antenna.radiowaves.left.and.right"
        case .todos:
            return "checklist"
        case .webPage:
            return "globe"
        case .terminal:
            return "terminal"
        case .acpPane:
            return "sparkles"
        }
    }

    static func file(url: URL, projectIdentifier: String? = nil) -> ContentViewerTab {
        file(reference: FileDocumentReference(url: url, projectIdentifier: projectIdentifier))
    }

    static func file(reference: FileDocumentReference) -> ContentViewerTab {
        ContentViewerTab(id: "file:\(reference.documentIdentity)", kind: .file(reference))
    }

    static var vibeCast: ContentViewerTab {
        ContentViewerTab(id: "vibeCast", kind: .vibeCast)
    }

    static var todos: ContentViewerTab {
        ContentViewerTab(id: "todos", kind: .todos)
    }

    static func webPage(
        url: URL,
        projectPath: String? = nil,
        linkedTileID: UUID? = nil,
        browserID: UUID? = nil
    ) -> ContentViewerTab {
        let reference = BrowserTabReference(
            browserID: browserID ?? linkedTileID ?? UUID(),
            url: url,
            projectPath: projectPath,
            linkedTileID: linkedTileID
        )
        return webPage(reference: reference)
    }

    static func webPage(reference: BrowserTabReference, customTitle: String? = nil) -> ContentViewerTab {
        ContentViewerTab(
            id: "web:\(reference.browserID.uuidString)",
            kind: .webPage(reference),
            customTitle: customTitle
        )
    }

    static func terminal(projectID: UUID, tabID: UUID) -> ContentViewerTab {
        ContentViewerTab(id: "terminal:\(projectID.uuidString):\(tabID.uuidString)", kind: .terminal(projectID: projectID, tabID: tabID))
    }

    static func acpPane(id: UUID) -> ContentViewerTab {
        ContentViewerTab(id: "acp:\(id.uuidString)", kind: .acpPane(id: id))
    }

    static func browserTitle(for url: URL) -> String {
        BrowserTabDisplayNameFormatter.title(for: url)
    }

    /// Resolve the project accent color for a tab based on its file path.
    static func projectColor(
        for tab: ContentViewerTab,
        projectColorTagsByPath: [String: ProjectColorTag],
        fallback: Color
    ) -> Color? {
        switch tab.kind {
        case .file(let reference):
            let filePath = reference.url.standardizedFileURL.path
            let match = projectColorTagsByPath.keys
                .filter { filePath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
                .max(by: { $0.count < $1.count })
            guard let match, let tag = projectColorTagsByPath[match] else { return nil }
            return tag.color
        case .acpPane:
            return fallback
        default:
            return nil
        }
    }
}

private struct ContentViewerTabDragPayload: Codable, Equatable {
    private enum PayloadKind: String, Codable {
        case file
        case vibeCast
        case todos
        case webPage
        case terminal
        case acpPane
    }

    private let kind: PayloadKind
    private let value: String?
    private let customTitle: String?
    private let browserReference: BrowserTabReference?
    private let fileReference: FileDocumentReference?

    init(tab: ContentViewerTab) {
        switch tab.kind {
        case .file(let reference):
            kind = .file
            value = reference.filePath
            customTitle = tab.customTitle
            browserReference = nil
            fileReference = reference
        case .vibeCast:
            kind = .vibeCast
            value = nil
            customTitle = tab.customTitle
            browserReference = nil
            fileReference = nil
        case .todos:
            kind = .todos
            value = nil
            customTitle = tab.customTitle
            browserReference = nil
            fileReference = nil
        case .webPage(let reference):
            kind = .webPage
            value = reference.seedURLString
            customTitle = tab.customTitle
            browserReference = reference
            fileReference = nil
        case .terminal(let projectID, let tabID):
            kind = .terminal
            value = "\(projectID.uuidString):\(tabID.uuidString)"
            customTitle = tab.customTitle
            browserReference = nil
            fileReference = nil
        case .acpPane(let id):
            kind = .acpPane
            value = id.uuidString
            customTitle = tab.customTitle
            browserReference = nil
            fileReference = nil
        }
    }

    var tab: ContentViewerTab? {
        switch kind {
        case .file:
            if let fileReference {
                return .file(reference: fileReference)
            }
            guard let value, !value.isEmpty else { return nil }
            return .file(url: URL(fileURLWithPath: value))
        case .vibeCast:
            return .vibeCast
        case .todos:
            return .todos
        case .webPage:
            if let browserReference {
                return .webPage(reference: browserReference, customTitle: customTitle)
            }
            guard let value, let url = URL(string: value) else { return nil }
            return .webPage(
                reference: BrowserTabReference(url: url),
                customTitle: customTitle
            )
        case .terminal:
            guard let value else { return nil }
            let parts = value.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let projectID = UUID(uuidString: String(parts[0])),
                  let tabID = UUID(uuidString: String(parts[1])) else { return nil }
            return .terminal(projectID: projectID, tabID: tabID)
        case .acpPane:
            guard let value, let id = UUID(uuidString: value) else { return nil }
            return .acpPane(id: id)
        }
    }
}

enum ContentViewerDropItem: Equatable {
    case tab(ContentViewerTab)
    case file(URL)
}

struct ContentViewerEmbeddedDropBridge {
    let updateTargeting: (_ location: CGPoint, _ size: CGSize) -> Void
    let clearTargeting: () -> Void
    let performDrop: (_ item: ContentViewerDropItem, _ location: CGPoint, _ size: CGSize) -> Bool
}

enum ContentViewerTabDragSupport {
    static let contentViewerTabType = UTType(exportedAs: "com.crispyvibe.app.content-viewer-tab")
    static let dropTypes: [UTType] = [contentViewerTabType, .fileURL]

    private static let logger = Logger(subsystem: "com.crispyvibe.app", category: "content-viewer-drag-drop")

    static func makeItemProvider(for tab: ContentViewerTab) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = ContentViewerTabDragPayload(tab: tab)

        provider.registerDataRepresentation(
            forTypeIdentifier: contentViewerTabType.identifier,
            visibility: .all
        ) { completion in
            do {
                let data = try JSONEncoder().encode(payload)
                completion(data, nil)
            } catch {
                logger.error("Failed to encode content viewer tab drag payload: \(error.localizedDescription, privacy: .public)")
                completion(nil, error)
            }
            return nil
        }

        return provider
    }

    static func loadDropItem(
        from providers: [NSItemProvider],
        completion: @escaping (ContentViewerDropItem?) -> Void
    ) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(contentViewerTabType.identifier) }) {
            loadTab(from: provider) { tab in
                completion(tab.map(ContentViewerDropItem.tab))
            }
            return true
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            loadFileURL(from: provider) { url in
                completion(url.map { ContentViewerDropItem.file($0) })
            }
            return true
        }

        logger.debug("Drop ignored because no supported content-viewer provider was found")
        return false
    }

    static func decodeTabPayload(_ data: Data) -> ContentViewerTab? {
        guard let payload = try? JSONDecoder().decode(ContentViewerTabDragPayload.self, from: data) else {
            return nil
        }
        return payload.tab
    }

    static func contentAreaDropTypes(for kind: ContentViewerTabKind?) -> [UTType] {
        guard let kind else { return dropTypes }
        if case .terminal = kind {
            return [contentViewerTabType]
        }
        return dropTypes
    }

    static func canReadDropItem(from pasteboard: NSPasteboard) -> Bool {
        if pasteboard.data(forType: NSPasteboard.PasteboardType(contentViewerTabType.identifier)) != nil {
            return true
        }
        return firstFileURL(from: pasteboard) != nil
    }

    static func readDropItem(from pasteboard: NSPasteboard) -> ContentViewerDropItem? {
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(contentViewerTabType.identifier)),
           let tab = decodeTabPayload(data) {
            return .tab(tab)
        }

        if let url = firstFileURL(from: pasteboard) {
            return .file(url)
        }

        return nil
    }

    private static func loadTab(
        from provider: NSItemProvider,
        completion: @escaping (ContentViewerTab?) -> Void
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: contentViewerTabType.identifier) { data, error in
            if let error {
                logger.error("Failed to load tab drag payload: \(error.localizedDescription, privacy: .public)")
            }
            guard let data else {
                logger.debug("Drop payload load returned no data for content viewer tab type")
                completion(nil)
                return
            }
            let tab = decodeTabPayload(data)
            if tab == nil {
                logger.debug("Drop payload decode failed for content viewer tab type")
            }
            completion(tab)
        }
    }

    private static func loadFileURL(
        from provider: NSItemProvider,
        completion: @escaping (URL?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                logger.error("Failed to load file URL drop payload: \(error.localizedDescription, privacy: .public)")
            }
            let url = fileURL(from: item)
            if url == nil {
                logger.debug("File URL drop payload could not be decoded")
            }
            completion(url)
        }
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url.standardizedFileURL
            }
            if let path = String(data: data, encoding: .utf8), !path.isEmpty {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
        }

        if let url = item as? URL {
            return url.standardizedFileURL
        }

        if let url = item as? NSURL {
            return (url as URL).standardizedFileURL
        }

        if let string = item as? String, !string.isEmpty {
            return URL(fileURLWithPath: string).standardizedFileURL
        }

        if let string = item as? NSString, !string.isEqual(to: "") {
            return URL(fileURLWithPath: string as String).standardizedFileURL
        }

        return nil
    }

    private static func firstFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first?.standardizedFileURL
    }
}
