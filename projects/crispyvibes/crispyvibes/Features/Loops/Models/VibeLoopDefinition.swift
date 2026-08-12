import CryptoKit
import Foundation

enum VibeLoopMissedRunPolicy: String, Codable, CaseIterable, Sendable {
    case runLatestOnce
    case skip
}

enum VibeLoopSchedule: Codable, Hashable, Sendable {
    case interval(anchor: Date, seconds: Int)
    case daily(hour: Int, minute: Int, timeZoneID: String)
    case weekly(weekdays: Set<Int>, hour: Int, minute: Int, timeZoneID: String)
}

struct VibeLoopDefinition: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var projectPath: String
    var taskInstruction: String
    var laneID: UUID
    var laneVersion: Int
    var laneSnapshot: VibeLaneDefinition
    var schedule: VibeLoopSchedule
    var missedRunPolicy: VibeLoopMissedRunPolicy
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        projectPath: String,
        taskInstruction: String,
        laneSnapshot: VibeLaneDefinition,
        schedule: VibeLoopSchedule,
        missedRunPolicy: VibeLoopMissedRunPolicy = .runLatestOnce,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.projectPath = projectPath
        self.taskInstruction = taskInstruction
        self.laneID = laneSnapshot.id
        self.laneVersion = laneSnapshot.version
        self.laneSnapshot = laneSnapshot
        self.schedule = schedule
        self.missedRunPolicy = missedRunPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func updateLaneSnapshot(_ lane: VibeLaneDefinition) {
        laneSnapshot = lane
        laneID = lane.id
        laneVersion = lane.version
        updatedAt = Date()
    }
}

enum VibeLoopFailureKind: String, Codable, Hashable, Sendable {
    case invalidProject
    case invalidLane
    case invalidSchedule
    case persistence
    case taskCreation
}

struct VibeLoopFailure: Codable, Hashable, Sendable {
    var kind: VibeLoopFailureKind
    var detail: String
    var at: Date
}

struct VibeLoopRuntimeState: Codable, Hashable, Sendable {
    var loopID: UUID
    var lastClaimedScheduledAt: Date?
    var lastTriggeredAt: Date?
    var lastTaskID: UUID?
    var lastFailure: VibeLoopFailure?

    init(
        loopID: UUID,
        lastClaimedScheduledAt: Date? = nil,
        lastTriggeredAt: Date? = nil,
        lastTaskID: UUID? = nil,
        lastFailure: VibeLoopFailure? = nil
    ) {
        self.loopID = loopID
        self.lastClaimedScheduledAt = lastClaimedScheduledAt
        self.lastTriggeredAt = lastTriggeredAt
        self.lastTaskID = lastTaskID
        self.lastFailure = lastFailure
    }
}

enum VibeLoopRunDisposition: String, Codable, Hashable, Sendable {
    case pending
    case started
    case skippedActiveRun
    case skippedMissed
    case blocked
    case creationFailed
}

struct VibeLoopRunRecord: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var loopID: UUID
    var scheduledAt: Date
    var triggeredAt: Date?
    var disposition: VibeLoopRunDisposition
    var taskID: UUID?
    var taskState: VibeLaneTaskState?
    var taskStopReason: VibeLaneStopReason?
    var taskUpdatedAt: Date?
    var detail: String?

    init(
        id: UUID,
        loopID: UUID,
        scheduledAt: Date,
        triggeredAt: Date? = nil,
        disposition: VibeLoopRunDisposition,
        taskID: UUID? = nil,
        taskState: VibeLaneTaskState? = nil,
        taskStopReason: VibeLaneStopReason? = nil,
        taskUpdatedAt: Date? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.loopID = loopID
        self.scheduledAt = scheduledAt
        self.triggeredAt = triggeredAt
        self.disposition = disposition
        self.taskID = taskID
        self.taskState = taskState
        self.taskStopReason = taskStopReason
        self.taskUpdatedAt = taskUpdatedAt
        self.detail = detail
    }
}

enum VibeLoopStatus: Equatable, Sendable {
    case scheduled
    case queued
    case running
    case needsInput
    case paused
    case blocked
}

enum VibeLoopScheduleState: Equatable, Sendable {
    case enabled
    case paused
    case blocked
}

enum VibeLoopExecutionState: Equatable, Sendable {
    case idle
    case queued
    case running
    case needsInput
}

struct VibeLoopStateSnapshot: Equatable, Sendable {
    var schedule: VibeLoopScheduleState
    var execution: VibeLoopExecutionState
    var activeTaskID: UUID?

    var status: VibeLoopStatus {
        switch execution {
        case .queued:
            return .queued
        case .running:
            return .running
        case .needsInput:
            return .needsInput
        case .idle:
            switch schedule {
            case .enabled: return .scheduled
            case .paused: return .paused
            case .blocked: return .blocked
            }
        }
    }
}

struct VibeLoopProjectOption: Identifiable, Hashable, Sendable {
    var path: String
    var name: String

    var id: String { path }
}

enum VibeLoopOccurrenceID {
    static func make(loopID: UUID, scheduledAt: Date) -> UUID {
        var payload = Data(loopID.uuidString.utf8)
        var bits = scheduledAt.timeIntervalSince1970.bitPattern.bigEndian
        withUnsafeBytes(of: &bits) { payload.append(contentsOf: $0) }
        let hex = SHA256.hash(data: payload)
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let first = String(hex.prefix(8))
        let second = String(hex.dropFirst(8).prefix(4))
        let third = String(hex.dropFirst(12).prefix(4))
        let fourth = String(hex.dropFirst(16).prefix(4))
        let fifth = String(hex.dropFirst(20).prefix(12))
        let value = "\(first)-\(second)-\(third)-\(fourth)-\(fifth)"
        return UUID(uuidString: value)!
    }
}
