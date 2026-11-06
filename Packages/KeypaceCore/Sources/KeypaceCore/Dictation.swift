import Foundation
import GRDB

/// One dictation: how many words a dictation app put into a text field, and how long the
/// microphone was open for it. Never the text.
public struct DictationRecord: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "dictation"

    public var id: Int64?
    /// When the microphone opened.
    public var start: Date
    /// When the text was put in.
    public var end: Date
    /// The app the text went to.
    public var appID: String
    /// The dictation app.
    public var sourceID: String
    public var words: Int
    /// Seconds the microphone was open, thinking pauses included; nil when it isn't known.
    public var speakingSeconds: Double?

    public init(
        id: Int64? = nil, start: Date, end: Date, appID: String, sourceID: String, words: Int, speakingSeconds: Double?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.appID = appID
        self.sourceID = sourceID
        self.words = words
        self.speakingSeconds = speakingSeconds
    }

    /// Words per minute of open microphone; nil without a speaking time.
    public var wpm: Double? {
        guard let speakingSeconds, speakingSeconds > 0 else { return nil }
        return Double(words) * 60 / speakingSeconds
    }

    /// The dictation as a speed sample for the charts shared with typing: its typing time is the
    /// speaking time and its net characters are five per word, so the sample's wpm is words per
    /// minute exactly. Nil when the speaking time is unknown, so untimed dictations never move a speed.
    public var speedSample: SessionRecord? {
        guard let speakingSeconds, speakingSeconds > 0 else { return nil }
        return SessionRecord(
            start: start, end: end, appID: appID,
            characters: words * 5, backspaces: 0, keystrokes: 0, deletions: 0, activeSeconds: speakingSeconds
        )
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Counts over some dictations.
public struct VoiceTotals: Sendable, Equatable {
    public var dictations = 0
    /// Every dictated word, timed or not.
    public var words = 0
    /// Words of dictations with a known speaking time; speed uses only these.
    public var timedWords = 0
    public var speakingSeconds = 0.0

    public init(_ dictations: [DictationRecord] = []) {
        for dictation in dictations {
            self.dictations += 1
            words += dictation.words
            if let seconds = dictation.speakingSeconds, seconds > 0 {
                timedWords += dictation.words
                speakingSeconds += seconds
            }
        }
    }

    public var wpm: Double? {
        speakingSeconds > 0 ? Double(timedWords) * 60 / speakingSeconds : nil
    }

    public var averageWords: Double? {
        dictations > 0 ? Double(words) / Double(dictations) : nil
    }
}

/// Words the way a reader counts them: runs of non-space characters.
public enum WordCount {
    public static func count(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
