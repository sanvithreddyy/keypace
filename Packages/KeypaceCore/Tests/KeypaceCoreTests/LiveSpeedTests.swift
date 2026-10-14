import Testing
@testable import KeypaceCore

struct LiveSpeedTests {
    @Test func `live speed leaves out the same thinking pauses as saved speed`() throws {
        var tracker = SessionTracker()
        let context = TypingContext(appID: "notes")
        for start in [0.0, 3.8] {
            for i in 0..<10 {
                _ = tracker.record(KeyPress(time: start + Double(i) * 0.2, keyCode: 0, kind: .character), in: context)
            }
        }
        let live = try #require(tracker.live.wordsPerMinute(at: 5.6))
        let ended = tracker.end()
        let saved = try #require(ended?.totals.wpm)
        #expect(abs(live - 60) < 1e-9)
        #expect(abs(saved - 60) < 1e-9)
    }

    @Test func `live corrections after a pause still reduce net speed`() throws {
        var tracker = SessionTracker()
        let context = TypingContext(appID: "notes")
        for i in 0..<12 {
            _ = tracker.record(KeyPress(time: Double(i) * 0.2, keyCode: 0, kind: .character), in: context)
        }
        for time in [4.2, 4.4] {
            _ = tracker.record(KeyPress(time: time, keyCode: 51, kind: .backspace), in: context)
        }
        let live = try #require(tracker.live.wordsPerMinute(at: 4.4))
        // The first character marks the window start; 11 characters minus 2 corrections over 13 typing gaps.
        let expected = 9.0 * 12 / 2.6
        #expect(abs(live - expected) < 1e-9)
        let ended = tracker.end()
        #expect(ended?.characters == 12)
        #expect(ended?.deletions == 2)
        #expect(abs(try #require(ended?.activeDuration) - 2.8) < 1e-9)
    }

    @Test func `live speed reuses the learned cutoff for slower typing`() throws {
        var tracker = SessionTracker()
        let context = TypingContext(appID: "notes")
        for i in 0..<40 {
            _ = tracker.record(KeyPress(time: Double(i) * 0.3, keyCode: 0, kind: .character), in: context)
        }
        for i in 0..<10 {
            _ = tracker.record(KeyPress(time: 12.6 + Double(i) * 0.3, keyCode: 0, kind: .character), in: context)
        }
        let live = try #require(tracker.live.wordsPerMinute(at: 15.3))
        // The learned 1.2-second cutoff retains the 0.9-second gap; the 8-second window starts at 7.5.
        #expect(abs(live - 24.0 * 12 / 7.8) < 1e-9)
    }

    private func typed(_ times: [Double], deletions: [Double: Int] = [:]) -> LiveSpeed {
        var live = LiveSpeed()
        for (index, t) in times.enumerated() {
            live.record(at: t, characters: deletions[t].map { -$0 } ?? 1,
                        typingSeconds: index > 0 ? t - times[index - 1] : 0)
        }
        return live
    }

    @Test func `counts the characters after the first over the span`() throws {
        // 11 characters 0.2 s apart: 10 gaps in 2 s → 10 characters / 5 per 2 s = 60 wpm.
        let live = typed((0...10).map { Double($0) * 0.2 })
        let wpm = try #require(live.wordsPerMinute(at: 2.0))
        #expect(abs(wpm - 60) < 1e-9)
    }

    @Test func `only the last 8 seconds count`() throws {
        let slow = (0..<10).map { Double($0) * 1.0 } // 1 per second, up to t = 9
        let fast = (1...20).map { 9 + Double($0) * 0.1 } // then 10 per second, up to t = 11
        let live = typed(slow + fast)
        // Window starts at t = 3: slow events at 3...9 (6 after the first) + 20 fast, over 8 s.
        let wpm = try #require(live.wordsPerMinute(at: 11))
        let expected: Double = 26.0 / 5 / (8.0 / 60)
        #expect(abs(wpm - expected) < 1e-9)
    }

    @Test func `goes quiet two seconds after typing stops, or with too few keys`() {
        let live = typed([0, 0.2, 0.4, 0.6])
        #expect(live.wordsPerMinute(at: 2.6) != nil)
        #expect(live.wordsPerMinute(at: 2.61) == nil)
        #expect(typed([0, 0.2]).wordsPerMinute(at: 0.3) == nil)
    }

    @Test func `deletions take characters back`() throws {
        // Four characters, then one deletion removing two, all 0.25 s apart.
        let live = typed([0, 0.25, 0.5, 0.75, 1.0], deletions: [1.0: 2])
        let wpm = try #require(live.wordsPerMinute(at: 1))
        let expected: Double = 1.0 / 5 / (1.0 / 60)
        #expect(abs(wpm - expected) < 1e-9)
    }
}
