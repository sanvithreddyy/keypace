import Foundation
import GRDB

/// A finished session as stored: wall-clock times and counts, never text.
public struct SessionRecord: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "session"

    public var id: Int64?
    public var start: Date
    public var end: Date
    public var appID: String
    public var keyboardID: String?
    public var inputSourceID: String?
    public var characters: Int
    public var backspaces: Int
    public var keystrokes: Int

    public init(
        id: Int64? = nil, start: Date, end: Date, appID: String,
        keyboardID: String? = nil, inputSourceID: String? = nil,
        characters: Int, backspaces: Int, keystrokes: Int
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.appID = appID
        self.keyboardID = keyboardID
        self.inputSourceID = inputSourceID
        self.characters = characters
        self.backspaces = backspaces
        self.keystrokes = keystrokes
    }

    /// - Parameter end: wall-clock time of the session's last press.
    public init(_ session: TypingSession, endingAt end: Date) {
        self.init(
            start: end.addingTimeInterval(-session.duration), end: end,
            appID: session.context.appID,
            keyboardID: session.context.keyboardID, inputSourceID: session.context.inputSourceID,
            characters: session.characters, backspaces: session.backspaces, keystrokes: session.keystrokes
        )
    }

    public var totals: TypingTotals {
        TypingTotals(characters: characters, backspaces: backspaces, keystrokes: keystrokes, duration: end.timeIntervalSince(start))
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// The local database. One file, aggregates only.
public struct SessionStore: Sendable {
    private let db: DatabaseQueue

    public init(path: String) throws {
        try self.init(DatabaseQueue(path: path))
    }

    public static func inMemory() throws -> SessionStore {
        try SessionStore(DatabaseQueue())
    }

    private init(_ db: DatabaseQueue) throws {
        self.db = db
        try Self.migrator.migrate(db)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull().indexed()
                t.column("end", .datetime).notNull()
                t.column("appID", .text).notNull().indexed()
                t.column("keyboardID", .text)
                t.column("inputSourceID", .text)
                t.column("characters", .integer).notNull()
                t.column("backspaces", .integer).notNull()
                t.column("keystrokes", .integer).notNull()
            }
        }
        migrator.registerMigration("v2-keys-devices") { db in
            try db.create(table: "keyStat") { t in
                t.column("day", .text).notNull()
                t.column("appID", .text).notNull()
                t.column("keyboardID", .text).notNull()
                t.column("inputSourceID", .text).notNull()
                t.column("keyCode", .integer).notNull()
                t.column("presses", .integer).notNull()
                t.column("corrections", .integer).notNull()
                t.primaryKey(["day", "appID", "keyboardID", "inputSourceID", "keyCode"])
            }
            try db.create(table: "pairStat") { t in
                t.column("day", .text).notNull()
                t.column("appID", .text).notNull()
                t.column("keyboardID", .text).notNull()
                t.column("inputSourceID", .text).notNull()
                t.column("fromKey", .integer).notNull()
                t.column("toKey", .integer).notNull()
                t.column("count", .integer).notNull()
                t.column("totalMilliseconds", .double).notNull()
                t.primaryKey(["day", "appID", "keyboardID", "inputSourceID", "fromKey", "toKey"])
            }
            try db.create(table: "keyboard") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("isBuiltIn", .boolean).notNull()
                t.column("customName", .text)
                t.column("lastSeen", .datetime).notNull()
            }
            try db.create(table: "inputSource") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("lastSeen", .datetime).notNull()
            }
            try db.create(table: "syntheticStat") { t in
                t.column("day", .text).notNull()
                t.column("appID", .text).notNull()
                t.column("count", .integer).notNull()
                t.primaryKey(["day", "appID"])
            }
        }
        return migrator
    }

    /// Saves a finished live session with its key and key-pair statistics.
    /// - Parameter end: wall-clock time of the session's last press.
    @discardableResult
    public func save(_ session: TypingSession, endingAt end: Date, calendar: Calendar) throws -> SessionRecord {
        let record = SessionRecord(session, endingAt: end)
        let scope = StatScope(day: Day.key(record.start, calendar: calendar), context: session.context)
        return try db.write { db in
            let saved = try record.inserted(db)
            try Self.add(keys: session.keys, scope: scope, db: db)
            try Self.add(pairs: session.pairs, scope: scope, db: db)
            return saved
        }
    }

    /// Adds key and pair statistics directly; used for imports and sample data.
    public func add(keys: [UInt16: KeyCount], pairs: [KeyPair: PairTiming], day: String, context: TypingContext) throws {
        let scope = StatScope(day: day, context: context)
        try db.write { db in
            try Self.add(keys: keys, scope: scope, db: db)
            try Self.add(pairs: pairs, scope: scope, db: db)
        }
    }

    private struct StatScope {
        var day: String
        var appID: String
        var keyboardID: String
        var inputSourceID: String

        init(day: String, context: TypingContext) {
            self.day = day
            appID = context.appID
            keyboardID = context.keyboardID ?? ""
            inputSourceID = context.inputSourceID ?? ""
        }

        var arguments: [any DatabaseValueConvertible] { [day, appID, keyboardID, inputSourceID] }
    }

    private static func add(keys: [UInt16: KeyCount], scope: StatScope, db: Database) throws {
        for (keyCode, count) in keys {
            try db.execute(sql: """
                INSERT INTO keyStat (day, appID, keyboardID, inputSourceID, keyCode, presses, corrections)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT DO UPDATE SET presses = presses + excluded.presses, corrections = corrections + excluded.corrections
                """, arguments: StatementArguments(scope.arguments + [Int(keyCode), count.presses, count.corrections]))
        }
    }

    private static func add(pairs: [KeyPair: PairTiming], scope: StatScope, db: Database) throws {
        for (pair, timing) in pairs {
            try db.execute(sql: """
                INSERT INTO pairStat (day, appID, keyboardID, inputSourceID, fromKey, toKey, count, totalMilliseconds)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT DO UPDATE SET count = count + excluded.count, totalMilliseconds = totalMilliseconds + excluded.totalMilliseconds
                """, arguments: StatementArguments(scope.arguments + [Int(pair.from), Int(pair.to), timing.count, timing.totalMilliseconds]))
        }
    }

    @discardableResult
    public func insert(_ record: SessionRecord) throws -> SessionRecord {
        try db.write { db in try record.inserted(db) }
    }

    /// Sessions that started inside the interval, oldest first.
    public func sessions(in interval: DateInterval) throws -> [SessionRecord] {
        try db.read { db in
            try SessionRecord
                .filter(Column("start") >= interval.start && Column("start") < interval.end)
                .order(Column("start"))
                .fetchAll(db)
        }
    }

    public func allSessions() throws -> [SessionRecord] {
        try db.read { db in try SessionRecord.order(Column("start")).fetchAll(db) }
    }

    public func firstSessionStart() throws -> Date? {
        try db.read { db in
            try Date.fetchOne(db, sql: "SELECT MIN(start) FROM session")
        }
    }

    /// Key statistics for the days in the interval, optionally narrowed to one keyboard or layout.
    public func keyStats(in interval: DateInterval, calendar: Calendar, filter: StatFilter = StatFilter()) throws -> [UInt16: KeyCount] {
        let (clause, arguments) = filter.sql(interval: interval, calendar: calendar)
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT keyCode, SUM(presses) AS presses, SUM(corrections) AS corrections FROM keyStat WHERE \(clause) GROUP BY keyCode", arguments: arguments)
            return Dictionary(uniqueKeysWithValues: rows.map { (UInt16($0["keyCode"] as Int), KeyCount(presses: $0["presses"], corrections: $0["corrections"])) })
        }
    }

    public func pairStats(in interval: DateInterval, calendar: Calendar, filter: StatFilter = StatFilter()) throws -> [KeyPair: PairTiming] {
        let (clause, arguments) = filter.sql(interval: interval, calendar: calendar)
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT fromKey, toKey, SUM(count) AS count, SUM(totalMilliseconds) AS total FROM pairStat WHERE \(clause) GROUP BY fromKey, toKey", arguments: arguments)
            return Dictionary(uniqueKeysWithValues: rows.map {
                (KeyPair(from: UInt16($0["fromKey"] as Int), to: UInt16($0["toKey"] as Int)), PairTiming(count: $0["count"], totalMilliseconds: $0["total"]))
            })
        }
    }

    // MARK: Devices

    public func noteKeyboard(_ keyboard: KeyboardRecord) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO keyboard (id, name, isBuiltIn, lastSeen) VALUES (?, ?, ?, ?)
                ON CONFLICT DO UPDATE SET name = excluded.name, isBuiltIn = excluded.isBuiltIn, lastSeen = excluded.lastSeen
                """, arguments: [keyboard.id, keyboard.name, keyboard.isBuiltIn, keyboard.lastSeen])
        }
    }

    public func renameKeyboard(id: String, to customName: String?) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE keyboard SET customName = ? WHERE id = ?", arguments: [customName, id])
        }
    }

    public func keyboards() throws -> [KeyboardRecord] {
        try db.read { db in try KeyboardRecord.order(Column("lastSeen").desc).fetchAll(db) }
    }

    public func noteInputSource(_ source: InputSourceRecord) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO inputSource (id, name, lastSeen) VALUES (?, ?, ?)
                ON CONFLICT DO UPDATE SET name = excluded.name, lastSeen = excluded.lastSeen
                """, arguments: [source.id, source.name, source.lastSeen])
        }
    }

    public func inputSources() throws -> [InputSourceRecord] {
        try db.read { db in try InputSourceRecord.order(Column("lastSeen").desc).fetchAll(db) }
    }

    // MARK: Synthetic input

    public func addSynthetic(count: Int, appID: String, day: String) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO syntheticStat (day, appID, count) VALUES (?, ?, ?)
                ON CONFLICT DO UPDATE SET count = count + excluded.count
                """, arguments: [day, appID, count])
        }
    }

    /// Key presses filtered out as synthetic on the days in the interval.
    public func syntheticCount(in interval: DateInterval, calendar: Calendar) throws -> Int {
        let (clause, arguments) = StatFilter().sql(interval: interval, calendar: calendar)
        return try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(count), 0) FROM syntheticStat WHERE \(clause)", arguments: arguments) ?? 0
        }
    }

    // MARK: Deletion

    public func deleteSessions(appID: String) throws {
        try db.write { db in
            _ = try SessionRecord.filter(Column("appID") == appID).deleteAll(db)
            for table in ["keyStat", "pairStat", "syntheticStat"] {
                try db.execute(sql: "DELETE FROM \(table) WHERE appID = ?", arguments: [appID])
            }
        }
    }

    public func deleteAll() throws {
        try db.write { db in
            for table in ["session", "keyStat", "pairStat", "syntheticStat", "keyboard", "inputSource"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}

/// Narrows key and pair statistics to one app, keyboard or layout.
public struct StatFilter: Sendable, Equatable {
    public var appID: String?
    public var keyboardID: String?
    public var inputSourceID: String?

    public init(appID: String? = nil, keyboardID: String? = nil, inputSourceID: String? = nil) {
        self.appID = appID
        self.keyboardID = keyboardID
        self.inputSourceID = inputSourceID
    }

    func sql(interval: DateInterval, calendar: Calendar) -> (String, StatementArguments) {
        var clauses = ["day >= ?", "day < ?"]
        var arguments: [any DatabaseValueConvertible] = [Day.key(interval.start, calendar: calendar), Day.key(interval.end, calendar: calendar)]
        for (column, value) in [("appID", appID), ("keyboardID", keyboardID), ("inputSourceID", inputSourceID)] {
            guard let value else { continue }
            clauses.append("\(column) = ?")
            arguments.append(value)
        }
        return (clauses.joined(separator: " AND "), StatementArguments(arguments))
    }
}

/// Calendar days as sortable "yyyy-MM-dd" keys.
public enum Day {
    public static func key(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

public struct KeyboardRecord: Codable, Sendable, Equatable, FetchableRecord, TableRecord {
    public static let databaseTableName = "keyboard"
    /// Vendor and product, e.g. "1452:834".
    public var id: String
    public var name: String
    public var isBuiltIn: Bool
    public var customName: String?
    public var lastSeen: Date

    public init(id: String, name: String, isBuiltIn: Bool, customName: String? = nil, lastSeen: Date) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.customName = customName
        self.lastSeen = lastSeen
    }

    public var displayName: String { customName ?? name }
}

public struct InputSourceRecord: Codable, Sendable, Equatable, FetchableRecord, TableRecord {
    public static let databaseTableName = "inputSource"
    public var id: String
    public var name: String
    public var lastSeen: Date

    public init(id: String, name: String, lastSeen: Date) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
    }
}
