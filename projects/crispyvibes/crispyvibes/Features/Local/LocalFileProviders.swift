// LocalFileProviders.swift — SSH Remote Development

import Foundation

/// Local file system operations via FileManager. All work runs off the main actor.
struct LocalFileSystemProvider: FileSystemProviding {
    func contentsOfDirectory(at path: String) async throws -> [FileItemDescriptor] {
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let url = URL(fileURLWithPath: path)
            let contents = try fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey]
            )
            return contents.map { childURL in
                let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey])
                return FileItemDescriptor(
                    name: childURL.lastPathComponent,
                    path: childURL.path,
                    isDirectory: values?.isDirectory ?? false,
                    isHidden: values?.isHidden ?? childURL.lastPathComponent.hasPrefix("."),
                    size: values?.fileSize.map(UInt64.init),
                    modificationDate: values?.contentModificationDate
                )
            }
        }.value
    }

    func createDirectory(at path: String) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }.value
    }

    func createFile(at path: String, contents: Data?) async throws {
        try await Task.detached(priority: .utility) {
            let created = FileManager.default.createFile(atPath: path, contents: contents)
            guard created else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
            }
        }.value
    }

    func removeItem(at path: String) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(atPath: path)
        }.value
    }

    func moveItem(from source: String, to destination: String) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.moveItem(atPath: source, toPath: destination)
        }.value
    }
}

/// Local file content read/write via Data. All work runs off the main actor.
struct LocalFileContentProvider: FileContentProviding {
    func readFile(at path: String) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: URL(fileURLWithPath: path))
        }.value
    }

    func writeFile(at path: String, contents: Data) async throws {
        try await Task.detached(priority: .utility) {
            try contents.write(to: URL(fileURLWithPath: path))
        }.value
    }

    func fileSize(at path: String) async throws -> UInt64? {
        try await Task.detached(priority: .utility) {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            return attrs[.size] as? UInt64
        }.value
    }
}
