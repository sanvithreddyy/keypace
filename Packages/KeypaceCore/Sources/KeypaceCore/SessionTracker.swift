/// Splits key presses into sessions.
///
/// Characters and backspaces open and extend a session. Other keys count as keystrokes
/// inside an open session but neither open one nor extend it, so time spent navigating
/// with arrows or shortcuts doesn't dilute speed. Held-key character repeats are ignored;
/// backspace repeats each delete a character, so they count as backspaces.
///
/// Each backspace is charged to the key that typed the character it deletes. Key-pair
/// timings cover consecutive character presses less than `maximumPairGap` apart; a
/// backspace or any other key breaks the chain.
public struct SessionTracker: Sendable {
    public var inactivityTimeout: Double
    /// Sessions with fewer characters than this are discarded when they close.
    public var minimumCharacters: Int
    /// Gaps longer than this are pauses, not transitions between keys.
    public var maximumPairGap = 2.0
    public private(set) var current: TypingSession?

    /// Keys of characters typed and not yet deleted, most recent last.
    private var typedKeys: [UInt16] = []
    private var lastCharacter: (keyCode: UInt16, time: Double)?
    private static let typedKeysLimit = 256

    public init(inactivityTimeout: Double = 5, minimumCharacters: Int = 10) {
        self.inactivityTimeout = inactivityTimeout
        self.minimumCharacters = minimumCharacters
    }

    /// Records a press and returns the session it closed, if any.
    public mutating func record(_ press: KeyPress, in context: TypingContext) -> TypingSession? {
        var closed: TypingSession?
        if let session = current, session.context != context || press.time - session.end > inactivityTimeout {
            closed = end()
        }

        switch (press.kind, press.isRepeat) {
        case (.character, true), (.other, true):
            break
        case (.other, false):
            guard current != nil else { break }
            current?.keystrokes += 1
            current?.keys[press.keyCode, default: KeyCount()].presses += 1
            lastCharacter = nil
        case (.character, false):
            var session = open(in: context, at: press.time)
            session.characters += 1
            session.keystrokes += 1
            session.keys[press.keyCode, default: KeyCount()].presses += 1
            if let last = lastCharacter, press.time - last.time <= maximumPairGap {
                session.pairs[KeyPair(from: last.keyCode, to: press.keyCode), default: PairTiming()] += PairTiming(count: 1, totalMilliseconds: (press.time - last.time) * 1000)
            }
            lastCharacter = (press.keyCode, press.time)
            typedKeys.append(press.keyCode)
            if typedKeys.count > Self.typedKeysLimit { typedKeys.removeFirst() }
            current = session
        case (.backspace, _):
            var session = open(in: context, at: press.time)
            session.backspaces += 1
            if !press.isRepeat {
                session.keystrokes += 1
                session.keys[press.keyCode, default: KeyCount()].presses += 1
            }
            if let deleted = typedKeys.popLast() { session.keys[deleted, default: KeyCount()].corrections += 1 }
            lastCharacter = nil
            current = session
        }
        return closed
    }

    /// Closes the open session if nothing has been typed for longer than the timeout.
    public mutating func closeIfIdle(at time: Double) -> TypingSession? {
        guard let session = current, time - session.end > inactivityTimeout else { return nil }
        return end()
    }

    /// Closes the open session now, e.g. on sleep or when capture stops.
    public mutating func end() -> TypingSession? {
        defer {
            current = nil
            typedKeys = []
            lastCharacter = nil
        }
        guard let session = current, session.characters >= minimumCharacters else { return nil }
        return session
    }

    /// The open session extended to `time`, or a new one starting there.
    private func open(in context: TypingContext, at time: Double) -> TypingSession {
        var session = current ?? TypingSession(context: context, start: time, end: time)
        session.end = time
        return session
    }
}
