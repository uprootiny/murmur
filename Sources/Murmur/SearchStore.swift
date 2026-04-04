import CSQLite
import Foundation

/// Result type for full-text search queries.
struct SearchResult: Identifiable {
    let id = UUID()
    let timestamp: Date
    let chunkID: Int
    let type: ResultType
    let snippet: String

    enum ResultType: String {
        case ocr = "ocr"
        case transcript = "transcript"
        case metadata = "metadata"
    }
}

/// SQLite + FTS5 backed search index for OCR text, transcripts, and app metadata.
///
/// Tables:
/// - `ocr_text(timestamp REAL, chunk_id INTEGER, text TEXT)`
/// - `transcripts(timestamp REAL, chunk_id INTEGER, text TEXT)`
/// - `metadata(timestamp REAL, app_name TEXT, window_title TEXT, url TEXT)`
/// - FTS5 virtual tables: `ocr_fts`, `transcripts_fts`
final class SearchStore {
    // MARK: - Private

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.uprootiny.murmur.searchstore", qos: .utility)

    // MARK: - Init

    init() {
        let dbURL = Self.databaseURL()
        // Ensure parent directory exists
        let dir = dbURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("[Murmur] Failed to open search database at \(dbURL.path)")
            db = nil
            return
        }

        createTablesIfNeeded()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Location

    static func databaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let murmurDir = appSupport.appendingPathComponent("Murmur", isDirectory: true)
        return murmurDir.appendingPathComponent("search.sqlite")
    }

    // MARK: - Schema

    private func createTablesIfNeeded() {
        let statements = [
            // Core tables
            """
            CREATE TABLE IF NOT EXISTS ocr_text (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                chunk_id INTEGER NOT NULL,
                text TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS transcripts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                chunk_id INTEGER NOT NULL,
                text TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS metadata (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                app_name TEXT,
                window_title TEXT,
                url TEXT
            );
            """,
            // FTS5 virtual tables
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS ocr_fts USING fts5(
                text,
                content='ocr_text',
                content_rowid='id'
            );
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts USING fts5(
                text,
                content='transcripts',
                content_rowid='id'
            );
            """,
            // Triggers to keep FTS in sync with content tables
            """
            CREATE TRIGGER IF NOT EXISTS ocr_text_ai AFTER INSERT ON ocr_text BEGIN
                INSERT INTO ocr_fts(rowid, text) VALUES (new.id, new.text);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS ocr_text_ad AFTER DELETE ON ocr_text BEGIN
                INSERT INTO ocr_fts(ocr_fts, rowid, text) VALUES ('delete', old.id, old.text);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS transcripts_ai AFTER INSERT ON transcripts BEGIN
                INSERT INTO transcripts_fts(rowid, text) VALUES (new.id, new.text);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS transcripts_ad AFTER DELETE ON transcripts BEGIN
                INSERT INTO transcripts_fts(transcripts_fts, rowid, text) VALUES ('delete', old.id, old.text);
            END;
            """,
            // Indexes for time-range queries
            "CREATE INDEX IF NOT EXISTS idx_ocr_timestamp ON ocr_text(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_transcripts_timestamp ON transcripts(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_metadata_timestamp ON metadata(timestamp);",
        ]

        for sql in statements {
            execute(sql)
        }
    }

    // MARK: - Insert Methods

    /// Insert OCR-recognized text for a given frame timestamp and chunk.
    func insertOCRText(timestamp: Date, chunkID: Int, text: String) {
        queue.async { [weak self] in
            self?.execute(
                "INSERT INTO ocr_text (timestamp, chunk_id, text) VALUES (?, ?, ?);",
                bindings: [.real(timestamp.timeIntervalSince1970), .integer(Int64(chunkID)), .text(text)]
            )
        }
    }

    /// Insert a transcript segment for a given audio chunk.
    func insertTranscript(timestamp: Date, chunkID: Int, text: String) {
        queue.async { [weak self] in
            self?.execute(
                "INSERT INTO transcripts (timestamp, chunk_id, text) VALUES (?, ?, ?);",
                bindings: [.real(timestamp.timeIntervalSince1970), .integer(Int64(chunkID)), .text(text)]
            )
        }
    }

    /// Insert metadata about the frontmost app at a point in time.
    func insertMetadata(timestamp: Date, appName: String?, windowTitle: String?, url: String?) {
        queue.async { [weak self] in
            self?.execute(
                "INSERT INTO metadata (timestamp, app_name, window_title, url) VALUES (?, ?, ?, ?);",
                bindings: [
                    .real(timestamp.timeIntervalSince1970),
                    appName.map { .text($0) } ?? .null,
                    windowTitle.map { .text($0) } ?? .null,
                    url.map { .text($0) } ?? .null,
                ]
            )
        }
    }

    // MARK: - Query Methods

    /// Full-text search across OCR and transcript tables.
    /// Returns results sorted by timestamp descending.
    func search(query: String) -> [SearchResult] {
        var results: [SearchResult] = []

        // Search OCR text
        let ocrSQL = """
            SELECT o.timestamp, o.chunk_id, snippet(ocr_fts, 0, '<b>', '</b>', '...', 32) AS snip
            FROM ocr_fts
            JOIN ocr_text o ON ocr_fts.rowid = o.id
            WHERE ocr_fts MATCH ?
            ORDER BY o.timestamp DESC
            LIMIT 100;
        """

        results += queryResults(sql: ocrSQL, query: query, type: .ocr)

        // Search transcripts
        let transcriptSQL = """
            SELECT t.timestamp, t.chunk_id, snippet(transcripts_fts, 0, '<b>', '</b>', '...', 32) AS snip
            FROM transcripts_fts
            JOIN transcripts t ON transcripts_fts.rowid = t.id
            WHERE transcripts_fts MATCH ?
            ORDER BY t.timestamp DESC
            LIMIT 100;
        """

        results += queryResults(sql: transcriptSQL, query: query, type: .transcript)

        // Search metadata (plain LIKE since no FTS on metadata)
        let metaSQL = """
            SELECT timestamp, 0 AS chunk_id,
                   COALESCE(app_name, '') || ' - ' || COALESCE(window_title, '') AS snip
            FROM metadata
            WHERE app_name LIKE ? OR window_title LIKE ? OR url LIKE ?
            ORDER BY timestamp DESC
            LIMIT 50;
        """

        let likeQuery = "%\(query)%"
        results += queryResultsLike(sql: metaSQL, likeQuery: likeQuery, type: .metadata)

        // Sort all results by timestamp descending
        results.sort { $0.timestamp > $1.timestamp }

        return results
    }

    /// Fetch metadata entries for a time range.
    func metadata(from start: Date, to end: Date) -> [(timestamp: Date, appName: String?, windowTitle: String?)] {
        var results: [(Date, String?, String?)] = []

        let sql = """
            SELECT timestamp, app_name, window_title FROM metadata
            WHERE timestamp BETWEEN ? AND ?
            ORDER BY timestamp ASC;
        """

        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, end.timeIntervalSince1970)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
                let app = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let title = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                results.append((ts, app, title))
            }
        }
        return results
    }

    /// Delete all records older than a given date.
    func pruneOlderThan(_ date: Date) {
        let ts = date.timeIntervalSince1970
        queue.async { [weak self] in
            self?.execute("DELETE FROM ocr_text WHERE timestamp < ?;", bindings: [.real(ts)])
            self?.execute("DELETE FROM transcripts WHERE timestamp < ?;", bindings: [.real(ts)])
            self?.execute("DELETE FROM metadata WHERE timestamp < ?;", bindings: [.real(ts)])
        }
    }

    // MARK: - Private Query Helpers

    private func queryResults(sql: String, query: String, type: SearchResult.ResultType) -> [SearchResult] {
        var results: [SearchResult] = []
        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (query as NSString).utf8String, -1, nil)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
                let chunkID = Int(sqlite3_column_int64(stmt, 1))
                let snippet = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                results.append(SearchResult(timestamp: ts, chunkID: chunkID, type: type, snippet: snippet))
            }
        }
        return results
    }

    private func queryResultsLike(sql: String, likeQuery: String, type: SearchResult.ResultType) -> [SearchResult] {
        var results: [SearchResult] = []
        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            // Bind all three LIKE parameters
            sqlite3_bind_text(stmt, 1, (likeQuery as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (likeQuery as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (likeQuery as NSString).utf8String, -1, nil)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
                let chunkID = Int(sqlite3_column_int64(stmt, 1))
                let snippet = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                results.append(SearchResult(timestamp: ts, chunkID: chunkID, type: type, snippet: snippet))
            }
        }
        return results
    }

    // MARK: - Low-level SQL Execution

    private enum SQLBinding {
        case text(String)
        case integer(Int64)
        case real(Double)
        case null
    }

    private func execute(_ sql: String, bindings: [SQLBinding] = []) {
        guard let db = db else { return }

        if bindings.isEmpty {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
                let msg = errMsg.map { String(cString: $0) } ?? "unknown"
                print("[Murmur] SQL error: \(msg)")
                sqlite3_free(errMsg)
            }
        } else {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("[Murmur] SQL prepare error: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }

            for (index, binding) in bindings.enumerated() {
                let pos = Int32(index + 1)
                switch binding {
                case .text(let value):
                    sqlite3_bind_text(stmt, pos, (value as NSString).utf8String, -1, nil)
                case .integer(let value):
                    sqlite3_bind_int64(stmt, pos, value)
                case .real(let value):
                    sqlite3_bind_double(stmt, pos, value)
                case .null:
                    sqlite3_bind_null(stmt, pos)
                }
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[Murmur] SQL step error: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }
}
