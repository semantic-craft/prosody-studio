import Foundation
import SQLite3

public final class SQLiteReviewStore: ReviewStore, @unchecked Sendable {
    private let connection: SQLiteConnection

    public init(databaseURL: URL, importCapturesFrom capturesURL: URL? = nil) throws {
        connection = try SQLiteConnection(databaseURL: databaseURL)
        try migrate(importCapturesFrom: capturesURL)
    }

    public func save(_ card: ReviewCard) throws {
        try connection.locked {
            try insert(card)
        }
    }

    public func update(_ card: ReviewCard) throws {
        try connection.locked {
            try updateExisting(card)
        }
    }

    public func recent(_ limit: Int) throws -> [ReviewCard] {
        try connection.locked {
            try fetchCards(
                sql: """
                SELECT id, created_at, source_text, language, idiomatic, reasons_json,
                       due_at, interval_days, repetitions, ease_factor
                FROM review_cards
                ORDER BY created_at DESC
                LIMIT ?;
                """,
                bind: { statement in sqlite3_bind_int(statement, 1, Int32(limit)) })
        }
    }

    public func due(now: Date = Date(), limit: Int) throws -> [ReviewCard] {
        try connection.locked {
            try fetchCards(
                sql: """
                SELECT id, created_at, source_text, language, idiomatic, reasons_json,
                       due_at, interval_days, repetitions, ease_factor
                FROM review_cards
                WHERE due_at <= ?
                ORDER BY due_at ASC
                LIMIT ?;
                """,
                bind: { statement in
                    sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
                    sqlite3_bind_int(statement, 2, Int32(limit))
                })
        }
    }

    public func count() throws -> Int {
        try connection.locked {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try connection.prepare("SELECT COUNT(*) FROM review_cards;", &statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw connection.lastError()
            }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    public func schemaVersion() throws -> Int {
        try connection.locked {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try connection.prepare("SELECT value FROM metadata WHERE key = 'schema_version';", &statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func migrate(importCapturesFrom capturesURL: URL?) throws {
        try connection.locked {
            try connection.execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """)
            try connection.execute("""
            CREATE TABLE IF NOT EXISTS review_cards (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                source_text TEXT NOT NULL,
                language TEXT NOT NULL,
                idiomatic TEXT NOT NULL,
                reasons_json TEXT NOT NULL,
                due_at REAL NOT NULL,
                interval_days INTEGER NOT NULL,
                repetitions INTEGER NOT NULL,
                ease_factor REAL NOT NULL
            );
            """)
            try connection.execute("""
            INSERT INTO metadata (key, value)
            VALUES ('schema_version', '\(AppSchemaVersion.current)')
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """)

            guard let capturesURL,
                  FileManager.default.fileExists(atPath: capturesURL.path) else { return }
            let data = try Data(contentsOf: capturesURL)
            let captures = try JSONDecoder().decode([CaptureItem].self, from: data)
            for capture in captures {
                try insert(ReviewCard(capture: capture))
            }
        }
    }

    private func insert(_ card: ReviewCard) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare("""
        INSERT OR IGNORE INTO review_cards (
            id, created_at, source_text, language, idiomatic, reasons_json,
            due_at, interval_days, repetitions, ease_factor
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, &statement)

        try connection.bind(card.id.uuidString, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, card.createdAt.timeIntervalSince1970)
        try connection.bind(card.sourceText, to: statement, at: 3)
        try connection.bind(card.language, to: statement, at: 4)
        try connection.bind(card.idiomatic, to: statement, at: 5)
        let reasons = try String(data: JSONEncoder().encode(card.reasons), encoding: .utf8)
            .ok("Unable to encode review reasons.")
        try connection.bind(reasons, to: statement, at: 6)
        sqlite3_bind_double(statement, 7, card.dueAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 8, Int32(card.intervalDays))
        sqlite3_bind_int(statement, 9, Int32(card.repetitions))
        sqlite3_bind_double(statement, 10, card.easeFactor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw connection.lastError()
        }
    }

    private func updateExisting(_ card: ReviewCard) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare("""
        UPDATE review_cards
        SET source_text = ?,
            language = ?,
            idiomatic = ?,
            reasons_json = ?,
            due_at = ?,
            interval_days = ?,
            repetitions = ?,
            ease_factor = ?
        WHERE id = ?;
        """, &statement)

        try connection.bind(card.sourceText, to: statement, at: 1)
        try connection.bind(card.language, to: statement, at: 2)
        try connection.bind(card.idiomatic, to: statement, at: 3)
        let reasons = try String(data: JSONEncoder().encode(card.reasons), encoding: .utf8)
            .ok("Unable to encode review reasons.")
        try connection.bind(reasons, to: statement, at: 4)
        sqlite3_bind_double(statement, 5, card.dueAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 6, Int32(card.intervalDays))
        sqlite3_bind_int(statement, 7, Int32(card.repetitions))
        sqlite3_bind_double(statement, 8, card.easeFactor)
        try connection.bind(card.id.uuidString, to: statement, at: 9)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw connection.lastError()
        }
        guard sqlite3_changes(connection.handle) > 0 else {
            throw PersistenceError.invalidStoredValue("Review card not found: \(card.id.uuidString).")
        }
    }

    private func fetchCards(
        sql: String,
        bind: (OpaquePointer?) throws -> Void
    ) throws -> [ReviewCard] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare(sql, &statement)
        try bind(statement)

        var cards: [ReviewCard] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            cards.append(try decodeCard(from: statement))
        }
        return cards
    }

    private func decodeCard(from statement: OpaquePointer?) throws -> ReviewCard {
        let id = try UUID(uuidString: try connection.columnText(statement, 0))
            .ok("Invalid review card id.")
        let reasonsData = Data(try connection.columnText(statement, 5).utf8)
        let reasons = try JSONDecoder().decode([String].self, from: reasonsData)

        return ReviewCard(
            id: id,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            sourceText: try connection.columnText(statement, 2),
            language: try connection.columnText(statement, 3),
            idiomatic: try connection.columnText(statement, 4),
            reasons: reasons,
            dueAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            intervalDays: Int(sqlite3_column_int(statement, 7)),
            repetitions: Int(sqlite3_column_int(statement, 8)),
            easeFactor: sqlite3_column_double(statement, 9))
    }
}

private extension Optional {
    func ok(_ message: String) throws -> Wrapped {
        guard let self else { throw PersistenceError.invalidStoredValue(message) }
        return self
    }
}

public extension ReviewStore where Self == SQLiteReviewStore {
    static func defaultStore(importCaptures: Bool = true) throws -> SQLiteReviewStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
        return try SQLiteReviewStore(
            databaseURL: base.appendingPathComponent("review.sqlite"),
            importCapturesFrom: importCaptures ? base.appendingPathComponent("captures.json") : nil)
    }
}
