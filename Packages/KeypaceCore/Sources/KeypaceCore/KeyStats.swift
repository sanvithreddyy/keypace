/// Characters typed with one physical key (or Delete presses), and how many of those characters were deleted.
public struct KeyCount: Sendable, Equatable {
    public var presses = 0
    public var corrections = 0

    public init(presses: Int = 0, corrections: Int = 0) {
        self.presses = presses
        self.corrections = corrections
    }

    /// Share of this key's characters that were deleted again.
    public var correctionRate: Double? {
        presses > 0 ? Double(corrections) / Double(presses) : nil
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(presses: lhs.presses + rhs.presses, corrections: lhs.corrections + rhs.corrections)
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}

/// Two physical keys typed one after the other.
public struct KeyPair: Sendable, Hashable {
    public var from: UInt16
    public var to: UInt16

    public init(from: UInt16, to: UInt16) {
        self.from = from
        self.to = to
    }
}

/// How often a key pair was typed and the total time between its two presses.
public struct PairTiming: Sendable, Equatable {
    public var count = 0
    public var totalMilliseconds = 0.0

    public init(count: Int = 0, totalMilliseconds: Double = 0) {
        self.count = count
        self.totalMilliseconds = totalMilliseconds
    }

    public var averageMilliseconds: Double? {
        count > 0 ? totalMilliseconds / Double(count) : nil
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(count: lhs.count + rhs.count, totalMilliseconds: lhs.totalMilliseconds + rhs.totalMilliseconds)
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}
