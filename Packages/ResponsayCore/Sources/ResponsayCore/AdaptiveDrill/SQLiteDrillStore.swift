import Foundation
import SQLite3

/// SQLite-backed `DrillStore`. One `drill_mistakes` table holds the mistake
/// content + its SM-2 spacing + attempt counts. Schema + row mapping here; open /
/// lock / bind plumbing in `SQLiteConnection`; reuses `SM2Scheduler`.
public final class SQLiteDrillStore: DrillStore, @unchecked Sendable {
    private let connection: SQLiteConnection

    public init(databaseURL: URL) throws {
        connection = try SQLiteConnection(databaseURL: databaseURL)
        try migrate()
    }

    // MARK: Write

    public func upsert(_ mistake: MistakeRecord) throws {
        let drillJSON = try String(data: JSONEncoder().encode(mistake.drillPrompts), encoding: .utf8) ?? "[]"
        try connection.locked {
            // Insert with default progress; on conflict update CONTENT ONLY (keep SM-2 + counts).
            try connection.run("""
            INSERT INTO drill_mistakes (
                id, category, prompt, expected, explanation, drill_prompts_json,
                created_at, source_language,
                attempts, successes, due_at, interval_days, repetitions, ease_factor
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, 0, 0, ?)
            ON CONFLICT(id) DO UPDATE SET
                category = excluded.category, prompt = excluded.prompt,
                expected = excluded.expected, explanation = excluded.explanation,
                drill_prompts_json = excluded.drill_prompts_json, source_language = excluded.source_language;
            """) { st in
                try self.connection.bind(mistake.id.uuidString, to: st, at: 1)
                try self.connection.bind(mistake.category, to: st, at: 2)
                try self.connection.bind(mistake.prompt, to: st, at: 3)
                try self.connection.bind(mistake.expected, to: st, at: 4)
                try self.connection.bind(mistake.explanation, to: st, at: 5)
                try self.connection.bind(drillJSON, to: st, at: 6)
                sqlite3_bind_double(st, 7, mistake.createdAt.timeIntervalSince1970)
                try self.connection.bindOptional(mistake.sourceLanguage, to: st, at: 8)
                sqlite3_bind_double(st, 9, mistake.createdAt.timeIntervalSince1970)  // initial due = created
                sqlite3_bind_double(st, 10, SM2Scheduler.defaultEaseFactor)
            }
        }
    }

    public func recordResult(mistakeID: UUID, correct: Bool, reviewedAt: Date) throws {
        try connection.locked {
            guard let current = try progressRow(mistakeID) else {
                throw PersistenceError.invalidStoredValue("Unknown drill mistake \(mistakeID.uuidString).")
            }
            let card = ReviewCard(
                id: mistakeID, sourceText: "", language: "", idiomatic: "", reasons: [],
                dueAt: current.dueAt, intervalDays: current.intervalDays,
                repetitions: current.repetitions, easeFactor: current.easeFactor)
            let scheduled = SM2Scheduler.schedule(card, grade: correct ? .good : .wrong, reviewedAt: reviewedAt)

            try connection.run("""
            UPDATE drill_mistakes SET
                attempts = attempts + 1,
                successes = successes + ?,
                due_at = ?, interval_days = ?, repetitions = ?, ease_factor = ?
            WHERE id = ?;
            """) { st in
                sqlite3_bind_int(st, 1, correct ? 1 : 0)
                sqlite3_bind_double(st, 2, scheduled.dueAt.timeIntervalSince1970)
                sqlite3_bind_int(st, 3, Int32(scheduled.intervalDays))
                sqlite3_bind_int(st, 4, Int32(scheduled.repetitions))
                sqlite3_bind_double(st, 5, scheduled.easeFactor)
                try self.connection.bind(mistakeID.uuidString, to: st, at: 6)
            }
        }
    }

    public func delete(id: UUID) throws {
        try connection.locked {
            try connection.run("DELETE FROM drill_mistakes WHERE id = ?;") {
                try self.connection.bind(id.uuidString, to: $0, at: 1)
            }
        }
    }

    // MARK: Read

    public func all() throws -> [MistakeRecord] {
        try connection.locked {
            try fetch("\(selectContent) ORDER BY created_at DESC;") { _ in }
        }
    }

    public func due(now: Date, limit: Int) throws -> [MistakeRecord] {
        try connection.locked {
            try fetch("\(selectContent) WHERE due_at <= ? ORDER BY due_at ASC LIMIT ?;") { st in
                sqlite3_bind_double(st, 1, now.timeIntervalSince1970)
                sqlite3_bind_int(st, 2, Int32(limit))
            }
        }
    }

    public func progress(for mistakeID: UUID) throws -> DrillProgress? {
        try connection.locked { try progressRow(mistakeID) }
    }

    // MARK: Migration

    private func migrate() throws {
        try connection.locked {
            try connection.execute("""
            CREATE TABLE IF NOT EXISTS drill_mistakes (
                id TEXT PRIMARY KEY NOT NULL,
                category TEXT NOT NULL, prompt TEXT NOT NULL,
                expected TEXT NOT NULL, explanation TEXT NOT NULL, drill_prompts_json TEXT NOT NULL,
                created_at REAL NOT NULL, source_language TEXT,
                attempts INTEGER NOT NULL, successes INTEGER NOT NULL,
                due_at REAL NOT NULL, interval_days INTEGER NOT NULL,
                repetitions INTEGER NOT NULL, ease_factor REAL NOT NULL
            );
            """)
            try connection.execute("CREATE INDEX IF NOT EXISTS idx_drill_due ON drill_mistakes(due_at);")
        }
    }

    private let selectContent = """
    SELECT id, category, prompt, expected, explanation, drill_prompts_json,
           created_at, source_language
    FROM drill_mistakes
    """

    private func fetch(_ sql: String, bind: (OpaquePointer?) throws -> Void) throws -> [MistakeRecord] {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        try connection.prepare(sql, &st)
        try bind(st)
        var out: [MistakeRecord] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(try decode(st)) }
        return out
    }

    private func decode(_ st: OpaquePointer?) throws -> MistakeRecord {
        let id = try UUID(uuidString: try connection.columnText(st, 0)).orThrow("Invalid drill id.")
        let drillData = Data(try connection.columnText(st, 5).utf8)
        let drillPrompts = (try? JSONDecoder().decode([String].self, from: drillData)) ?? []
        return MistakeRecord(
            id: id, category: try connection.columnText(st, 1), prompt: try connection.columnText(st, 2),
            expected: try connection.columnText(st, 3), explanation: try connection.columnText(st, 4),
            drillPrompts: drillPrompts,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 6)),
            sourceLanguage: connection.columnOptionalText(st, 7))
    }

    private func progressRow(_ mistakeID: UUID) throws -> DrillProgress? {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        try connection.prepare("""
        SELECT attempts, successes, due_at, interval_days, repetitions, ease_factor
        FROM drill_mistakes WHERE id = ?;
        """, &st)
        try connection.bind(mistakeID.uuidString, to: st, at: 1)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return DrillProgress(
            mistakeID: mistakeID,
            attempts: Int(sqlite3_column_int(st, 0)),
            successes: Int(sqlite3_column_int(st, 1)),
            dueAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)),
            intervalDays: Int(sqlite3_column_int(st, 3)),
            repetitions: Int(sqlite3_column_int(st, 4)),
            easeFactor: sqlite3_column_double(st, 5))
    }
}

private extension Optional {
    func orThrow(_ message: String) throws -> Wrapped {
        guard let self else { throw PersistenceError.invalidStoredValue(message) }
        return self
    }
}

public extension DrillStore where Self == SQLiteDrillStore {
    /// App-default store: `drills.sqlite` under Application Support/Responsay.
    static func defaultStore() throws -> SQLiteDrillStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
        return try SQLiteDrillStore(databaseURL: base.appendingPathComponent("drills.sqlite"))
    }
}
