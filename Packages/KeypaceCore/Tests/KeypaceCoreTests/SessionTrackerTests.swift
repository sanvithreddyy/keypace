import Testing
@testable import KeypaceCore

private let notes = TypingContext(appID: "com.apple.Notes")
private let mail = TypingContext(appID: "com.apple.mail")

private func char(_ t: Double) -> KeyPress { KeyPress(time: t, keyCode: 0, kind: .character) }
private func backspace(_ t: Double, held: Bool = false) -> KeyPress {
    KeyPress(time: t, keyCode: 51, kind: .backspace, isRepeat: held)
}

/// Types `count` characters starting at `start`, one every `interval` seconds.
private func type(_ count: Int, from start: Double, every interval: Double, into tracker: inout SessionTracker, context: TypingContext = notes) -> [TypingSession] {
    (0..<count).compactMap { tracker.record(char(start + Double($0) * interval), in: context) }
}

struct SessionTrackerTests {
    @Test func `steady typing gives net characters per minute over five`() throws {
        var tracker = SessionTracker()
        _ = type(30, from: 0, every: 0.2, into: &tracker)
        let ended = tracker.end()
        let session = try #require(ended)
        #expect(session.characters == 30)
        #expect(abs(session.duration - 5.8) < 1e-9)
        #expect(abs(try #require(session.totals.wpm) - 30 * 60 / 5.8 / 5) < 1e-9)
        #expect(abs(try #require(session.totals.kpm) - 30 * 60 / 5.8) < 1e-9)
    }

    @Test func `backspaces reduce net speed and set the correction rate`() throws {
        var tracker = SessionTracker()
        _ = type(20, from: 0, every: 0.25, into: &tracker)
        _ = tracker.record(backspace(5), in: notes)
        _ = tracker.record(backspace(5.25), in: notes)
        let ended = tracker.end()
        let session = try #require(ended)
        #expect(session.totals.netCharacters == 18)
        #expect(session.keystrokes == 22)
        #expect(session.totals.correctionRate == 0.1)
        #expect(abs(try #require(session.totals.wpm) - 18 * 60 / 5.25 / 5) < 1e-9)
    }

    @Test func `a pause longer than the timeout splits sessions`() throws {
        var tracker = SessionTracker(inactivityTimeout: 5)
        #expect(type(12, from: 0, every: 0.2, into: &tracker).isEmpty)
        let closed = type(12, from: 2.2 + 5.1, every: 0.2, into: &tracker)
        #expect(closed.count == 1)
        #expect(closed.first?.characters == 12)
        #expect(tracker.current?.characters == 12)
    }

    @Test func `a pause within the timeout stays in one session`() {
        var tracker = SessionTracker(inactivityTimeout: 5)
        _ = type(12, from: 0, every: 0.2, into: &tracker)
        #expect(type(12, from: 2.2 + 4.9, every: 0.2, into: &tracker).isEmpty)
        #expect(tracker.current?.characters == 24)
    }

    @Test func `idle check closes only after the timeout`() {
        var tracker = SessionTracker(inactivityTimeout: 5)
        _ = type(12, from: 0, every: 0.2, into: &tracker)
        #expect(tracker.closeIfIdle(at: 2.2 + 5) == nil)
        #expect(tracker.closeIfIdle(at: 2.2 + 5.01)?.characters == 12)
        #expect(tracker.current == nil)
    }

    @Test func `switching apps closes the session`() {
        var tracker = SessionTracker()
        _ = type(12, from: 0, every: 0.2, into: &tracker)
        let closed = tracker.record(char(2.4), in: mail)
        #expect(closed?.context == notes)
        #expect(tracker.current?.context == mail)
    }

    @Test func `held character repeats are ignored, held backspace deletes`() throws {
        var tracker = SessionTracker()
        _ = type(12, from: 0, every: 0.2, into: &tracker)
        _ = tracker.record(KeyPress(time: 2.3, keyCode: 0, kind: .character, isRepeat: true), in: notes)
        _ = tracker.record(backspace(2.5), in: notes)
        _ = tracker.record(backspace(2.6, held: true), in: notes)
        _ = tracker.record(backspace(2.7, held: true), in: notes)
        let ended = tracker.end()
        let session = try #require(ended)
        #expect(session.characters == 12)
        #expect(session.backspaces == 3)
        #expect(session.keystrokes == 13)
        #expect(session.end == 2.7)
    }

    @Test func `other keys count inside a session but never open or extend one`() throws {
        var tracker = SessionTracker()
        let arrow = KeyPress(time: 0, keyCode: 123, kind: .other)
        _ = tracker.record(arrow, in: notes)
        #expect(tracker.current == nil)

        _ = type(12, from: 1, every: 0.2, into: &tracker)
        _ = tracker.record(KeyPress(time: 4, keyCode: 123, kind: .other), in: notes)
        let ended = tracker.end()
        let session = try #require(ended)
        #expect(session.keystrokes == 13)
        #expect(abs(session.end - 3.2) < 1e-9)
    }

    @Test func `sessions under the minimum are discarded`() {
        var tracker = SessionTracker(minimumCharacters: 10)
        _ = type(9, from: 0, every: 0.2, into: &tracker)
        #expect(tracker.end() == nil)
        #expect(tracker.current == nil)
    }

    @Test func `a single press has no speed`() {
        let session = TypingSession(context: notes, start: 1, end: 1, characters: 1, keystrokes: 1)
        #expect(session.totals.wpm == nil)
        #expect(session.totals.kpm == nil)
    }
}
