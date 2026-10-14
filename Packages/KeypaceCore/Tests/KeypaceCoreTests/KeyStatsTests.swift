import Testing
@testable import KeypaceCore

private let notes = TypingContext(appID: "com.apple.Notes")

/// macOS virtual key codes used below.
private enum Key {
    static let t: UInt16 = 17, h: UInt16 = 4, e: UInt16 = 14, space: UInt16 = 49, delete: UInt16 = 51, left: UInt16 = 123
}

private func press(_ key: UInt16, at time: Double, repeat isRepeat: Bool = false) -> KeyPress {
    let kind: KeyPress.Kind = key == Key.delete ? .backspace : key == Key.left ? .other : .character
    return KeyPress(time: time, keyCode: key, kind: kind, isRepeat: isRepeat)
}

private func run(_ presses: [KeyPress]) -> TypingSession? {
    var tracker = SessionTracker(minimumCharacters: 1)
    for p in presses { _ = tracker.record(p, in: notes) }
    return tracker.end()
}

struct KeyStatsTests {
    @Test func `presses are counted per physical key`() throws {
        let session = try #require(run([press(Key.t, at: 0), press(Key.h, at: 0.1), press(Key.e, at: 0.2), press(Key.space, at: 0.3), press(Key.t, at: 0.4)]))
        #expect(session.keys[Key.t]?.presses == 2)
        #expect(session.keys[Key.space]?.presses == 1)
    }

    @Test func `a backspace is charged to the key whose character it deletes`() throws {
        // Types "teh", deletes "h" and "e", then types "he".
        let session = try #require(run([
            press(Key.t, at: 0), press(Key.e, at: 0.1), press(Key.h, at: 0.2),
            press(Key.delete, at: 0.5), press(Key.delete, at: 0.6),
            press(Key.h, at: 0.8), press(Key.e, at: 0.9),
        ]))
        #expect(session.keys[Key.h] == KeyCount(presses: 2, corrections: 1))
        #expect(session.keys[Key.e] == KeyCount(presses: 2, corrections: 1))
        #expect(session.keys[Key.t] == KeyCount(presses: 1, corrections: 0))
        #expect(session.keys[Key.delete]?.presses == 2)
    }

    @Test func `held delete charges every deleted key but counts one press`() throws {
        let session = try #require(run([
            press(Key.t, at: 0), press(Key.h, at: 0.1), press(Key.e, at: 0.2),
            press(Key.delete, at: 0.5), press(Key.delete, at: 0.55, repeat: true), press(Key.delete, at: 0.6, repeat: true),
        ]))
        #expect(session.keys[Key.delete]?.presses == 1)
        #expect(session.backspaces == 3)
        #expect([Key.t, Key.h, Key.e].allSatisfy { session.keys[$0]?.corrections == 1 })
    }

    @Test func `pair timings cover consecutive characters only`() throws {
        let session = try #require(run([
            press(Key.t, at: 0), press(Key.h, at: 0.12), press(Key.e, at: 0.30),
            press(Key.delete, at: 0.5), press(Key.e, at: 0.7), // delete breaks the chain
            press(Key.left, at: 0.8), press(Key.t, at: 0.9), // so does another key
            press(Key.h, at: 3.5), // a 2.6 s gap is a pause, not a transition
            press(Key.e, at: 3.6),
        ]))
        let th = try #require(session.pairs[KeyPair(from: Key.t, to: Key.h)])
        #expect(th.count == 1)
        #expect(abs(th.totalMilliseconds - 120) < 1e-6)
        #expect(session.pairs[KeyPair(from: Key.h, to: Key.e)]?.count == 2)
        #expect(session.pairs.count == 2)
    }

    @Test func `deletions don't reach into the previous session`() throws {
        var tracker = SessionTracker(inactivityTimeout: 5, minimumCharacters: 1)
        _ = tracker.record(press(Key.t, at: 0), in: notes)
        let closed = tracker.record(press(Key.delete, at: 10), in: notes)
        #expect(closed?.keys[Key.t]?.corrections == 0)
        #expect(tracker.current?.keys[Key.t] == nil)
    }
}

struct LongSessionTests {
    @Test func `every deletion is attributed, however long the session`() throws {
        var tracker = SessionTracker(minimumCharacters: 1)
        for i in 0..<300 { _ = tracker.record(KeyPress(time: Double(i) * 0.1, keyCode: 0, kind: .character), in: TypingContext(appID: "a")) }
        _ = tracker.record(KeyPress(time: 30.1, keyCode: 51, kind: .backspace), in: TypingContext(appID: "a"))
        for i in 1..<300 { _ = tracker.record(KeyPress(time: 30.1 + Double(i) * 0.03, keyCode: 51, kind: .backspace, isRepeat: true), in: TypingContext(appID: "a")) }
        let ended = tracker.end()
        let session = try #require(ended)
        #expect(session.backspaces == 300)
        #expect(session.keys[0]?.corrections == 300)
    }
}
