import Foundation

/// F052: helpers for creating new whiteboard documents on disk.
enum WhiteboardDocument {
    static let fileExtension = "excalidraw"

    /// An empty Excalidraw scene in the v2 `.excalidraw` file format. New
    /// whiteboards start from this; the canvas fills in defaults (including a
    /// theme-appropriate background) on load.
    static let emptyScene = #"""
    {"type":"excalidraw","version":2,"source":"crispyvibes","elements":[],"appState":{},"files":{}}
    """#

    /// Creates a uniquely-named empty whiteboard in `directory` and returns its
    /// URL, or `nil` if the file could not be written.
    static func createUntitled(in directory: URL, fileManager: FileManager = .default) -> URL? {
        let base = "Untitled Whiteboard"
        var candidate = directory.appendingPathComponent("\(base).\(fileExtension)")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix).\(fileExtension)")
            suffix += 1
        }
        do {
            try emptyScene.write(to: candidate, atomically: true, encoding: .utf8)
            return candidate.standardizedFileURL
        } catch {
            return nil
        }
    }
}
