import Foundation
import SQLite3
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "history")

/// One logged capture. What the Recent list shows and what re-copy reads back.
public struct HistoryItem: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let toolID: String
    public let createdAt: Date
    public let text: String?
    public let fileURL: URL?
    public let duration: TimeInterval?
    /// App name the result was pasted into, when it was.
    public let pastedInto: String?

    public init(
        id: UUID, toolID: String, createdAt: Date, text: String?, fileURL: URL?,
        duration: TimeInterval?, pastedInto: String?
    ) {
        self.id = id
        self.toolID = toolID
        self.createdAt = createdAt
        self.text = text
        self.fileURL = fileURL
        self.duration = duration
        self.pastedInto = pastedInto
    }
}

/// Lightweight log of every `ToolResult`. Plain SQLite, one table, no ORM.
/// Lives at `~/Library/Application Support/Deskpouch/history.sqlite`; `inMemory()` for tests.
@MainActor
public final class HistoryStore {
    public enum StoreError: Error, Equatable {
        case open(String)
        case sql(String)
    }

    private var db: OpaquePointer? { connection.handle }
    private let connection = Connection()

    /// Owns the sqlite3 handle so it can be closed from a nonisolated deinit.
    private final class Connection: @unchecked Sendable {
        var handle: OpaquePointer?
        deinit { if let handle { sqlite3_close(handle) } }
    }

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Deskpouch", directoryHint: .isDirectory)
            .appending(path: "history.sqlite")
    }

    /// Opens (creating if needed) the database at `url`. The parent directory is created.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try open(url.path)
        // Owner-only. Keeps other local users out; any app running as this user can still read it.
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path + suffix)
        }
    }

    /// Fresh in-memory database. Tests and demos.
    public static func inMemory() throws -> HistoryStore {
        try HistoryStore(path: ":memory:")
    }

    private init(path: String) throws {
        try open(path)
    }

    private func open(_ path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw StoreError.open(message)
        }
        connection.handle = handle
        try exec("PRAGMA journal_mode = WAL")
        try exec(
            """
            CREATE TABLE IF NOT EXISTS results (
                id TEXT PRIMARY KEY,
                tool_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                text TEXT,
                file_path TEXT,
                duration REAL,
                pasted_into TEXT
            )
            """
        )
        try exec("CREATE INDEX IF NOT EXISTS results_created_at ON results(created_at DESC)")
    }

    // MARK: Writes

    public func record(_ item: HistoryItem) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO results (id, tool_id, created_at, text, file_path, duration, pasted_into)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, item.id.uuidString)
        bind(statement, 2, item.toolID)
        sqlite3_bind_double(statement, 3, item.createdAt.timeIntervalSince1970)
        bind(statement, 4, item.text)
        bind(statement, 5, item.fileURL?.path)
        if let duration = item.duration {
            sqlite3_bind_double(statement, 6, duration)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        bind(statement, 7, item.pastedInto)
        try step(statement, expecting: SQLITE_DONE)
    }

    public func delete(id: UUID) throws {
        let statement = try prepare("DELETE FROM results WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, id.uuidString)
        try step(statement, expecting: SQLITE_DONE)
    }

    public func clear() throws {
        try exec("DELETE FROM results")
    }

    // MARK: Reads

    /// Newest first.
    public func recent(limit: Int) throws -> [HistoryItem] {
        try items(matching: "", toolID: nil, limit: limit, offset: 0)
    }

    /// Newest first, filtered by a substring of the text or file name and optionally by tool, paged by `offset`.
    public func items(matching query: String, toolID: String?, limit: Int, offset: Int) throws -> [HistoryItem] {
        let statement = try prepare(
            """
            SELECT id, tool_id, created_at, text, file_path, duration, pasted_into
            FROM results
            WHERE (? = '' OR text LIKE ? ESCAPE '\\' OR file_path LIKE ? ESCAPE '\\')
              AND (? IS NULL OR tool_id = ?)
            ORDER BY created_at DESC, rowid DESC LIMIT ? OFFSET ?
            """
        )
        defer { sqlite3_finalize(statement) }
        let pattern = Self.likePattern(query)
        bind(statement, 1, query)
        bind(statement, 2, pattern)
        bind(statement, 3, pattern)
        bind(statement, 4, toolID)
        bind(statement, 5, toolID)
        sqlite3_bind_int(statement, 6, Int32(max(0, limit)))
        sqlite3_bind_int(statement, 7, Int32(max(0, offset)))
        var items: [HistoryItem] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw StoreError.sql(errorMessage()) }
            guard let idText = column(statement, 0), let id = UUID(uuidString: idText),
                  let toolID = column(statement, 1) else { continue }
            items.append(HistoryItem(
                id: id,
                toolID: toolID,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                text: column(statement, 3),
                fileURL: column(statement, 4).map { URL(fileURLWithPath: $0) },
                duration: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5),
                pastedInto: column(statement, 6)
            ))
        }
        return items
    }

    /// Paths of every logged file, for the "items · size" line in General.
    public func filePaths() throws -> [String] {
        let statement = try prepare("SELECT file_path FROM results WHERE file_path IS NOT NULL")
        defer { sqlite3_finalize(statement) }
        var paths: [String] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw StoreError.sql(errorMessage()) }
            if let path = column(statement, 0) { paths.append(path) }
        }
        return paths
    }

    public func count() throws -> Int {
        try count(matching: "", toolID: nil)
    }

    /// Rows `items(matching:toolID:limit:offset:)` would page through.
    public func count(matching query: String, toolID: String?) throws -> Int {
        let statement = try prepare(
            """
            SELECT COUNT(*) FROM results
            WHERE (? = '' OR text LIKE ? ESCAPE '\\' OR file_path LIKE ? ESCAPE '\\')
              AND (? IS NULL OR tool_id = ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        let pattern = Self.likePattern(query)
        bind(statement, 1, query)
        bind(statement, 2, pattern)
        bind(statement, 3, pattern)
        bind(statement, 4, toolID)
        bind(statement, 5, toolID)
        try step(statement, expecting: SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// `%query%` with SQLite's LIKE wildcards escaped, so a literal % or _ in the search matches itself.
    static func likePattern(_ query: String) -> String {
        var escaped = ""
        for character in query {
            if character == "%" || character == "_" || character == "\\" { escaped.append("\\") }
            escaped.append(character)
        }
        return "%" + escaped + "%"
    }

    // MARK: SQLite plumbing

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage()
            sqlite3_free(error)
            log.error("exec failed: \(message, privacy: .public)")
            throw StoreError.sql(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.sql(errorMessage())
        }
        return statement
    }

    private func step(_ statement: OpaquePointer, expecting: Int32) throws {
        guard sqlite3_step(statement) == expecting else {
            let message = errorMessage()
            log.error("step failed: \(message, privacy: .public)")
            throw StoreError.sql(message)
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            // SQLITE_TRANSIENT: SQLite copies the bytes before this call returns.
            sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func errorMessage() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }
}
