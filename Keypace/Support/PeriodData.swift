import Foundation
import KeypaceCore

/// Sessions for a period and for the period before it. In voice mode the sessions are the
/// dictations' speed samples, so the speed charts read the same, and the dictations come along
/// for word counts.
struct PeriodData {
    var period: Period
    var mode: Mode
    var interval: DateInterval?
    var previousInterval: DateInterval?
    var sessions: [SessionRecord] = []
    var previousSessions: [SessionRecord]?
    var dictations: [DictationRecord] = []
    var previousDictations: [DictationRecord]?

    var totals: TypingTotals { Statistics.totals(sessions) }
    var previousTotals: TypingTotals? { previousSessions.map(Statistics.totals) }
    var voice: VoiceTotals { VoiceTotals(dictations) }
    var previousVoice: VoiceTotals? { previousDictations.map(VoiceTotals.init) }

    @MainActor
    init(_ period: Period, tracker: LiveTracker, mode: Mode = .typing, now: Date = .now, calendar: Calendar = .current) {
        self.period = period
        self.mode = mode
        let first = mode == .voice ? tracker.firstDictationStart() : tracker.firstHistoryStart()
        interval = period.interval(now: now, calendar: calendar, firstSession: first)
        previousInterval = period.previous(now: now, calendar: calendar)
        switch mode {
        case .typing:
            if let interval { sessions = tracker.sessions(in: interval) }
            if let previousInterval { previousSessions = tracker.sessions(in: previousInterval) }
        case .voice:
            if let interval {
                dictations = tracker.dictations(in: interval)
                sessions = dictations.compactMap(\.speedSample)
            }
            if let previousInterval {
                let previous = tracker.dictations(in: previousInterval)
                previousDictations = previous
                previousSessions = previous.compactMap(\.speedSample)
            }
        }
    }

    /// Nothing recorded in the period.
    var isEmpty: Bool { mode == .voice ? dictations.isEmpty : sessions.isEmpty }
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
