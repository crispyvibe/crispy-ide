import AppKit
import Foundation
import XCTest
@testable import CrispyVibes

func makeTempDirectory(prefix: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
    let url = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
func waitForCondition(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.05,
    condition: @escaping () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
    return condition()
}

func decodeJSON<T: Decodable>(_ text: String?) throws -> T {
    let payload = try XCTUnwrap(text)
    return try JSONDecoder().decode(T.self, from: Data(payload.utf8))
}

func captureUserDefaultsSnapshot(
    keys: [String],
    defaults: UserDefaults = .standard
) -> [String: Any?] {
    var snapshot: [String: Any?] = [:]
    for key in keys {
        snapshot[key] = defaults.object(forKey: key)
    }
    return snapshot
}

func restoreUserDefaultsSnapshot(
    _ snapshot: [String: Any?],
    defaults: UserDefaults = .standard
) {
    for (key, value) in snapshot {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

@discardableResult
func withUserDefaultsSnapshot<T>(
    keys: [String],
    defaults: UserDefaults = .standard,
    perform: () throws -> T
) rethrows -> T {
    let snapshot = captureUserDefaultsSnapshot(keys: keys, defaults: defaults)
    defer {
        restoreUserDefaultsSnapshot(snapshot, defaults: defaults)
    }
    return try perform()
}

private func loadBuiltProductInfoPlist() -> [String: Any]? {
    let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
    for bundle in bundles {
        guard let info = bundle.infoDictionary else {
            continue
        }
        let identifier = (info["CFBundleIdentifier"] as? String) ?? bundle.bundleIdentifier ?? ""
        let displayName = info["CFBundleDisplayName"] as? String
        if identifier == "com.crispyvibe.app" || displayName == "Crispy" {
            return info
        }
    }
    return nil
}

func loadRepositoryInfoPlist(filePath: String = #filePath) throws -> [String: Any] {
    if let runtimeInfo = loadBuiltProductInfoPlist() {
        return runtimeInfo
    }

    let fileURL = URL(fileURLWithPath: filePath)
    let repositoryRoot = fileURL
        .deletingLastPathComponent() // unit
        .deletingLastPathComponent() // tests
        .deletingLastPathComponent() // crispyvibes
        .deletingLastPathComponent() // projects
        .deletingLastPathComponent() // repo root
    let infoPlistURL = repositoryRoot.appendingPathComponent("projects/crispyvibes/crispyvibes/Info.plist")
    let dictionary = NSDictionary(contentsOf: infoPlistURL)
    return try XCTUnwrap(dictionary as? [String: Any])
}

func gitAvailable() throws -> Bool {
    let result = try runProcess(executable: "/usr/bin/env", arguments: ["git", "--version"], workingDirectory: nil)
    return result.terminationStatus == 0
}

@discardableResult
func runProcess(
    executable: String,
    arguments: [String],
    workingDirectory: URL?
) throws -> (terminationStatus: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let workingDirectory {
        process.currentDirectoryURL = workingDirectory
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, stdout, stderr)
}
