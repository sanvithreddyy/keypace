import Foundation

/// Personal bests across stored sessions. Short sessions are left out so a quick burst
/// can't set a speed record.
public struct Records: Sendable {
    public static let minimumDuration = 30.0
    public static let minimumCharacters = 100
    /// A day needs this much typing, in seconds, to count as a fastest day.
    public static let minimumDayDuration = 600.0

    public var fastestSession: SessionRecord?
    public var cleanestSession: SessionRecord?
    public var longestSession: SessionRecord?
    public var fastestDay: (day: Date, totals: TypingTotals)?
    public var busiestDay: (day: Date, totals: TypingTotals)?
    /// Fastest qualifying session per app, fastest first.
    public var fastestByApp: [SessionRecord]

    public init(_ sessions: [SessionRecord], calendar: Calendar) {
        let qualifying = sessions.filter(Self.qualifies)
        fastestSession = qualifying.max { ($0.totals.wpm ?? 0) < ($1.totals.wpm ?? 0) }
        cleanestSession = qualifying.filter { $0.characters >= 2 * Self.minimumCharacters }
            .min { ($0.totals.correctionRate ?? 1) < ($1.totals.correctionRate ?? 1) }
        longestSession = sessions.max { $0.totals.duration < $1.totals.duration }

        let days = Statistics.byDay(sessions, calendar: calendar).map { (day: $0.key, totals: $0.value) }
        fastestDay = days.filter { $0.totals.duration >= Self.minimumDayDuration }.max { ($0.totals.wpm ?? 0) < ($1.totals.wpm ?? 0) }
        busiestDay = days.max { $0.totals.duration < $1.totals.duration }

        fastestByApp = Dictionary(grouping: qualifying, by: \.appID)
            .compactMap { $0.value.max { ($0.totals.wpm ?? 0) < ($1.totals.wpm ?? 0) } }
            .sorted { ($0.totals.wpm ?? 0) > ($1.totals.wpm ?? 0) }
    }

    public static func qualifies(_ session: SessionRecord) -> Bool {
        session.totals.duration >= minimumDuration && session.characters >= minimumCharacters
    }
}
