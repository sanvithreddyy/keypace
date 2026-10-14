import KeypaceCore

/// The same sample thresholds and ranking rules for the dropdown and the Keys page.
enum KeyRankings {
    static let minimumPresses = 20
    static let minimumPairCount = 5

    static func corrected(_ keys: [UInt16: KeyCount], sources: InputSources?, layout: InputSourceRecord? = nil,
                          limit: Int) -> [(key: UInt16, count: KeyCount)] {
        keys.filter {
            $0.value.presses >= minimumPresses && $0.value.corrections > 0
                && KeyLabels.isPrintable($0.key, using: sources, layout: layout)
        }
            .sorted { ($0.value.correctionRate ?? 0) > ($1.value.correctionRate ?? 0) }
            .prefix(limit)
            .map { (key: $0.key, count: $0.value) }
    }

    static func pairs(_ pairs: [KeyPair: PairTiming], slowest: Bool, sources: InputSources?,
                      layout: InputSourceRecord? = nil, limit: Int) -> [(pair: KeyPair, timing: PairTiming)] {
        pairs.filter {
            $0.value.count >= minimumPairCount
                && KeyLabels.isPrintable($0.key.from, using: sources, layout: layout)
                && KeyLabels.isPrintable($0.key.to, using: sources, layout: layout)
        }
            .sorted {
                slowest ? ($0.value.averageMilliseconds ?? 0) > ($1.value.averageMilliseconds ?? 0)
                    : ($0.value.averageMilliseconds ?? 0) < ($1.value.averageMilliseconds ?? 0)
            }
            .prefix(limit)
            .map { (pair: $0.key, timing: $0.value) }
    }
}
