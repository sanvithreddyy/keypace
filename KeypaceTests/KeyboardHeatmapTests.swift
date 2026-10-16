import Testing
import KeypaceCore

@MainActor
struct KeyboardHeatmapTests {
    @Test func `usage shading only includes drawable keys`() {
        let heatmap = KeyboardHeatmap(keys: [0: KeyCount(presses: 10), 1: KeyCount(presses: 5),
                                            123: KeyCount(presses: 100), 53: KeyCount(presses: 200),
                                            122: KeyCount(presses: 300)], mode: .usage) { String($0) }
        #expect(heatmap.values == [0: 10, 1: 5])
        #expect(heatmap.values.values.max() == 10)
    }

    @Test func `correction shading only includes eligible drawable keys`() {
        let heatmap = KeyboardHeatmap(keys: [0: KeyCount(presses: 20, corrections: 2),
                                            1: KeyCount(presses: 19, corrections: 19),
                                            51: KeyCount(presses: 20, corrections: 20),
                                            123: KeyCount(presses: 100, corrections: 100)], mode: .corrections) { String($0) }
        #expect(heatmap.values == [0: 0.1])
    }
}
