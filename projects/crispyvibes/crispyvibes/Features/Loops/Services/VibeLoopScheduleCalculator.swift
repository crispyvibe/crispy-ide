import Foundation

enum VibeLoopScheduleValidationError: Error, Equatable {
    case intervalTooShort
    case invalidTime
    case invalidTimeZone
    case missingWeekday
    case invalidWeekday
}

enum VibeLoopScheduleCalculator {
    static let minimumIntervalSeconds = 15 * 60
    static let maximumIntervalSeconds = 366 * 24 * 60 * 60

    static func validate(_ schedule: VibeLoopSchedule) throws {
        switch schedule {
        case .interval(_, let seconds):
            guard seconds >= minimumIntervalSeconds else {
                throw VibeLoopScheduleValidationError.intervalTooShort
            }
            guard seconds <= maximumIntervalSeconds else {
                throw VibeLoopScheduleValidationError.invalidTime
            }
        case .daily(let hour, let minute, let timeZoneID):
            try validateTime(hour: hour, minute: minute, timeZoneID: timeZoneID)
        case .weekly(let weekdays, let hour, let minute, let timeZoneID):
            try validateTime(hour: hour, minute: minute, timeZoneID: timeZoneID)
            guard !weekdays.isEmpty else {
                throw VibeLoopScheduleValidationError.missingWeekday
            }
            guard weekdays.allSatisfy((1...7).contains) else {
                throw VibeLoopScheduleValidationError.invalidWeekday
            }
        }
    }

    static func nextOccurrence(after date: Date, schedule: VibeLoopSchedule) -> Date? {
        guard (try? validate(schedule)) != nil else { return nil }
        switch schedule {
        case .interval(let anchor, let seconds):
            if date < anchor { return anchor }
            let elapsed = date.timeIntervalSince(anchor)
            let steps = floor(elapsed / Double(seconds)) + 1
            return anchor.addingTimeInterval(steps * Double(seconds))
        case .daily(let hour, let minute, let timeZoneID):
            return nextCalendarOccurrence(
                after: date,
                hour: hour,
                minute: minute,
                weekday: nil,
                timeZoneID: timeZoneID
            )
        case .weekly(let weekdays, let hour, let minute, let timeZoneID):
            return weekdays.compactMap {
                nextCalendarOccurrence(
                    after: date,
                    hour: hour,
                    minute: minute,
                    weekday: $0,
                    timeZoneID: timeZoneID
                )
            }.min()
        }
    }

    static func latestOccurrence(
        onOrBefore date: Date,
        schedule: VibeLoopSchedule
    ) -> Date? {
        guard (try? validate(schedule)) != nil else { return nil }
        switch schedule {
        case .interval(let anchor, let seconds):
            guard date >= anchor else { return nil }
            let steps = floor(date.timeIntervalSince(anchor) / Double(seconds))
            return anchor.addingTimeInterval(steps * Double(seconds))
        case .daily(let hour, let minute, let timeZoneID):
            return previousCalendarOccurrence(
                onOrBefore: date,
                hour: hour,
                minute: minute,
                weekday: nil,
                timeZoneID: timeZoneID
            )
        case .weekly(let weekdays, let hour, let minute, let timeZoneID):
            return weekdays.compactMap {
                previousCalendarOccurrence(
                    onOrBefore: date,
                    hour: hour,
                    minute: minute,
                    weekday: $0,
                    timeZoneID: timeZoneID
                )
            }.max()
        }
    }

    static func latestDueOccurrence(
        for definition: VibeLoopDefinition,
        runtime: VibeLoopRuntimeState?,
        now: Date
    ) -> Date? {
        guard let latest = latestOccurrence(onOrBefore: now, schedule: definition.schedule) else {
            return nil
        }
        let baseline = max(definition.createdAt, runtime?.lastClaimedScheduledAt ?? definition.createdAt)
        return latest > baseline ? latest : nil
    }

    static func nextOccurrence(
        for definition: VibeLoopDefinition,
        runtime: VibeLoopRuntimeState?
    ) -> Date? {
        let baseline = max(definition.createdAt, runtime?.lastClaimedScheduledAt ?? definition.createdAt)
        return nextOccurrence(after: baseline, schedule: definition.schedule)
    }

    private static func validateTime(hour: Int, minute: Int, timeZoneID: String) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw VibeLoopScheduleValidationError.invalidTime
        }
        guard TimeZone(identifier: timeZoneID) != nil else {
            throw VibeLoopScheduleValidationError.invalidTimeZone
        }
    }

    private static func calendar(timeZoneID: String) -> Calendar? {
        guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func components(hour: Int, minute: Int, weekday: Int?) -> DateComponents {
        var result = DateComponents()
        result.hour = hour
        result.minute = minute
        result.second = 0
        result.weekday = weekday
        return result
    }

    private static func nextCalendarOccurrence(
        after date: Date,
        hour: Int,
        minute: Int,
        weekday: Int?,
        timeZoneID: String
    ) -> Date? {
        guard let calendar = calendar(timeZoneID: timeZoneID) else { return nil }
        return calendar.nextDate(
            after: date,
            matching: components(hour: hour, minute: minute, weekday: weekday),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private static func previousCalendarOccurrence(
        onOrBefore date: Date,
        hour: Int,
        minute: Int,
        weekday: Int?,
        timeZoneID: String
    ) -> Date? {
        guard let calendar = calendar(timeZoneID: timeZoneID) else { return nil }
        return calendar.nextDate(
            after: date.addingTimeInterval(1),
            matching: components(hour: hour, minute: minute, weekday: weekday),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward
        )
    }
}

