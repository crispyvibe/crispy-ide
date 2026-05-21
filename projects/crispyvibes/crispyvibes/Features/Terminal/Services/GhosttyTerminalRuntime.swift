import AppKit
import Foundation
import GhosttyKit

@MainActor
final class GhosttyTerminalRuntime {
    weak var terminalServices: TerminalServices?
    var app: ghostty_app_t?
    var config: ghostty_config_t?
    var callbackContextPointer: UnsafeMutableRawPointer?
    var initialized = false

    var isAvailable: Bool {
        app != nil
    }

    init(terminalServices: TerminalServices) {
        self.terminalServices = terminalServices
        configureProcessEnvironment()
        initializeIfNeeded()
    }

    deinit {
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
        if let callbackContextPointer {
            Unmanaged<GhosttyRuntimeCallbackContext>.fromOpaque(callbackContextPointer).release()
        }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func configureProcessEnvironment() {
        guard let resourceRoot = Self.resourceRootURL() else {
            return
        }

        let ghosttyURL = resourceRoot.appendingPathComponent("ghostty", isDirectory: true)
        let terminfoURL = resourceRoot.appendingPathComponent("terminfo", isDirectory: true)
        if FileManager.default.fileExists(atPath: ghosttyURL.path) {
            setenv("GHOSTTY_RESOURCES_DIR", ghosttyURL.path, 1)
        }

        let resourceRootPath = resourceRoot.path
        let existingDataDirs = ProcessInfo.processInfo.environment["XDG_DATA_DIRS"] ?? ""
        if !existingDataDirs.split(separator: ":").contains(Substring(resourceRootPath)) {
            let joined = existingDataDirs.isEmpty ? resourceRootPath : "\(resourceRootPath):\(existingDataDirs)"
            setenv("XDG_DATA_DIRS", joined, 1)
        }

        let manPath = resourceRoot.appendingPathComponent("man", isDirectory: true).path
        let existingManPath = ProcessInfo.processInfo.environment["MANPATH"] ?? ""
        if FileManager.default.fileExists(atPath: manPath),
           !existingManPath.split(separator: ":").contains(Substring(manPath)) {
            let joined = existingManPath.isEmpty ? manPath : "\(manPath):\(existingManPath)"
            setenv("MANPATH", joined, 1)
        }

        if FileManager.default.fileExists(atPath: terminfoURL.path) {
            setenv("TERMINFO", terminfoURL.path, 1)
        }
        setenv("TERM_PROGRAM", "ghostty", 1)
    }

}
