import Testing
@testable import KeypaceCore

/// Runs presses through a filter and returns which were judged synthetic.
private func judge(_ strength: SyntheticFilter.Strength, _ presses: [(state: Int64, pid: Int64, time: Double, isRepeat: Bool)]) -> [Bool] {
    var filter = SyntheticFilter(strength: strength)
    return presses.map { filter.isSynthetic(sourceStateID: $0.state, sourceProcessID: $0.pid, time: $0.time, isRepeat: $0.isRepeat) }
}

struct SyntheticFilterTests {
    @Test func `hardware events pass and posted events are filtered`() {
        #expect(judge(.normal, [(1, 0, 0, false), (1, 812, 1, false), (0, 0, 2, false)]) == [false, true, true])
    }

    @Test func `off keeps everything`() {
        #expect(judge(.off, [(0, 812, 0, false)]) == [false])
    }

    @Test func `strict also drops presses faster than a person types`() {
        // The second press follows 2 ms after the first; key repeat is fast by design and isn't a burst.
        let presses: [(state: Int64, pid: Int64, time: Double, isRepeat: Bool)] = [(1, 0, 1.000, false), (1, 0, 1.002, false), (1, 0, 1.100, false), (1, 0, 1.101, true)]
        #expect(judge(.strict, presses) == [false, true, false, false])
        #expect(judge(.normal, presses) == [false, false, false, false])
    }
}
