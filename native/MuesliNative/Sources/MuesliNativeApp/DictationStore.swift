import Foundation
import SQLite3

final class DictationStore {
    private let databaseURL: URL

    init() {
        let supportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Muesli", isDirectory: true)
        self.databaseURL = supportURL.appendingPathComponent("muesli.db")
    }

    func migrateIfNeeded() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let createSQL = """
        CREATE TABLE IF NOT EXISTS dictations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            duration_seconds REAL,
            raw_text TEXT,
            app_context TEXT,
            word_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'dictation',
            started_at TEXT,
            ended_at TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_dictations_timestamp ON dictations(timestamp DESC);
        """
        try exec(createSQL, db: db)
    }

    func insertDictation(
        text: String,
        durationSeconds: Double,
        appContext: String = "",
        startedAt: Date,
        endedAt: Date
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO dictations
        (timestamp, duration_seconds, raw_text, app_context, word_count, source, started_at, ended_at)
        VALUES (?, ?, ?, ?, ?, 'dictation', ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        let timestamp = ISO8601DateFormatter().string(from: endedAt)
        let started = ISO8601DateFormatter().string(from: startedAt)
        let ended = ISO8601DateFormatter().string(from: endedAt)
        sqlite3_bind_text(statement, 1, (timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 2, durationSeconds)
        sqlite3_bind_text(statement, 3, (text as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (appContext as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(Self.countWords(in: text)))
        sqlite3_bind_text(statement, 6, (started as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (ended as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    func recentDictations(limit: Int = 10) throws -> [DictationRecord] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, timestamp, duration_seconds, raw_text, app_context, word_count
        FROM dictations
        ORDER BY timestamp DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var rows: [DictationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                DictationRecord(
                    id: sqlite3_column_int64(statement, 0),
                    timestamp: stringColumn(statement, index: 1),
                    durationSeconds: sqlite3_column_double(statement, 2),
                    rawText: stringColumn(statement, index: 3),
                    appContext: stringColumn(statement, index: 4),
                    wordCount: Int(sqlite3_column_int(statement, 5))
                )
            )
        }
        return rows
    }

    func clearDictations() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try exec("DELETE FROM dictations", db: db)
    }

    func databasePath() -> URL {
        databaseURL
    }

    static func countWords(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func openDatabase() throws -> OpaquePointer? {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw lastError(db)
        }
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
        return db
    }

    private func exec(_ sql: String, db: OpaquePointer?) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
    }

    private func lastError(_ db: OpaquePointer?) -> NSError {
        NSError(
            domain: "MuesliDB",
            code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
        )
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }
}
