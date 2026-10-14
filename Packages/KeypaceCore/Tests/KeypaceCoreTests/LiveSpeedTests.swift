import Testing
@testable import KeypaceCore

struct LiveSpeedTests {
    private func typed(_ times: [Double], deletions: [Double: Int] = [:]) -> LiveSpeed {
        var live = LiveSpeed()
        for t in times { live.record(at: t, characters: deletions[t].map { -$0 } ?? 1) }
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
