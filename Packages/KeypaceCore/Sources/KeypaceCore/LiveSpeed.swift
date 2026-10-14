/// Speed over the last few seconds of typing, for the menu bar and the live window.
///
/// Uses the typing events within `window` seconds of the newest one, and goes quiet once nothing has
/// been typed for `idleGap` seconds or there are fewer than three events. Gaps use the same typing time
/// measured by the session engine, with thinking pauses left out. The first event in the window only
/// marks the start, so each counted character has a gap before it.
public struct LiveSpeed: Sendable {
    public var window = 8.0
    public var idleGap = 2.0
    private var events: [(time: Double, characters: Int, typingSeconds: Double)] = []

    public init() {}

    /// - Parameters:
    ///   - characters: +1 for a typed character, minus the characters a deletion removed.
    ///   - typingSeconds: typing time credited to this event by the session engine.
    public mutating func record(at time: Double, characters: Int, typingSeconds: Double) {
        events.append((time, characters, typingSeconds))
        events.removeAll { time - $0.time > window }
    }

    public mutating func reset() {
        events = []
    }

    public func wordsPerMinute(at now: Double) -> Double? {
        guard events.count >= 3, let first = events.first, let last = events.last, now - last.time <= idleGap else { return nil }
        let span = last.time - first.time
        guard span > 0 else { return nil }
        let counted = events.dropFirst()
        let net = counted.reduce(0) { $0 + $1.characters }
        // Burst allowances after navigation can't credit more time than actually elapsed.
        let typingSeconds = min(counted.reduce(0) { $0 + $1.typingSeconds }, span)
        guard typingSeconds > 0 else { return nil }
        return Double(max(net, 0)) / 5 / (typingSeconds / 60)
    }
}
