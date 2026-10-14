import Foundation

/// Aggregations over stored sessions. A session counts toward the hour, day and weekday it started in.
public enum Statistics {
    public static func totals(_ sessions: [SessionRecord]) -> TypingTotals {
        sessions.reduce(into: TypingTotals()) { $0 += $1.totals }
    }

    /// Per app, most typing time first.
    public static func byApp(_ sessions: [SessionRecord]) -> [(appID: String, totals: TypingTotals)] {
        grouped(sessions) { $0.appID }
            .map { (appID: $0.key, totals: $0.value) }
            .sorted { $0.totals.duration > $1.totals.duration }
    }

    /// Keyed by hour of day, 0–23.
    public static func byHourOfDay(_ sessions: [SessionRecord], calendar: Calendar) -> [Int: TypingTotals] {
        grouped(sessions) { calendar.component(.hour, from: $0.start) }
    }

    /// Keyed by `Calendar` weekday, 1 (Sunday) – 7 (Saturday).
    public static func byWeekday(_ sessions: [SessionRecord], calendar: Calendar) -> [Int: TypingTotals] {
        grouped(sessions) { calendar.component(.weekday, from: $0.start) }
    }

    /// Keyed by the start of each day.
    public static func byDay(_ sessions: [SessionRecord], calendar: Calendar) -> [Date: TypingTotals] {
        grouped(sessions) { calendar.startOfDay(for: $0.start) }
    }

    /// Consecutive days with typing. The current streak survives until today ends, so it counts
    /// back from today if you've typed today, otherwise from yesterday.
    public static func streaks(_ sessions: [SessionRecord], today: Date, calendar: Calendar) -> (current: Int, longest: Int) {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.start) })
        let todayStart = calendar.startOfDay(for: today)

        var current = 0
        var day = days.contains(todayStart) ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        while days.contains(day) {
            current += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }

        var longest = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return (current, longest)
    }

    fileprivate static func grouped<Key: Hashable>(_ sessions: [SessionRecord], by key: (SessionRecord) -> Key) -> [Key: TypingTotals] {
        sessions.reduce(into: [:]) { $0[key($1), default: TypingTotals()] += $1.totals }
    }
}

public extension Statistics {
    struct WeekdayHour: Hashable, Sendable {
        /// `Calendar` weekday, 1 (Sunday) – 7 (Saturday).
        public var weekday: Int
        public var hour: Int
        public init(weekday: Int, hour: Int) {
            self.weekday = weekday
            self.hour = hour
        }
    }

    static func byWeekdayAndHour(_ sessions: [SessionRecord], calendar: Calendar) -> [WeekdayHour: TypingTotals] {
        grouped(sessions) {
            WeekdayHour(weekday: calendar.component(.weekday, from: $0.start), hour: calendar.component(.hour, from: $0.start))
        }
    }
}

/// The ranges the app's period pickers offer. Every range ends at the end of today.
public enum Period: String, CaseIterable, Sendable {
    case today, week, month, allTime

    /// - Parameter firstSession: start of the oldest stored session; all-time is nil without one.
    public func interval(now: Date, calendar: Calendar, firstSession: Date?) -> DateInterval? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let days: Int
        switch self {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        case .allTime:
            guard let firstSession else { return nil }
            return DateInterval(start: calendar.startOfDay(for: firstSession), end: tomorrow)
        }
        return DateInterval(start: calendar.date(byAdding: .day, value: -days, to: tomorrow)!, end: tomorrow)
    }

    /// The range to compare against: the same number of days just before. All-time has none.
    public func previous(now: Date, calendar: Calendar) -> DateInterval? {
        guard self != .allTime, let current = interval(now: now, calendar: calendar, firstSession: nil) else { return nil }
        let days = calendar.dateComponents([.day], from: current.start, to: current.end).day!
        return DateInterval(start: calendar.date(byAdding: .day, value: -days, to: current.start)!, end: current.start)
    }
}
