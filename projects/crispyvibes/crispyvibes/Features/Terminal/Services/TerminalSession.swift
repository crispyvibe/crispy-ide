import AppKit
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
        pendingStartupTask = Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                let resolution = resolutionProvider()
                var environment = Self.launchEnvironment
                // Per-session Agent CLI context (F044-R04). The vibespace ID
                // is resolved server-side from focused state; only the caller's
                // tagged context and project path are injected here.
                environment.append("CRISPY_CONTEXT=terminal.\(terminalID)")
                environment.append("CRISPY_PROJECT_PATH=\(projectPath)")
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
            let tmuxLaunch = TmuxService.launchArguments(
                sessionName: tmuxSessionName,
                shell: shellPath,
                workingDirectory: initialWorkingDirectory.path
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

    /// Records user input both to the per-session insight observer (last-input only)
    /// and to the centralized ComposeHistoryStore (full history, capped).
    func recordSentInput(_ text: String) {
        insightObserver?.recordInput(text)
        // The insight observer accumulates keystrokes and emits lastInput when Enter is pressed.
        // Use that as the authoritative finalized command text, since character-by-character
        // forwarding means `text` alone may just be "\n" when Enter is pressed separately.
        if let finalized = insightObserver?.lastInput,
           !finalized.isEmpty {
            composeHistoryStore?.append(finalized, for: id)
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            composeHistoryStore?.append(trimmed, for: id)
        }
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
