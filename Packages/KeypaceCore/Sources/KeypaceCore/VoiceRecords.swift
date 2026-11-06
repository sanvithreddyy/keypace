import Foundation

/// Personal bests across dictations. Short dictations are left out of speed records so a few
/// quick words can't set one.
public struct VoiceRecords: Sendable {
    public static let minimumSeconds = 20.0
    public static let minimumWords = 20
    /// A day needs this much speaking, in seconds, to count as a fastest day.
    public static let minimumDaySeconds = 120.0

    public var fastest: DictationRecord?
    public var mostWords: DictationRecord?
    public var longest: DictationRecord?
    public var fastestDay: (day: Date, totals: VoiceTotals)?
    public var mostWordsDay: (day: Date, totals: VoiceTotals)?
    /// Fastest qualifying dictation per app, fastest first.
    public var fastestByApp: [DictationRecord]

    public init(_ dictations: [DictationRecord], calendar: Calendar) {
        let qualifying = dictations.filter(Self.qualifies)
        fastest = qualifying.max { ($0.wpm ?? 0) < ($1.wpm ?? 0) }
        mostWords = dictations.max { $0.words < $1.words }
        longest = dictations.filter { $0.speakingSeconds != nil }.max { ($0.speakingSeconds ?? 0) < ($1.speakingSeconds ?? 0) }

        let days = VoiceStatistics.byDay(dictations, calendar: calendar).map { (day: $0.key, totals: $0.value) }
        fastestDay = days.filter { $0.totals.speakingSeconds >= Self.minimumDaySeconds }.max { ($0.totals.wpm ?? 0) < ($1.totals.wpm ?? 0) }
        mostWordsDay = days.max { $0.totals.words < $1.totals.words }

        fastestByApp = Dictionary(grouping: qualifying, by: \.appID)
            .compactMap { $0.value.max { ($0.wpm ?? 0) < ($1.wpm ?? 0) } }
            .sorted { ($0.wpm ?? 0) > ($1.wpm ?? 0) }
    }

    public static func qualifies(_ dictation: DictationRecord) -> Bool {
        (dictation.speakingSeconds ?? 0) >= minimumSeconds && dictation.words >= minimumWords
    }
}

/// Groupings of dictations. A dictation counts toward the hour and day it started in.
public enum VoiceStatistics {
    /// Keyed by the start of each day.
    public static func byDay(_ dictations: [DictationRecord], calendar: Calendar) -> [Date: VoiceTotals] {
        Dictionary(grouping: dictations) { calendar.startOfDay(for: $0.start) }.mapValues(VoiceTotals.init)
    }

    /// Keyed by hour of day, 0–23.
    public static func byHourOfDay(_ dictations: [DictationRecord], calendar: Calendar) -> [Int: VoiceTotals] {
        Dictionary(grouping: dictations) { calendar.component(.hour, from: $0.start) }.mapValues(VoiceTotals.init)
    }

    /// Per dictation app, most words first.
    public static func bySource(_ dictations: [DictationRecord]) -> [(sourceID: String, totals: VoiceTotals)] {
        Dictionary(grouping: dictations, by: \.sourceID).mapValues(VoiceTotals.init)
            .map { (sourceID: $0.key, totals: $0.value) }
            .sorted { $0.totals.words > $1.totals.words }
    }

    /// Per app, most words first.
    public static func byApp(_ dictations: [DictationRecord]) -> [(appID: String, totals: VoiceTotals)] {
        Dictionary(grouping: dictations, by: \.appID).mapValues(VoiceTotals.init)
            .map { (appID: $0.key, totals: $0.value) }
            .sorted { $0.totals.words > $1.totals.words }
    }

    /// Dictations long enough for their own speed to mean something, for pace statistics.
    public static let paceMinimumSeconds = 5.0

    public static func paced(_ dictations: [DictationRecord]) -> [DictationRecord] {
        dictations.filter { ($0.speakingSeconds ?? 0) >= paceMinimumSeconds }
    }

    /// How many paced dictations fall in each band of `width` wpm, keyed by the band's lower edge.
    /// Bands run from the slowest to the fastest band with any dictation, empty ones included.
    public static func paceBands(_ dictations: [DictationRecord], width: Int = 20) -> [(lower: Int, count: Int)] {
        let speeds = paced(dictations).compactMap(\.wpm)
        guard let low = speeds.min(), let high = speeds.max() else { return [] }
        let counts = Dictionary(grouping: speeds) { Int($0) / width * width }.mapValues(\.count)
        return stride(from: Int(low) / width * width, through: Int(high) / width * width, by: width).map { ($0, counts[$0] ?? 0) }
    }

    /// The middle speed of paced dictations.
    public static func medianWPM(_ dictations: [DictationRecord]) -> Double? {
        let speeds = paced(dictations).compactMap(\.wpm).sorted()
        guard !speeds.isEmpty else { return nil }
        let middle = speeds.count / 2
        return speeds.count % 2 == 1 ? speeds[middle] : (speeds[middle - 1] + speeds[middle]) / 2
    }

    /// Paced dictations faster than the given speed, and how many paced dictations there are.
    public static func faster(than wpm: Double, _ dictations: [DictationRecord]) -> (count: Int, of: Int) {
        let paced = paced(dictations)
        return (paced.filter { ($0.wpm ?? 0) > wpm }.count, paced.count)
    }

    /// Dictation lengths, by word count.
    public enum Length: CaseIterable, Sendable {
        case short, medium, long, veryLong

        public var words: ClosedRange<Int> {
            switch self {
            case .short: 1...10
            case .medium: 11...30
            case .long: 31...100
            case .veryLong: 101...Int.max
            }
        }

        public static func of(_ words: Int) -> Length {
            allCases.first { $0.words.contains(words) } ?? .veryLong
        }
    }

    /// Totals per length, shortest first; lengths without dictations are left out.
    public static func byLength(_ dictations: [DictationRecord]) -> [(length: Length, totals: VoiceTotals)] {
        let grouped = Dictionary(grouping: dictations) { Length.of($0.words) }
        return Length.allCases.compactMap { length in grouped[length].map { (length, VoiceTotals($0)) } }
    }
}
