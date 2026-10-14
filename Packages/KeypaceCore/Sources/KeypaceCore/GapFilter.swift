/// Decides whether the gap before a keystroke was typing or a pause.
///
/// A gap counts as typing when it's under `medianMultiple` times your usual gap, clamped between
/// `floor` and `ceiling`. "Usual" is the median of recent typing gaps for the same key pair once it has
/// enough samples, else for the same key, else across all keys. Before there's any history, gaps up to
/// `coldStart` count. Only gaps judged as typing are remembered.
public struct GapFilter: Sendable {
    public struct Config: Sendable {
        public var medianMultiple = 4.0
        /// Seconds.
        public var floor = 0.25
        public var ceiling = 3.0
        public var coldStart = 0.6
        public var minimumPairSamples = 25
        public var minimumKeySamples = 50
        public var minimumGlobalSamples = 40
        /// How many recent gaps each median looks at.
        public var pairWindow = 50
        public var keyWindow = 100
        public var globalWindow = 300
        /// The typical gap before there's any history, in seconds.
        public var defaultGap = 0.2

        public init() {}
    }

    public let config: Config
    private var pairs: [KeyPair: RecentValues] = [:]
    private var keys: [UInt16: RecentValues] = [:]
    private var global: RecentValues

    public init(config: Config = Config()) {
        self.config = config
        global = RecentValues(capacity: config.globalWindow)
    }

    /// The longest gap, in seconds, that still counts as typing between these two keys.
    public func threshold(from: UInt16, to: UInt16) -> Double {
        let reference: Double? = {
            if let pair = pairs[KeyPair(from: from, to: to)], pair.count >= config.minimumPairSamples { return pair.median }
            if let key = keys[to], key.count >= config.minimumKeySamples { return key.median }
            if global.count >= config.minimumGlobalSamples { return global.median }
            return nil
        }()
        guard let reference else { return config.coldStart }
        return min(max(reference * config.medianMultiple, config.floor), config.ceiling)
    }

    /// Judges a gap and remembers it if it counts as typing.
    public mutating func accepts(_ gap: Double, from: UInt16, to: UInt16) -> Bool {
        guard gap.isFinite, gap >= 0, gap <= threshold(from: from, to: to) else { return false }
        pairs[KeyPair(from: from, to: to), default: RecentValues(capacity: config.pairWindow)].append(gap)
        keys[to, default: RecentValues(capacity: config.keyWindow)].append(gap)
        global.append(gap)
        return true
    }

    /// Your usual gap across all keys, used as the time of a keystroke that follows a pause.
    public var typicalGap: Double {
        global.count > 0 ? global.median : config.defaultGap
    }
}

/// The most recent values up to a capacity.
struct RecentValues: Sendable {
    private var values: [Double] = []
    private var next = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    var count: Int { values.count }

    mutating func append(_ value: Double) {
        if values.count < capacity {
            values.append(value)
        } else {
            values[next] = value
            next = (next + 1) % capacity
        }
    }

    var median: Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
