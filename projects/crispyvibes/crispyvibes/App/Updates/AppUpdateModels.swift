import Foundation

private enum AppUpdateManifestDecodingError: LocalizedError {
    case missingVersion
    case missingDownloadURL
    case invalidDownloadURL(String)

    var errorDescription: String? {
        switch self {
        case .missingVersion:
            return "Update manifest is missing version."
        case .missingDownloadURL:
            return "Update manifest is missing download URL."
        case let .invalidDownloadURL(rawValue):
            return "Update manifest has invalid download URL: \(rawValue)"
        }
    }
}

struct AppUpdateManifest: Decodable, Equatable {
    let version: String
    let build: String
    let downloadURL: URL
    let releaseNotesURL: URL?
    let releaseNotes: String?

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case downloadURL
        case downloadUrl
        case download_url
        case releaseNotesURL
        case releaseNotesUrl
        case release_notes_url
        case releaseNotes
        case release_notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let parsedVersion = try container.decode(String.self, forKey: .version)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsedVersion.isEmpty else {
            throw AppUpdateManifestDecodingError.missingVersion
        }
        version = parsedVersion

        let parsedBuild = (try container.decodeIfPresent(String.self, forKey: .build))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        build = (parsedBuild?.isEmpty == false) ? parsedBuild! : "0"

        guard let rawDownloadURL = try Self.decodeOptionalString(
            from: container,
            keys: [.downloadURL, .downloadUrl, .download_url]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rawDownloadURL.isEmpty else {
            throw AppUpdateManifestDecodingError.missingDownloadURL
        }
        guard let decodedDownloadURL = URL(string: rawDownloadURL), decodedDownloadURL.scheme != nil else {
            throw AppUpdateManifestDecodingError.invalidDownloadURL(rawDownloadURL)
        }
        downloadURL = decodedDownloadURL

        let rawReleaseNotesURL = try Self.decodeOptionalString(
            from: container,
            keys: [.releaseNotesURL, .releaseNotesUrl, .release_notes_url]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawReleaseNotesURL,
           !rawReleaseNotesURL.isEmpty,
           let decodedReleaseNotesURL = URL(string: rawReleaseNotesURL),
           decodedReleaseNotesURL.scheme != nil {
            releaseNotesURL = decodedReleaseNotesURL
        } else {
            releaseNotesURL = nil
        }

        releaseNotes = try Self.decodeOptionalString(from: container, keys: [.releaseNotes, .release_notes])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeOptionalString(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> String? {
        for key in keys {
            if let value = try container.decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

enum AppUpdateVersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(
                rhs.trimmingCharacters(in: .whitespacesAndNewlines),
                options: .numeric
            )
    }

    static func isRemoteNewer(
        currentVersion: String,
        currentBuild: String,
        remoteVersion: String,
        remoteBuild: String
    ) -> Bool {
        return compare(currentBuild, remoteBuild) == .orderedAscending
    }
}

enum AppUpdateDecision: Equatable {
    case upToDate
    case updateAvailable(AppUpdateManifest)

    static func evaluate(
        currentVersion: String,
        currentBuild: String,
        manifest: AppUpdateManifest
    ) -> AppUpdateDecision {
        if AppUpdateVersionComparator.isRemoteNewer(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            remoteVersion: manifest.version,
            remoteBuild: manifest.build
        ) {
            return .updateAvailable(manifest)
        }
        return .upToDate
    }
}

enum AppUpdateSchedule {
    static func shouldRunAutomaticCheck(
        autoCheckEnabled: Bool,
        lastSuccessfulCheck: Date?,
        now: Date,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard autoCheckEnabled else { return false }
        guard let lastSuccessfulCheck else { return true }
        return now.timeIntervalSince(lastSuccessfulCheck) >= minimumInterval
    }
}
