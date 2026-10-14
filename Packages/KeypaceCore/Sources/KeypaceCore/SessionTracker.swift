/// Splits key presses into sessions.
///
/// Characters and backspaces open and extend a session. Other keys count as keystrokes
/// inside an open session but neither open one nor extend it, so time spent navigating
/// with arrows or shortcuts doesn't dilute speed. Held-key character repeats are ignored;
/// backspace repeats each delete a character, so they count as backspaces.
public struct SessionTracker: Sendable {
    public var inactivityTimeout: Double
    /// Sessions with fewer characters than this are discarded when they close.
    public var minimumCharacters: Int
    public private(set) var current: TypingSession?

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
            current?.keystrokes += 1
        case (.character, false), (.backspace, _):
            var session = current ?? TypingSession(context: context, start: press.time, end: press.time)
            session.end = press.time
            if press.kind == .character {
                session.characters += 1
            } else {
                session.backspaces += 1
            }
            if !press.isRepeat { session.keystrokes += 1 }
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
        defer { current = nil }
        guard let session = current, session.characters >= minimumCharacters else { return nil }
        return session
    }
}
