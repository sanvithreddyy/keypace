import AppKit
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
        #expect(tracker.pressCounts(in: history).isEmpty)
    }

    @Test func `excluded apps are not recorded`() throws {
        let tracker = try makeTracker(clock: clock)
        tracker.filter = AppFilter(mode: .allExcept, appIDs: ["com.1password.1password"])
        var typist = Typist(tracker: tracker, clock: clock)
        typist.appID = "com.1password.1password"
        typist.type("correct horse battery staple")
        typist.pause()
        #expect(tracker.allSessions().isEmpty)
        tracker.endSession()
        #expect(tracker.pressCounts(in: history).isEmpty)
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
        #expect(data.presses == 43)
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
        #expect(tracker.pressCounts(in: history).isEmpty)
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

    @Test func `live and saved speed both leave out thinking pauses`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("abcdefghij")
        clock.advance(1.8) // With the next key's interval, a 2-second thinking pause.
        typist.type("abcdefghij")
        let live = try #require(tracker.liveWPM)
        #expect(abs(live - 60) < 1e-6)
        typist.pause()
        #expect(tracker.liveWPM == nil)
        let saved = try #require(tracker.allSessions().first)
        #expect(saved.characters == 20)
        #expect(saved.deletions == 0)
        #expect(abs(try #require(saved.totals.wpm) - 60) < 1e-6)
    }

    @Test(arguments: ["foo-bar", "foo\tbar", "foo\n", "foo/bar", "can't", "foo_bar", "foo-", "hello, world", "'foo", "foo''bar", "foo©", "foo$", "foo©$", "foo$© ", "foo$$", "foo++", "foo==", "foo©©", "example.com", "foo.bar", "3.14", ".foo", "foo..bar", "e.g."])
    func `option-delete respects native word boundaries`(text: String) throws {
        let tracker = try makeTracker(clock: clock, minimumCharacters: 1)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type(text)

        let editor = NSTextView(frame: .zero)
        editor.string = text
        editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        editor.deleteWordBackward(nil)
        let removed = text.count - editor.string.count
        clock.advance(0.2)
        tracker.handle(ObservedKey(keyCode: 51, time: clock.uptime, text: "\u{7F}", commandOrControl: false,
                                   command: false, option: true, isRepeat: false, sourceStateID: 1, sourceProcessID: 0),
                       appID: typist.appID, keyboard: typist.keyboard, inputSource: typist.inputSource)
        #expect(tracker.current?.deletions == removed)
        // Ownership of the remaining suffix must also match the next ordinary Delete.
        typist.type("⌫")
        typist.pause()
        let saved = try #require(tracker.allSessions().first)
        #expect(saved.deletions == removed + (editor.string.isEmpty ? 0 : 1))
    }

    @Test func `command-delete does not guess a wrapped line length`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        let text = String(repeating: "hello world ", count: 8)
        typist.type(text)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 500))
        editor.isHorizontallyResizable = false
        editor.textContainer!.containerSize = NSSize(width: 100, height: 10_000)
        editor.textContainer!.widthTracksTextView = true
        editor.string = text
        editor.layoutManager!.ensureLayout(for: editor.textContainer!)
        editor.setSelectedRange(NSRange(location: text.count, length: 0))
        editor.deleteToBeginningOfLine(nil)
        #expect(editor.string.count > 0 && editor.string.count < text.count)
        clock.advance(0.2)
        tracker.handle(ObservedKey(keyCode: 51, time: clock.uptime, text: "\u{7F}", commandOrControl: true,
                                   command: true, option: false, isRepeat: false, sourceStateID: 1, sourceProcessID: 0),
                       appID: typist.appID, keyboard: typist.keyboard, inputSource: typist.inputSource)
        typist.type("⌫")
        typist.pause()
        let saved = try #require(tracker.allSessions().first)
        #expect(saved.characters == text.count)
        #expect(saved.deletions == 0)
        let keys = tracker.keyStats(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(keys.values.allSatisfy { $0.corrections == 0 })
    }

    @Test func `live speed clears when capture stops`() throws {
        let tracker = try makeTracker(clock: clock)
        Typist(tracker: tracker, clock: clock).type("the quick brown fox", interval: 0.15)
        #expect(tracker.liveWPM != nil)
        tracker.captureStopped()
        #expect(tracker.liveWPM == nil)
        #expect(tracker.allSessions().count == 1)
    }

    @Test func `a short burst counts presses without saving a session`() throws {
        let tracker = try makeTracker(clock: clock, minimumCharacters: nil)
        #expect(tracker.minimumCharacters == 25)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("quick burst of text")
        typist.pause()
        #expect(tracker.allSessions().isEmpty)
        tracker.endSession()
        #expect(tracker.pressCounts(in: history).values.reduce(0, +) == 19)
        #expect(tracker.keyStats(in: history).isEmpty)
        #expect(tracker.keyboards().map(\.id) == ["1452:834"])
        #expect(tracker.inputSourceRecords().map(\.id) == ["com.apple.keylayout.US"])
    }

    @Test func `shortcuts navigation and other key-downs count without an open session`() throws {
        let tracker = try makeTracker(clock: clock)
        press(8, to: tracker, command: true)
        for code: UInt16 in [123, 124, 125, 126, 53, 122, 51, 36] { press(code, to: tracker) }
        tracker.endSession()
        #expect(tracker.allSessions().isEmpty)
        #expect(tracker.pressCounts(in: history) == [8: 1, 123: 1, 124: 1, 125: 1, 126: 1, 53: 1, 122: 1, 51: 1, 36: 1])
    }

    @Test(arguments: [UInt16(0), 51, 123, 36])
    func `held-key repeats never add presses`(code: UInt16) throws {
        let tracker = try makeTracker(clock: clock)
        press(code, to: tracker)
        for _ in 0..<3 { press(code, to: tracker, isRepeat: true) }
        tracker.endSession()
        #expect(tracker.pressCounts(in: history) == [code: 1])
    }

    @Test(arguments: ["session save", "endSession", "60 ticks"])
    func `pending presses flush at each save boundary`(boundary: String) throws {
        let tracker = try makeTracker(clock: clock, minimumCharacters: nil)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("abc")
        #expect(try tracker.store?.pressCounts(in: history).isEmpty == true)
        var expected = 3
        switch boundary {
        case "session save":
            typist.type(String(repeating: "a", count: 25))
            typist.pause()
            expected = 28
            #expect(tracker.allSessions().count == 1)
        case "endSession":
            tracker.endSession()
        default:
            for _ in 0..<59 { clock.advance(1); tracker.tick() }
            #expect(try tracker.store?.pressCounts(in: history).isEmpty == true)
            clock.advance(1)
            tracker.tick()
        }
        #expect(try tracker.store?.pressCounts(in: history).values.reduce(0, +) == expected)
        tracker.endSession()
        tracker.endSession()
        #expect(tracker.pressCounts(in: history).values.reduce(0, +) == expected)
    }

    @Test func `deleting an app removes pending and stored presses for only that app`() throws {
        let tracker = try makeTracker(clock: clock)
        var typist = Typist(tracker: tracker, clock: clock)
        typist.type("aaa")
        tracker.endSession()
        typist.appID = "com.apple.mail"
        typist.type("bbb")
        tracker.endSession()
        typist.type("bb")
        typist.appID = "com.apple.Notes"
        typist.type("aa")
        tracker.deleteHistory(appID: "com.apple.Notes")
        tracker.endSession()
        #expect(tracker.pressCounts(in: history) == [USKeys.code(for: "b"): 5])
        #expect(tracker.pressCounts(in: history, filter: StatFilter(appID: "com.apple.Notes")).isEmpty)
        #expect(tracker.pressCounts(in: history, filter: StatFilter(appID: "com.apple.mail")).values.reduce(0, +) == 5)
    }

    @Test func `deleting all history clears pending and stored presses`() throws {
        let tracker = try makeTracker(clock: clock)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("abc")
        tracker.endSession()
        typist.type("def")
        tracker.deleteAllHistory()
        tracker.endSession()
        #expect(tracker.pressCounts(in: history).isEmpty)
    }

    @Test func `presses retain the hour app keyboard and layout seen on arrival`() throws {
        let tracker = try makeTracker(clock: clock)
        var typist = Typist(tracker: tracker, clock: clock)
        let firstHour = Hour.index(clock.date)
        typist.type("aa")
        clock.advance(3600)
        typist.appID = "com.apple.mail"
        typist.keyboard = SampleData.mxKeys
        typist.inputSource = SampleData.british
        typist.type("bbb")
        tracker.endSession()
        let first = DateInterval(start: Date(timeIntervalSince1970: Double(firstHour) * 3600), duration: 3600)
        #expect(tracker.pressCounts(in: first) == [USKeys.code(for: "a"): 2])
        #expect(tracker.pressCounts(in: history, filter: StatFilter(appID: "com.apple.mail", keyboardID: SampleData.mxKeys.id, inputSourceID: SampleData.british.id)) == [USKeys.code(for: "b"): 3])
    }

    @Test func `all-time and comparison press totals include short bursts`() throws {
        let tracker = try makeTracker(clock: clock, minimumCharacters: nil)
        let now = clock.date
        clock.date = now.addingTimeInterval(-86_400)
        let typist = Typist(tracker: tracker, clock: clock)
        typist.type("abc")
        tracker.endSession()
        clock.date = now
        typist.type("abcdef")
        tracker.endSession()
        let today = PeriodData(.today, tracker: tracker, now: now)
        #expect(today.sessions.isEmpty)
        #expect(today.presses == 6)
        #expect(today.previousPresses == 3)
        let all = PeriodData(.allTime, tracker: tracker, now: now)
        #expect(all.interval != nil)
        #expect(all.presses == 9)
        #expect(all.previousPresses == nil)
    }

    private var history: DateInterval { DateInterval(start: .distantPast, end: .distantFuture) }

    private func press(_ code: UInt16, to tracker: LiveTracker, isRepeat: Bool = false, command: Bool = false) {
        clock.advance(0.2)
        tracker.handle(ObservedKey(keyCode: code, time: clock.uptime, text: "", commandOrControl: command,
                                   command: command, option: false, isRepeat: isRepeat, sourceStateID: 1, sourceProcessID: 0),
                       appID: "com.apple.Notes", keyboard: nil, inputSource: nil)
    }
}
