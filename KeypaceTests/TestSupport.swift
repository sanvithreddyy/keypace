import Foundation
import KeypaceCore

/// A clock the test moves by hand.
final class TestClock {
    var date: Date
    var uptime: Double

    init(date: Date, uptime: Double = 1000) {
        self.date = date
        self.uptime = uptime
    }

    var clock: LiveTracker.Clock {
        LiveTracker.Clock(now: { [unowned self] in date }, uptime: { [unowned self] in uptime })
    }

    func advance(_ seconds: Double) {
        date = date.addingTimeInterval(seconds)
        uptime += seconds
    }
}

/// Feeds text into a tracker as hardware key-downs, one every `interval` seconds.
@MainActor
struct Typist {
    let tracker: LiveTracker
    let clock: TestClock
    var appID = "com.apple.Notes"
    var keyboard: KeyboardRecord? = KeyboardRecord(id: "1452:834", name: "Apple Internal Keyboard", isBuiltIn: true, lastSeen: .now)
    var inputSource: InputSourceRecord? = InputSourceRecord(id: "com.apple.keylayout.US", name: "U.S.", lastSeen: .now)
    var sourceProcessID: Int64 = 0

    /// Type characters; "⌫" presses Delete.
    func type(_ text: String, interval: Double = 0.2) {
        for character in text {
            clock.advance(interval)
            let isDelete = character == "⌫"
            let key = ObservedKey(
                keyCode: isDelete ? 51 : USKeys.code(for: character),
                time: clock.uptime,
                text: isDelete ? "\u{7F}" : String(character),
                commandOrControl: false,
                command: false,
                option: false,
                isRepeat: false,
                sourceStateID: 1,
                sourceProcessID: sourceProcessID
            )
            tracker.handle(key, appID: appID, keyboard: keyboard, inputSource: inputSource)
        }
    }

    /// Waits past the inactivity timeout so the session closes and is saved.
    func pause(_ seconds: Double = 6) {
        clock.advance(seconds)
        tracker.tick()
    }
}

/// macOS virtual key codes for the US layout.
enum USKeys {
    static func code(for character: Character) -> UInt16 {
        codes[Character(character.lowercased())] ?? 0
    }

    private static let codes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
        "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
        "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49, "\n": 36,
    ]
}

@MainActor
func makeTracker(clock: TestClock) throws -> LiveTracker {
    let defaults = UserDefaults(suiteName: "KeypaceTests-\(UUID().uuidString)")!
    return LiveTracker(store: try SessionStore.inMemory(), defaults: defaults, clock: clock.clock, capture: false)
}
