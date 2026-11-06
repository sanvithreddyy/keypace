import Foundation
import Testing
@testable import KeypaceCore

private func dictation(
    _ app: String = "com.apple.mail", at start: Date, words: Int = 140, seconds: Double? = 60,
    source: String = "com.example.dictation"
) -> DictationRecord {
    DictationRecord(
        start: start, end: start.addingTimeInterval(seconds ?? 0), appID: app, sourceID: source,
        words: words, speakingSeconds: seconds
    )
}

struct DictationTotalsTests {
    @Test func `speed is words per minute of open microphone`() {
        let totals = VoiceTotals([dictation(at: monday, words: 140, seconds: 60), dictation(at: monday, words: 70, seconds: 60)])
        #expect(totals.dictations == 2)
        #expect(totals.words == 210)
        #expect(totals.wpm == 105)
        #expect(totals.averageWords == 105)
    }

    @Test func `untimed dictations add words but never move speed`() {
        let totals = VoiceTotals([dictation(at: monday, words: 120, seconds: 60), dictation(at: monday, words: 500, seconds: nil)])
        #expect(totals.words == 620)
        #expect(totals.timedWords == 120)
        #expect(totals.wpm == 120)
    }

    @Test func `a speed sample has the dictation's speed and speaking time`() throws {
        let sample = try #require(dictation(at: monday, words: 160, seconds: 63).speedSample)
        let wpm = try #require(sample.totals.wpm)
        #expect(abs(wpm - 160 * 60 / 63.0) < 1e-9)
        #expect(sample.totals.duration == 63)
        #expect(sample.totals.correctionRate == 0)
        #expect(dictation(at: monday, seconds: nil).speedSample == nil)
    }

    @Test func `words are runs of non-space characters`() {
        #expect(WordCount.count("Hello there,  world.\nNew line") == 5)
        #expect(WordCount.count("   ") == 0)
    }
}

struct DictationDetectorTests {
    @Test func `a paste after the microphone closes is one dictation`() throws {
        var detector = DictationDetector()
        detector.microphoneStarted(processID: 42, sourceID: "com.example.dictation", at: 100)
        #expect(detector.isRecording)
        detector.microphoneStopped(processID: 42, at: 163)
        let pasted = detector.pasted(words: 160, by: "com.example.dictation", at: 163.2)
        let found = try #require(pasted)
        #expect(found == .init(sourceID: "com.example.dictation", words: 160, start: 100, end: 163.2, speakingSeconds: 63))
        // The session is used up: a second paste from the same app isn't another dictation.
        #expect(detector.pasted(words: 160, by: "com.example.dictation", at: 163.4) == nil)
    }

    @Test func `pastes from other apps, late pastes and calls are not dictation`() {
        var detector = DictationDetector()
        detector.microphoneStarted(processID: 42, sourceID: "com.example.dictation", at: 100)
        detector.microphoneStopped(processID: 42, at: 110)
        #expect(detector.pasted(words: 10, by: "com.example.clipboard", at: 110.2) == nil)
        #expect(detector.pasted(words: 10, by: "com.example.dictation", at: 110 + DictationDetector.pasteWindow + 0.1) == nil)

        // A call: the microphone opens and closes, nothing is pasted, nothing is recorded.
        detector.microphoneStarted(processID: 9, sourceID: "us.zoom.xos", at: 200)
        detector.microphoneStopped(processID: 9, at: 900)
        #expect(detector.flush(at: 905).isEmpty)
    }

    @Test func `text pasted while the microphone stays open counts up to the paste`() throws {
        var detector = DictationDetector()
        detector.microphoneStarted(processID: 5, sourceID: "com.example.flow", at: 10)
        let pasted = detector.pasted(words: 30, by: "com.example.flow", at: 25)
        let found = try #require(pasted)
        #expect(found.speakingSeconds == 15)
    }

    @Test func `a helper that records and a main process that pastes still pair`() {
        var detector = DictationDetector()
        detector.microphoneStarted(processID: 11, sourceID: "com.example.app", at: 0)
        detector.microphoneStopped(processID: 11, at: 4)
        #expect(detector.expectsText(from: "com.example.app", at: 4.1))
        #expect(!detector.expectsText(from: "com.example.other", at: 4.1))
        #expect(detector.pasted(words: 9, by: "com.example.app", at: 4.2)?.words == 9)
    }

    @Test func `typed-out text is counted once it stops`() throws {
        var detector = DictationDetector()
        detector.microphoneStarted(processID: 8, sourceID: "com.example.typer", at: 0)
        detector.microphoneStopped(processID: 8, at: 6)
        var time = 6.2
        for character in "three short words" {
            detector.typed(String(character), by: "com.example.typer", at: time)
            time += 0.01
        }
        #expect(detector.flush(at: time + 0.1).isEmpty)
        let flushed = detector.flush(at: time + 1)
        let found = try #require(flushed.first)
        #expect(found.words == 3)
        #expect(found.speakingSeconds == 6)
    }

    @Test func `posted characters without a microphone session are ignored`() {
        var detector = DictationDetector()
        detector.typed("expanded snippet", by: "com.example.expander", at: 1)
        #expect(detector.flush(at: 5).isEmpty)
    }
}

struct DictationStoreTests {
    @Test func `dictations are read by start time and deleted with their app`() throws {
        let store = try SessionStore.inMemory()
        try store.save(dictation("com.apple.Notes", at: monday))
        try store.save(dictation(at: monday.addingTimeInterval(86_400)))
        let firstDay = DateInterval(start: monday, duration: 86_400)
        #expect(try store.dictations(in: firstDay).map(\.appID) == ["com.apple.Notes"])
        #expect(try store.firstDictationStart() == monday)

        try store.deleteSessions(appID: "com.apple.Notes")
        #expect(try store.allDictations().count == 1)
        try store.deleteAll()
        #expect(try store.allDictations().isEmpty)
    }
}

struct VoiceRecordsTests {
    @Test func `speed records skip short dictations, and untimed ones still count for words`() throws {
        let calendar = Calendar(identifier: .gregorian)
        let records = VoiceRecords([
            dictation(at: monday, words: 30, seconds: 5),                                        // too short for speed
            dictation(at: monday.addingTimeInterval(60), words: 150, seconds: 70),
            dictation("com.apple.Notes", at: monday.addingTimeInterval(120), words: 100, seconds: 50),
            dictation(at: monday.addingTimeInterval(86_400), words: 900, seconds: nil),          // speaking time unknown
        ], calendar: calendar)
        #expect(records.fastest?.words == 150)
        #expect(records.mostWords?.words == 900)
        #expect(records.longest?.speakingSeconds == 70)
        #expect(records.fastestByApp.map(\.appID) == ["com.apple.mail", "com.apple.Notes"])
        #expect(records.mostWordsDay?.totals.words == 900)
        // The second day has no speaking time, so it can't be the fastest day.
        let fastestDay = try #require(records.fastestDay)
        #expect(fastestDay.day == calendar.startOfDay(for: monday))
    }

    @Test func `dictation apps are ranked by words`() {
        let sources = VoiceStatistics.bySource([
            dictation(at: monday, words: 50, source: "com.example.small"),
            dictation(at: monday, words: 300, source: "com.example.big"),
            dictation(at: monday, words: 100, source: "com.example.small"),
        ])
        #expect(sources.map(\.sourceID) == ["com.example.big", "com.example.small"])
        #expect(sources.last?.totals.dictations == 2)
    }

    @Test func `pace bands, median and how many beat a speed`() {
        let dictations = [
            dictation(at: monday, words: 20, seconds: 10),   // 120 wpm
            dictation(at: monday, words: 25, seconds: 10),   // 150
            dictation(at: monday, words: 26, seconds: 10),   // 156
            dictation(at: monday, words: 10, seconds: 10),   // 60
            dictation(at: monday, words: 30, seconds: 3),    // too short to pace
            dictation(at: monday, words: 900, seconds: nil),
        ]
        #expect(VoiceStatistics.paceBands(dictations).map(\.lower) == [60, 80, 100, 120, 140])
        #expect(VoiceStatistics.paceBands(dictations).map(\.count) == [1, 0, 0, 1, 2])
        #expect(VoiceStatistics.medianWPM(dictations) == 135)
        let faster = VoiceStatistics.faster(than: 61, dictations)
        #expect(faster.count == 3 && faster.of == 4)
    }

    @Test func `lengths group by words and skip empty ones`() {
        let lengths = VoiceStatistics.byLength([
            dictation(at: monday, words: 5, seconds: 6),
            dictation(at: monday, words: 150, seconds: 60),
            dictation(at: monday, words: 101, seconds: 40),
        ])
        #expect(lengths.map(\.length) == [.short, .veryLong])
        #expect(lengths.last?.totals.words == 251)
    }

    @Test func `streaks count days with dictation`() {
        let calendar = Calendar(identifier: .gregorian)
        let starts = [monday, monday.addingTimeInterval(86_400), monday.addingTimeInterval(3 * 86_400)]
        let streaks = Statistics.streaks(starts: starts, today: monday.addingTimeInterval(3 * 86_400 + 60), calendar: calendar)
        #expect(streaks.current == 1)
        #expect(streaks.longest == 2)
    }
}
