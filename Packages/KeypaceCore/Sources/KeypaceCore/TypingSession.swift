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
    /// Delete presses, including held repeats and deletes of text typed earlier.
    public var backspaces = 0
    /// Characters typed in the session and then deleted again.
    public var deletions = 0
    /// Physical presses of any kind; held-key repeats are not presses.
    public var keystrokes = 0
    /// Seconds of typing, with pauses left out.
    public var duration = 0.0

    /// - Parameter deletions: defaults to `backspaces`, how sessions were counted before deletions were tracked.
    public init(characters: Int = 0, backspaces: Int = 0, deletions: Int? = nil, keystrokes: Int = 0, duration: Double = 0) {
        self.characters = characters
        self.backspaces = backspaces
        self.deletions = deletions ?? backspaces
        self.keystrokes = keystrokes
        self.duration = duration
    }

    /// Characters that stayed: typed minus deleted again.
    public var netCharacters: Int { max(characters - deletions, 0) }

    /// Net characters per minute, five characters to a word.
    public var wpm: Double? { cpm.map { $0 / 5 } }
    public var cpm: Double? { perMinute(netCharacters) }
    public var kpm: Double? { perMinute(keystrokes) }

    /// Share of typed characters deleted again. Counts every correction, including deliberate rewrites.
    public var correctionRate: Double? {
        characters > 0 ? Double(deletions) / Double(characters) : nil
    }

    private func perMinute(_ count: Int) -> Double? {
        duration > 0 ? Double(count) * 60 / duration : nil
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            characters: lhs.characters + rhs.characters,
            backspaces: lhs.backspaces + rhs.backspaces,
            deletions: lhs.deletions + rhs.deletions,
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
    /// Time of the last character or deletion.
    public var end: Double
    public var characters = 0
    public var backspaces = 0
    /// Characters typed in this session and deleted again.
    public var deletions = 0
    public var keystrokes = 0
    /// Seconds of typing between `start` and `end`, with pauses left out.
    public var activeDuration = 0.0
    /// Per physical key: characters typed (or Delete presses), and characters later deleted.
    public var keys: [UInt16: KeyCount] = [:]
    /// Time between consecutive character presses, per key pair.
    public var pairs: [KeyPair: PairTiming] = [:]

    /// Seconds from the first press to the last, pauses included.
    public var duration: Double { end - start }

    public var totals: TypingTotals {
        TypingTotals(characters: characters, backspaces: backspaces, deletions: deletions, keystrokes: keystrokes, duration: activeDuration)
    }
}
