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
    /// Characters typed in the session and deleted again; nil for sessions saved before it was tracked.
    public var deletions: Int?
    /// Seconds of typing with pauses left out; nil for sessions saved before it was tracked.
    public var activeSeconds: Double?

    public init(
        id: Int64? = nil, start: Date, end: Date, appID: String,
        keyboardID: String? = nil, inputSourceID: String? = nil,
        characters: Int, backspaces: Int, keystrokes: Int,
        deletions: Int? = nil, activeSeconds: Double? = nil
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
        self.deletions = deletions
        self.activeSeconds = activeSeconds
    }

    /// - Parameter end: wall-clock time of the session's last press.
    public init(_ session: TypingSession, endingAt end: Date) {
        self.init(
            start: end.addingTimeInterval(-session.duration), end: end,
            appID: session.context.appID,
            keyboardID: session.context.keyboardID, inputSourceID: session.context.inputSourceID,
            characters: session.characters, backspaces: session.backspaces, keystrokes: session.keystrokes,
            deletions: session.deletions, activeSeconds: session.activeDuration
        )
    }

    /// Older sessions without typing time or deletions fall back to their elapsed time and backspaces.
    public var totals: TypingTotals {
        TypingTotals(characters: characters, backspaces: backspaces, deletions: deletions, keystrokes: keystrokes,
                     duration: activeSeconds ?? end.timeIntervalSince(start))
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

    init(_ db: DatabaseQueue) throws {
        self.db = db
        try Self.migrator.migrate(db)
    }

    static var migrator: DatabaseMigrator {
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
        migrator.registerMigration("v3-per-session-stats") { db in
            // Key and pair statistics move from daily rows to rows per session, so they group
            // exactly like sessions in any time zone and go with their session when it's deleted.
            try db.drop(table: "keyStat")
            try db.drop(table: "pairStat")
            try db.drop(table: "syntheticStat")
            try db.create(table: "sessionKey") { t in
                t.belongsTo("session", onDelete: .cascade).notNull()
                t.column("keyCode", .integer).notNull()
                t.column("presses", .integer).notNull()
                t.column("corrections", .integer).notNull()
                t.primaryKey(["sessionId", "keyCode"])
            }
            try db.create(table: "sessionPair") { t in
                t.belongsTo("session", onDelete: .cascade).notNull()
                t.column("fromKey", .integer).notNull()
                t.column("toKey", .integer).notNull()
                t.column("count", .integer).notNull()
                t.column("totalMilliseconds", .double).notNull()
                t.primaryKey(["sessionId", "fromKey", "toKey"])
            }
            // Filtered presses aren't part of a session; they're counted per hour since 1970 (UTC).
            try db.create(table: "syntheticStat") { t in
                t.column("hour", .integer).notNull()
                t.column("appID", .text).notNull()
                t.column("count", .integer).notNull()
                t.primaryKey(["hour", "appID"])
            }
        }
        migrator.registerMigration("v4-layout-labels") { db in
            try db.alter(table: "inputSource") { t in t.add(column: "labels", .text) }
        }
        migrator.registerMigration("v5-typing-time") { db in
            try db.alter(table: "session") { t in
                t.add(column: "deletions", .integer)
                t.add(column: "activeSeconds", .double)
            }
        }
        migrator.registerMigration("v6-press-counts") { db in
            try db.create(table: "pressStat") { t in
                t.column("hour", .integer).notNull()
                t.column("appID", .text).notNull()
                t.column("keyboardID", .text).notNull()
                t.column("inputSourceID", .text).notNull()
                t.column("keyCode", .integer).notNull()
                t.column("presses", .integer).notNull()
                t.primaryKey(["hour", "appID", "keyboardID", "inputSourceID", "keyCode"])
            }
        }
        return migrator
    }

    /// Saves a finished live session with its key and key-pair statistics.
    /// - Parameter end: wall-clock time of the session's last press.
    @discardableResult
    public func save(_ session: TypingSession, endingAt end: Date) throws -> SessionRecord {
        try db.write { db in
            let saved = try SessionRecord(session, endingAt: end).inserted(db)
            for (keyCode, count) in session.keys {
                try db.execute(
                    sql: "INSERT INTO sessionKey (sessionId, keyCode, presses, corrections) VALUES (?, ?, ?, ?)",
                    arguments: [saved.id, Int(keyCode), count.presses, count.corrections]
                )
            }
            for (pair, timing) in session.pairs {
                try db.execute(
                    sql: "INSERT INTO sessionPair (sessionId, fromKey, toKey, count, totalMilliseconds) VALUES (?, ?, ?, ?, ?)",
                    arguments: [saved.id, Int(pair.from), Int(pair.to), timing.count, timing.totalMilliseconds]
                )
            }
            return saved
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

    /// The oldest session start or press-count hour, for ranges that include short bursts too.
    public func firstHistoryStart() throws -> Date? {
        try db.read { db in
            let session = try Date.fetchOne(db, sql: "SELECT MIN(start) FROM session")
            let hour = try Int.fetchOne(db, sql: "SELECT MIN(hour) FROM pressStat")
            return [session, hour.map { Date(timeIntervalSince1970: Double($0) * 3600) }].compactMap { $0 }.min()
        }
    }

    /// All presses in hours overlapping the interval, optionally narrowed to an app, keyboard or layout.
    /// Before the first stored press-count hour, uses sessions that started in the interval and before
    /// that hour. Those older key counts cover only character keys and Delete. With no press counts,
    /// the entire interval uses sessions. Coverage starts globally, regardless of the filter.
    public func pressCounts(in interval: DateInterval, filter: StatFilter = StatFilter()) throws -> [UInt16: Int] {
        guard interval.duration > 0 else { return [:] }
        return try db.read { db in
            let firstHour = try Int.fetchOne(db, sql: "SELECT MIN(hour) FROM pressStat")
            let coverage = firstHour.map { Date(timeIntervalSince1970: Double($0) * 3600) }
            var counts: [UInt16: Int] = [:]
            let sessionEnd = min(interval.end, coverage ?? interval.end)
            if sessionEnd > interval.start {
                let (clause, arguments) = filter.sql(interval: DateInterval(start: interval.start, end: sessionEnd))
                let rows = try Row.fetchAll(db, sql: """
                    SELECT k.keyCode, SUM(k.presses) AS presses
                    FROM sessionKey k JOIN session s ON s.id = k.sessionId
                    WHERE \(clause) GROUP BY k.keyCode
                    """, arguments: arguments)
                for row in rows { counts[UInt16(row["keyCode"] as Int)] = row["presses"] }
            }
            if firstHour != nil {
                var clauses = ["hour >= ?", "hour < ?"]
                var arguments: [any DatabaseValueConvertible] = [Hour.index(interval.start), Hour.index(interval.end, roundingUp: true)]
                for (column, value) in [("appID", filter.appID), ("keyboardID", filter.keyboardID), ("inputSourceID", filter.inputSourceID)] {
                    guard let value else { continue }
                    clauses.append("\(column) = ?")
                    arguments.append(value)
                }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT keyCode, SUM(presses) AS presses FROM pressStat
                    WHERE \(clauses.joined(separator: " AND ")) GROUP BY keyCode
                    """, arguments: StatementArguments(arguments))
                for row in rows { counts[UInt16(row["keyCode"] as Int), default: 0] += row["presses"] as Int }
            }
            return counts
        }
    }

    public func addPresses(count: Int, keyCode: UInt16, appID: String, keyboardID: String?, inputSourceID: String?, hour: Int) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO pressStat (hour, appID, keyboardID, inputSourceID, keyCode, presses) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT DO UPDATE SET presses = presses + excluded.presses
                """, arguments: [hour, appID, keyboardID ?? "", inputSourceID ?? "", Int(keyCode), count])
        }
    }

    /// Key statistics of sessions that started in the interval, optionally narrowed to an app, keyboard or layout.
    public func keyStats(in interval: DateInterval, filter: StatFilter = StatFilter()) throws -> [UInt16: KeyCount] {
        let (clause, arguments) = filter.sql(interval: interval)
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT k.keyCode, SUM(k.presses) AS presses, SUM(k.corrections) AS corrections
                FROM sessionKey k JOIN session s ON s.id = k.sessionId
                WHERE \(clause) GROUP BY k.keyCode
                """, arguments: arguments)
            return Dictionary(uniqueKeysWithValues: rows.map { (UInt16($0["keyCode"] as Int), KeyCount(presses: $0["presses"], corrections: $0["corrections"])) })
        }
    }

    public func pairStats(in interval: DateInterval, filter: StatFilter = StatFilter()) throws -> [KeyPair: PairTiming] {
        let (clause, arguments) = filter.sql(interval: interval)
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.fromKey, p.toKey, SUM(p.count) AS count, SUM(p.totalMilliseconds) AS total
                FROM sessionPair p JOIN session s ON s.id = p.sessionId
                WHERE \(clause) GROUP BY p.fromKey, p.toKey
                """, arguments: arguments)
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

    /// Records a layout as seen; its key labels are kept so its statistics stay labeled after it's removed.
    public func noteInputSource(_ source: InputSourceRecord) throws {
        let labels = try source.labels.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO inputSource (id, name, lastSeen, labels) VALUES (?, ?, ?, ?)
                ON CONFLICT DO UPDATE SET name = excluded.name, lastSeen = excluded.lastSeen, labels = COALESCE(excluded.labels, labels)
                """, arguments: [source.id, source.name, source.lastSeen, labels])
        }
    }

    public func inputSources() throws -> [InputSourceRecord] {
        try db.read { db in try InputSourceRecord.order(Column("lastSeen").desc).fetchAll(db) }
    }

    // MARK: Synthetic input

    public func addSynthetic(count: Int, appID: String, hour: Int) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO syntheticStat (hour, appID, count) VALUES (?, ?, ?)
                ON CONFLICT DO UPDATE SET count = count + excluded.count
                """, arguments: [hour, appID, count])
        }
    }

    /// Key presses filtered out as synthetic in the hours overlapping the interval, optionally for one app.
    public func syntheticCount(in interval: DateInterval, appID: String? = nil) throws -> Int {
        guard interval.duration > 0 else { return 0 }
        var sql = "SELECT COALESCE(SUM(count), 0) FROM syntheticStat WHERE hour >= ? AND hour < ?"
        var arguments: [any DatabaseValueConvertible] = [Hour.index(interval.start), Hour.index(interval.end, roundingUp: true)]
        if let appID {
            sql += " AND appID = ?"
            arguments.append(appID)
        }
        return try db.read { db in try Int.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) ?? 0 }
    }

    // MARK: Deletion

    /// Deletes an app's sessions, with their key and pair statistics, and its press and filtered-input counts.
    public func deleteSessions(appID: String) throws {
        try db.write { db in
            _ = try SessionRecord.filter(Column("appID") == appID).deleteAll(db)
            try db.execute(sql: "DELETE FROM syntheticStat WHERE appID = ?", arguments: [appID])
            try db.execute(sql: "DELETE FROM pressStat WHERE appID = ?", arguments: [appID])
        }
    }

    public func deleteAll() throws {
        try db.write { db in
            for table in ["session", "syntheticStat", "pressStat", "keyboard", "inputSource"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}

/// Narrows press, key and pair statistics to one app, keyboard or layout.
public struct StatFilter: Sendable, Equatable {
    public var appID: String?
    public var keyboardID: String?
    public var inputSourceID: String?

    public init(appID: String? = nil, keyboardID: String? = nil, inputSourceID: String? = nil) {
        self.appID = appID
        self.keyboardID = keyboardID
        self.inputSourceID = inputSourceID
    }

    /// A WHERE clause over the session table aliased `s`.
    func sql(interval: DateInterval) -> (String, StatementArguments) {
        var clauses = ["s.start >= ?", "s.start < ?"]
        var arguments: [any DatabaseValueConvertible] = [interval.start, interval.end]
        for (column, value) in [("appID", appID), ("keyboardID", keyboardID), ("inputSourceID", inputSourceID)] {
            guard let value else { continue }
            clauses.append("s.\(column) = ?")
            arguments.append(value)
        }
        return (clauses.joined(separator: " AND "), StatementArguments(arguments))
    }
}

/// Hours since 1970 in UTC, the bucket for press and filtered-input counts.
public enum Hour {
    /// - Parameter roundingUp: true for an exclusive upper bound, so a partial hour counts.
    public static func index(_ date: Date, roundingUp: Bool = false) -> Int {
        Int((date.timeIntervalSince1970 / 3600).rounded(roundingUp ? .up : .down))
    }
}

public struct KeyboardRecord: Codable, Sendable, Equatable, FetchableRecord, TableRecord {
    public static let databaseTableName = "keyboard"
    /// Vendor and product, plus the serial number when reported, e.g. "1133:50475:F2A1";
    /// the device name for keyboards without IDs, e.g. "Apple Internal Keyboard / Trackpad".
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
    /// What each key types under this layout, captured while it was active.
    public var labels: [UInt16: String]?

    public init(id: String, name: String, lastSeen: Date, labels: [UInt16: String]? = nil) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
        self.labels = labels
    }
}
