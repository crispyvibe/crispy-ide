import AppKit
import Foundation
import UniformTypeIdentifiers

struct VibeSpaceDragPayload: Codable, Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.crispyvibesde.vibespace-item")
    static let typeIdentifier = "dev.crispyvibesde.vibespace-item"

    let path: String

    init(url: URL) {
        path = url.standardizedFileURL.path
    }

    var fileURL: URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    func makePasteboardItem() -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()

        if let data = try? JSONEncoder().encode(self) {
            pasteboardItem.setData(data, forType: Self.pasteboardType)
        }

        pasteboardItem.setString(path, forType: .string)
        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)
        return pasteboardItem
    }

    func makeItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()

        if let data = try? JSONEncoder().encode(self) {
            provider.registerDataRepresentation(
                forTypeIdentifier: Self.typeIdentifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }

        provider.registerObject(path as NSString, visibility: .all)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            completion(self.fileURL.dataRepresentation, nil)
            return nil
        }

        return provider
    }
}

enum VibeSpaceDragPayloadDecoder {
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.pasteboardItems?.compactMap(url(from:)) ?? []
    }

    static func url(from item: NSPasteboardItem) -> URL? {
        if let data = item.data(forType: VibeSpaceDragPayload.pasteboardType),
           let payload = try? JSONDecoder().decode(VibeSpaceDragPayload.self, from: data) {
            return payload.fileURL
        }

        if let fileURLString = item.string(forType: .fileURL),
           let url = URL(string: fileURLString) {
            return url.standardizedFileURL
        }

        if let path = item.string(forType: .string), !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        return nil
    }

    static func loadURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        guard !providers.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var decodedURLs: [URL] = []

        for provider in providers {
            group.enter()
            loadURL(from: provider) { url in
                defer { group.leave() }
                guard let url else { return }
                lock.lock()
                decodedURLs.append(url.standardizedFileURL)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            completion(decodedURLs)
        }
    }

    private static func loadURL(
        from provider: NSItemProvider,
        completion: @escaping (URL?) -> Void
    ) {
        if provider.hasItemConformingToTypeIdentifier(VibeSpaceDragPayload.typeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: VibeSpaceDragPayload.typeIdentifier) { data, _ in
                guard let data,
                      let payload = try? JSONDecoder().decode(VibeSpaceDragPayload.self, from: data)
                else {
                    completion(nil)
                    return
                }
                completion(payload.fileURL)
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                completion(url(fromLoadedItem: item))
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                completion(url(fromLoadedItem: item))
            }
            return
        }

        completion(nil)
    }

    private static func url(fromLoadedItem item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            if let payload = try? JSONDecoder().decode(VibeSpaceDragPayload.self, from: data) {
                return payload.fileURL
            }
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url.standardizedFileURL
            }
            if let path = String(data: data, encoding: .utf8), !path.isEmpty {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
        }

        if let path = item as? String, !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        if let string = item as? NSString, !string.isEqual(to: "") {
            return URL(fileURLWithPath: string as String).standardizedFileURL
        }

        if let url = item as? URL {
            return url.standardizedFileURL
        }

        if let url = item as? NSURL {
            return (url as URL).standardizedFileURL
        }

        return nil
    }
}
