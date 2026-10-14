import Testing
@testable import KeypaceCore

struct KeyboardGeometryTests {
    typealias G = KeyboardGeometry

    @Test func `every key code appears once`() {
        let codes = G.keys.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
        #expect(codes.count == 54) // 14 number row, 14 top, 13 home, 12 bottom, Space
    }

    @Test func `touch-typing fingers for familiar keys`() {
        #expect(G.key(0)?.finger == .leftPinky) // A
        #expect(G.key(17)?.finger == .leftIndex) // T
        #expect(G.key(16)?.finger == .rightIndex) // Y
        #expect(G.key(41)?.finger == .rightPinky) // ;
        #expect(G.key(49)?.finger == .thumb) // Space
    }

    @Test func `reach is zero at home and one key pitch straight up`() throws {
        #expect(G.reach(3) == 0) // F
        #expect(G.reach(49) == 0) // Space
        // R sits a quarter key left of F's column, one row up.
        let r = try #require(G.reach(15))
        #expect(abs(r - (0.25 * 0.25 + 1).squareRoot() * G.keyPitch) < 1e-9)
        #expect(G.reach(999) == nil)
    }

    @Test func `finger stats from counts`() throws {
        // F ×6 (home), R ×2 (reach), J ×2 (home), Space ×10.
        let keys: [UInt16: KeyCount] = [3: KeyCount(presses: 6), 15: KeyCount(presses: 2), 38: KeyCount(presses: 2), 49: KeyCount(presses: 10)]
        let pairs: [KeyPair: PairTiming] = [
            KeyPair(from: 3, to: 38): PairTiming(count: 3), // F→J alternates hands
            KeyPair(from: 15, to: 3): PairTiming(count: 1), // R→F same finger
            KeyPair(from: 3, to: 3): PairTiming(count: 1), // repeated key: not a same-finger switch
            KeyPair(from: 3, to: 49): PairTiming(count: 5), // thumb pairs are left out
        ]
        let stats = FingerStats(keys: keys, pairs: pairs)
        #expect(stats.load[.leftIndex] == 0.4)
        #expect(stats.load[.thumb] == 0.5)
        #expect(stats.leftShare == 0.8)
        #expect(stats.homeRowShare == 0.8)
        #expect(stats.handAlternation == 0.6)
        #expect(stats.sameFinger == 0.2)
        let expectedTravel = 2 * 2 * (G.reach(15) ?? 0) / 1000
        #expect(abs(stats.travelMetres - expectedTravel) < 1e-12)
    }
}
