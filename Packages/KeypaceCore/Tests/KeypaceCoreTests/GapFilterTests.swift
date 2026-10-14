import Testing
@testable import KeypaceCore

struct GapFilterTests {
    @Test func `before any history, gaps up to 600 ms count`() {
        var filter = GapFilter()
        let r1 = filter.accepts(0.6, from: 0, to: 1)
        #expect(r1)
        let r2 = filter.accepts(0.61, from: 0, to: 1)
        #expect(!r2)
        #expect(filter.typicalGap == 0.6)
    }

    @Test func `with enough history the cutoff is four times the usual gap`() {
        var filter = GapFilter()
        for _ in 0..<40 { _ = filter.accepts(0.15, from: 0, to: 1) }
        // Too few samples for the pair (25) or key (50) yet, so the global median, 150 ms, sets it.
        #expect(abs(filter.threshold(from: 3, to: 4) - 0.6) < 1e-9)
        let r3 = filter.accepts(0.59, from: 3, to: 4)
        #expect(r3)
        let r4 = filter.accepts(0.65, from: 3, to: 4)
        #expect(!r4)
    }

    @Test func `a slow key pair gets its own, longer cutoff`() {
        var filter = GapFilter()
        for _ in 0..<40 { _ = filter.accepts(0.12, from: 0, to: 1) }
        for _ in 0..<25 { _ = filter.accepts(0.4, from: 7, to: 8) }
        #expect(abs(filter.threshold(from: 7, to: 8) - 1.6) < 1e-9)
        #expect(abs(filter.threshold(from: 9, to: 10) - filter.threshold(from: 0, to: 2)) < 1e-9)
    }

    @Test func `the cutoff stays between 250 ms and 3 s`() {
        var fast = GapFilter()
        for _ in 0..<40 { _ = fast.accepts(0.03, from: 0, to: 1) }
        #expect(fast.threshold(from: 5, to: 6) == 0.25)

        var config = GapFilter.Config()
        config.coldStart = 2
        var slow = GapFilter(config: config)
        for _ in 0..<40 { _ = slow.accepts(1.5, from: 0, to: 1) }
        #expect(slow.threshold(from: 5, to: 6) == 3)
    }

    @Test func `pauses aren't remembered, so they can't stretch the cutoff`() {
        var filter = GapFilter()
        for _ in 0..<40 { _ = filter.accepts(0.15, from: 0, to: 1) }
        for _ in 0..<100 { _ = filter.accepts(5, from: 0, to: 1) }
        #expect(abs(filter.threshold(from: 3, to: 4) - 0.6) < 1e-9)
    }

    @Test func `the typical gap is the median of recent typing`() {
        var filter = GapFilter()
        for gap in [0.1, 0.2, 0.3] { _ = filter.accepts(gap, from: 0, to: 1) }
        #expect(abs(filter.typicalGap - 0.2) < 1e-9)
    }
}
