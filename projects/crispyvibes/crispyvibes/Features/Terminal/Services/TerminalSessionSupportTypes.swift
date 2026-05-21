import AppKit
import Foundation
import SwiftTerm

enum TerminalMemoryBudget {
    static let scrollbackLines = 2_000
    static let swiftTermKittyImageCacheLimitBytes = 32 * 1024 * 1024
}

@MainActor
final class TerminalServices {
    let focusCoordinator: TerminalFocusCoordinator
    let diagnosticsSnapshot: TerminalDiagnosticsSnapshot
    let hostOwnershipCoordinator: TerminalHostOwnershipCoordinator
    let vibespaceInteraction: VibeSpaceInteractionService
    let composeHistoryStore: ComposeHistoryStore?
    lazy var ghosttyRuntime = GhosttyTerminalRuntime(terminalServices: self)

    init(
        focusCoordinator: TerminalFocusCoordinator,
        diagnosticsSnapshot: TerminalDiagnosticsSnapshot,
        hostOwnershipCoordinator: TerminalHostOwnershipCoordinator,
        vibespaceInteraction: VibeSpaceInteractionService,
        composeHistoryStore: ComposeHistoryStore? = nil
    ) {
        self.focusCoordinator = focusCoordinator
        self.diagnosticsSnapshot = diagnosticsSnapshot
        self.hostOwnershipCoordinator = hostOwnershipCoordinator
        self.vibespaceInteraction = vibespaceInteraction
        self.composeHistoryStore = composeHistoryStore
    }

    convenience init() {
        self.init(
            focusCoordinator: TerminalFocusCoordinator(),
            diagnosticsSnapshot: TerminalDiagnosticsSnapshot(),
            hostOwnershipCoordinator: TerminalHostOwnershipCoordinator(),
            vibespaceInteraction: VibeSpaceInteractionService()
        )
    }

    func activeGhosttyEngines() -> [GhosttyTerminalEngine] {
        diagnosticsSnapshot.entries.values.compactMap { entry in
            entry.engine as? GhosttyTerminalEngine
        }
    }

    @discardableResult
    func routeGhosttyNativeLinkTarget(_ url: URL, currentDirectoryURL: URL?, sessionID: UUID?) -> Bool {
        var userInfo: [String: Any] = [AppCommandUserInfoKey.url: url]
        if let currentDirectoryURL {
            userInfo[AppCommandUserInfoKey.currentDirectoryURL] = currentDirectoryURL
        }
        if let sessionID {
            userInfo[AppCommandUserInfoKey.sessionID] = sessionID
        }
        NotificationCenter.default.post(
            name: .ghosttyOpenLinkTargetRequested,
            object: nil,
            userInfo: userInfo
        )
        return true
    }

    @discardableResult
    func routeGhosttyNativeFileSystemTarget(
        _ target: TerminalFileSystemTarget,
        currentDirectoryURL: URL?,
        sessionID: UUID?
    ) -> Bool {
        var userInfo: [String: Any] = [AppCommandUserInfoKey.url: target.url]
        if let currentDirectoryURL {
            userInfo[AppCommandUserInfoKey.currentDirectoryURL] = currentDirectoryURL
        }
        if let sessionID {
            userInfo[AppCommandUserInfoKey.sessionID] = sessionID
        }
        if let line = target.line {
            userInfo[AppCommandUserInfoKey.line] = line
        }
        if let column = target.column {
            userInfo[AppCommandUserInfoKey.column] = column
        }
        NotificationCenter.default.post(
            name: .ghosttyOpenFileSystemTargetRequested,
            object: nil,
            userInfo: userInfo
        )
        return true
    }
}

enum TerminalDisplayDensity: Equatable, Sendable {
    case regular
    case compact

    var fontSize: CGFloat {
        switch self {
        case .regular:
            return AppPreferences.codeFontSize()
        case .compact:
            return AppPreferences.railTerminalCompactFontSize()
        }
    }
}

enum TerminalTextDeliveryMode: Sendable {
    case typedKeys
    case textInjection
}

enum TerminalSubmitVariant: String, CaseIterable, Identifiable, Sendable {
    case returnKey
    case keypadEnter
    case controlJ
    case controlM
    case lineFeedByte
    case carriageReturnByte

    var id: String { rawValue }
}

enum CommandPathResolver {
    static func searchPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> [String] {
        let defaultPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/bin"
        ]

        let configuredPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidatePaths = configuredPaths + defaultPaths

        var resolvedPaths: [String] = []
        var seenPaths = Set<String>()
        for rawPath in candidatePaths {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seenPaths.insert(trimmed).inserted else { continue }
            resolvedPaths.append(trimmed)
        }
        return resolvedPaths
    }

    static func resolvedPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        searchPaths(environment: environment, homeDirectory: homeDirectory)
            .joined(separator: ":")
    }

    static func environmentWithResolvedPath(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["PATH"] = resolvedPath(environment: baseEnvironment, homeDirectory: homeDirectory)
        return environment
    }
}

@MainActor
struct TerminalSessionActionHandlers {
    var onSplitTerminalRequested: (() -> Void)? = nil
    var onTemporaryTerminalRequested: (() -> Void)? = nil
    var onOpenInEditorPaneRequested: (() -> Void)? = nil
    var onLinkTargetActivated: ((URL) -> Void)? = nil
    var onFileSystemTargetActivated: ((TerminalFileSystemTarget) -> Void)? = nil
    var onInlineTriggerTextInput: ((String) -> Bool)? = nil
    var onInlineTriggerCommand: ((TerminalInlineTriggerCommand) -> Bool)? = nil
    var currentDirectoryProvider: (() -> URL?)? = nil
}

@MainActor
protocol TerminalSessionEngineDelegate: AnyObject {
    func terminalEngine(_ engine: any TerminalSessionEngine, didChangeSizeToCols cols: Int, rows: Int)
    func terminalEngine(_ engine: any TerminalSessionEngine, didChangeTitle title: String)
    func terminalEngine(_ engine: any TerminalSessionEngine, didUpdateCurrentDirectory directory: String?)
    func terminalEngine(_ engine: any TerminalSessionEngine, didTerminateWithExitCode exitCode: Int32?)
    func terminalEngine(_ engine: any TerminalSessionEngine, didReceiveRenderableOutput sample: String?)
    func terminalEngineDidBecomeInteractive(_ engine: any TerminalSessionEngine)
    func terminalEngineDidReceiveSignificantOutput(_ engine: any TerminalSessionEngine)
}

@MainActor
protocol TerminalSessionEngine: AnyObject {
    var hostedView: NSView { get }
    var effectiveAppearance: NSAppearance { get }
    var font: NSFont { get set }
    var processIsRunning: Bool { get }
    var shellProcessID: Int32 { get }
    var debugIdentifier: String { get }
    var canDispatchStandardCommandsBeforeFirstOutput: Bool { get }
    var requiresInteractivePromptForStartupCommands: Bool { get }
    var sessionID: UUID? { get set }

    func configure(
        delegate: any TerminalSessionEngineDelegate,
        initialFont: NSFont,
        optionAsMetaKey: Bool,
        historySize: Int
    )
    func startProcess(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String
    )
    func terminate()
    func copySelection()
    func pasteFromClipboard()
    func send(text: String)
    func typeCharacters(_ text: String)
    func pressEnter()
    func pressSubmitVariant(_ variant: TerminalSubmitVariant)
    func registerOscHandler(code: Int, handler: @escaping (ArraySlice<UInt8>) -> Void)
    func currentDimensions() -> (cols: Int, rows: Int)
    func resize(cols: Int, rows: Int)
    func updateActionHandlers(_ handlers: TerminalSessionActionHandlers)
    func applyThemePalette(_ palette: AppThemePalette)
    func setSurfaceFocus(_ focused: Bool)
}

extension TerminalSessionEngine {
    var canDispatchStandardCommandsBeforeFirstOutput: Bool { false }
    var requiresInteractivePromptForStartupCommands: Bool { false }
    func pressEnter() { pressSubmitVariant(.returnKey) }
    func pressSubmitVariant(_ variant: TerminalSubmitVariant) {
        switch variant {
        case .returnKey, .keypadEnter, .controlM, .carriageReturnByte:
            send(text: "\r")
        case .controlJ, .lineFeedByte:
            send(text: "\n")
        }
    }
    func setSurfaceFocus(_ focused: Bool) {}
}
