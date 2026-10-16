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
            let record = try SessionRecord(id: 7, start: monday, end: monday.addingTimeInterval(30), appID: "notes",
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
            #expect(try Int64.fetchOne(db, sql: "SELECT legacySessionID FROM pressHistory") == old.id)
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

    private func legacyDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue()
        try SessionStore.migrator.migrate(db, upTo: "v5-typing-time")
        return db
    }

    @discardableResult
    private func saveLegacy(_ db: DatabaseQueue, at start: Date, app: String = "notes", keyboard: String = "built-in", layout: String = "US", presses: Int) throws -> SessionRecord {
        try db.write { db in
            let saved = try SessionRecord(start: start, end: start.addingTimeInterval(30), appID: app,
                                          keyboardID: keyboard, inputSourceID: layout,
                                          characters: presses, backspaces: 0, keystrokes: presses).inserted(db)
            try db.execute(sql: "INSERT INTO sessionKey VALUES (?, 0, ?, 2)", arguments: [saved.id, presses])
            return saved
        }
    }

    @Test func `legacy sessions in the first press hour keep all their presses`() throws {
        let db = try legacyDatabase()
        let hour = monday.addingTimeInterval(10 * 3600)
        try saveLegacy(db, at: hour.addingTimeInterval(10 * 60), presses: 40)
        let store = try SessionStore(db)
        try save(store, at: hour.addingTimeInterval(30 * 60), presses: 3)
        try add(store, 3, hour: Hour.index(hour))
        let counts = try store.pressCounts(in: day)
        #expect(counts == [0: 43])
        #expect(try store.pressCounts(in: DateInterval(start: hour, duration: 3600)) == [0: 43])
        #expect(try SessionStore(db).pressCounts(in: day) == [0: 43])
    }

    @Test func `legacy history uses session starts and new sessions never add presses twice`() throws {
        let db = try legacyDatabase()
        let hour = monday.addingTimeInterval(3600)
        try saveLegacy(db, at: monday.addingTimeInterval(-30), presses: 100)
        try saveLegacy(db, at: monday, presses: 10)
        try saveLegacy(db, at: hour.addingTimeInterval(-10), presses: 4)
        let store = try SessionStore(db)
        // Even a new session with an earlier start is outside the immutable legacy boundary.
        try save(store, at: monday.addingTimeInterval(60), presses: 99)
        try save(store, at: hour.addingTimeInterval(600), presses: 99)
        try add(store, 7, hour: Hour.index(hour))
        try add(store, 3, code: 123, hour: Hour.index(hour) + 1)
        #expect(try store.pressCounts(in: day) == [0: 21, 123: 3])
        #expect(try store.pressCounts(in: DateInterval(start: monday, end: hour)) == [0: 14])
        #expect(try store.pressCounts(in: DateInterval(start: hour, end: day.end)) == [0: 7, 123: 3])
        #expect(try store.keyStats(in: day)[0] == KeyCount(presses: 212, corrections: 8))
    }

    @Test func `every filter applies to both legacy sessions and new press counts`() throws {
        let db = try legacyDatabase()
        try saveLegacy(db, at: monday, presses: 2)
        try saveLegacy(db, at: monday, keyboard: "external", presses: 3)
        try saveLegacy(db, at: monday, app: "mail", keyboard: "external", layout: "GB", presses: 5)
        try saveLegacy(db, at: day.end, presses: 99)
        let store = try SessionStore(db)
        try add(store, 11)
        try add(store, 13, keyboard: "external")
        try add(store, 17, app: "mail", keyboard: "external", layout: "GB")
        #expect(try store.pressCounts(in: day) == [0: 51])
        #expect(try store.pressCounts(in: day, filter: StatFilter(appID: "notes")) == [0: 29])
        #expect(try store.pressCounts(in: day, filter: StatFilter(keyboardID: "external")) == [0: 38])
        #expect(try store.pressCounts(in: day, filter: StatFilter(inputSourceID: "GB")) == [0: 22])
        #expect(try store.pressCounts(in: day, filter: StatFilter(appID: "notes", keyboardID: "external", inputSourceID: "US")) == [0: 16])
        #expect(try store.pressCounts(in: day, filter: StatFilter(appID: "mail", inputSourceID: "US")).isEmpty)
    }

    @Test func `without new press rows legacy sessions retain their own counts and filters`() throws {
        let db = try legacyDatabase()
        try saveLegacy(db, at: monday, presses: 4)
        try saveLegacy(db, at: monday.addingTimeInterval(60), app: "mail", keyboard: "external", layout: "GB", presses: 6)
        try saveLegacy(db, at: day.end, presses: 99)
        let store = try SessionStore(db)
        #expect(try store.pressCounts(in: day) == [0: 10])
        for filter in [StatFilter(appID: "mail"), StatFilter(keyboardID: "external"), StatFilter(inputSourceID: "GB")] {
            #expect(try store.pressCounts(in: day, filter: filter) == [0: 6])
        }
        try save(store, at: monday, presses: 99)
        #expect(try store.pressCounts(in: day) == [0: 10])
    }

    @Test func `fresh stores start at boundary zero and use only independent press counts`() throws {
        let db = try DatabaseQueue()
        let store = try SessionStore(db)
        #expect(try db.read { try Int64.fetchOne($0, sql: "SELECT legacySessionID FROM pressHistory") } == 0)
        #expect(try store.pressCounts(in: day).isEmpty)
        try save(store, at: monday, presses: 3)
        #expect(try store.pressCounts(in: day).isEmpty)
        try add(store, 3)
        #expect(try store.pressCounts(in: day) == [0: 3])
    }

    @Test func `deleting legacy history preserves the boundary and never reuses legacy IDs`() throws {
        let db = try legacyDatabase()
        let old = try saveLegacy(db, at: monday, presses: 40)
        let store = try SessionStore(db)
        try store.deleteAll()
        try save(store, at: monday, presses: 3)
        #expect(try #require(store.allSessions().first?.id) > #require(old.id))
        #expect(try db.read { try Int64.fetchOne($0, sql: "SELECT legacySessionID FROM pressHistory") } == old.id)
        #expect(try store.pressCounts(in: day).isEmpty)
        try add(store, 3)
        #expect(try store.pressCounts(in: day) == [0: 3])
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
