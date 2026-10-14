/// Splits key presses into sessions and measures them.
///
/// Characters and deletions of characters typed in the session open and extend a session; other keys
/// count as keystrokes but neither open nor extend one. Typing time is the sum of the gaps the
/// `GapFilter` judges as typing, plus one usual gap for the keystroke that starts each burst, so pauses
/// inside a session don't count and short bursts aren't overstated.
///
/// A deletion only counts against speed and as a correction when it removes a character typed in the
/// session; deleting text that was already there is editing. Option-Delete removes back to the start of
/// the word, using transient character categories for boundaries. Command-Delete is editing because
/// visual line wrapping is unknown; it forgets ownership rather than guessing a deletion count.
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
    /// Characters typed in the open session and not yet deleted, most recent last. Held-key repeats are
    /// kept so deletes and word boundaries see them, but they aren't counted.
    private var typedKeys: [(keyCode: UInt16, counted: Bool, category: KeyPress.TextCategory)] = []
    /// The last typing event in the open session; cleared by other keys and by editing.
    private var lastTyping: (keyCode: UInt16, time: Double, isCharacter: Bool)?

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
            if current != nil { typedKeys.append((press.keyCode, false, press.textCategory)) }
        case .character:
            var session = open(in: context, at: press.time)
            session.characters += 1
            session.keystrokes += 1
            session.keys[press.keyCode, default: KeyCount()].presses += 1
            let typingSeconds = addTypingTime(to: &session, press: press, pairs: true)
            typedKeys.append((press.keyCode, true, press.textCategory))
            live.record(at: press.time, characters: 1, typingSeconds: typingSeconds)
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
            let typingSeconds = addTypingTime(to: &session, press: press, pairs: false)
            live.record(at: press.time, characters: -removed.count, typingSeconds: typingSeconds)
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
        guard var session = current, session.characters >= minimumCharacters else { return nil }
        // Burst-start allowances can't make typing time longer than the session itself plus the first keystroke's.
        session.activeDuration = min(session.activeDuration, session.duration + gaps.typicalGap)
        return session
    }

    /// The open session extended to `time`, or a new one starting there.
    private func open(in context: TypingContext, at time: Double) -> TypingSession {
        var session = current ?? TypingSession(context: context, start: time, end: time)
        session.end = time
        return session
    }

    /// Adds the gap before this press to the session's typing time if it was typing, or one usual gap
    /// if the press starts a new burst. Returns that time so live speed uses the same measurement.
    private mutating func addTypingTime(to session: inout TypingSession, press: KeyPress, pairs: Bool) -> Double {
        guard let last = lastTyping else {
            let duration = gaps.typicalGap
            session.activeDuration += duration
            return duration
        }
        let gap = press.time - last.time
        let duration: Double
        if press.isRepeat {
            // Held Delete fires at the key-repeat rate; that's typing time but not a typing gap to learn from.
            duration = gap <= gaps.config.ceiling ? gap : gaps.typicalGap
        } else if gaps.accepts(gap, from: last.keyCode, to: press.keyCode) {
            duration = gap
            if pairs, last.isCharacter {
                session.pairs[KeyPair(from: last.keyCode, to: press.keyCode), default: PairTiming()] += PairTiming(count: 1, totalMilliseconds: gap * 1000)
            }
        } else {
            duration = gaps.typicalGap
        }
        session.activeDuration += duration
        return duration
    }

    /// Removes the characters a delete removes from the session's typed keys and returns the counted ones.
    private mutating func removeTyped(_ kind: KeyPress.Kind) -> [UInt16] {
        var removed: [(keyCode: UInt16, counted: Bool, category: KeyPress.TextCategory)] = []
        func pop() { if let key = typedKeys.popLast() { removed.append(key) } }
        switch kind {
        case .deleteWord:
            // A trailing separator or whitespace is deleted with the preceding word.
            while let last = typedKeys.last, last.category != .word && last.category != .symbol { pop() }
            if typedKeys.last?.category == .symbol {
                pop()
                break
            }
            while let last = typedKeys.last {
                if last.category == .word {
                    pop()
                } else if last.category == .joiner, typedKeys.count >= 2,
                          typedKeys[typedKeys.count - 2].category == .word {
                    // Join contractions and dotted words, but leave opening quotes and leading dots outside.
                    pop()
                } else {
                    break
                }
            }
        case .deleteLine:
            // Keyboard events cannot reveal where the editor wrapped this line.
            typedKeys = []
        default:
            pop()
        }
        return removed.filter(\.counted).map(\.keyCode)
    }
}
