import Foundation
import SwiftUI

enum VibeLoopFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case paused
    case attention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.Loops.all
        case .active: AppStrings.Loops.active
        case .paused: AppStrings.Loops.paused
        case .attention: AppStrings.Loops.attention
        }
    }

    func includes(_ state: VibeLoopStateSnapshot) -> Bool {
        switch self {
        case .all:
            true
        case .active:
            state.schedule == .enabled || state.execution != .idle
        case .paused:
            state.schedule == .paused
        case .attention:
            state.schedule == .blocked || state.execution == .needsInput
        }
    }
}

extension VibeLoopStatus {
    var title: String {
        switch self {
        case .scheduled: AppStrings.Loops.scheduled
        case .queued: AppStrings.Loops.queued
        case .running: AppStrings.Loops.running
        case .needsInput: AppStrings.Loops.needsYou
        case .paused: AppStrings.Loops.paused
        case .blocked: AppStrings.Loops.blocked
        }
    }

    var color: Color {
        switch self {
        case .scheduled: .blue
        case .queued: .secondary
        case .running: .green
        case .needsInput: .orange
        case .paused: .secondary
        case .blocked: .red
        }
    }
}

extension VibeLoopScheduleState {
    var title: String {
        switch self {
        case .enabled: return AppStrings.Loops.scheduled
        case .paused: return AppStrings.Loops.schedulePaused
        case .blocked: return AppStrings.Loops.blocked
        }
    }
}

extension VibeLoopSchedule {
    var summary: String {
        switch self {
        case .interval(_, let seconds):
            let value: Int
            let unit: String
            if seconds.isMultiple(of: 86_400) {
                value = seconds / 86_400
                unit = AppStrings.Loops.days.lowercased()
            } else if seconds.isMultiple(of: 3_600) {
                value = seconds / 3_600
                unit = AppStrings.Loops.hours.lowercased()
            } else {
                value = seconds / 60
                unit = AppStrings.Loops.minutes.lowercased()
            }
            return "\(AppStrings.Loops.every) \(value) \(unit)"
        case .daily(let hour, let minute, let timeZoneID):
            return "\(AppStrings.Loops.daily) \(AppStrings.Loops.at.lowercased()) \(Self.time(hour, minute)) · \(timeZoneID)"
        case .weekly(let weekdays, let hour, let minute, let timeZoneID):
            let symbols = Calendar.current.shortWeekdaySymbols
            let days = weekdays.sorted().compactMap { day in
                symbols.indices.contains(day - 1) ? symbols[day - 1] : nil
            }.joined(separator: ", ")
            return "\(days) \(AppStrings.Loops.at.lowercased()) \(Self.time(hour, minute)) · \(timeZoneID)"
        }
    }

    private static func time(_ hour: Int, _ minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

extension VibeLoopRunDisposition {
    var title: String {
        switch self {
        case .pending: AppStrings.Loops.runPending
        case .started: AppStrings.Loops.runStarted
        case .skippedActiveRun: AppStrings.Loops.runSkipped
        case .skippedMissed: AppStrings.Loops.runSkipped
        case .blocked: AppStrings.Loops.blocked
        case .creationFailed: AppStrings.Loops.runFailed
        }
    }
}

extension VibeLoopRunRecord {
    var statusTitle: String {
        guard disposition == .started, let taskState else { return disposition.title }
        switch taskState {
        case .running: return AppStrings.Loops.running
        case .needsInput: return AppStrings.Loops.needsYou
        case .stopped: return AppStrings.Loops.runStopped
        case .done: return AppStrings.Loops.runCompleted
        }
    }

    var statusSymbol: String {
        guard disposition == .started, let taskState else {
            switch disposition {
            case .pending: return "clock"
            case .started: return "play.circle.fill"
            case .skippedActiveRun, .skippedMissed: return "minus.circle"
            case .blocked: return "exclamationmark.octagon.fill"
            case .creationFailed: return "xmark.circle.fill"
            }
        }
        switch taskState {
        case .running: return "play.circle.fill"
        case .needsInput: return "exclamationmark.circle.fill"
        case .stopped: return "xmark.circle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var statusColor: Color {
        guard disposition == .started, let taskState else {
            switch disposition {
            case .started: return .green
            case .blocked, .creationFailed: return .red
            case .pending, .skippedActiveRun, .skippedMissed: return .secondary
            }
        }
        switch taskState {
        case .running: return .green
        case .needsInput: return .orange
        case .stopped: return .red
        case .done: return .green
        }
    }

    var statusDetail: String? {
        if let detail { return detail }
        guard taskState == .stopped, let taskStopReason else { return nil }
        switch taskStopReason {
        case .done: return nil
        case .verificationFailed: return AppStrings.VibeLanes.reasonVerificationFailed
        case .timeout: return AppStrings.VibeLanes.reasonTimedOut
        case .stoppedByUser: return AppStrings.VibeLanes.reasonStoppedByYou
        case .error: return AppStrings.VibeLanes.reasonError
        case .missingInput: return AppStrings.VibeLanes.reasonMissingInput
        case .misAuthoredLane: return AppStrings.VibeLanes.reasonMisAuthoredLane
        case .steerLimitReached: return AppStrings.VibeLanes.reasonSteerLimitReached
        }
    }
}

enum VibeLoopScheduleKind: String, CaseIterable, Identifiable {
    case interval
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interval: AppStrings.Loops.interval
        case .daily: AppStrings.Loops.daily
        case .weekly: AppStrings.Loops.weekly
        }
    }
}

enum VibeLoopIntervalUnit: Int, CaseIterable, Identifiable {
    case minutes = 60
    case hours = 3_600
    case days = 86_400

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .minutes: AppStrings.Loops.minutes
        case .hours: AppStrings.Loops.hours
        case .days: AppStrings.Loops.days
        }
    }

    var minimum: Int { self == .minutes ? 15 : 1 }
}

struct VibeLoopEditorScheduleState {
    var kind: VibeLoopScheduleKind
    var intervalValue: Int
    var intervalUnit: VibeLoopIntervalUnit
    var anchor: Date
    var time: Date
    var weekdays: Set<Int>
    var timeZoneID: String

    static func decode(_ schedule: VibeLoopSchedule) -> Self {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: Date())
        switch schedule {
        case .interval(let anchor, let seconds):
            let unit: VibeLoopIntervalUnit = seconds.isMultiple(of: 86_400) ? .days
                : seconds.isMultiple(of: 3_600) ? .hours : .minutes
            return Self(
                kind: .interval,
                intervalValue: seconds / unit.rawValue,
                intervalUnit: unit,
                anchor: anchor,
                time: Date(),
                weekdays: [currentWeekday],
                timeZoneID: TimeZone.current.identifier
            )
        case .daily(let hour, let minute, let zone):
            let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            return Self(
                kind: .daily,
                intervalValue: 15,
                intervalUnit: .minutes,
                anchor: Date(),
                time: time,
                weekdays: [currentWeekday],
                timeZoneID: zone
            )
        case .weekly(let weekdays, let hour, let minute, let zone):
            let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            return Self(
                kind: .weekly,
                intervalValue: 15,
                intervalUnit: .minutes,
                anchor: Date(),
                time: time,
                weekdays: weekdays,
                timeZoneID: zone
            )
        }
    }
}
