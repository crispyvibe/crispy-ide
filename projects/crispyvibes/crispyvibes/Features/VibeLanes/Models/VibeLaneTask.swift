import Foundation

// F059 — Vibe Lanes execution schema (one run through a lane).
// Mirrors specs/features/ai-agents/vibe-lanes/schema-design.md §2.
// Owned by the execution component; the UI observes it and never mutates it directly.

enum VibeLaneTaskState: String, Codable, Sendable {
    case running
    case needsInput
    case stopped
    case done
}

/// Why a task ended (or stopped at a checkpoint).
enum VibeLaneStopReason: String, Codable, Sendable {
    case done
    case verificationFailed   // attempts exhausted without a passing verification
    case timeout              // checkpoint time limit reached
    case stoppedByUser
    case error                // a transport/tool failure
    case missingInput         // a required carry-forward input was not available
    case misAuthoredLane      // a lane required an input no prior step/user can supply
    case steerLimitReached
}

enum VibeLanePromptKind: String, Codable, Sendable {
    case goal
    case feedback
    case steer
}

enum VibeLaneCheckpointRunStatus: String, Codable, Sendable {
    case pending
    case running
    case needsInput
    case passed
    case stopped
}

enum VibeLaneActivityKind: String, Codable, Sendable {
    case system
    case worker
    case verify
    case input
    case error
}

enum VibeLaneInputRequestKind: String, Codable, Sendable {
    case supply
    case steer
    /// The user takes the reviewer's seat: approve the checkpoint's outcome or
    /// send it back with feedback (checkpoints authored with `humanReview`).
    case review
}

/// The outcome of an independent reviewer checking the checkpoint's outcome.
struct VibeLaneVerificationResult: Codable, Hashable, Sendable {
    var passed: Bool
    /// The reviewer's evidence/summary.
    var detail: String?
    /// Fed back to the worker on a fail.
    var feedback: String?

    init(passed: Bool, detail: String? = nil, feedback: String? = nil) {
        self.passed = passed
        self.detail = detail
        self.feedback = feedback
    }
}

struct VibeLaneActivityLogEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var at: Date
    var kind: VibeLaneActivityKind
    var message: String
    var detail: String?

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        kind: VibeLaneActivityKind,
        message: String,
        detail: String? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.message = message
        self.detail = detail
    }
}

struct VibeLaneInputRequest: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var kind: VibeLaneInputRequestKind
    var checkpointKey: String
    var createdAt: Date
    var prompt: String
    var missingKeys: [String]
    var lastFeedback: String?
    var reason: VibeLaneStopReason?

    init(
        id: UUID = UUID(),
        kind: VibeLaneInputRequestKind,
        checkpointKey: String,
        createdAt: Date = Date(),
        prompt: String,
        missingKeys: [String] = [],
        lastFeedback: String? = nil,
        reason: VibeLaneStopReason? = nil
    ) {
        self.id = id
        self.kind = kind
        self.checkpointKey = checkpointKey
        self.createdAt = createdAt
        self.prompt = prompt
        self.missingKeys = missingKeys
        self.lastFeedback = lastFeedback
        self.reason = reason
    }
}

/// One iteration inside a checkpoint: the agent worked, then verification ran.
struct VibeLaneAttempt: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var index: Int
    var promptKind: VibeLanePromptKind
    var result: VibeLaneVerificationResult?
    var at: Date
    var budgetEpoch: Int

    init(
        id: UUID = UUID(),
        index: Int,
        promptKind: VibeLanePromptKind,
        result: VibeLaneVerificationResult? = nil,
        at: Date = Date(),
        budgetEpoch: Int = 0
    ) {
        self.id = id
        self.index = index
        self.promptKind = promptKind
        self.result = result
        self.at = at
        self.budgetEpoch = budgetEpoch
    }
}

extension VibeLaneAttempt {
    enum CodingKeys: String, CodingKey {
        case id, index, promptKind, result, at, budgetEpoch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        index = try container.decode(Int.self, forKey: .index)
        promptKind = try container.decode(VibeLanePromptKind.self, forKey: .promptKind)
        result = try container.decodeIfPresent(VibeLaneVerificationResult.self, forKey: .result)
        at = try container.decodeIfPresent(Date.self, forKey: .at) ?? Date()
        budgetEpoch = try container.decodeIfPresent(Int.self, forKey: .budgetEpoch) ?? 0
    }
}

/// The record of a task working one checkpoint.
struct VibeLaneCheckpointRun: Codable, Hashable, Identifiable, Sendable {
    var checkpointKey: String
    var status: VibeLaneCheckpointRunStatus
    var stopReason: VibeLaneStopReason?
    var summary: String?
    var attempts: [VibeLaneAttempt]
    var startedAt: Date?
    var endedAt: Date?
    var activeWindowStartedAt: Date?
    var budgetEpoch: Int

    var id: String { checkpointKey }

    init(
        checkpointKey: String,
        status: VibeLaneCheckpointRunStatus = .pending,
        stopReason: VibeLaneStopReason? = nil,
        summary: String? = nil,
        attempts: [VibeLaneAttempt] = [],
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        activeWindowStartedAt: Date? = nil,
        budgetEpoch: Int = 0
    ) {
        self.checkpointKey = checkpointKey
        self.status = status
        self.stopReason = stopReason
        self.summary = summary
        self.attempts = attempts
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeWindowStartedAt = activeWindowStartedAt
        self.budgetEpoch = budgetEpoch
    }
}

extension VibeLaneCheckpointRun {
    enum CodingKeys: String, CodingKey {
        case checkpointKey, status, stopReason, summary, attempts, startedAt, endedAt, activeWindowStartedAt, budgetEpoch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkpointKey = try container.decode(String.self, forKey: .checkpointKey)
        status = try container.decodeIfPresent(VibeLaneCheckpointRunStatus.self, forKey: .status) ?? .pending
        stopReason = try container.decodeIfPresent(VibeLaneStopReason.self, forKey: .stopReason)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        attempts = try container.decodeIfPresent([VibeLaneAttempt].self, forKey: .attempts) ?? []
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        activeWindowStartedAt = try container.decodeIfPresent(Date.self, forKey: .activeWindowStartedAt) ?? startedAt
        budgetEpoch = try container.decodeIfPresent(Int.self, forKey: .budgetEpoch) ?? 0
    }
}

/// One run of a piece of work through a lane. Pins the lane version it runs
/// against so later lane edits never mutate an in-flight or finished task.
struct VibeLaneTask: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var projectPath: String
    var title: String
    var laneID: UUID
    /// The lane content revision this task pinned at creation. The engine runs
    /// (and the UI renders) against this exact revision, resolved from the store,
    /// so later lane edits never change an in-flight or finished task's
    /// checkpoints, order, or verification semantics (R07/S07).
    var laneVersion: Int
    /// ACP agent this task's worker/reviewer sessions use. nil = the app-wide
    /// default agent at send time.
    var agentID: String?
    var state: VibeLaneTaskState
    var stopReason: VibeLaneStopReason?
    var currentCheckpointKey: String
    // ACP sessions (for resume + openable chats).
    var workerSessionRef: String?
    var workerThreadRef: String?
    var reviewerSessionRef: String?      // only when a checkpoint declares a reviewer
    var reviewerThreadRef: String?
    // Live diagnostics for the UI.
    var currentActivity: String?
    var lastVerification: VibeLaneVerificationResult?
    var activityLog: [VibeLaneActivityLogEntry]?
    /// Reserved for later per-task workspace isolation (deferred); nil today.
    var workspaceRef: String?
    /// Accumulating carry-forward: output keys steps declared they `produces`,
    /// mapped to a one-line reference. The engine validates a step's `requires`
    /// against this before entering it. Optional/absent = empty (back-compatible).
    var carryForward: [String: String]?
    /// The final wrap-up written by the worker on the last checkpoint (shown as
    /// the task Outcome). Distinct from the per-step handoff summaries.
    var outcomeSummary: String?
    /// Repo HEAD captured when the task was created, so reviewer evidence can be
    /// scoped to this task's changes. nil = not a git repo (or no commits).
    var repoBaselineRef: String?
    var openInputRequest: VibeLaneInputRequest?
    var steerCount: Int
    var pendingSteerGuidance: String?
    /// A human Review verdict answered while paused, applied by the engine as
    /// the checkpoint's verification result on resume (never re-runs the worker).
    var pendingHumanVerdict: VibeLaneVerificationResult?
    var createdAt: Date
    var updatedAt: Date
    var checkpointRuns: [VibeLaneCheckpointRun]

    init(
        id: UUID = UUID(),
        projectPath: String,
        title: String,
        laneID: UUID,
        laneVersion: Int,
        agentID: String? = nil,
        state: VibeLaneTaskState = .running,
        stopReason: VibeLaneStopReason? = nil,
        currentCheckpointKey: String,
        workerSessionRef: String? = nil,
        workerThreadRef: String? = nil,
        reviewerSessionRef: String? = nil,
        reviewerThreadRef: String? = nil,
        currentActivity: String? = nil,
        lastVerification: VibeLaneVerificationResult? = nil,
        activityLog: [VibeLaneActivityLogEntry]? = [],
        workspaceRef: String? = nil,
        carryForward: [String: String]? = nil,
        outcomeSummary: String? = nil,
        repoBaselineRef: String? = nil,
        openInputRequest: VibeLaneInputRequest? = nil,
        steerCount: Int = 0,
        pendingSteerGuidance: String? = nil,
        pendingHumanVerdict: VibeLaneVerificationResult? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        checkpointRuns: [VibeLaneCheckpointRun] = []
    ) {
        self.id = id
        self.projectPath = projectPath
        self.title = title
        self.laneID = laneID
        self.laneVersion = laneVersion
        self.agentID = agentID
        self.state = state
        self.stopReason = stopReason
        self.currentCheckpointKey = currentCheckpointKey
        self.workerSessionRef = workerSessionRef
        self.workerThreadRef = workerThreadRef
        self.reviewerSessionRef = reviewerSessionRef
        self.reviewerThreadRef = reviewerThreadRef
        self.currentActivity = currentActivity
        self.lastVerification = lastVerification
        self.activityLog = activityLog
        self.workspaceRef = workspaceRef
        self.carryForward = carryForward
        self.outcomeSummary = outcomeSummary
        self.repoBaselineRef = repoBaselineRef
        self.openInputRequest = openInputRequest
        self.steerCount = steerCount
        self.pendingSteerGuidance = pendingSteerGuidance
        self.pendingHumanVerdict = pendingHumanVerdict
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.checkpointRuns = checkpointRuns
    }

    // MARK: - Derived

    var totalAttempts: Int {
        checkpointRuns.reduce(0) { $0 + $1.attempts.count }
    }

    var attemptsOnCurrentCheckpoint: Int {
        guard let run = run(forKey: currentCheckpointKey) else { return 0 }
        return run.attempts.filter { $0.budgetEpoch == run.budgetEpoch }.count
    }

    var isTerminal: Bool {
        state == .done || state == .stopped
    }

    var visibleActivityLog: [VibeLaneActivityLogEntry] {
        (activityLog ?? []).sorted { $0.at < $1.at }
    }

    func run(forKey key: String) -> VibeLaneCheckpointRun? {
        checkpointRuns.first { $0.checkpointKey == key }
    }

    /// Internal consistency check used before replaying a resumed task.
    ///
    /// This intentionally rejects impossible persisted combinations instead of
    /// repairing them in-place. Replay is allowed only when the task state, open
    /// request, checkpoint run status, and steer history agree with the pinned lane.
    func isConsistent(with lane: VibeLaneDefinition) -> Bool {
        guard lane.id == laneID else { return false }
        guard let currentCheckpoint = lane.checkpoint(forKey: currentCheckpointKey) else { return false }
        guard steerCount >= 0, steerCount <= lane.steerLimit else { return false }
        guard Set(checkpointRuns.map(\.checkpointKey)).count == checkpointRuns.count else { return false }

        var consumedSteers = 0
        for runRecord in checkpointRuns {
            guard lane.checkpoint(forKey: runRecord.checkpointKey) != nil else { return false }
            guard runRecord.budgetEpoch >= 0 else { return false }
            consumedSteers += runRecord.budgetEpoch
            for (offset, attempt) in runRecord.attempts.enumerated() {
                guard attempt.index == offset else { return false }
                guard attempt.budgetEpoch >= 0, attempt.budgetEpoch <= runRecord.budgetEpoch else { return false }
            }
            switch runRecord.status {
            case .passed:
                guard runRecord.stopReason == nil else { return false }
            case .stopped, .needsInput:
                break
            case .running, .pending:
                guard runRecord.stopReason == nil else { return false }
            }
        }
        guard consumedSteers <= steerCount else { return false }

        let currentRun = run(forKey: currentCheckpointKey)
        switch state {
        case .running:
            guard openInputRequest == nil else { return false }
            if let currentRun {
                guard currentRun.status == .running || currentRun.status == .pending else { return false }
            }
            return true

        case .needsInput:
            guard let request = openInputRequest,
                  request.checkpointKey == currentCheckpointKey,
                  request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  let currentRun,
                  currentRun.status == .needsInput else { return false }
            return isValid(request: request, checkpoint: currentCheckpoint, run: currentRun, lane: lane)

        case .stopped:
            guard openInputRequest == nil else { return false }
            guard stopReason != .done else { return false }
            guard let reason = stopReason else { return false }
            if reason == .stoppedByUser {
                if let currentRun {
                    guard currentRun.status == .stopped, currentRun.stopReason == .stoppedByUser else { return false }
                }
                return true
            }
            guard let currentRun,
                  currentRun.status == .stopped,
                  currentRun.stopReason == reason else { return false }
            return true

        case .done:
            guard openInputRequest == nil, stopReason == .done else { return false }
            guard lane.orderedCheckpoints.last?.key == currentCheckpointKey else { return false }
            for checkpoint in lane.orderedCheckpoints {
                guard let run = run(forKey: checkpoint.key), run.status == .passed else { return false }
            }
            return true
        }
    }

    private func isValid(
        request: VibeLaneInputRequest,
        checkpoint: VibeLaneCheckpoint,
        run: VibeLaneCheckpointRun,
        lane: VibeLaneDefinition
    ) -> Bool {
        switch request.kind {
        case .supply:
            guard request.reason == nil, request.lastFeedback == nil else { return false }
            guard !request.missingKeys.isEmpty else { return false }
            guard Set(request.missingKeys).count == request.missingKeys.count else { return false }
            let carried = carryForward ?? [:]
            let askUserKeys = Set(checkpoint.askUserInputs.map(\.key))
            for key in request.missingKeys {
                guard askUserKeys.contains(key) else { return false }
                let carriedValue = carried[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard carriedValue.isEmpty else { return false }
            }
            return true

        case .steer:
            guard request.missingKeys.isEmpty else { return false }
            guard checkpoint.bounds.onExhausted == .escalate else { return false }
            guard steerCount < lane.steerLimit else { return false }
            guard request.reason == .verificationFailed || request.reason == .timeout else { return false }
            guard run.stopReason == request.reason else { return false }
            if request.reason == .verificationFailed {
                guard run.attempts.contains(where: { $0.budgetEpoch == run.budgetEpoch && $0.result?.passed == false }) else {
                    return false
                }
            }
            return true

        case .review:
            guard request.missingKeys.isEmpty, request.reason == nil else { return false }
            guard checkpoint.verify.humanReview else { return false }
            return true
        }
    }
}

extension VibeLaneTask {
    enum CodingKeys: String, CodingKey {
        case id, projectPath, title, laneID, laneVersion, agentID, state, stopReason, currentCheckpointKey
        case workerSessionRef, workerThreadRef, reviewerSessionRef, reviewerThreadRef
        case currentActivity, lastVerification, activityLog, workspaceRef, carryForward, outcomeSummary
        case repoBaselineRef, openInputRequest, steerCount, pendingSteerGuidance, pendingHumanVerdict, createdAt, updatedAt, checkpointRuns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectPath = try container.decode(String.self, forKey: .projectPath)
        title = try container.decode(String.self, forKey: .title)
        laneID = try container.decode(UUID.self, forKey: .laneID)
        laneVersion = try container.decode(Int.self, forKey: .laneVersion)
        agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
        state = try container.decodeIfPresent(VibeLaneTaskState.self, forKey: .state) ?? .running
        stopReason = try container.decodeIfPresent(VibeLaneStopReason.self, forKey: .stopReason)
        currentCheckpointKey = try container.decode(String.self, forKey: .currentCheckpointKey)
        workerSessionRef = try container.decodeIfPresent(String.self, forKey: .workerSessionRef)
        workerThreadRef = try container.decodeIfPresent(String.self, forKey: .workerThreadRef)
        reviewerSessionRef = try container.decodeIfPresent(String.self, forKey: .reviewerSessionRef)
        reviewerThreadRef = try container.decodeIfPresent(String.self, forKey: .reviewerThreadRef)
        currentActivity = try container.decodeIfPresent(String.self, forKey: .currentActivity)
        lastVerification = try container.decodeIfPresent(VibeLaneVerificationResult.self, forKey: .lastVerification)
        activityLog = try container.decodeIfPresent([VibeLaneActivityLogEntry].self, forKey: .activityLog) ?? []
        workspaceRef = try container.decodeIfPresent(String.self, forKey: .workspaceRef)
        carryForward = try container.decodeIfPresent([String: String].self, forKey: .carryForward)
        outcomeSummary = try container.decodeIfPresent(String.self, forKey: .outcomeSummary)
        repoBaselineRef = try container.decodeIfPresent(String.self, forKey: .repoBaselineRef)
        openInputRequest = try container.decodeIfPresent(VibeLaneInputRequest.self, forKey: .openInputRequest)
        steerCount = try container.decodeIfPresent(Int.self, forKey: .steerCount) ?? 0
        pendingSteerGuidance = try container.decodeIfPresent(String.self, forKey: .pendingSteerGuidance)
        pendingHumanVerdict = try container.decodeIfPresent(VibeLaneVerificationResult.self, forKey: .pendingHumanVerdict)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        checkpointRuns = try container.decodeIfPresent([VibeLaneCheckpointRun].self, forKey: .checkpointRuns) ?? []
    }
}
