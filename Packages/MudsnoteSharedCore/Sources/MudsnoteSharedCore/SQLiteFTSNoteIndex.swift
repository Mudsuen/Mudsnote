import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteNoteIndexRecord: Equatable, Sendable {
    public let path: String
    public let modifiedAt: TimeInterval
    public let createdAt: TimeInterval
    public let fileSize: UInt64
    public let title: String
    public let body: String
    public let snippet: String
    public let tags: [String]
    public let extraJSON: Data?

    public init(
        path: String,
        modifiedAt: TimeInterval,
        createdAt: TimeInterval,
        fileSize: UInt64,
        title: String,
        body: String,
        snippet: String,
        tags: [String],
        extraJSON: Data? = nil
    ) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.fileSize = fileSize
        self.title = title
        self.body = body
        self.snippet = snippet
        self.tags = tags
        self.extraJSON = extraJSON
    }
}

public struct SQLiteFTSSearchHit: Equatable, Sendable {
    public let path: String
    public let score: Double

    public init(path: String, score: Double) {
        self.path = path
        self.score = score
    }
}

/// Embedded WAL-mode SQLite3 + FTS5 trigram incremental cache shared by macOS and iOS.
/// Updates only changed/deleted rows per transaction instead of rewriting a monolithic JSON snapshot.
public final class SQLiteFTSNoteIndex: @unchecked Sendable {
    public static let currentSchemaVersion = 2

    public let databaseURL: URL
    private let lock = NSLock()
    private var db: OpaquePointer?

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL.standardizedFileURL
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    public func removeDatabaseFiles() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
        removeFilesLocked()
    }

    /// Loads all indexed records if the on-disk database matches `expectedSchemaVersion`
    /// and `expectedRootsKey`. Removes corrupt or incompatible database files automatically.
    public func loadAll(
        expectedRootsKey: [String],
        expectedSchemaVersion: Int = SQLiteFTSNoteIndex.currentSchemaVersion
    ) -> [SQLiteNoteIndexRecord]? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }
        guard openLocked(createIfMissing: false) else {
            removeFilesLocked()
            return nil
        }

        guard readMetaLocked(key: "schema_version") == String(expectedSchemaVersion),
              let storedRootsData = readMetaLocked(key: "roots_key")?.data(using: .utf8),
              let storedRoots = try? JSONDecoder().decode([String].self, from: storedRootsData),
              storedRoots == expectedRootsKey else {
            return nil
        }

        let sql = """
        SELECT path, modified_at, created_at, file_size, title, body, snippet, tags_json, extra_json
        FROM notes
        ORDER BY rowid ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            closeLocked()
            removeFilesLocked()
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var records: [SQLiteNoteIndexRecord] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                closeLocked()
                removeFilesLocked()
                return nil
            }
            guard let path = columnText(stmt, 0) else { continue }
            let modifiedAt = sqlite3_column_double(stmt, 1)
            let createdAt = sqlite3_column_double(stmt, 2)
            let fileSize = UInt64(max(0, sqlite3_column_int64(stmt, 3)))
            let title = columnText(stmt, 4) ?? ""
            let body = columnText(stmt, 5) ?? ""
            let snippet = columnText(stmt, 6) ?? ""
            let tagsString = columnText(stmt, 7) ?? "[]"
            let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsString.utf8))) ?? []
            let extraJSON = columnBlob(stmt, 8)
            records.append(SQLiteNoteIndexRecord(
                path: path,
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                fileSize: fileSize,
                title: title,
                body: body,
                snippet: snippet,
                tags: tags,
                extraJSON: extraJSON
            ))
        }
        return records
    }

    /// Replaces the entire cache atomically (used on initial full scan or roots change).
    @discardableResult
    public func replaceAll(
        rootsKey: [String],
        records: [SQLiteNoteIndexRecord],
        schemaVersion: Int = SQLiteFTSNoteIndex.currentSchemaVersion
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard openLocked(createIfMissing: true) else {
            closeLocked()
            removeFilesLocked()
            return false
        }
        guard beginTransactionLocked() else {
            closeLocked()
            removeFilesLocked()
            return false
        }

        let rootsJSON = (try? String(data: JSONEncoder().encode(rootsKey), encoding: .utf8)) ?? "[]"
        guard execLocked("DELETE FROM notes;"),
              execLocked("DELETE FROM notes_fts;"),
              writeMetaLocked(key: "schema_version", value: String(schemaVersion)),
              writeMetaLocked(key: "roots_key", value: rootsJSON),
              upsertRecordsInTransactionLocked(records),
              commitTransactionLocked() else {
            _ = execLocked("ROLLBACK;")
            closeLocked()
            removeFilesLocked()
            return false
        }
        return true
    }

    /// Incrementally upserts modified/added records and deletes removed paths in a single transaction.
    @discardableResult
    public func applyIncrementalChanges(
        rootsKey: [String],
        upserts: [SQLiteNoteIndexRecord],
        deletes: [String],
        schemaVersion: Int = SQLiteFTSNoteIndex.currentSchemaVersion
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard openLocked(createIfMissing: true) else {
            closeLocked()
            removeFilesLocked()
            return false
        }

        // Verify metadata matches; if not, caller should do a full replace.
        if let existingSchema = readMetaLocked(key: "schema_version"),
           existingSchema != String(schemaVersion) {
            return false
        }
        if let storedRootsData = readMetaLocked(key: "roots_key")?.data(using: .utf8),
           let storedRoots = try? JSONDecoder().decode([String].self, from: storedRootsData),
           storedRoots != rootsKey {
            return false
        }

        guard beginTransactionLocked() else {
            closeLocked()
            removeFilesLocked()
            return false
        }

        let rootsJSON = (try? String(data: JSONEncoder().encode(rootsKey), encoding: .utf8)) ?? "[]"
        guard writeMetaLocked(key: "schema_version", value: String(schemaVersion)),
              writeMetaLocked(key: "roots_key", value: rootsJSON),
              deletePathsInTransactionLocked(deletes),
              upsertRecordsInTransactionLocked(upserts),
              commitTransactionLocked() else {
            _ = execLocked("ROLLBACK;")
            closeLocked()
            removeFilesLocked()
            return false
        }
        return true
    }

    /// Queries the FTS5 trigram index (with BM25 ranking) for >= 3-char terms and combines with
    /// normalized substring filtering for 1-2 char terms so CJK & short Latin queries have 100% recall.
    public func search(query: String, limit: Int = 200) -> [SQLiteFTSSearchHit]? {
        lock.lock()
        defer { lock.unlock() }

        let terms = NoteSearchTokenizer.terms(from: query)
        guard !terms.isEmpty else { return [] }
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              openLocked(createIfMissing: false) else {
            return nil
        }

        let ftsTerms = terms.filter { $0.count >= 3 }
        let shortTerms = terms.filter { $0.count < 3 }

        if !ftsTerms.isEmpty {
            let matchExpr = ftsTerms
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: " AND ")

            var whereClauses = ["notes_fts MATCH ?"]
            for _ in shortTerms {
                whereClauses.append("(instr(lower(notes.title), ?) > 0 OR instr(lower(notes.tags_text), ?) > 0 OR instr(lower(notes.body), ?) > 0)")
            }
            let sql = """
            SELECT notes.path, -bm25(notes_fts, 10.0, 6.0, 1.0) AS rank_score
            FROM notes_fts
            JOIN notes ON notes.path = notes_fts.path
            WHERE \(whereClauses.joined(separator: " AND "))
            ORDER BY rank_score DESC, notes.modified_at DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            var bindIndex: Int32 = 1
            sqlite3_bind_text(stmt, bindIndex, matchExpr, -1, sqliteTransient)
            bindIndex += 1
            for shortTerm in shortTerms {
                let lower = shortTerm.lowercased()
                sqlite3_bind_text(stmt, bindIndex, lower, -1, sqliteTransient)
                bindIndex += 1
                sqlite3_bind_text(stmt, bindIndex, lower, -1, sqliteTransient)
                bindIndex += 1
                sqlite3_bind_text(stmt, bindIndex, lower, -1, sqliteTransient)
                bindIndex += 1
            }
            sqlite3_bind_int(stmt, bindIndex, Int32(max(1, min(limit, Int(Int32.max)))))

            var hits: [SQLiteFTSSearchHit] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let path = columnText(stmt, 0) {
                    hits.append(SQLiteFTSSearchHit(path: path, score: sqlite3_column_double(stmt, 1)))
                }
            }
            return hits
        } else {
            var whereClauses: [String] = []
            for _ in shortTerms {
                whereClauses.append("(instr(lower(title), ?) > 0 OR instr(lower(tags_text), ?) > 0 OR instr(lower(body), ?) > 0)")
            }
            let sql = """
            SELECT path,
                   CASE WHEN instr(lower(title), ?) > 0 THEN 10.0 ELSE 1.0 END AS rank_score
            FROM notes
            WHERE \(whereClauses.joined(separator: " AND "))
            ORDER BY rank_score DESC, modified_at DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            var bindIndex: Int32 = 1
            let primary = shortTerms[0].lowercased()
            sqlite3_bind_text(stmt, bindIndex, primary, -1, sqliteTransient)
            bindIndex += 1
            for shortTerm in shortTerms {
                let lower = shortTerm.lowercased()
                sqlite3_bind_text(stmt, bindIndex, lower, -1, sqliteTransient)
                bindIndex += 1
                sqlite3_bind_text(stmt, bindIndex, lower, -1, sqliteTransient)
                bindIndex += 1
                sqlite3_bind_text(stmt, bindIndex, lower, -1, sqliteTransient)
                bindIndex += 1
            }
            sqlite3_bind_int(stmt, bindIndex, Int32(max(1, min(limit, Int(Int32.max)))))

            var hits: [SQLiteFTSSearchHit] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let path = columnText(stmt, 0) {
                    hits.append(SQLiteFTSSearchHit(path: path, score: sqlite3_column_double(stmt, 1)))
                }
            }
            return hits
        }
    }

    // MARK: - Private SQLite helpers

    private func openLocked(createIfMissing: Bool) -> Bool {
        if db != nil { return true }
        let directory = databaseURL.deletingLastPathComponent()
        if createIfMissing {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }
        let flags = createIfMissing
            ? (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX)
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX)

        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            return false
        }
        db = handle
        sqlite3_busy_timeout(handle, 2_000)

        guard execLocked("PRAGMA journal_mode=WAL;"),
              execLocked("PRAGMA synchronous=NORMAL;"),
              execLocked("PRAGMA temp_store=MEMORY;"),
              createSchemaLocked() else {
            closeLocked()
            return false
        }
        return true
    }

    private func createSchemaLocked() -> Bool {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS notes (
                path TEXT PRIMARY KEY,
                modified_at REAL NOT NULL,
                created_at REAL NOT NULL,
                file_size INTEGER NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                snippet TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                tags_text TEXT NOT NULL,
                extra_json BLOB
            );
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
                path UNINDEXED,
                title,
                tags,
                body,
                tokenize='trigram'
            );
            """
        ]
        for sql in statements {
            guard execLocked(sql) else { return false }
        }
        return true
    }

    private func closeLocked() {
        if let db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    private func removeFilesLocked() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    private func beginTransactionLocked() -> Bool {
        execLocked("BEGIN IMMEDIATE;")
    }

    private func commitTransactionLocked() -> Bool {
        execLocked("COMMIT;")
    }

    private func execLocked(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func readMetaLocked(key: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnText(stmt, 0)
    }

    private func writeMetaLocked(key: String, value: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?);", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, value, -1, sqliteTransient)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func deletePathsInTransactionLocked(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else { return true }
        guard let db else { return false }
        var delNotes: OpaquePointer?
        var delFTS: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM notes WHERE path = ?;", -1, &delNotes, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db, "DELETE FROM notes_fts WHERE path = ?;", -1, &delFTS, nil) == SQLITE_OK else {
            sqlite3_finalize(delNotes)
            sqlite3_finalize(delFTS)
            return false
        }
        defer {
            sqlite3_finalize(delNotes)
            sqlite3_finalize(delFTS)
        }
        for path in paths {
            sqlite3_reset(delNotes)
            sqlite3_clear_bindings(delNotes)
            sqlite3_bind_text(delNotes, 1, path, -1, sqliteTransient)
            guard sqlite3_step(delNotes) == SQLITE_DONE else { return false }

            sqlite3_reset(delFTS)
            sqlite3_clear_bindings(delFTS)
            sqlite3_bind_text(delFTS, 1, path, -1, sqliteTransient)
            guard sqlite3_step(delFTS) == SQLITE_DONE else { return false }
        }
        return true
    }

    private func upsertRecordsInTransactionLocked(_ records: [SQLiteNoteIndexRecord]) -> Bool {
        guard !records.isEmpty else { return true }
        guard let db else { return false }
        let noteSQL = """
        INSERT OR REPLACE INTO notes
        (path, modified_at, created_at, file_size, title, body, snippet, tags_json, tags_text, extra_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var noteStmt: OpaquePointer?
        var delFTSStmt: OpaquePointer?
        var insFTSStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, noteSQL, -1, &noteStmt, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db, "DELETE FROM notes_fts WHERE path = ?;", -1, &delFTSStmt, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db, "INSERT INTO notes_fts(path, title, tags, body) VALUES (?, ?, ?, ?);", -1, &insFTSStmt, nil) == SQLITE_OK else {
            sqlite3_finalize(noteStmt)
            sqlite3_finalize(delFTSStmt)
            sqlite3_finalize(insFTSStmt)
            return false
        }
        defer {
            sqlite3_finalize(noteStmt)
            sqlite3_finalize(delFTSStmt)
            sqlite3_finalize(insFTSStmt)
        }

        let encoder = JSONEncoder()
        for record in records {
            let tagsJSON = (try? String(data: encoder.encode(record.tags), encoding: .utf8)) ?? "[]"
            let tagsText = record.tags.joined(separator: " ")

            sqlite3_reset(noteStmt)
            sqlite3_clear_bindings(noteStmt)
            sqlite3_bind_text(noteStmt, 1, record.path, -1, sqliteTransient)
            sqlite3_bind_double(noteStmt, 2, record.modifiedAt)
            sqlite3_bind_double(noteStmt, 3, record.createdAt)
            sqlite3_bind_int64(noteStmt, 4, Int64(min(record.fileSize, UInt64(Int64.max))))
            sqlite3_bind_text(noteStmt, 5, record.title, -1, sqliteTransient)
            sqlite3_bind_text(noteStmt, 6, record.body, -1, sqliteTransient)
            sqlite3_bind_text(noteStmt, 7, record.snippet, -1, sqliteTransient)
            sqlite3_bind_text(noteStmt, 8, tagsJSON, -1, sqliteTransient)
            sqlite3_bind_text(noteStmt, 9, tagsText, -1, sqliteTransient)
            if let extra = record.extraJSON {
                _ = extra.withUnsafeBytes { rawBuffer in
                    sqlite3_bind_blob(noteStmt, 10, rawBuffer.baseAddress, Int32(extra.count), sqliteTransient)
                }
            } else {
                sqlite3_bind_null(noteStmt, 10)
            }
            guard sqlite3_step(noteStmt) == SQLITE_DONE else { return false }

            sqlite3_reset(delFTSStmt)
            sqlite3_clear_bindings(delFTSStmt)
            sqlite3_bind_text(delFTSStmt, 1, record.path, -1, sqliteTransient)
            guard sqlite3_step(delFTSStmt) == SQLITE_DONE else { return false }

            sqlite3_reset(insFTSStmt)
            sqlite3_clear_bindings(insFTSStmt)
            sqlite3_bind_text(insFTSStmt, 1, record.path, -1, sqliteTransient)
            sqlite3_bind_text(insFTSStmt, 2, record.title, -1, sqliteTransient)
            sqlite3_bind_text(insFTSStmt, 3, tagsText, -1, sqliteTransient)
            sqlite3_bind_text(insFTSStmt, 4, record.body, -1, sqliteTransient)
            guard sqlite3_step(insFTSStmt) == SQLITE_DONE else { return false }
        }
        return true
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
