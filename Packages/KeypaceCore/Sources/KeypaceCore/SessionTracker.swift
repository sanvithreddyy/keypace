/// Splits key presses into sessions and measures them.
///
/// Characters and deletions of characters typed in the session open and extend a session; other keys
/// count as keystrokes but neither open nor extend one. Typing time is the sum of the gaps the
/// `GapFilter` judges as typing, plus one usual gap for the keystroke that starts each burst, so pauses
/// inside a session don't count and short bursts aren't overstated.
///
/// A deletion only counts against speed and as a correction when it removes a character typed in the
/// session; deleting text that was already there is editing. Option-Delete removes back to the start of
/// the word and Command-Delete back to the start of the line, counting each character they remove.
/// Each removed character is charged to the key that typed it. Held character repeats are ignored.
/// Key-pair timings cover consecutive characters whose gap counted as typing.
public struct SessionTracker: Sendable {
    public var inactivityTimeout: Double
    /// Sessions with fewer characters than this are discarded when they close.
    public var minimumCharacters: Int
    public private(set) var current: TypingSession?
    /// Speed over the last few seconds, across sessions.
    public private(set) var live = LiveSpeed()

    private var gaps = GapFilter()
    /// Keys of characters typed in the open session and not yet deleted, most recent last.
    private var typedKeys: [UInt16] = []
    /// The last typing event in the open session; cleared by other keys and by editing.
    private var lastTyping: (keyCode: UInt16, time: Double, isCharacter: Bool)?

    private static let lineBreaks: Set<UInt16> = [36, 76] // Return, keypad Enter
    private static let spaceKeyCode: UInt16 = 49
    /// Stands in for a held-key repeat in `typedKeys`.
    private static let uncounted = UInt16.max

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

        switch press.kind {
        case .other:
            if !press.isRepeat { current?.keystrokes += 1 }
            // Navigation and shortcuts may move the cursor, so what's before it is no longer known to be yours.
            cursorMoved()
        case .character where press.isRepeat:
            // A held key types more characters. They aren't counted, but deleting them mustn't be charged
            // to the characters typed before them.
            if current != nil { typedKeys.append(Self.uncounted) }
        case .character:
            var session = open(in: context, at: press.time)
            session.characters += 1
            session.keystrokes += 1
            session.keys[press.keyCode, default: KeyCount()].presses += 1
            addTypingTime(to: &session, press: press, pairs: true)
            typedKeys.append(press.keyCode)
            live.record(at: press.time, characters: 1)
            lastTyping = (press.keyCode, press.time, true)
            current = session
        case .backspace, .deleteWord, .deleteLine:
            let removed = removeTyped(press.kind)
            if removed.isEmpty {
                // Deleting text that was there before the session is editing, not typing.
                if current != nil {
                    current?.backspaces += 1
                    if !press.isRepeat {
                        current?.keystrokes += 1
                        current?.keys[press.keyCode, default: KeyCount()].presses += 1
                    }
                }
                lastTyping = nil
                break
            }
            var session = open(in: context, at: press.time)
            session.backspaces += 1
            session.deletions += removed.count
            if !press.isRepeat {
                session.keystrokes += 1
                session.keys[press.keyCode, default: KeyCount()].presses += 1
            }
            for key in removed { session.keys[key, default: KeyCount()].corrections += 1 }
            addTypingTime(to: &session, press: press, pairs: false)
            live.record(at: press.time, characters: -removed.count)
            lastTyping = (press.keyCode, press.time, false)
            current = session
        }
        return closed
    }

    /// Forgets which text before the cursor was typed in this session, e.g. after a mouse click.
    public mutating func cursorMoved() {
        typedKeys = []
        lastTyping = nil
    }

    /// Clears live speed, e.g. when capture stops.
    public mutating func resetLive() {
        live.reset()
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
            lastTyping = nil
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

    /// Adds the gap before this press to the session's typing time if it was typing, or one usual gap
    /// if the press starts a new burst.
    private mutating func addTypingTime(to session: inout TypingSession, press: KeyPress, pairs: Bool) {
        guard let last = lastTyping else {
            session.activeDuration += gaps.typicalGap
            return
        }
        let gap = press.time - last.time
        if press.isRepeat {
            // Held Delete fires at the key-repeat rate; that's typing time but not a typing gap to learn from.
            session.activeDuration += gap <= gaps.config.ceiling ? gap : gaps.typicalGap
        } else if gaps.accepts(gap, from: last.keyCode, to: press.keyCode) {
            session.activeDuration += gap
            if pairs, last.isCharacter {
                session.pairs[KeyPair(from: last.keyCode, to: press.keyCode), default: PairTiming()] += PairTiming(count: 1, totalMilliseconds: gap * 1000)
            }
        } else {
            session.activeDuration += gaps.typicalGap
        }
    }

    /// Removes the characters a delete removes from the session's typed keys and returns the counted ones.
    private mutating func removeTyped(_ kind: KeyPress.Kind) -> [UInt16] {
        var removed: [UInt16] = []
        func pop() { if let key = typedKeys.popLast() { removed.append(key) } }
        switch kind {
        case .deleteWord:
            while typedKeys.last == Self.spaceKeyCode { pop() }
            while let key = typedKeys.last, key != Self.spaceKeyCode, !Self.lineBreaks.contains(key) { pop() }
        case .deleteLine:
            while let key = typedKeys.last, !Self.lineBreaks.contains(key) { pop() }
        default:
            pop()
        }
        return removed.filter { $0 != Self.uncounted }
    }
}
