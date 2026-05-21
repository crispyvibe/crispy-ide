import AppKit
import Foundation

@MainActor
enum AppInstallationGuard {
    private enum LaunchLocation {
        case applications
        case mountedDiskImage
        case downloads
        case temporary
        case other

        var requiresMovePrompt: Bool {
            switch self {
            case .mountedDiskImage, .downloads, .temporary:
                return true
            case .applications, .other:
                return false
            }
        }

        var contextMessage: String {
            switch self {
            case .mountedDiskImage:
                return "You're running Crispy from a disk image."
            case .downloads:
                return "You're running Crispy from Downloads."
            case .temporary:
                return "You're running Crispy from a temporary location."
            case .applications, .other:
                return ""
            }
        }
    }

    static func handleLaunchIfNeeded() -> Bool {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let launchLocation = classifyLaunchLocation(for: bundleURL)
        guard launchLocation.requiresMovePrompt else { return false }
        return promptForMoveAndInstallIfNeeded(from: bundleURL, location: launchLocation)
    }

    private static func classifyLaunchLocation(for bundleURL: URL) -> LaunchLocation {
        if isInstalledApplicationsLocation(bundleURL) {
            return .applications
        }
        if isMountedReadOnlyVolume(bundleURL) {
            return .mountedDiskImage
        }
        if let downloadsDirectoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
           isContained(bundleURL, in: downloadsDirectoryURL) {
            return .downloads
        }

        let path = bundleURL.path
        if path == "/private/tmp" || path.hasPrefix("/private/tmp/") ||
            path == "/private/var/folders" || path.hasPrefix("/private/var/folders/") {
            return .temporary
        }

        return .other
    }

    private static func isInstalledApplicationsLocation(_ bundleURL: URL) -> Bool {
        let fileManager = FileManager.default
        let applicationsDirectories =
            fileManager.urls(for: .applicationDirectory, in: .localDomainMask) +
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask)

        return applicationsDirectories.contains { directoryURL in
            isContained(bundleURL, in: directoryURL)
        }
    }

    private static func isMountedReadOnlyVolume(_ bundleURL: URL) -> Bool {
        guard bundleURL.path == "/Volumes" || bundleURL.path.hasPrefix("/Volumes/") else {
            return false
        }

        let resourceValues = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return resourceValues?.volumeIsReadOnly == true
    }

    private static func isContained(_ fileURL: URL, in directoryURL: URL) -> Bool {
        let filePath = fileURL.standardizedFileURL.path
        let directoryPath = directoryURL.standardizedFileURL.path

        if filePath == directoryPath {
            return true
        }

        let normalizedDirectoryPath = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return filePath.hasPrefix(normalizedDirectoryPath)
    }

    private static func promptForMoveAndInstallIfNeeded(from bundleURL: URL, location: LaunchLocation) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move to Applications?"
        alert.informativeText = "\(location.contextMessage) Move Crispy to Applications to avoid duplicate Open With entries."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        do {
            let installedURL = try installApplicationToApplications(from: bundleURL)
            try relaunchInstalledApplication(at: installedURL)
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return true
        } catch {
            let failureAlert = NSAlert()
            failureAlert.alertStyle = .warning
            failureAlert.messageText = "Couldn't Move Crispy"
            failureAlert.informativeText = error.localizedDescription
            failureAlert.addButton(withTitle: "OK")
            failureAlert.runModal()
            return false
        }
    }

    private static func installApplicationToApplications(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let applicationsDirectoryURL =
            fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first ??
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        let destinationURL = applicationsDirectoryURL
            .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
            .standardizedFileURL

        guard sourceURL.standardizedFileURL.path != destinationURL.path else {
            return destinationURL
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            let stagingDirectoryURL = fileManager.temporaryDirectory
                .appendingPathComponent("crispyvibes-install-guard", isDirectory: true)
            try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)

            let stagedCopyURL = stagingDirectoryURL
                .appendingPathComponent("Crispy-\(UUID().uuidString).app", isDirectory: true)
            try fileManager.copyItem(at: sourceURL, to: stagedCopyURL)
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagedCopyURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return destinationURL
    }

    private static func relaunchInstalledApplication(at installedURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", installedURL.path]
        try process.run()
    }
}
