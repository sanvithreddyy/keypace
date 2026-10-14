import Foundation
import Testing
import KeypaceCore

/// Key-downs through the whole app path: filters, session engine, storage, and the data screens read.
@MainActor
struct PipelineTests {
    let clock = TestClock(date: Date(timeIntervalSince1970: 1_791_810_000)) // 2026-10-12 13:00 UTC

    @Test func `a typed sentence is saved with its counts, keys and keyboard`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("the quick brown fox jumps over the lazy dog")
        typist.pause()

        let sessions = tracker.allSessions()
        let session = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(session.characters == 43)
        #expect(session.backspaces == 0)
        #expect(session.appID == "com.apple.Notes")
        #expect(session.keyboardID == "1452:834")
        #expect(session.inputSourceID == "com.apple.keylayout.US")
        // 43 presses 0.2 s apart span 8.4 s: 43 / 5 words in 8.4 s.
        let wpm = try #require(session.totals.wpm)
        let expected: Double = 43.0 / 5 / 8.4 * 60
        #expect(abs(wpm - expected) < 1e-6)

        let day = DateInterval(start: clock.date.addingTimeInterval(-86_400), end: clock.date.addingTimeInterval(86_400))
        let keys = tracker.keyStats(in: day)
        #expect(keys[USKeys.code(for: "o")]?.presses == 4)
        #expect(keys[49]?.presses == 8)
        #expect(tracker.pairStats(in: day)[KeyPair(from: USKeys.code(for: "t"), to: USKeys.code(for: "h"))]?.count == 2)
        #expect(tracker.keyboards().map(\.id) == ["1452:834"])
        #expect(tracker.inputSourceRecords().map(\.id) == ["com.apple.keylayout.US"])
    }

    @Test func `corrections are charged to the deleted keys`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("teh⌫⌫he quick brown fox")
        typist.pause()

        let session = try #require(tracker.allSessions().first)
        #expect(session.characters == 21)
        #expect(session.backspaces == 2)
        let keys = tracker.keyStats(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(keys[USKeys.code(for: "h")]?.corrections == 1)
        #expect(keys[USKeys.code(for: "e")]?.corrections == 1)
        #expect(keys[USKeys.code(for: "t")]?.corrections == 0)
    }

    @Test func `posted keystrokes are counted as synthetic, not typing`() throws {
        let tracker = try makeTracker(clock: clock)
        var expander = Typist(tracker: tracker, clock: clock)
        expander.sourceProcessID = 4242
        expander.type("best regards, sanvith", interval: 0.001)
        tracker.endSession()

        #expect(tracker.allSessions().isEmpty)
        #expect(tracker.syntheticCount(in: DateInterval(start: .distantPast, end: .distantFuture)) == 21)
    }

    @Test func `excluded apps are not recorded`() throws {
        let tracker = try makeTracker(clock: clock)
        tracker.filter = AppFilter(mode: .allExcept, appIDs: ["com.1password.1password"])
        var typist = Typist(tracker: tracker, clock: clock)
        typist.appID = "com.1password.1password"
        typist.type("correct horse battery staple")
        typist.pause()
        #expect(tracker.allSessions().isEmpty)
    }

    @Test func `switching keyboards or apps starts a new session`() throws {
        let tracker = try makeTracker(clock: clock)
        var typist = Typist(tracker: tracker, clock: clock)
        typist.type("hello from the laptop")
        typist.keyboard = KeyboardRecord(id: "1133:50475", name: "MX Keys", isBuiltIn: false, lastSeen: .now)
        typist.type("hello from the mx keys")
        typist.appID = "com.apple.mail"
        typist.type("hello from mail on mx")
        typist.pause()

        let sessions = tracker.allSessions()
        #expect(sessions.map(\.keyboardID) == ["1452:834", "1133:50475", "1133:50475"])
        #expect(sessions.map(\.appID) == ["com.apple.Notes", "com.apple.Notes", "com.apple.mail"])
        #expect(Set(tracker.keyboards().map(\.id)) == ["1452:834", "1133:50475"])
    }

    @Test func `today's period data reflects saved sessions`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("the quick brown fox jumps over the lazy dog")
        typist.pause()
        let data = PeriodData(.today, tracker: tracker, now: clock.date)
        #expect(data.sessions.count == 1)
        #expect(data.totals.characters == 43)
    }
}
