import Testing
import KeypaceCore

@MainActor
struct KeyRankingsTests {
    private let keys: [UInt16: KeyCount] = [
        0: KeyCount(presses: 20, corrections: 2),
        1: KeyCount(presses: 20, corrections: 3),
        43: KeyCount(presses: 20, corrections: 1),
        36: KeyCount(presses: 20, corrections: 20),
        48: KeyCount(presses: 20, corrections: 19),
        49: KeyCount(presses: 20, corrections: 18),
        51: KeyCount(presses: 20, corrections: 17),
        2: KeyCount(presses: 19, corrections: 19),
    ]

    @Test func `saved layout labels preserve printable keys and reject whitespace and unknown keys`() {
        let layout = InputSourceRecord(id: "custom", name: "Custom", lastSeen: .now,
                                       labels: [10: "§", 44: "?", 36: "A", 48: "B", 0: "\u{00A0}"])
        #expect(KeyLabels.isPrintable(10, using: nil, layout: layout))
        #expect(KeyLabels.isPrintable(44, using: nil, layout: layout))
        #expect(!KeyLabels.isPrintable(36, using: nil, layout: layout))
        #expect(!KeyLabels.isPrintable(48, using: nil, layout: layout))
        #expect(!KeyLabels.isPrintable(0, using: nil, layout: layout))
        #expect(!KeyLabels.isPrintable(76, using: nil, layout: layout))
        #expect(!KeyLabels.isPrintable(999, using: nil, layout: layout))
    }

    @Test(arguments: [4, 6])
    func `dropdown and page corrected rankings exclude control keys`(limit: Int) {
        let ranked = KeyRankings.corrected(keys, sources: nil, limit: limit)
        #expect(ranked.map(\.key) == [1, 0, 43])
        #expect(keys[36]?.presses == 20 && keys[49]?.presses == 20)
    }

    @Test(arguments: [(true, 3), (true, 6), (false, 6)])
    func `dropdown slowest and page slowest and fastest exclude whitespace pairs`(slowest: Bool, limit: Int) {
        var pairs: [KeyPair: PairTiming] = [:]
        for (pair, milliseconds) in [
            (KeyPair(from: 36, to: 0), 800.0),
            (KeyPair(from: 49, to: 3), 700),
            (KeyPair(from: 48, to: 0), 600),
            (KeyPair(from: 0, to: 36), 1),
            (KeyPair(from: 0, to: 48), 2),
            (KeyPair(from: 0, to: 49), 3),
            (KeyPair(from: 0, to: 1), 200),
            (KeyPair(from: 1, to: 0), 100),
            (KeyPair(from: 43, to: 0), 50),
        ] {
            pairs[pair] = PairTiming(count: 5, totalMilliseconds: milliseconds * 5)
        }
        pairs[KeyPair(from: 2, to: 0)] = PairTiming(count: 4, totalMilliseconds: 4_000)
        let ranked = KeyRankings.pairs(pairs, slowest: slowest, sources: nil, limit: limit)
        let visible = [KeyPair(from: 0, to: 1), KeyPair(from: 1, to: 0), KeyPair(from: 43, to: 0)]
        #expect(ranked.map(\.pair) == (slowest ? visible : visible.reversed()))
        #expect(pairs[KeyPair(from: 49, to: 3)]?.count == 5)
    }
}
