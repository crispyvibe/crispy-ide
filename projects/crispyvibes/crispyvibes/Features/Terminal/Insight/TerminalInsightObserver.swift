// TerminalInsightObserver.swift — Terminal Insight (Phase 18)
// Traceability: REQ-P18-INS-005 through REQ-P18-INS-016

import Foundation

/// Observes a single terminal session's input and grid state, publishing structured insights.
@MainActor
final class TerminalInsightObserver: ObservableObject {
    @Published private(set) var lastInput: String?
    @Published private(set) var lastChange: TerminalChangeEvent = .noChange

    private var inputBuffer = ""
    private let maxInputBuffer = 1024
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

    // MARK: - Input Recording

    func recordInput(_ text: String) {
        for char in text {
            if char == "\n" || char == "\r" {
                let trimmed = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2 {
                    if isVisibleOnScreen(trimmed) {
                        lastInput = trimmed
                    }
                }
                inputBuffer = ""
            } else {
                inputBuffer.append(char)
                if inputBuffer.count > maxInputBuffer {
                    inputBuffer = String(inputBuffer.suffix(maxInputBuffer))
                }
            }
        }
        lastInputTime = Date()

        // Resume full-rate if throttled
        if isThrottled {
            isThrottled = false
            consecutiveFullRedraws = 0
        }
    }

    /// Reads visible screen and checks if the text is present.
    /// If no reader is available, allows through (can't validate).
    private func isVisibleOnScreen(_ text: String) -> Bool {
        guard let reader = readVisibleScreen else { return true }
        let screen = reader()
        guard !screen.isEmpty else { return true }
        return screen.contains(text)
    }

    /// Called when user starts typing new input — dismisses the overlay.
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
                    lastInput = nil
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

        // Dismiss overlay on streaming
        if case .streamingOutput = event {
            lastInput = nil
        }
    }

    /// Whether the terminal appears to be in a TUI (sustained full redraws).
    var isTUIMode: Bool {
        consecutiveFullRedraws >= streamingThreshold
    }

    /// Clears the overlay (e.g., when user starts typing next command).
    func dismissOverlay() {
        lastInput = nil
    }
}
