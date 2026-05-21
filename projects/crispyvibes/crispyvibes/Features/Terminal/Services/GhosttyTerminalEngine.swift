import AppKit
import Foundation
import GhosttyKit

@MainActor
final class GhosttyTerminalEngine: NSObject, TerminalSessionEngine {
    weak var delegate: (any TerminalSessionEngineDelegate)?
    let terminalView = GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 960, height: 520))
    let terminalServices: TerminalServices
    var sessionID: UUID?
    let runtimeConfigURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("crispyvibes-ghostty-\(UUID().uuidString).conf")
    var font: NSFont = AppPreferences.codeFont(size: TerminalDisplayDensity.regular.fontSize) {
        didSet {
            terminalView.setDesiredGridSize(columns: preferredColumns, rows: preferredRows, font: font)
            applyFontSizeToSurface()
        }
    }
    var actionHandlers = TerminalSessionActionHandlers()
    var lastVisibleContents = ""
    var hasReportedRenderableOutput = false
    var pendingExitCode: Int32?
    var preferredColumns = 120
    var preferredRows = 32
    var started = false
    var executablePath = ""
    var launchArgs = [String]()
    var launchEnvironment = [String]()
    var currentDirectoryPath = NSHomeDirectory()
    var currentPalette = AppThemePalette.graphiteDark
    var runtimeConfig: ghostty_config_t?
    var historySize = 10_000
    var pendingTextQueue: [Data] = []
    var pendingTextBytes = 0
    let maxPendingTextBytes = 512 * 1024
    var hasAttemptedInitialBannerCleanup = false
    var hasObservedInteractivePrompt = false
    var outputPollTimer: DispatchSourceTimer?
    var isPollingActive = false
    var isLightweightTracking = false
    var lastVisibleContentsHash: Int = 0
    var surfaceDebugID: Int?
    var sessionDebugID: Int?
    var pendingRendererRecoveryWorkItem: DispatchWorkItem?
    var onOutputPollingSyncRequestedForTesting: (() -> Void)?

    init(terminalServices: TerminalServices) {
        self.terminalServices = terminalServices
        super.init()
        terminalView.engine = self
    }

    deinit {
        pendingRendererRecoveryWorkItem?.cancel()
        pendingRendererRecoveryWorkItem = nil
        outputPollTimer?.cancel()
        outputPollTimer = nil
        if let runtimeConfig {
            ghostty_config_free(runtimeConfig)
        }
        try? FileManager.default.removeItem(at: runtimeConfigURL)
    }

    var hostedView: NSView { terminalView }
    var effectiveAppearance: NSAppearance { terminalView.effectiveAppearance }
    var processIsRunning: Bool {
        guard let surface else { return false }
        return !ghostty_surface_process_exited(surface)
    }
    var shellProcessID: Int32 { processIsRunning ? 1 : 0 }
    var debugIdentifier: String { "ghostty-\(ObjectIdentifier(self).hashValue)" }
    var canDispatchStandardCommandsBeforeFirstOutput: Bool { false }
    var requiresInteractivePromptForStartupCommands: Bool { true }

    var surface: ghostty_surface_t? {
        terminalView.surface
    }

    var canCreateSurface: Bool {
        started && launchCommand != nil
    }

    var launchWorkingDirectory: URL {
        URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
    }

    var initialSurfaceInput: String? {
        GhosttyTerminalEngineSupport.initialSurfaceInput()
    }

    var launchCommand: String? {
        let trimmed = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : shellEscapedCommand(trimmed, args: launchArgs)
    }

    var launchEnvironmentDictionary: [String: String] {
        var resolved = ProcessInfo.processInfo.environment
        for item in launchEnvironment {
            let pieces = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            resolved[pieces[0]] = pieces[1]
        }
        resolved["TERM"] = "xterm-ghostty"
        resolved["TERM_PROGRAM"] = "ghostty"
        return resolved
    }

    var pendingTextForTesting: [String] {
        var pending: [String] = []
        for chunk in pendingTextQueue {
            if chunk == queuedEnterMarker {
                if pending.isEmpty {
                    pending.append("\n")
                } else {
                    pending[pending.count - 1].append("\n")
                }
                continue
            }
            if let text = String(data: chunk, encoding: .utf8) {
                pending.append(text)
            }
        }
        return pending
    }

    func configure(
        delegate: any TerminalSessionEngineDelegate,
        initialFont: NSFont,
        optionAsMetaKey: Bool,
        historySize: Int
    ) {
        self.delegate = delegate
        self.font = initialFont
        self.historySize = historySize
        terminalView.setDesiredGridSize(columns: preferredColumns, rows: preferredRows, font: initialFont)
        _ = optionAsMetaKey
    }

    func copySelection() {
        terminalView.copySelectionToPasteboard()
    }

    func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
            send(text: string)
            return
        }

        if let imagePath = saveClipboardImageIfNeeded() {
            send(text: shellEscapeForTerminal(imagePath))
        }
    }

    func registerOscHandler(code: Int, handler: @escaping (ArraySlice<UInt8>) -> Void) {
        _ = code
        _ = handler
    }

    func updateActionHandlers(_ handlers: TerminalSessionActionHandlers) {
        actionHandlers = handlers
    }

    func handleWorkingDirectoryChange(_ directory: String?) {
        if let directory {
            if let parsedURL = URL(string: directory), parsedURL.isFileURL {
                currentDirectoryPath = parsedURL.standardizedFileURL.path
            } else {
                currentDirectoryPath = URL(fileURLWithPath: directory).standardizedFileURL.path
            }
        }
        delegate?.terminalEngine(self, didUpdateCurrentDirectory: directory)
    }

    func handleOpenURL(_ rawURL: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
            .standardizedFileURL

        // Absolute file paths don't have a scheme — use fileURLWithPath
        if NSString(string: trimmed).isAbsolutePath {
            let fileURL = URL(fileURLWithPath: trimmed)
            let target = TerminalFileSystemTarget(url: fileURL, line: nil, column: nil)
            if terminalServices.routeGhosttyNativeFileSystemTarget(
                target,
                currentDirectoryURL: currentDirectoryURL,
                sessionID: sessionID
            ) {
                return
            } else {
                terminalServices.vibespaceInteraction.open(fileURL)
            }
            return
        }

        guard let url = URL(string: trimmed) else { return }
        if url.isFileURL {
            let target = TerminalFileSystemTarget(url: url, line: nil, column: nil)
            if terminalServices.routeGhosttyNativeFileSystemTarget(
                target,
                currentDirectoryURL: currentDirectoryURL,
                sessionID: sessionID
            ) {
                return
            } else {
                terminalServices.vibespaceInteraction.open(url)
            }
            return
        }

        if !terminalServices.routeGhosttyNativeLinkTarget(
            url,
            currentDirectoryURL: currentDirectoryURL,
            sessionID: sessionID
        ) {
            terminalServices.vibespaceInteraction.open(url)
        }
    }

    func handleSurfaceClosed(processAlive: Bool) {
        if processAlive {
            return
        }
        handleProcessExit(exitCode: pendingExitCode)
    }

    func handleProcessExit(exitCode: Int32?) {
        pendingExitCode = exitCode
        delegate?.terminalEngine(self, didTerminateWithExitCode: exitCode)
    }

    private func saveClipboardImageIfNeeded() -> String? {
        let pasteboard = NSPasteboard.general

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return nil
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let filename = "clipboard-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString.prefix(8)).png"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crispyvibes-terminal-paste", isDirectory: true)
        let fileURL = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }

    private func shellEscapeForTerminal(_ value: String) -> String {
        ShellEscaping.singleQuote(value)
    }
}
