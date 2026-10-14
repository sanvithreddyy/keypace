/// Where typing happened. A change of context ends the current session.
public struct TypingContext: Sendable, Hashable {
    public var appID: String
    public var keyboardID: String?
    public var inputSourceID: String?

    public init(appID: String, keyboardID: String? = nil, inputSourceID: String? = nil) {
        self.appID = appID
        self.keyboardID = keyboardID
        self.inputSourceID = inputSourceID
    }
}

/// Counts over some amount of typing time, and the speeds derived from them.
/// Summing totals and then deriving speed weights every session by its length.
public struct TypingTotals: Sendable, Equatable {
    public var characters = 0
    public var backspaces = 0
    /// Physical presses of any kind; held-key repeats are not presses.
    public var keystrokes = 0
    /// Seconds of typing.
    public var duration = 0.0

    public init(characters: Int = 0, backspaces: Int = 0, keystrokes: Int = 0, duration: Double = 0) {
        self.characters = characters
        self.backspaces = backspaces
        self.keystrokes = keystrokes
        self.duration = duration
    }

    public var netCharacters: Int { max(characters - backspaces, 0) }

    /// Net characters per minute, five characters to a word.
    public var wpm: Double? { cpm.map { $0 / 5 } }
    public var cpm: Double? { perMinute(netCharacters) }
    public var kpm: Double? { perMinute(keystrokes) }

    /// Backspaces per character typed. Counts every correction, including deliberate rewrites.
    public var correctionRate: Double? {
        characters > 0 ? Double(backspaces) / Double(characters) : nil
    }

    private func perMinute(_ count: Int) -> Double? {
        duration > 0 ? Double(count) * 60 / duration : nil
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            characters: lhs.characters + rhs.characters,
            backspaces: lhs.backspaces + rhs.backspaces,
            keystrokes: lhs.keystrokes + rhs.keystrokes,
            duration: lhs.duration + rhs.duration
        )
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}

/// A stretch of typing with no pause longer than the inactivity timeout.
public struct TypingSession: Sendable, Equatable {
    public var context: TypingContext
    /// Time of the first counted press.
    public var start: Double
    /// Time of the last character or backspace.
    public var end: Double
    public var characters = 0
    public var backspaces = 0
    public var keystrokes = 0
    /// Per physical key: presses, and characters later deleted.
    public var keys: [UInt16: KeyCount] = [:]
    /// Time between consecutive character presses, per key pair.
    public var pairs: [KeyPair: PairTiming] = [:]

    public var duration: Double { end - start }

    public var totals: TypingTotals {
        TypingTotals(characters: characters, backspaces: backspaces, keystrokes: keystrokes, duration: duration)
    }
}
