import Foundation

extension PaneWorkerExecutor {
    private static let maxReadableTextFileBytes = 6 * 1024 * 1024
    private static let readableTextFileResourceKeys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey]

    static func readTextFile(at url: URL) throws -> String {
        try validateReadableTextFileSize(at: url)

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        throw PaneWorkerError.workerFailure("File encoding is not supported.")
    }

    private static func validateReadableTextFileSize(at url: URL) throws {
        let values = try url.resourceValues(forKeys: readableTextFileResourceKeys)
        let fileSize = values.totalFileAllocatedSize ?? values.fileSize ?? 0
        guard fileSize <= maxReadableTextFileBytes else {
            let maximumMegabytes = maxReadableTextFileBytes / (1024 * 1024)
            throw PaneWorkerError.workerFailure(
                "File is too large to open in the editor. Maximum supported size is \(maximumMegabytes) MB."
            )
        }
    }
}
