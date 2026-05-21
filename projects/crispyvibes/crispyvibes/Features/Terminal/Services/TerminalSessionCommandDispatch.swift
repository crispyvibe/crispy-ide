import Foundation
import os.signpost

@MainActor
extension TerminalSession {
    func suppressActivity(for interval: TimeInterval) {
        let suppressedUntil = Date().addingTimeInterval(interval)
        if suppressedUntil > activitySuppressedUntil {
            activitySuppressedUntil = suppressedUntil
        }
    }

    func markReadyFromOutput(renderableSample: String?) {
        var shouldNotifyObservers = false
        let now = Date()

        if firstRenderableTextSample == nil,
           let normalizedSample = normalizedRenderableOutputSample(renderableSample) {
            firstRenderableTextSample = normalizedSample
            shouldNotifyObservers = true
        }

        if !hasReceivedOutput {
            hasReceivedOutput = true
            firstOutputReceivedAt = now
            shouldNotifyObservers = true
        }
        lastOutputReceivedAt = now

        if shouldNotifyObservers {
            notifyFirstOutputObservers()
        }
        flushPendingCommandsIfReady()
    }

    func markRenderableActivityFromOutput(isInitialOutput: Bool) {
        lastOutputReceivedAt = Date()
        if isInitialOutput,
           Date() < activitySuppressedUntil {
            return
        }
        markActivity()
    }

    func markSignificantActivityFromOutput() {
        lastOutputReceivedAt = Date()
        markActivity()
    }

    func markActivity() {
        scheduleIdleReset()
        if !isCurrentlyActive {
            isCurrentlyActive = true
            onActivityChanged?(true)
        }
    }

    func scheduleIdleReset() {
        idleResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isCurrentlyActive else { return }
                self.isCurrentlyActive = false
                self.onActivityChanged?(false)
            }
        }
        idleResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + idleThreshold, execute: workItem)
    }

    func notifyFirstOutputObservers() {
        for observer in firstOutputObservers.values {
            observer()
        }
    }

    private func normalizedRenderableOutputSample(_ sample: String?) -> String? {
        guard let sample else { return nil }
        let normalized = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(120))
    }

    func enqueueCommand(_ command: String, policy: CommandDispatchPolicy) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        startIfNeeded()
        let pending = PendingCommand(
            text: trimmed,
            policy: policy,
            enqueuedAt: Date()
        )
        if commandDispatchReady(for: pending) {
            dispatchCommand(trimmed)
            return
        }

        pendingCommands.append(pending)
        schedulePendingCommandEvaluationIfNeeded()
    }

    func schedulePendingCommandEvaluationIfNeeded(now: Date = Date()) {
        guard let pending = pendingCommands.first else {
            cancelPendingCommandEvaluation()
            return
        }
        guard !commandDispatchReady(for: pending, now: now) else {
            cancelPendingCommandEvaluation()
            return
        }
        guard let nextDate = nextPendingCommandEvaluationDate(for: pending, now: now) else {
            cancelPendingCommandEvaluation()
            return
        }
        if let pendingCommandEvaluationDeadline,
           abs(pendingCommandEvaluationDeadline.timeIntervalSince(nextDate)) < 0.01,
           pendingCommandEvaluationWorkItem != nil {
            return
        }

        cancelPendingCommandEvaluation()
        pendingCommandEvaluationDeadline = nextDate
        let delay = max(0, nextDate.timeIntervalSince(now))
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingCommandEvaluationWorkItem = nil
                self.pendingCommandEvaluationDeadline = nil
                self.flushPendingCommandsIfReady()
            }
        }
        pendingCommandEvaluationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPendingCommandEvaluation() {
        pendingCommandEvaluationWorkItem?.cancel()
        pendingCommandEvaluationWorkItem = nil
        pendingCommandEvaluationDeadline = nil
    }

    func commandDispatchReady(
        for pending: PendingCommand,
        now: Date = Date()
    ) -> Bool {
        guard engine.processIsRunning,
              engine.shellProcessID > 0 else {
            return false
        }

        let standardDispatchReady =
            now >= activitySuppressedUntil &&
            (hasReceivedOutput || engine.canDispatchStandardCommandsBeforeFirstOutput)

        switch pending.policy {
        case .standard:
            return standardDispatchReady
        case .startup:
            if engine.requiresInteractivePromptForStartupCommands {
                if hasObservedInteractivePrompt {
                    return true
                }
                // Hard fallback only: absolute timeout for shells without shell integration
                let queuedAge = now.timeIntervalSince(pending.enqueuedAt)
                return queuedAge >= startupCommandFallbackDelay * 3
            }
            if standardDispatchReady {
                return true
            }
            let queuedAge = now.timeIntervalSince(pending.enqueuedAt)
            return queuedAge >= startupCommandFallbackDelay
        case .uiInteractive:
            guard hasReceivedOutput else { return false }
            if hasObservedInteractivePrompt {
                return true
            }
            let queuedAge = now.timeIntervalSince(pending.enqueuedAt)
            let hasVisibleHost = hasVisibleTerminalHost()

            if !hasVisibleHost {
                return queuedAge >= uiVisibleHostFallbackDelay
            }

            if !hasReceivedResizeSinceStart {
                return queuedAge >= uiResizeReadyFallbackDelay
            }

            if hasReceivedDirectoryUpdate {
                return true
            }

            return queuedAge >= uiDirectoryReadyFallbackDelay
        }
    }

    func nextPendingCommandEvaluationDate(
        for pending: PendingCommand,
        now: Date
    ) -> Date? {
        var nextDate: Date?

        if pending.policy != .startup,
           activitySuppressedUntil > now {
            nextDate = activitySuppressedUntil
        }

        func schedule(at candidateDate: Date) {
            guard candidateDate > now else { return }
            if let existing = nextDate {
                if candidateDate < existing {
                    nextDate = candidateDate
                }
            } else {
                nextDate = candidateDate
            }
        }

        switch pending.policy {
        case .standard:
            break
        case .startup:
            if engine.requiresInteractivePromptForStartupCommands {
                // Only schedule the hard fallback for shells without integration
                schedule(at: pending.enqueuedAt.addingTimeInterval(startupCommandFallbackDelay * 3))
            } else {
                schedule(at: pending.enqueuedAt.addingTimeInterval(startupCommandFallbackDelay))
            }
        case .uiInteractive:
            let visibleHost = hasVisibleTerminalHost()
            if !visibleHost {
                schedule(at: pending.enqueuedAt.addingTimeInterval(uiVisibleHostFallbackDelay))
            } else if !hasReceivedResizeSinceStart {
                schedule(at: pending.enqueuedAt.addingTimeInterval(uiResizeReadyFallbackDelay))
            } else if !hasReceivedDirectoryUpdate {
                schedule(at: pending.enqueuedAt.addingTimeInterval(uiDirectoryReadyFallbackDelay))
            }
        }

        return nextDate
    }

    func hasVisibleTerminalHost() -> Bool {
        hostedView.window != nil &&
            hostedView.superview != nil &&
            hostedView.bounds.width >= 20 &&
            hostedView.bounds.height >= 20
    }

    func flushPendingCommandsIfReady() {
        guard !pendingCommands.isEmpty else {
            cancelPendingCommandEvaluation()
            return
        }

        while let pending = pendingCommands.first {
            let now = Date()
            guard commandDispatchReady(for: pending, now: now) else {
                schedulePendingCommandEvaluationIfNeeded(now: now)
                return
            }
            pendingCommands.removeFirst()
            dispatchCommand(pending.text)
        }

        cancelPendingCommandEvaluation()
    }

    func clearPendingCommands() {
        cancelPendingCommandEvaluation()
        pendingCommands.removeAll()
    }

    func dispatchCommand(_ command: String) {
        AppDiagnostics.record(
            category: .terminalLifecycle,
            level: .debug,
            event: "terminal_command_sent",
            metadata: [
                "session": self.id.uuidString,
                "command_hash": AppDiagnostics.sha256Hex(command).prefix(12).description
            ]
        )
        os_signpost(
            .event,
            log: AppDiagnostics.terminalSignpostLog,
            name: "TerminalCommandSent",
            "session=%{public}@",
            id.uuidString
        )
        engine.send(text: "\(command)\n")
        recordSentInput("\(command)\n")
    }
}
