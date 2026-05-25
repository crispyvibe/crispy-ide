import AppKit
import Combine
import Foundation
import os.signpost

@MainActor
final class TerminalSession: NSObject {
    let id: UUID
    let debugID: Int
    let initialWorkingDirectory: URL
    var currentWorkingDirectory: URL
    let terminalServices: TerminalServices
    let engine: any TerminalSessionEngine
    let viewIdentity = UUID()

    var onTitleChanged: ((String) -> Void)?
    var onDirectoryChanged: ((URL?) -> Void)?
    var onProcessTerminated: ((Int32?) -> Void)?
    var onOutputReceived: ((String) -> Void)?
    var onActivityChanged: ((Bool) -> Void)?

    private(set) var isStarted = false
    var idleResetWorkItem: DispatchWorkItem?
    let idleThreshold: TimeInterval = 1.5
    let startupActivitySuppression: TimeInterval = 0.9
    let resizeActivitySuppression: TimeInterval = 0.35
    var startupCommandFallbackDelay: TimeInterval = 3.0
    var isCurrentlyActive = false
    var activitySuppressedUntil = Date.distantPast
    var currentDisplayDensity: TerminalDisplayDensity = .regular
    let focusRetryLimit = 16
    var focusRequestGeneration: UInt = 0
    let shellResolutionProvider: @Sendable () -> TerminalShellResolution
    var operationMetricsStore: OperationMetricsStore?
    var tmuxSessionName: String?
    /// F044-R04: tagged vibespace ID exported to spawned shells as
    /// `CRISPY_VIBESPACE`. Set by `ProjectSession` via the
    /// `sessionConfigurator` hook on `TerminalViewModel`. Nil for
    /// detached/standalone terminals not owned by a vibespace.
    /// F044-R04 / F012: vibespace ID exported via CRISPY_VIBESPACE so the
    /// agent CLI can route requests to the right vibespace runtime.
    /// Set once at session construction by `ProjectSession.wireViewModels`'s
    /// `sessionConfigurator`; not intended to mutate over the session's lifetime.
    /// Kept `var` (rather than `private(set)`/`let`) only because the
    /// `sessionConfigurator` closure is invoked from `TerminalViewModelTabs`
    /// after `init` returns — matching the same pattern used by sibling
    /// fields like `operationMetricsStore` and `tmuxSessionName`.
    var vibespaceID: UUID?
    /// Override for remote SSH terminals. When set, replaces the shell executable/args.
    /// Returns (executable, arguments) to launch instead of the local shell.
    var processLaunchOverride: ((TerminalSession) -> (String, [String]))?
    private var startMetricsTime: Date?
    var hasReceivedOutput = false
    var firstOutputReceivedAt: Date?
    var lastOutputReceivedAt: Date?
    var firstRenderableTextSample: String?
    var hasObservedInteractivePrompt = false
    var hasReceivedDirectoryUpdate = false
    var hasReceivedResizeSinceStart = false
    let uiVisibleHostFallbackDelay: TimeInterval = 1.2
    let uiResizeReadyFallbackDelay: TimeInterval = 2.0
    let uiDirectoryReadyFallbackDelay: TimeInterval = 2.8
    var pendingCommands: [PendingCommand] = []
    var pendingCommandEvaluationWorkItem: DispatchWorkItem?
    var pendingCommandEvaluationDeadline: Date?
    var pendingStartupTask: Task<Void, Never>?
    var firstOutputObservers: [UUID: @MainActor () -> Void] = [:]
    let offscreenStartupCols = 120
    let offscreenStartupRows = 32
    var insightObserver: TerminalInsightObserver?
    /// Per-terminal context-summary state. Persists across UI surface transitions
    /// (board ↔ spotlight ↔ rail). Created when the experimental feature is enabled
    /// at session-construction time. F041-R11.
    var contextSummarySession: TerminalContextSummarySession?
    /// Subscription that mirrors observer-classified visible inputs into the
    /// shared compose history store. F001-T06: this is the single writer to
    /// compose history for both keystroke and compose-UI paths — sensitive
    /// classifications are filtered out at this layer by construction.
    var composeHistorySubscription: AnyCancellable?
    var composeHistoryStore: ComposeHistoryStore?

    enum CommandDispatchPolicy: Sendable {
        case standard
        case startup
        case uiInteractive
    }

    struct PendingCommand {
        let text: String
        let policy: CommandDispatchPolicy
        let enqueuedAt: Date
    }

    init(
        id: UUID,
        workingDirectory: URL,
        terminalServices: TerminalServices,
        engineFactory: @escaping @MainActor (TerminalServices) -> any TerminalSessionEngine = {
            TerminalSession.makeDefaultEngine(terminalServices: $0)
        },
        shellResolutionProvider: @escaping @Sendable () -> TerminalShellResolution = {
            TerminalShellResolver.resolve(context: TerminalShellResolutionContext())
        }
    ) {
        self.id = id
        self.debugID = TerminalDebugID.nextSession()
        self.initialWorkingDirectory = workingDirectory
        self.currentWorkingDirectory = workingDirectory
        self.terminalServices = terminalServices
        self.shellResolutionProvider = shellResolutionProvider
        self.engine = engineFactory(terminalServices)
        super.init()
        self.composeHistoryStore = terminalServices.composeHistoryStore
        configureTerminalEngine()
        terminalServices.diagnosticsSnapshot.register(sessionID: id, sessionDebugID: debugID, engine: engine)
        terminalServices.diagnosticsSnapshot.recordStartupMilestone(sessionID: id) { $0.sessionCreated = Date() }
        TerminalLifecycleLogger.log(event: .sessionCreate, sessionDebugID: debugID, surfaceDebugID: nil, sessionID: id)
    }

    func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        startMetricsTime = Date()

        let signpostID = OSSignpostID(log: AppDiagnostics.terminalSignpostLog)
        os_signpost(
            .begin,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalSessionStart",
            signpostID: signpostID,
            "session=%{public}@",
            id.uuidString
        )

        hasReceivedDirectoryUpdate = false
        hasReceivedResizeSinceStart = false
        hasObservedInteractivePrompt = false
        firstOutputReceivedAt = nil
        lastOutputReceivedAt = nil
        suppressActivity(for: startupActivitySuppression)
        startProcessAsync(signpostID: signpostID)
    }

    func startProcessAsync(signpostID: OSSignpostID) {
        pendingStartupTask?.cancel()
        let resolutionProvider = shellResolutionProvider
        let terminalID = self.id.uuidString
        let projectPath = self.initialWorkingDirectory.path
        let vibespaceID = self.vibespaceID
        pendingStartupTask = Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                let resolution = resolutionProvider()
                var environment = Self.launchEnvironment
                // Per-session Agent CLI context (F044-R04).
                environment.append("CRISPY_CONTEXT=terminal.\(terminalID)")
                environment.append("CRISPY_PROJECT_PATH=\(projectPath)")
                if let vibespaceID {
                    environment.append("CRISPY_VIBESPACE=vibespace.\(vibespaceID.uuidString)")
                }
                return (resolution, environment)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.isStarted else { return }
                self.pendingStartupTask = nil
                self.startProcess(
                    shellResolution: prepared.0,
                    environment: prepared.1,
                    signpostID: signpostID
                )
            }
        }
    }

    func startProcess(
        shellResolution: TerminalShellResolution,
        environment: [String],
        signpostID: OSSignpostID
    ) {
        ensureHeadlessStartupGridSizeIfNeeded()

        let shellPath = shellResolution.selected.executablePath
        let shellArgs = TerminalShellLaunchPolicy.startupArguments

        let executable: String
        let args: [String]

        if let processLaunchOverride {
            let (exe, a) = processLaunchOverride(self)
            executable = exe
            args = a
        } else if let tmuxSessionName, TmuxService.isEnabled, TmuxService.isAvailable {
            // Extract CRISPY_* env vars so tmux can refresh them on reattach
            // (F044-R04 + tmux-session env refresh — see TmuxService.refreshSessionEnvironment).
            var agentCLIEnv: [String: String] = [:]
            for entry in environment {
                let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                guard key.hasPrefix("CRISPY_") else { continue }
                agentCLIEnv[key] = String(parts[1])
            }
            let tmuxLaunch = TmuxService.launchArguments(
                sessionName: tmuxSessionName,
                shell: shellPath,
                workingDirectory: initialWorkingDirectory.path,
                agentCLIEnvironment: agentCLIEnv
            )
            executable = tmuxLaunch.executable
            args = tmuxLaunch.args
        } else {
            executable = shellPath
            args = shellArgs
        }

        engine.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            currentDirectory: initialWorkingDirectory.path
        )

        terminalServices.diagnosticsSnapshot.recordStartupMilestone(sessionID: id) {
            $0.shellLaunched = Date()
            $0.shellExecutable = shellPath
            $0.launchArguments = shellArgs.joined(separator: " ")
            $0.workingDirectoryPath = initialWorkingDirectory.path
        }

        var metadata: [String: String] = [
            "session": self.id.uuidString,
            "shell": shellPath,
            "shell_source": shellResolution.selected.source.rawValue,
            "shell_requested": shellResolution.requested.executablePath,
            "shell_requested_source": shellResolution.requested.source.rawValue,
            "shell_args": shellArgs.joined(separator: " "),
            "cwd": AppDiagnostics.pathToken(self.initialWorkingDirectory.path),
            "tmux": tmuxSessionName != nil && TmuxService.isEnabled ? "yes" : "no"
        ]
        if !shellResolution.rejectedCandidates.isEmpty {
            metadata["shell_rejected_count"] = String(shellResolution.rejectedCandidates.count)
            metadata["shell_rejected_sources"] = shellResolution.rejectedCandidates
                .map(\.source.rawValue)
                .joined(separator: ",")
        }

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .notice,
            event: "terminal_session_started",
            metadata: metadata
        )
        if shellResolution.didFallback {
            AppDiagnostics.record(
                category: .terminalLifecycle,
                level: .notice,
                event: "terminal_shell_fallback_applied",
                metadata: [
                    "session": self.id.uuidString,
                    "requested_shell": shellResolution.requested.executablePath,
                    "requested_source": shellResolution.requested.source.rawValue,
                    "selected_shell": shellResolution.selected.executablePath,
                    "selected_source": shellResolution.selected.source.rawValue
                ]
            )
        }
        os_signpost(
            .end,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalSessionStart",
            signpostID: signpostID,
            "session=%{public}@",
            id.uuidString
        )
        if let startMetricsTime {
            operationMetricsStore?.recordOperation(
                name: "terminal.launch",
                projectContext: initialWorkingDirectory.path,
                startTime: startMetricsTime
            )
        }
    }

    func terminate() {
        pendingStartupTask?.cancel()
        pendingStartupTask = nil
        idleResetWorkItem?.cancel()
        idleResetWorkItem = nil
        firstOutputObservers.removeAll()
        clearPendingCommands()
        composeHistorySubscription?.cancel()
        composeHistorySubscription = nil
        contextSummarySession?.shutdown()
        insightObserver?.shutdown()
        engine.terminate()

        let surfaceStillExists = (engine as? GhosttyTerminalEngine)?.surface != nil
        TerminalLifecycleLogger.log(
            event: .sessionTerminate,
            sessionDebugID: debugID,
            surfaceDebugID: nil,
            sessionID: id,
            reason: .terminate
        )
        TerminalLifecycleLogger.assertSurfaceDestroyedOnTerminate(
            sessionDebugID: debugID,
            surfaceExists: surfaceStillExists
        )
        terminalServices.diagnosticsSnapshot.unregister(sessionID: id)

        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .notice,
            event: "terminal_session_terminated",
            metadata: ["session": self.id.uuidString]
        )
        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalSessionTerminated",
            "session=%{public}@",
            id.uuidString
        )
    }

    @discardableResult
    func addFirstOutputObserver(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let token = UUID()
        firstOutputObservers[token] = observer
        if hasReceivedOutput {
            observer()
        }
        return token
    }

    func removeFirstOutputObserver(_ token: UUID) {
        firstOutputObservers.removeValue(forKey: token)
    }

    func copySelection() {
        engine.copySelection()
    }

    func pasteFromClipboard() {
        engine.pasteFromClipboard()
    }

    func sendCommand(_ command: String) {
        enqueueCommand(command, policy: .standard)
    }

    func sendStartupCommand(_ command: String) {
        enqueueCommand(command, policy: .startup)
    }

    func sendUICommand(_ command: String) {
        enqueueCommand(command, policy: .uiInteractive)
    }

    func sendRawText(_ text: String) {
        startIfNeeded()
        engine.send(text: text)
    }

    /// Records user input submitted from a SwiftUI compose UI (VibeCast,
    /// Spotlight compose, inline triggers). The text was authored in a visible
    /// UI field, so it is classified `.visible` directly by the observer and the
    /// compose-history subscription appends it without surface inspection.
    /// F001-T06, F041-R17.
    func recordSentInput(_ text: String) {
        insightObserver?.recordSubmittedFromComposeUI(text)
    }

    func sendRawTextWithEnter(_ text: String) {
        startIfNeeded()
        recordSentInput("\(text)\n")
        // Vibe Cast TUIs were most reliable when the body was pasted,
        // then submitted after a short pause with normal Return.
        // Keypad Enter also worked in testing and is a viable fallback
        // if Return ever regresses for specific apps.
        sendRawText(
            text,
            deliveryMode: .textInjection,
            submitVariant: .returnKey,
            submitDelay: 0.2
        )
    }

    func sendRawText(
        _ text: String,
        deliveryMode: TerminalTextDeliveryMode,
        submitVariant: TerminalSubmitVariant,
        submitDelay: TimeInterval = 0
    ) {
        startIfNeeded()
        switch deliveryMode {
        case .typedKeys:
            engine.typeCharacters(text)
        case .textInjection:
            engine.send(text: text)
        }

        let submit: @MainActor () -> Void = { [weak self] in
            self?.engine.pressSubmitVariant(submitVariant)
        }
        if submitDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + submitDelay) {
                submit()
            }
        } else {
            submit()
        }
    }

    func recordStartupCompletion() {
        guard let startMetricsTime else { return }
        operationMetricsStore?.recordOperation(
            name: "terminal.startup",
            projectContext: initialWorkingDirectory.path,
            startTime: startMetricsTime
        )
        self.startMetricsTime = nil
    }

    func requestKeyboardFocus() {
        startIfNeeded()
        requestKeyboardFocus(retryCount: 0)
    }

    var hostedView: NSView {
        engine.hostedView
    }

}
