import CryptoKit
import Foundation

private struct SignedFileWrapper: Codable {
    var payload: String
    var signature: String
}

final class AppPersistenceDataStore {
    static let shared = AppPersistenceDataStore()

    private let fileManager: FileManager
    private let appDirectoryURL: URL
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        appDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appDirectoryURL = appDirectoryURL ?? Self.defaultAppDirectoryURL(using: fileManager)
    }

    func appFileURL(relativePath: String, isDirectory: Bool = false) -> URL {
        appDirectoryURL.appendingPathComponent(relativePath, isDirectory: isDirectory)
    }

    func load<T: Decodable>(_ type: T.Type, from fileURL: URL) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        return decoded
    }

    func save<T: Encodable>(_ value: T, to fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // App persistence is best-effort only.
        }
    }

    func removeFile(at fileURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL)
    }

    func removeDirectoryIfEmpty(_ directoryURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), entries.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: directoryURL)
    }

    func resetAppStorage() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: appDirectoryURL)
    }

    func directoryExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    func createDirectory(at url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func contentsOfDirectory(at url: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    func removeDirectory(at url: URL) {
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Integrity Signing (HMAC-SHA256)

    struct SignedLoadResult<T> {
        let value: T
        let verified: Bool
    }

    func saveWithIntegrity<T: Encodable>(_ value: T, to fileURL: URL, using signingKey: SymmetricKey) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            let signature = HMAC<SHA256>.authenticationCode(for: data, using: signingKey)
            let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
            let wrapper = SignedFileWrapper(payload: data.base64EncodedString(), signature: signatureHex)
            let wrapperData = try JSONEncoder().encode(wrapper)
            try wrapperData.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort persistence
        }
    }

    func loadWithIntegrity<T: Decodable>(_ type: T.Type, from fileURL: URL, using signingKey: SymmetricKey) -> SignedLoadResult<T>? {
        lock.lock()
        defer { lock.unlock() }
        guard let wrapperData = try? Data(contentsOf: fileURL),
              let wrapper = try? JSONDecoder().decode(SignedFileWrapper.self, from: wrapperData),
              let payloadData = Data(base64Encoded: wrapper.payload),
              let value = try? JSONDecoder().decode(type, from: payloadData) else {
            return nil
        }
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: payloadData, using: signingKey)
        let expectedHex = expectedSignature.map { String(format: "%02x", $0) }.joined()
        let verified = expectedHex == wrapper.signature
        return SignedLoadResult(value: value, verified: verified)
    }

    private static func defaultAppDirectoryURL(using fileManager: FileManager) -> URL {
        let appSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return appSupportDirectory.appendingPathComponent(
            appSupportDirectoryName(),
            isDirectory: true
        )
    }

    private static func appSupportDirectoryName() -> String {
        let infoKey = "CrispyVibesAppSupportDirectoryName"
        if let configuredName = (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredName.isEmpty {
            return configuredName
        }

        if let bundleName = (Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleName.isEmpty {
            return bundleName
        }

        return "CrispyVibes"
    }
}
