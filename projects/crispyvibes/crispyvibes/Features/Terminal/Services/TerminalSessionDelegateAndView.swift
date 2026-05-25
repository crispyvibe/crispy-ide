import Combine
import Foundation
import os.signpost

@MainActor
extension TerminalSession: TerminalSessionEngineDelegate {
    func terminalEngine(_ engine: any TerminalSessionEngine, didChangeSizeToCols cols: Int, rows: Int) {
        suppressActivity(for: resizeActivitySuppression)
        if cols > 0, rows > 0 {
            hasReceivedResizeSinceStart = true
            flushPendingCommandsIfReady()
        }
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didChangeTitle title: String) {
        onTitleChanged?(title)
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didUpdateCurrentDirectory directory: String?) {
        hasReceivedDirectoryUpdate = true
        flushPendingCommandsIfReady()
        guard let directory else {
            onDirectoryChanged?(nil)
            return
        }

        if let parsedURL = URL(string: directory), parsedURL.isFileURL {
            let resolvedURL = parsedURL.standardizedFileURL
            currentWorkingDirectory = resolvedURL
            onDirectoryChanged?(resolvedURL)
            return
        }

        let resolvedURL = URL(fileURLWithPath: directory).standardizedFileURL
        currentWorkingDirectory = resolvedURL
        onDirectoryChanged?(resolvedURL)
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didTerminateWithExitCode exitCode: Int32?) {
        idleResetWorkItem?.cancel()
        idleResetWorkItem = nil
        if isCurrentlyActive {
            isCurrentlyActive = false
            onActivityChanged?(false)
        }
        clearPendingCommands()
        onProcessTerminated?(exitCode)
        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .notice,
            event: "terminal_process_exit",
            metadata: [
                "session": self.id.uuidString,
                "exit_code": exitCode.map(String.init) ?? "none"
            ]
        )
        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalProcessExited",
            "session=%{public}@ code=%{public}@",
            id.uuidString,
            exitCode.map(String.init) ?? "none"
        )
    }

    func terminalEngine(_ engine: any TerminalSessionEngine, didReceiveRenderableOutput sample: String?) {
        let isInitialOutput = !hasReceivedOutput
        markReadyFromOutput(renderableSample: sample)
        markRenderableActivityFromOutput(isInitialOutput: isInitialOutput)
        if let sample, !sample.isEmpty {
            onOutputReceived?(sample)
        }
        if isInitialOutput {
            terminalServices.diagnosticsSnapshot.recordStartupMilestone(sessionID: id) { $0.firstRenderObserved = Date() }
        }
    }

    func terminalEngineDidBecomeInteractive(_ engine: any TerminalSessionEngine) {
        hasObservedInteractivePrompt = true
        flushPendingCommandsIfReady()
        terminalServices.diagnosticsSnapshot.recordStartupMilestone(sessionID: id) { $0.firstInteractivePromptObserved = Date() }
        recordStartupCompletion()
    }

    func terminalEngineDidReceiveSignificantOutput(_ engine: any TerminalSessionEngine) {
        markSignificantActivityFromOutput()
    }

    func configureTerminalEngine() {
        engine.sessionID = id
        if let ghosttyEngine = engine as? GhosttyTerminalEngine {
            ghosttyEngine.sessionDebugID = debugID
        }
        engine.configure(
            delegate: self,
            initialFont: AppPreferences.codeFont(size: TerminalDisplayDensity.regular.fontSize),
            optionAsMetaKey: true,
            historySize: TerminalMemoryBudget.scrollbackLines
        )
        engine.registerOscHandler(code: 697) { _ in }
        applySystemAppearance()

        let observer = TerminalInsightObserver()
        observer.readVisibleScreen = { [weak self] in
            // Read live from Ghostty's surface every check. The engine's
            // `lastVisibleContents` is only refreshed on a ~1 s lightweight
            // polling heartbeat after the first interactive prompt, which is
            // too stale to race the deferred classification budget. The live
            // read is a single `ghostty_surface_read_text` call — cheap enough
            // to invoke up to seven times per Enter (immediate + retries).
            guard let engine = self?.engine as? GhosttyTerminalEngine else { return "" }
            return engine.terminalView.visibleContents()
        }
        // Install diagnostic hooks (e.g., sensitive-classification recorder)
        // before publishing the observer. F041-T07.
        terminalServices.insightObserverConfigurator?(observer)
        insightObserver = observer

        // Compose history is fed by the observer's classification stream so that
        // sensitive keystroke-path input (echo-disabled prompts) is never
        // appended. F001-T06, F041-T07.
        composeHistorySubscription = observer.$lastRecordedInput
            .compactMap { $0 }
            .sink { [weak self] event in
                guard let self else { return }
                if case .visible(let text) = event, !text.isEmpty {
                    self.composeHistoryStore?.append(text, for: self.id)
                }
            }

        // Per-terminal AI summary session is opt-in via the experimental flag, encoded
        // in the factory provided by `AppContainer.makeDefault()`. When disabled the
        // factory returns nil and only the observer (which feeds compose-history) is
        // wired. F041-R11.
        if let summarySession = terminalServices.contextSummarySessionFactory?(observer) {
            summarySession.start()
            contextSummarySession = summarySession
        }
    }

    func ensureHeadlessStartupGridSizeIfNeeded() {
        let dims = engine.currentDimensions()
        guard dims.cols <= 2 || dims.rows <= 1 else { return }
        engine.resize(cols: offscreenStartupCols, rows: offscreenStartupRows)
    }

    func updateActionHandlers(_ handlers: TerminalSessionActionHandlers) {
        engine.updateActionHandlers(handlers)
    }
}
