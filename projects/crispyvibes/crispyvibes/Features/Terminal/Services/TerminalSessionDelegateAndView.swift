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

        if ExperimentalFeaturesService().isTerminalInsightEnabled {
            insightObserver = TerminalInsightObserver()
            insightObserver?.readVisibleScreen = { [weak self] in
                (self?.engine as? GhosttyTerminalEngine)?.lastVisibleContents ?? ""
            }
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
