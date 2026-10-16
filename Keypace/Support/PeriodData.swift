import Foundation
import KeypaceCore

/// Sessions and press totals for a period and for the period before it.
struct PeriodData {
    var period: Period
    var interval: DateInterval?
    var sessions: [SessionRecord] = []
    var previousSessions: [SessionRecord]?
    var presses = 0
    var previousPresses: Int?

    var totals: TypingTotals { Statistics.totals(sessions) }
    var previousTotals: TypingTotals? { previousSessions.map(Statistics.totals) }

    @MainActor
    init(_ period: Period, tracker: LiveTracker, now: Date = .now, calendar: Calendar = .current) {
        self.period = period
        interval = period.interval(now: now, calendar: calendar, firstSession: tracker.firstHistoryStart())
        if let interval {
            sessions = tracker.sessions(in: interval)
            presses = tracker.pressCounts(in: interval).values.reduce(0, +)
        }
        if let previous = period.previous(now: now, calendar: calendar) {
            previousSessions = tracker.sessions(in: previous)
            previousPresses = tracker.pressCounts(in: previous).values.reduce(0, +)
        }
    }
}

extension Period {
    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        case .allTime: "All time"
        }
    }

    /// The previous period as a noun: "yesterday", "the previous 7 days".
    var comparisonNoun: String {
        switch self {
        case .today: "yesterday"
        case .week: "the previous 7 days"
        case .month: "the previous 30 days"
        case .allTime: ""
        }
    }

    /// How the comparison reads: "vs yesterday", "vs previous 7 days".
    var comparison: String {
        switch self {
        case .today: "vs yesterday"
        case .week: "vs previous 7 days"
        case .month: "vs previous 30 days"
        case .allTime: ""
        }
    }
}
