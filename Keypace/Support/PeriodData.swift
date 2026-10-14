import Foundation
import KeypaceCore

/// Sessions for a period and for the period before it.
struct PeriodData {
    var period: Period
    var interval: DateInterval?
    var sessions: [SessionRecord] = []
    var previousSessions: [SessionRecord]?

    var totals: TypingTotals { Statistics.totals(sessions) }
    var previousTotals: TypingTotals? { previousSessions.map(Statistics.totals) }

    @MainActor
    init(_ period: Period, tracker: LiveTracker, now: Date = .now, calendar: Calendar = .current) {
        self.period = period
        interval = period.interval(now: now, calendar: calendar, firstSession: tracker.firstSessionStart())
        if let interval { sessions = tracker.sessions(in: interval) }
        if let previous = period.previous(now: now, calendar: calendar) { previousSessions = tracker.sessions(in: previous) }
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
