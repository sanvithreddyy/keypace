import Foundation
import Testing
@testable import KeypaceCore

/// 2026-10-12 00:00 UTC, a Monday.
let monday = Date(timeIntervalSince1970: 1_791_763_200)

func record(_ app: String = "com.apple.Notes", at start: Date, seconds: Double = 60, characters: Int = 300, backspaces: Int = 0) -> SessionRecord {
    SessionRecord(
        start: start, end: start.addingTimeInterval(seconds), appID: app,
        characters: characters, backspaces: backspaces, keystrokes: characters + backspaces
    )
}

struct SessionStoreTests {
    @Test func `a live session is stored with wall-clock times`() throws {
        let store = try SessionStore.inMemory()
        let live = TypingSession(context: TypingContext(appID: "com.apple.Notes"), start: 100, end: 112, characters: 50, backspaces: 5, keystrokes: 56)
        let end = monday.addingTimeInterval(3600)
        let saved = try store.insert(SessionRecord(live, endingAt: end))

        #expect(saved.id != nil)
        let fetched = try #require(try store.allSessions().first)
        #expect(fetched == saved)
        #expect(fetched.start == end.addingTimeInterval(-12))
        #expect(fetched.totals == live.totals)
    }

    @Test func `range queries include the start and exclude the end`() throws {
        let store = try SessionStore.inMemory()
        let day = DateInterval(start: monday, duration: 86_400)
        try store.insert(record(at: monday))
        try store.insert(record(at: monday.addingTimeInterval(86_399)))
        try store.insert(record(at: monday.addingTimeInterval(86_400)))
        try store.insert(record(at: monday.addingTimeInterval(-1)))

        #expect(try store.sessions(in: day).count == 2)
        #expect(try store.firstSessionStart() == monday.addingTimeInterval(-1))
    }

    @Test func `deleting an app removes only its sessions`() throws {
        let store = try SessionStore.inMemory()
        try store.insert(record("com.apple.Notes", at: monday))
        try store.insert(record("com.apple.mail", at: monday))
        try store.deleteSessions(appID: "com.apple.mail")
        #expect(try store.allSessions().map(\.appID) == ["com.apple.Notes"])

        try store.deleteAll()
        #expect(try store.allSessions().isEmpty)
    }

    @Test func `sessions survive reopening the database file`() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try SessionStore(path: path).insert(record(at: monday))
        #expect(try SessionStore(path: path).allSessions().count == 1)
    }
}

struct StatisticsTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func `combined speed weights sessions by length, not an average of averages`() throws {
        // 300 net chars in 60 s = 60 wpm; 100 net chars in 60 s = 20 wpm; over 120 s total → 40 wpm.
        let totals = Statistics.totals([record(at: monday), record(at: monday, characters: 100)])
        #expect(try #require(totals.wpm) == 40)
        // A 10 s burst at 120 wpm barely moves an hour at 20 wpm.
        let skewed = Statistics.totals([record(at: monday, seconds: 10, characters: 100), record(at: monday, seconds: 3600, characters: 6000)])
        #expect(try #require(skewed.wpm) < 21)
    }

    @Test func `by app sorts by typing time`() {
        let apps = Statistics.byApp([
            record("com.apple.mail", at: monday, seconds: 30),
            record("com.apple.Notes", at: monday, seconds: 60),
            record("com.apple.mail", at: monday, seconds: 50),
        ])
        #expect(apps.map(\.appID) == ["com.apple.mail", "com.apple.Notes"])
        #expect(apps.first?.totals.duration == 80)
    }

    @Test func `by keyboard and layout skip sessions without one`() {
        var laptop = record(at: monday, seconds: 30)
        laptop.keyboardID = "1452:834"
        laptop.inputSourceID = "com.apple.keylayout.US"
        var external = record(at: monday, seconds: 90)
        external.keyboardID = "1133:50475"
        let unknown = record(at: monday, seconds: 500)
        let sessions = [laptop, external, unknown]
        #expect(Statistics.byKeyboard(sessions).map(\.id) == ["1133:50475", "1452:834"])
        #expect(Statistics.byInputSource(sessions).map(\.id) == ["com.apple.keylayout.US"])
    }

    @Test func `hour, weekday and day use the session's start`() {
        let sessions = [
            record(at: monday.addingTimeInterval(9 * 3600 + 59 * 60)), // Mon 09:59, runs into 10:00
            record(at: monday.addingTimeInterval(86_400 + 9 * 3600)), // Tue 09:00
        ]
        #expect(Statistics.byHourOfDay(sessions, calendar: utc).keys.sorted() == [9])
        #expect(Statistics.byWeekday(sessions, calendar: utc).keys.sorted() == [2, 3])
        #expect(Statistics.byDay(sessions, calendar: utc).keys.sorted() == [monday, monday.addingTimeInterval(86_400)])
    }

    @Test func `streaks count consecutive days and survive until today ends`() {
        let days = [-6, -5, -3, -2, -1].map { record(at: monday.addingTimeInterval(Double($0) * 86_400 + 3600)) }
        let beforeTypingToday = Statistics.streaks(days, today: monday.addingTimeInterval(3600), calendar: utc)
        #expect(beforeTypingToday.current == 3)
        #expect(beforeTypingToday.longest == 3)

        let afterTypingToday = Statistics.streaks(days + [record(at: monday.addingTimeInterval(7200))], today: monday.addingTimeInterval(7200), calendar: utc)
        #expect(afterTypingToday.current == 4)
        #expect(afterTypingToday.longest == 4)

        let broken = Statistics.streaks(days, today: monday.addingTimeInterval(86_400 + 3600), calendar: utc)
        #expect(broken.current == 0)
    }
}

struct SessionCSVTests {
    @Test func `rows hold counts and derived speed, and quote awkward fields`() {
        let csv = SessionCSV.make([record("com.example,odd", at: monday, characters: 330, backspaces: 30)])
        let lines = csv.split(separator: "\n")
        #expect(lines.first.map(String.init) == SessionCSV.header)
        #expect(lines.last == "2026-10-12T00:00:00Z,2026-10-12T00:01:00Z,\"com.example,odd\",,,330,30,360,60.0,60.0,0.0909")
    }
}
