// TerminalInsightObserver.swift — Terminal Insight (Phase 18 + F041)
// Traceability: REQ-P18-INS-005 through REQ-P18-INS-016, F041-R17 (sensitive input).

import Foundation

/// A single input event finalized when a command is submitted.
///
/// `.visible` carries the typed text that was either echoed to the terminal screen
/// (for the keystroke path) or authored by the user in a SwiftUI compose field
/// (for the compose-UI path). `.sensitive` indicates a keystroke-path command that
/// the surface never echoed within the classification budget — typically a
/// password / passphrase / OTP / sudo prompt with echo disabled. The actual bytes
/// are never exposed alongside `.sensitive`.
enum RecordedInput: Equatable {
    case visible(String)
    case sensitive
}

/// Diagnostic payload published whenever the keystroke classifier finalizes a
/// `.sensitive` event. Used by the developer-tools surface (F041) to inspect
/// why a given line was classified sensitive — e.g., timing race vs. genuine
/// echo-disabled prompt. The `screenSnapshot` is the last visible-surface
/// content the classifier checked; by definition it does not contain the typed
/// text, so storing / displaying it is safe. `typedText` is the actual line
/// the user submitted — included for diagnostics only and only consumed by the
/// in-memory dev-tools trace; it never reaches the LLM, compose history, or
/// the user-facing timeline. `attempts` counts the immediate synchronous check
/// plus any retries that ran before the budget exhausted.
struct InsightSensitiveClassification: Equatable {
    let screenSnapshot: String
    let typedText: String
    let attempts: Int
    let timestamp: Date

    init(
        screenSnapshot: String,
        typedText: String,
        attempts: Int,
        timestamp: Date = Date()
    ) {
        self.screenSnapshot = screenSnapshot
        self.typedText = typedText
        self.attempts = attempts
        self.timestamp = timestamp
    }
}

/// Configurable retry policy for keystroke-path classification.
///
/// Production runs an immediate synchronous check followed by up to
/// `maxRetries` retries spaced by `retryInterval`, with a hard `timeBudget`
/// ceiling. Tests can compress these values for fast deterministic runs.
struct InsightClassificationPolicy: Equatable {
    var retryInterval: TimeInterval
    var maxRetries: Int
    var timeBudget: TimeInterval

    /// Production policy: immediate + 6 × 150 ms retries, 1 s ceiling.
    static let `default` = InsightClassificationPolicy(
        retryInterval: 0.150,
        maxRetries: 6,
        timeBudget: 1.0
    )
}

/// Observes a single terminal session's input and grid state, publishing structured insights.
///
/// Two input paths feed into a single published stream:
///
/// 1. **Keystroke path** (`recordTypedKeystroke`) — used by `GhosttyTerminalViewInput`
///    when the user types directly into the terminal surface. Characters are
///    accumulated in an internal buffer; on Enter, the buffered command is
///    classified by checking whether the terminal surface ever echoed it.
///    Classification is deferred (immediate + retries) to absorb the
///    keystroke→PTY→shell-echo→render round-trip without leaking content that
///    was never displayed.
///
/// 2. **Compose-UI path** (`recordSubmittedFromComposeUI`) — used by
///    `TerminalSession.recordSentInput` for VibeCast / Spotlight compose / inline
///    triggers. The submitted command is classified `.visible` immediately by
///    trust boundary — the user authored it in a visible SwiftUI field, so no
///    surface inspection is needed. F001-T06, F041-T07.
@MainActor
final class TerminalInsightObserver: ObservableObject {
    /// Most recent finalized input event (visible command or sensitive marker).
    @Published private(set) var lastRecordedInput: RecordedInput?

    /// Convenience: returns the last visible command text, or nil for sensitive / no input.
    /// Sensitive input is intentionally invisible to this accessor.
    var lastInput: String? {
        switch lastRecordedInput {
        case .visible(let text): return text
        case .sensitive, .none: return nil
        }
    }

    @Published private(set) var lastChange: TerminalChangeEvent = .noChange

    /// Retry policy for the keystroke path. Mutable so tests can compress the
    /// timing for deterministic runs.
    var classificationPolicy: InsightClassificationPolicy = .default

    private var inputBuffer = ""
    private let maxInputBuffer = 1024
    private let minSubmittedLength = 2

    private var previousSnapshot: TerminalGridSnapshot?
    private var lastInputTime: Date?
    private var consecutiveFullRedraws = 0
    private var isThrottled = false
    private var lastFrameTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 0.1
    private let streamingThreshold = 3
    private let recentInputWindow: TimeInterval = 0.2

    /// Closure that reads the current visible screen contents. Injected by the session.
    var readVisibleScreen: (() -> String)?

    /// Diagnostic hook fired every time the keystroke classifier finalizes a
    /// `.sensitive` event. Optional — only the developer-tools surface installs
    /// it. Receives a snapshot of the screen at classification time, the
    /// length of the typed line, and the number of visibility checks performed.
    /// F041-T07 diagnostic.
    var onSensitiveClassification: ((InsightSensitiveClassification) -> Void)?

    // MARK: - Pending Classification (keystroke path)

    /// At most one classification is in flight at a time. A new submission
    /// supersedes any pending work for the previous line.
    private var pendingText: String?
    private var pendingStartedAt: Date?
    private var pendingAttempt: Int = 0
    private var pendingWorkItem: DispatchWorkItem?

    // MARK: - Keystroke Path

    /// Records keystrokes typed directly into the terminal surface. The argument
    /// may be one or more characters (e.g., from IME composition or paste).
    /// Newline / carriage return finalizes the buffered command and starts
    /// classification.
    func recordTypedKeystroke(_ text: String) {
        for char in text {
            if char == "\n" || char == "\r" {
                let trimmed = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                inputBuffer = ""
                guard trimmed.count >= minSubmittedLength else { continue }
                startKeystrokeClassification(of: trimmed)
            } else if char == "\u{7f}" || char == "\u{08}" {
                // Backspace / delete: the user is correcting their input. Pop the
                // most recent buffered character so the reconstructed line tracks
                // what is actually on the surface, not the raw keystroke history.
                // Without this the buffer accumulates typed-then-deleted chars
                // and the visibility contains-check spuriously misses, classifying
                // the line as sensitive even though it was a benign correction.
                // Other line-editing keys (Ctrl-U, Ctrl-W, arrows) are not yet
                // honoured — they remain a residual until we adopt OSC 133-based
                // capture (F041 future work).
                if !inputBuffer.isEmpty {
                    inputBuffer.removeLast()
                }
            } else {
                if inputBuffer.isEmpty {
                    // Capture the screen for the prompt that's about to receive
                    // input. F041-R17 (cf. surface-snapshot context for sensitive
                    // diagnostics — held only in observer state).
                }
                inputBuffer.append(char)
                if inputBuffer.count > maxInputBuffer {
                    inputBuffer = String(inputBuffer.suffix(maxInputBuffer))
                }
            }
        }
        lastInputTime = Date()
        if isThrottled {
            isThrottled = false
            consecutiveFullRedraws = 0
        }
    }

    private func startKeystrokeClassification(of text: String) {
        // Cancel any classification still in flight for a previous line — the
        // new submission supersedes it.
        cancelPendingClassification()

        // First check is synchronous. The happy case (echo already rendered when
        // Enter was processed) stays free of any deferral.
        if checkVisibility(of: text) {
            lastRecordedInput = .visible(text)
            return
        }

        // Otherwise, schedule retries.
        pendingText = text
        pendingStartedAt = Date()
        pendingAttempt = 0
        scheduleNextClassificationAttempt()
    }

    private func scheduleNextClassificationAttempt() {
        let work = DispatchWorkItem { [weak self] in
            self?.runClassificationAttempt()
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + classificationPolicy.retryInterval,
            execute: work
        )
    }

    private func runClassificationAttempt() {
        guard let text = pendingText, let start = pendingStartedAt else { return }
        pendingAttempt += 1

        if checkVisibility(of: text) {
            lastRecordedInput = .visible(text)
            clearPendingClassificationState()
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let exhaustedRetries = pendingAttempt >= classificationPolicy.maxRetries
        let exhaustedBudget = elapsed >= classificationPolicy.timeBudget
        if exhaustedRetries || exhaustedBudget {
            // Surface never showed the typed text within the budget — sensitive.
            // Fire the diagnostic hook BEFORE publishing so any developer-tools
            // recorder sees the classification context. Total attempts include
            // the immediate synchronous check (which failed before retries
            // started), so it's `pendingAttempt + 1`. The typed text is passed
            // for the in-memory dev-tools trace; it never reaches the LLM,
            // compose history, or the user-facing timeline.
            let snapshot = readVisibleScreen?() ?? ""
            onSensitiveClassification?(
                InsightSensitiveClassification(
                    screenSnapshot: snapshot,
                    typedText: text,
                    attempts: pendingAttempt + 1
                )
            )
            lastRecordedInput = .sensitive
            clearPendingClassificationState()
            return
        }
        scheduleNextClassificationAttempt()
    }

    private func cancelPendingClassification() {
        pendingWorkItem?.cancel()
        clearPendingClassificationState()
    }

    private func clearPendingClassificationState() {
        pendingText = nil
        pendingStartedAt = nil
        pendingAttempt = 0
        pendingWorkItem = nil
    }

    private func checkVisibility(of text: String) -> Bool {
        guard let reader = readVisibleScreen else { return true }  // no validator → allow
        let screen = reader()
        guard !screen.isEmpty else { return true }
        // Normalize both sides so that wrap-newlines and other whitespace
        // collapse into single spaces. This lets a typed line that the
        // terminal soft-wrapped across rows still match its on-screen
        // representation. The check remains substring containment of the
        // typed text within the rendered surface, so echo-disabled prompts
        // (passwords, OTP) still fail and classify as `.sensitive`.
        return Self.normalizeForVisibilityCheck(screen)
            .contains(Self.normalizeForVisibilityCheck(text))
    }

    /// Collapse runs of whitespace (including newlines, tabs, multiple spaces)
    /// into single spaces. Used by `checkVisibility` so terminal-induced wrap
    /// doesn't cause false-positive sensitive classifications.
    private static func normalizeForVisibilityCheck(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: - Compose-UI Path

    /// Records a complete command submitted from a SwiftUI compose UI (VibeCast,
    /// Spotlight compose, inline triggers, …). The user authored this content in
    /// a visible UI field before pressing Send, so it is classified `.visible`
    /// immediately by trust boundary — no surface inspection.
    ///
    /// Any keystroke classification still in flight is cancelled; the compose
    /// submission supersedes whatever the user may have been typing into the
    /// terminal.
    func recordSubmittedFromComposeUI(_ command: String) {
        cancelPendingClassification()
        inputBuffer = ""

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minSubmittedLength else { return }
        lastRecordedInput = .visible(trimmed)
        lastInputTime = Date()
    }

    // MARK: - Lifecycle

    /// Releases any in-flight classification work. Called from
    /// `TerminalSession.terminate()`.
    func shutdown() {
        cancelPendingClassification()
    }

    /// Called when user starts typing new input — used by other features to track activity.
    func recordKeystroke() {
        lastInputTime = Date()
    }

    // MARK: - Frame Processing

    func processFrame(_ contents: String) {
        let now = Date()

        // Throttle gate: skip frames when in streaming mode
        if isThrottled, now.timeIntervalSince(lastFrameTime) < throttleInterval {
            return
        }
        lastFrameTime = now

        let snapshot = TerminalGridSnapshot(contents: contents)

        guard let previous = previousSnapshot else {
            previousSnapshot = snapshot
            return
        }

        let event = TerminalGridDiff.diff(old: previous.lineHashes, new: snapshot.lineHashes)
        previousSnapshot = snapshot

        // Streaming detection: consecutive full redraws with no recent input
        if case .fullRedraw = event {
            let hasRecentInput = lastInputTime.map { now.timeIntervalSince($0) < recentInputWindow } ?? false
            if !hasRecentInput {
                consecutiveFullRedraws += 1
                if consecutiveFullRedraws >= streamingThreshold {
                    isThrottled = true
                    lastChange = .streamingOutput
                    lastRecordedInput = nil
                    // A pending classification can't be resolved against a screen
                    // that's repainting wholesale — drop it. The corresponding
                    // command will not appear in compose history; this is a
                    // documented residual (TUI launches that race the streaming
                    // threshold).
                    cancelPendingClassification()
                    return
                }
            }
        } else {
            consecutiveFullRedraws = 0
            if isThrottled {
                isThrottled = false
            }
        }

        lastChange = event

        if case .streamingOutput = event {
            lastRecordedInput = nil
            cancelPendingClassification()
        }
    }

    /// Whether the terminal appears to be in a TUI (sustained full redraws).
    var isTUIMode: Bool {
        consecutiveFullRedraws >= streamingThreshold
    }

    /// Clears the overlay (e.g., when user starts typing next command).
    func dismissOverlay() {
        lastRecordedInput = nil
    }
}
