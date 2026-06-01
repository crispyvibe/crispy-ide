import AppKit
import Foundation
import GhosttyKit

@MainActor
extension GhosttyTerminalEngine {
    func syncOutputPollingToVisibility() {
        onOutputPollingSyncRequestedForTesting?()
        guard started else {
            stopOutputPolling()
            return
        }

        if canPollVisibleSurface {
            resumeAppropriateOutputPolling()
        } else {
            stopOutputPolling()
        }
    }

    func handleSurfaceCreated() {
        applyColorSchemePreference()
        applyThemeOverrideIfPossible()
        applyFontSizeToSurface()
        captureVisibleContentsIfNeeded()
        flushPendingTextIfNeeded()
        handleSurfaceSizeDidChange()
        captureVisibleContentsIfNeeded()
    }

    func handleSurfaceSizeDidChange() {
        let dimensions = currentDimensions()
        delegate?.terminalEngine(self, didChangeSizeToCols: dimensions.cols, rows: dimensions.rows)
    }

    func handleTitleChange(_ title: String) {
        _ = markRenderableOutputIfNeeded(sample: title)
        delegate?.terminalEngine(self, didChangeTitle: title)
    }

    func handleCommandFinished(exitCode: Int16, duration: UInt64) {
        if !hasObservedInteractivePrompt {
            markInteractiveAndTransitionToLightweightTracking()
        }
        delegate?.terminalEngineDidReceiveSignificantOutput(self)
    }

    func captureVisibleContentsIfNeeded() {
        guard started else { return }
        let snapshot = terminalView.visibleContents()
        guard snapshot != lastVisibleContents else { return }

        let trimmed = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = trimmed.split(separator: "\n").first.map(String.init)
        lastVisibleContents = snapshot

        // Forward to insight observer if available
        if let session = delegate as? TerminalSession {
            session.insightObserver?.processFrame(snapshot)
        }

        if !trimmed.isEmpty {
            // Skip the login-banner clear for tmux-backed sessions: on reconnect
            // the terminal reattaches to a live session (possibly running an
            // agent), and typing a screen/scrollback clear would wipe it. tmux
            // redraws its pane on attach anyway.
            let isTmuxBacked = (delegate as? TerminalSession)?.tmuxSessionName != nil
            if !hasReportedRenderableOutput,
               !hasAttemptedInitialBannerCleanup,
               !isTmuxBacked,
               GhosttyTerminalEngineSupport.shouldSuppressInitialLoginBanner(in: snapshot) {
                hasAttemptedInitialBannerCleanup = true
                DispatchQueue.main.async { [weak self] in
                    self?.send(text: GhosttyTerminalEngineSupport.startupBootstrapCommand() + "\n")
                }
                return
            }
            if !hasObservedInteractivePrompt,
               GhosttyTerminalEngineSupport.likelyInteractivePrompt(in: snapshot) {
                markInteractiveAndTransitionToLightweightTracking()
            }
            if !markRenderableOutputIfNeeded(sample: sample) {
                delegate?.terminalEngineDidReceiveSignificantOutput(self)
            }
        }
    }

    func handleRenderAction() {
        if !isLightweightTracking {
            captureVisibleContentsIfNeeded()
        }
    }

    func startOutputPolling() {
        guard canPollVisibleSurface else {
            stopOutputPolling()
            return
        }
        let pollingStartTime = CFAbsoluteTimeGetCurrent()
        startPolling(initialDelay: 0.3, repeating: 0.3, updateDiagnostics: true) { [weak self] in
            guard let self else { return }
            if !self.hasObservedInteractivePrompt,
               CFAbsoluteTimeGetCurrent() - pollingStartTime > 5.0 {
                self.markInteractiveAndTransitionToLightweightTracking()
                return
            }
            self.captureVisibleContentsIfNeeded()
        }
    }

    func stopOutputPolling() {
        outputPollTimer?.cancel()
        outputPollTimer = nil
        setPollingActive(false, updateDiagnostics: true)
    }

    func transitionToLightweightTracking() {
        guard !isLightweightTracking else { return }
        isLightweightTracking = true
        lastVisibleContentsHash = lastVisibleContents.hashValue
        // Keep lastVisibleContents populated so currentInteractiveVisibleContents()
        // returns the cached value instead of calling ghostty_surface_read_text()
        // on every mouse move — which leaks through Ghostty's CAllocator.
        stopOutputPolling()
        startLightweightPolling()
    }

    func startLightweightPolling() {
        guard canPollVisibleSurface else {
            stopOutputPolling()
            return
        }
        startPolling(initialDelay: 1.0, repeating: 1.0, updateDiagnostics: false) { [weak self] in
            guard let self else { return }
            let snapshot = self.terminalView.visibleContents()
            let hash = snapshot.hashValue
            guard hash != self.lastVisibleContentsHash else { return }
            self.lastVisibleContentsHash = hash
            self.lastVisibleContents = snapshot
            self.delegate?.terminalEngineDidReceiveSignificantOutput(self)
        }
    }

    private var canPollVisibleSurface: Bool {
        terminalView.window != nil && terminalView.surface != nil
    }

    private func startPolling(
        initialDelay: TimeInterval,
        repeating: TimeInterval,
        updateDiagnostics: Bool,
        handler: @escaping @MainActor () -> Void
    ) {
        stopOutputPolling()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + initialDelay, repeating: repeating)
        timer.setEventHandler { [weak self] in
            guard let self, self.canPollVisibleSurface else { return }
            handler()
        }
        outputPollTimer = timer
        timer.resume()
        setPollingActive(true, updateDiagnostics: updateDiagnostics)
    }

    private func setPollingActive(_ active: Bool, updateDiagnostics: Bool) {
        isPollingActive = active
        guard updateDiagnostics, let sid = sessionID else { return }
        terminalServices.diagnosticsSnapshot.update(sessionID: sid) { $0.pollingActive = active }
    }

    @discardableResult
    private func markRenderableOutputIfNeeded(sample: String?) -> Bool {
        guard !hasReportedRenderableOutput else { return false }
        hasReportedRenderableOutput = true
        startOutputPolling()
        delegate?.terminalEngine(self, didReceiveRenderableOutput: sample)
        return true
    }

    private func markInteractiveAndTransitionToLightweightTracking() {
        hasObservedInteractivePrompt = true
        transitionToLightweightTracking()
        delegate?.terminalEngineDidBecomeInteractive(self)
    }

    func resumeAppropriateOutputPolling() {
        guard started else { return }
        if isLightweightTracking {
            startLightweightPolling()
        } else {
            startOutputPolling()
        }
    }
}
