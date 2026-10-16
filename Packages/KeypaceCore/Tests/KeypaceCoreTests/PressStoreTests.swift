import Foundation
import GRDB
import Testing
@testable import KeypaceCore

struct PressStoreTests {
    private let day = DateInterval(start: monday, duration: 86_400)

    private func save(_ store: SessionStore, at start: Date, app: String = "notes", keyboard: String? = "built-in", layout: String? = "US", presses: Int = 10) throws {
        var session = TypingSession(context: TypingContext(appID: app, keyboardID: keyboard, inputSourceID: layout), start: 0, end: 30)
        session.characters = presses
        session.keystrokes = presses
        session.keys = [0: KeyCount(presses: presses, corrections: 2)]
        session.pairs = [KeyPair(from: 0, to: 1): PairTiming(count: 2, totalMilliseconds: 300)]
        try store.save(session, endingAt: start.addingTimeInterval(30))
    }

    private func add(_ store: SessionStore, _ count: Int, code: UInt16 = 0, hour: Int = Hour.index(monday), app: String = "notes", keyboard: String? = "built-in", layout: String? = "US") throws {
        try store.addPresses(count: count, keyCode: code, appID: app, keyboardID: keyboard, inputSourceID: layout, hour: hour)
    }

    @Test func `v6 creates press counts without changing v5 history`() throws {
        let db = try DatabaseQueue()
        try SessionStore.migrator.migrate(db, upTo: "v5-typing-time")
        let old = try db.write { db in
            let record = try SessionRecord(start: monday, end: monday.addingTimeInterval(30), appID: "notes",
                                           characters: 10, backspaces: 2, keystrokes: 12, deletions: 1, activeSeconds: 2.5).inserted(db)
            try db.execute(sql: "INSERT INTO sessionKey VALUES (?, 0, 10, 1)", arguments: [record.id])
            try db.execute(sql: "INSERT INTO sessionPair VALUES (?, 0, 1, 2, 300)", arguments: [record.id])
            try db.execute(sql: "INSERT INTO syntheticStat VALUES (?, 'notes', 3)", arguments: [Hour.index(monday)])
            return record
        }
        let store = try SessionStore(db)
        try db.read { db in
            let columns = try db.columns(in: "pressStat")
            #expect(columns.map(\.name) == ["hour", "appID", "keyboardID", "inputSourceID", "keyCode", "presses"])
            #expect(columns.allSatisfy { $0.isNotNull })
            #expect(columns.map(\.primaryKeyIndex) == [1, 2, 3, 4, 5, 0])
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pressStat") == 0)
        }
        #expect(try store.allSessions() == [old])
        #expect(try store.keyStats(in: day) == [0: KeyCount(presses: 10, corrections: 1)])
        #expect(try store.pairStats(in: day)[KeyPair(from: 0, to: 1)] == PairTiming(count: 2, totalMilliseconds: 300))
        #expect(try store.syntheticCount(in: day) == 3)
        #expect(try store.pressCounts(in: day) == [0: 10])
    }

    @Test func `press upserts add and unknown devices use empty IDs`() throws {
        let db = try DatabaseQueue()
        let store = try SessionStore(db)
        try add(store, 2, keyboard: nil, layout: nil)
        try add(store, 3, keyboard: nil, layout: nil)
        #expect(try store.pressCounts(in: day) == [0: 5])
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM pressStat")
            #expect(rows.count == 1)
            #expect(rows.first?["keyboardID"] as String? == "")
            #expect(rows.first?["inputSourceID"] as String? == "")
        }
    }

    @Test func `press queries sum per key and respect every filter`() throws {
        let store = try SessionStore.inMemory()
        try add(store, 2)
        try add(store, 3, keyboard: "external")
        try add(store, 5, code: 123, app: "mail", keyboard: "external", layout: "GB")
        try add(store, 7, code: 53, keyboard: nil, layout: nil)
        #expect(try store.pressCounts(in: day) == [0: 5, 123: 5, 53: 7])
        #expect(try store.pressCounts(in: day).values.reduce(0, +) == 17)
        #expect(try store.pressCounts(in: day, filter: StatFilter(appID: "mail")) == [123: 5])
        #expect(try store.pressCounts(in: day, filter: StatFilter(keyboardID: "external")) == [0: 3, 123: 5])
        #expect(try store.pressCounts(in: day, filter: StatFilter(inputSourceID: "US")) == [0: 5])
        #expect(try store.pressCounts(in: day, filter: StatFilter(appID: "notes", keyboardID: "external", inputSourceID: "US")) == [0: 3])
        #expect(try store.pressCounts(in: day, filter: StatFilter(keyboardID: "", inputSourceID: "")) == [53: 7])
        #expect(try store.pressCounts(in: day, filter: StatFilter(appID: "missing")).isEmpty)
    }

    @Test func `history stitches at the first press hour using session starts`() throws {
        let store = try SessionStore.inMemory()
        let coverage = monday.addingTimeInterval(3600)
        try save(store, at: monday.addingTimeInterval(-30), presses: 100)
        try save(store, at: monday, presses: 10)
        // A session crossing the coverage start stays in the older portion in full.
        try save(store, at: coverage.addingTimeInterval(-10), presses: 4)
        try save(store, at: coverage, presses: 99)
        try save(store, at: coverage.addingTimeInterval(600), presses: 99)
        try add(store, 7, hour: Hour.index(coverage))
        try add(store, 3, code: 123, hour: Hour.index(coverage) + 1)
        #expect(try store.pressCounts(in: day) == [0: 21, 123: 3])
        #expect(try store.pressCounts(in: DateInterval(start: monday, end: coverage)) == [0: 14])
        #expect(try store.pressCounts(in: DateInterval(start: coverage, end: day.end)) == [0: 7, 123: 3])
        // Session-based corrections and their denominators are untouched.
        #expect(try store.keyStats(in: day)[0] == KeyCount(presses: 212, corrections: 8))
    }

    @Test func `coverage is global even when filtered presses are absent`() throws {
        let store = try SessionStore.inMemory()
        let coverage = monday.addingTimeInterval(3600)
        try save(store, at: monday, app: "mail", keyboard: "external", layout: "GB", presses: 4)
        try save(store, at: coverage, app: "mail", keyboard: "external", layout: "GB", presses: 99)
        try add(store, 7, hour: Hour.index(coverage))
        for filter in [StatFilter(appID: "mail"), StatFilter(keyboardID: "external"), StatFilter(inputSourceID: "GB")] {
            #expect(try store.pressCounts(in: day, filter: filter) == [0: 4])
            #expect(try store.pressCounts(in: DateInterval(start: coverage, end: day.end), filter: filter).isEmpty)
        }
    }

    @Test func `without press rows history uses session keys and their filters`() throws {
        let store = try SessionStore.inMemory()
        try save(store, at: monday, presses: 4)
        try save(store, at: monday.addingTimeInterval(60), app: "mail", keyboard: "external", layout: "GB", presses: 6)
        try save(store, at: day.end, presses: 99)
        #expect(try store.pressCounts(in: day) == [0: 10])
        for filter in [StatFilter(appID: "mail"), StatFilter(keyboardID: "external"), StatFilter(inputSourceID: "GB")] {
            #expect(try store.pressCounts(in: day, filter: filter) == [0: 6])
        }
    }

    @Test func `press hours count whenever they overlap a nonempty interval`() throws {
        let store = try SessionStore.inMemory()
        try add(store, 2)
        try add(store, 3, hour: Hour.index(monday) + 1)
        #expect(try store.pressCounts(in: DateInterval(start: monday.addingTimeInterval(300), duration: 1)) == [0: 2])
        #expect(try store.pressCounts(in: DateInterval(start: monday, duration: 3600)) == [0: 2])
        #expect(try store.pressCounts(in: DateInterval(start: monday, duration: 3600.25)) == [0: 5])
        #expect(try store.pressCounts(in: DateInterval(start: monday.addingTimeInterval(3600), duration: 1)) == [0: 3])
        #expect(try store.pressCounts(in: DateInterval(start: monday.addingTimeInterval(300), duration: 0)).isEmpty)
    }

    @Test func `deleting history clears press rows for only the requested app or all apps`() throws {
        let store = try SessionStore.inMemory()
        try add(store, 2)
        try add(store, 3, code: 123, app: "mail")
        try store.deleteSessions(appID: "notes")
        #expect(try store.pressCounts(in: day) == [123: 3])
        #expect(try store.pressCounts(in: day, filter: StatFilter(appID: "notes")).isEmpty)
        try store.deleteAll()
        #expect(try store.pressCounts(in: day).isEmpty)
        #expect(try store.firstHistoryStart() == nil)
    }

    @Test func `history starts at the oldest session or press hour`() throws {
        let store = try SessionStore.inMemory()
        #expect(try store.firstHistoryStart() == nil)
        try add(store, 1, hour: Hour.index(monday) + 1)
        #expect(try store.firstHistoryStart() == monday.addingTimeInterval(3600))
        try save(store, at: monday)
        #expect(try store.firstHistoryStart() == monday)
        try add(store, 1, hour: Hour.index(monday) - 1)
        #expect(try store.firstHistoryStart() == monday.addingTimeInterval(-3600))
    }
}
