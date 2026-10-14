import Foundation
import Testing
@testable import KeypaceCore

struct StatStoreTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func session(app: String = "com.apple.Notes", keyboard: String? = "1452:834", keys: [UInt16: KeyCount], pairs: [KeyPair: PairTiming] = [:]) -> TypingSession {
        var session = TypingSession(context: TypingContext(appID: app, keyboardID: keyboard, inputSourceID: "com.apple.keylayout.US"), start: 0, end: 30, characters: 100, backspaces: 4, keystrokes: 104)
        session.keys = keys
        session.pairs = pairs
        return session
    }

    @Test func `day keys sort as dates in the given calendar`() {
        #expect(Day.key(monday, calendar: utc) == "2026-10-12")
        #expect(Day.key(monday.addingTimeInterval(-1), calendar: utc) == "2026-10-11")
    }

    @Test func `saved sessions add up their key and pair statistics`() throws {
        let store = try SessionStore.inMemory()
        let pair = KeyPair(from: 17, to: 4)
        try store.save(session(keys: [17: KeyCount(presses: 10, corrections: 1)], pairs: [pair: PairTiming(count: 2, totalMilliseconds: 300)]), endingAt: monday.addingTimeInterval(3600), calendar: utc)
        try store.save(session(keys: [17: KeyCount(presses: 5, corrections: 2), 4: KeyCount(presses: 3)], pairs: [pair: PairTiming(count: 1, totalMilliseconds: 90)]), endingAt: monday.addingTimeInterval(7200), calendar: utc)

        let day = DateInterval(start: monday, duration: 86_400)
        let keys = try store.keyStats(in: day, calendar: utc)
        #expect(keys[17] == KeyCount(presses: 15, corrections: 3))
        #expect(keys[4] == KeyCount(presses: 3))
        #expect(try store.pairStats(in: day, calendar: utc)[pair] == PairTiming(count: 3, totalMilliseconds: 390))
        #expect(try store.allSessions().count == 2)
    }

    @Test func `statistics respect the date range and filters`() throws {
        let store = try SessionStore.inMemory()
        try store.save(session(keyboard: "1452:834", keys: [17: KeyCount(presses: 10)]), endingAt: monday.addingTimeInterval(3600), calendar: utc)
        try store.save(session(keyboard: "1133:50475", keys: [17: KeyCount(presses: 7)]), endingAt: monday.addingTimeInterval(3600), calendar: utc)
        try store.save(session(keyboard: "1452:834", keys: [17: KeyCount(presses: 99)]), endingAt: monday.addingTimeInterval(86_400 + 3600), calendar: utc)

        let day = DateInterval(start: monday, duration: 86_400)
        #expect(try store.keyStats(in: day, calendar: utc)[17]?.presses == 17)
        #expect(try store.keyStats(in: day, calendar: utc, filter: StatFilter(keyboardID: "1133:50475"))[17]?.presses == 7)
        #expect(try store.keyStats(in: DateInterval(start: monday, duration: 2 * 86_400), calendar: utc)[17]?.presses == 116)
    }

    @Test func `deleting an app removes its statistics too`() throws {
        let store = try SessionStore.inMemory()
        try store.save(session(app: "com.apple.mail", keys: [17: KeyCount(presses: 10)]), endingAt: monday.addingTimeInterval(3600), calendar: utc)
        try store.save(session(app: "com.apple.Notes", keys: [17: KeyCount(presses: 4)]), endingAt: monday.addingTimeInterval(3600), calendar: utc)
        try store.addSynthetic(count: 30, appID: "com.apple.mail", day: "2026-10-12")
        try store.deleteSessions(appID: "com.apple.mail")

        let day = DateInterval(start: monday, duration: 86_400)
        #expect(try store.keyStats(in: day, calendar: utc)[17]?.presses == 4)
        #expect(try store.syntheticCount(in: day, calendar: utc) == 0)
    }

    @Test func `keyboards keep their custom name when seen again`() throws {
        let store = try SessionStore.inMemory()
        try store.noteKeyboard(KeyboardRecord(id: "1452:834", name: "Apple Internal Keyboard", isBuiltIn: true, lastSeen: monday))
        try store.renameKeyboard(id: "1452:834", to: "Laptop")
        try store.noteKeyboard(KeyboardRecord(id: "1452:834", name: "Apple Internal Keyboard", isBuiltIn: true, lastSeen: monday.addingTimeInterval(60)))
        let keyboard = try #require(try store.keyboards().first)
        #expect(keyboard.displayName == "Laptop")
        #expect(keyboard.lastSeen == monday.addingTimeInterval(60))
    }

    @Test func `synthetic counts add up per day`() throws {
        let store = try SessionStore.inMemory()
        try store.addSynthetic(count: 12, appID: "com.apple.Notes", day: "2026-10-12")
        try store.addSynthetic(count: 8, appID: "com.apple.Notes", day: "2026-10-12")
        try store.addSynthetic(count: 5, appID: "com.apple.Notes", day: "2026-10-13")
        #expect(try store.syntheticCount(in: DateInterval(start: monday, duration: 86_400), calendar: utc) == 20)
    }
}
