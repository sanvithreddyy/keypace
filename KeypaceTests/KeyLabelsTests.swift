import Testing
import KeypaceCore

@MainActor
struct KeyLabelsTests {
    @Test func `named keys keep their names even when a saved layout has characters for them`() {
        let layout = InputSourceRecord(id: "com.apple.keylayout.US", name: "U.S.", lastSeen: .now, labels: [48: "\t", 36: "\r", 51: "\u{08}", 1: "S"])
        #expect(KeyLabels.label(48, using: nil, layout: layout) == "tab")
        #expect(KeyLabels.label(36, using: nil, layout: layout) == "return")
        #expect(KeyLabels.label(51, using: nil, layout: layout) == "delete")
        #expect(KeyLabels.label(1, using: nil, layout: layout) == "S")
        #expect(KeyLabels.pair((48, 49), using: nil, layout: layout) == "⇥ → ␣")
        #expect(KeyLabels.pair((36, 36), using: nil, layout: layout) == "⏎ → ⏎")
    }

    @Test func `without a layout, keys fall back to US labels`() {
        #expect(KeyLabels.label(12, using: nil) == "Q")
        #expect(KeyLabels.label(49, using: nil) == "space")
    }
}
