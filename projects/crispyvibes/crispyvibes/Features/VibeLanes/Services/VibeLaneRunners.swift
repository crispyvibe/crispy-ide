import Foundation
import UserNotifications

// F059 — execution-side collaborators for the Vibe Lanes engine.
// All are protocols so the engine is unit-testable with fakes (no shell, no agent, no clock).
//
// Each checkpoint is Work → Verification. A single independent reviewer checks
// the OUTCOME against the checkpoint's authored verification definition.

// MARK: - Worker

/// Result of one worker agent turn.
struct VibeLaneWorkTurn: Sendable {
    var sessionRef: String?
    var threadRef: String?
    /// Whether the turn completed without a transport/tool failure.
    var ok: Bool
    var note: String?
    var responseText: String?
    var engine: VibeLaneEngineSnapshot?

    init(
        sessionRef: String? = nil,
        threadRef: String? = nil,
        ok: Bool = true,
        note: String? = nil,
        responseText: String? = nil,
        engine: VibeLaneEngineSnapshot? = nil
    ) {
        self.sessionRef = sessionRef
        self.threadRef = threadRef
        self.ok = ok
        self.note = note
        self.responseText = responseText
        self.engine = engine
    }
}

/// Drives one worker turn for a checkpoint. The engine treats worker output as
/// untrusted and never reads it to decide a verification. `@MainActor` because
/// the ACP session stack is main-actor isolated.
@MainActor
protocol VibeLaneWorkRunning: AnyObject {
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn
    /// Restore a persisted logical transcript before attaching a fresh process.
    func restoreTranscript(
        sessionRef: String?,
        threadRef: String?,
        projectPath: String,
        engine: VibeLaneEngineConfiguration
    ) async
    /// Release the process while retaining its durable transcript.
    func release(sessionRef: String?)
    /// Release the process and discard the in-memory transcript owner.
    func discard(sessionRef: String?)
}

extension VibeLaneWorkRunning {
    func restoreTranscript(
        sessionRef: String?,
        threadRef: String?,
        projectPath: String,
        engine: VibeLaneEngineConfiguration
    ) async {}
    func release(sessionRef: String?) {}
    func discard(sessionRef: String?) { release(sessionRef: sessionRef) }
    func work(prompt: String, projectPath: String, sessionRef: String?) async -> VibeLaneWorkTurn {
        await work(prompt: prompt, projectPath: projectPath, sessionRef: sessionRef, engine: .default)
    }

    /// Compatibility helper for API callers that still supply only an agent.
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        agentID: String?
    ) async -> VibeLaneWorkTurn {
        await work(
            prompt: prompt,
            projectPath: projectPath,
            sessionRef: sessionRef,
            engine: VibeLaneEngineConfiguration(agentID: agentID)
        )
    }
}

// MARK: - Reviewer

/// What an independent reviewer is asked to evaluate (the checkpoint's outcome).
struct VibeLaneReviewRequest: Sendable {
    var taskTitle: String
    var projectPath: String
    var checkpoint: VibeLaneCheckpoint
    var attemptIndex: Int
    /// Repo HEAD when the task started, so the reviewer's diff can be scoped to
    /// this task's changes rather than the whole working tree. nil = no repo/baseline.
    var engine: VibeLaneEngineConfiguration = .default
    /// Resolved paths to review-only skills. Contents stay on disk and the
    /// reviewer reads their SKILL.md files on demand.
    var reviewSkillsText: String? = nil
}

/// Outcome of a reviewer evaluation. Ambiguous output MUST be `passed == false`.
struct VibeLaneReviewOutcome: Sendable {
    var passed: Bool
    var sessionRef: String?
    var threadRef: String?
    var summary: String?
    var feedback: String?
    /// Evidence the REVIEWER reports for its verdict. The engine gathers none.
    var evidence: String?
    var engine: VibeLaneEngineSnapshot?

    init(
        passed: Bool,
        sessionRef: String? = nil,
        threadRef: String? = nil,
        summary: String? = nil,
        feedback: String? = nil,
        evidence: String? = nil,
        engine: VibeLaneEngineSnapshot? = nil
    ) {
        self.passed = passed
        self.sessionRef = sessionRef
        self.threadRef = threadRef
        self.summary = summary
        self.feedback = feedback
        self.evidence = evidence
        self.engine = engine
    }
}

/// Independent reviewer that checks a checkpoint's outcome against its authored
/// verification definition. Used for every checkpoint.
@MainActor
protocol VibeLaneReviewing: AnyObject {
    func review(_ request: VibeLaneReviewRequest, sessionRef: String?) async -> VibeLaneReviewOutcome
    /// Restore a persisted logical transcript before attaching a fresh process.
    func restoreTranscript(
        sessionRef: String?,
        threadRef: String?,
        projectPath: String,
        engine: VibeLaneEngineConfiguration
    ) async
    /// Release the process while retaining its durable transcript.
    func release(sessionRef: String?)
    /// Release the process and discard the in-memory transcript owner.
    func discard(sessionRef: String?)
}

extension VibeLaneReviewing {
    func restoreTranscript(
        sessionRef: String?,
        threadRef: String?,
        projectPath: String,
        engine: VibeLaneEngineConfiguration
    ) async {}
    func release(sessionRef: String?) {}
    func discard(sessionRef: String?) { release(sessionRef: sessionRef) }
}

// MARK: - Notifier

/// Notifies the user when a task needs them (Supply or Steer). The vision
/// requires Needs-you moments to be surfaced with a notification, not just
/// dashboard sorting — unattended work is only manageable if pauses are loud.
@MainActor
protocol VibeLaneNotifying: AnyObject {
    func notifyNeedsInput(_ task: VibeLaneTask)
}

/// User-notification-center-backed notifier. No-ops when the process has no
/// bundle (unit tests) or the user declined notification permission.
@MainActor
final class VibeLaneUserNotifier: VibeLaneNotifying {
    func notifyNeedsInput(_ task: VibeLaneTask) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = AppStrings.VibeLanes.notificationNeedsYouTitle
        content.body = AppStrings.VibeLanes.notificationNeedsYouBody(task: task.title)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "vibelane-needs-input-\(task.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    center.add(request)
                }
            case .authorized, .provisional:
                center.add(request)
            default:
                break
            }
        }
    }
}

// MARK: - Clock

/// Injectable clock so timeout bounds are testable.
protocol VibeLaneClock: Sendable {
    var now: Date { get }
}

// MARK: - Real implementations

struct VibeLaneSystemClock: VibeLaneClock {
    var now: Date { Date() }
}

/// Placeholder worker used in tests/previews and as a safe default. Reports a
/// tool failure so a misconfigured engine stops loudly rather than spinning.
@MainActor
final class VibeLaneUnimplementedWorkRunner: VibeLaneWorkRunning {
    func work(
        prompt: String,
        projectPath: String,
        sessionRef: String?,
        engine: VibeLaneEngineConfiguration
    ) async -> VibeLaneWorkTurn {
        VibeLaneWorkTurn(sessionRef: sessionRef, ok: false, note: "worker not configured")
    }
}

/// Safe default reviewer for previews/misconfiguration: fails closed.
@MainActor
final class VibeLaneUnavailableReviewer: VibeLaneReviewing {
    func review(_ request: VibeLaneReviewRequest, sessionRef: String?) async -> VibeLaneReviewOutcome {
        VibeLaneReviewOutcome(passed: false, sessionRef: sessionRef, summary: "no reviewer configured", feedback: "No reviewer is configured to verify this checkpoint.")
    }
}
