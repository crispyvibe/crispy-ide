// FileItemDescriptor.swift — SSH Remote Development

import Foundation

/// Lightweight descriptor for a file system entry returned by FileSystemProviding.
/// Used to bridge between SFTP/local file system and the app's FileItem model.
struct FileItemDescriptor: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isHidden: Bool
    let size: UInt64?
    let modificationDate: Date?
}
