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
        return migrator
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

    public func deleteSessions(appID: String) throws {
        _ = try db.write { db in try SessionRecord.filter(Column("appID") == appID).deleteAll(db) }
    }

    public func deleteAll() throws {
        _ = try db.write { db in try SessionRecord.deleteAll(db) }
    }
}
