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
        // 42 gaps of 0.2 s plus one usual gap for the first press: 8.6 s of typing for 43 characters.
        let wpm = try #require(session.totals.wpm)
        let expected: Double = 60
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

    @Test func `deleting an app's history also drops its unsaved typing`() throws {
        let tracker = try makeTracker(clock: clock)
        var typist = Typist(tracker: tracker, clock: clock)
        typist.type("the quick brown fox jumps over the lazy dog")
        typist.sourceProcessID = 4242
        typist.type("expanded snippet", interval: 0.001)
        tracker.deleteHistory(appID: "com.apple.Notes")
        typist.pause()
        tracker.endSession()

        #expect(tracker.allSessions().isEmpty)
        #expect(tracker.keyStats(in: DateInterval(start: .distantPast, end: .distantFuture)).isEmpty)
        #expect(tracker.syntheticCount(in: DateInterval(start: .distantPast, end: .distantFuture)) == 0)
    }

    @Test func `filtered input is dated when it arrives`() throws {
        let calendar = Calendar.current
        let lateNight = calendar.date(bySettingHour: 23, minute: 59, second: 58, of: clock.date)!
        let lateClock = TestClock(date: lateNight)
        let tracker = try makeTracker(clock: lateClock)
        var expander = Typist(tracker: tracker, clock: lateClock)
        expander.sourceProcessID = 4242
        expander.type("x", interval: 0.001)
        lateClock.advance(4)
        let revision = tracker.revision
        tracker.endSession()

        let thatDay = calendar.dateInterval(of: .day, for: lateNight)!
        #expect(tracker.syntheticCount(in: thatDay) == 1)
        #expect(tracker.revision > revision)
    }

    @Test func `live speed follows the last few seconds and clears when typing stops`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("the quick brown fox", interval: 0.15)
        // 19 characters 0.15 s apart: 18 counted over 2.7 s.
        let live = try #require(tracker.liveWPM)
        let expected: Double = 18.0 / 5 / (2.7 / 60)
        #expect(abs(live - expected) < 1e-6)
        clock.advance(2.5)
        tracker.tick()
        #expect(tracker.liveWPM == nil)
    }

    @Test func `option-delete from the keyboard removes the whole word`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("hello brave world")
        clock.advance(0.2)
        let optionDelete = ObservedKey(keyCode: 51, time: clock.uptime, text: "\u{7F}", commandOrControl: false,
                                       command: false, option: true, isRepeat: false, sourceStateID: 1, sourceProcessID: 0)
        tracker.handle(optionDelete, appID: "com.apple.Notes", keyboard: typist.keyboard, inputSource: typist.inputSource)
        typist.pause()

        let session = try #require(tracker.allSessions().first)
        #expect(session.characters == 17)
        #expect(session.deletions == 5)
        #expect(session.totals.netCharacters == 12)
    }

    @Test func `live speed clears when capture stops`() throws {
        let tracker = try makeTracker(clock: clock)
        Typist(tracker: tracker, clock: clock).type("the quick brown fox", interval: 0.15)
        #expect(tracker.liveWPM != nil)
        tracker.captureStopped()
        #expect(tracker.liveWPM == nil)
        #expect(tracker.allSessions().count == 1)
    }

    @Test func `a fresh install ignores sessions under 25 characters`() throws {
        let tracker = try makeTracker(clock: clock, minimumCharacters: nil)
        #expect(tracker.minimumCharacters == 25)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("quick burst of text")
        typist.pause()
        #expect(tracker.allSessions().isEmpty)
    }
}
