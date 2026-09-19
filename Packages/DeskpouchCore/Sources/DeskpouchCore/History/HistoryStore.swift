import Foundation
import SQLite3
import os

private let log = Logger(subsystem: "com.constantinchirila.deskpouch", category: "history")

/// Which bucket a history row belongs to. Backs the History view's filter segments.
public enum HistoryKind: String, Codable, Sendable, CaseIterable {
    case text, recording, screenshot, meeting, convert
    /// A picked colour; `text` holds the copied value in whatever format was chosen.
    case color
}

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
    public let kind: HistoryKind
    /// Small JPEG cached for image results, so Recent/History can show a tile without loading the original file.
    public let thumbURL: URL?
    /// Per-tool extras: the exact colour of a `color` row, the display and rect of a capture.
    public let meta: ResultMeta?
    /// Marked in the gallery to keep it easy to find.
    public let starred: Bool

    /// `kind` defaults to an inference from the row's shape (a file means recording, no file means text) so
    /// existing callers that predate screenshots and thumbnails keep compiling unchanged.
    public init(
        id: UUID, toolID: String, createdAt: Date, text: String?, fileURL: URL?,
        duration: TimeInterval?, pastedInto: String?, kind: HistoryKind? = nil, thumbURL: URL? = nil,
        meta: ResultMeta? = nil, starred: Bool = false
    ) {
        self.meta = meta
        self.starred = starred
        self.id = id
        self.toolID = toolID
        self.createdAt = createdAt
        self.text = text
        self.fileURL = fileURL
        self.duration = duration
        self.pastedInto = pastedInto
        self.kind = kind ?? (fileURL == nil ? .text : .recording)
        self.thumbURL = thumbURL
    }
}

/// What the gallery asks the store for. Every part narrows the result; the defaults match everything.
public struct HistoryQuery: Sendable, Equatable {
    /// Substring of the text (a transcript, a colour value) or of the file's path.
    public var text = ""
    public var toolID: String?
    /// Nil means every kind.
    public var kinds: Set<HistoryKind>?
    /// `createdAt` at or after this.
    public var from: Date?
    /// `createdAt` before this.
    public var before: Date?
    public var starredOnly = false
    /// App name the result was pasted into.
    public var pastedInto: String?

    public init(
        text: String = "", toolID: String? = nil, kinds: Set<HistoryKind>? = nil, from: Date? = nil,
        before: Date? = nil, starredOnly: Bool = false, pastedInto: String? = nil
    ) {
        self.text = text
        self.toolID = toolID
        self.kinds = kinds
        self.from = from
        self.before = before
        self.starredOnly = starredOnly
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
                pasted_into TEXT,
                kind TEXT NOT NULL DEFAULT 'text',
                thumb_path TEXT,
                meta TEXT,
                starred INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        try migrateColumnsIfNeeded()
        try exec("CREATE INDEX IF NOT EXISTS results_created_at ON results(created_at DESC)")
    }

    /// Adds `kind`, `thumb_path`, `meta` and `starred` to a database opened from before this schema existed. `CREATE TABLE IF NOT
    /// EXISTS` above only applies to a table it creates, so an older on-disk file needs its own two columns
    /// added. Existing rows get the same inference `HistoryItem.init` uses for a nil `kind`: a file means
    /// recording, no file means text, the only two kinds earlier builds ever produced.
    private func migrateColumnsIfNeeded() throws {
        let existing = try existingColumns()
        if !existing.contains("kind") {
            try exec("ALTER TABLE results ADD COLUMN kind TEXT NOT NULL DEFAULT 'text'")
            try exec("UPDATE results SET kind = 'recording' WHERE file_path IS NOT NULL")
        }
        if !existing.contains("thumb_path") {
            try exec("ALTER TABLE results ADD COLUMN thumb_path TEXT")
        }
        if !existing.contains("meta") {
            try exec("ALTER TABLE results ADD COLUMN meta TEXT")
        }
        if !existing.contains("starred") {
            try exec("ALTER TABLE results ADD COLUMN starred INTEGER NOT NULL DEFAULT 0")
        }
    }

    private func existingColumns() throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(results)")
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw StoreError.sql(errorMessage()) }
            // Column 1 is `name` in a PRAGMA table_info row.
            if let name = column(statement, 1) { columns.insert(name) }
        }
        return columns
    }

    // MARK: Writes

    public func record(_ item: HistoryItem) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO results (id, tool_id, created_at, text, file_path, duration, pasted_into, kind, thumb_path, meta, starred)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        bind(statement, 8, item.kind.rawValue)
        bind(statement, 9, item.thumbURL?.path)
        bind(statement, 10, item.meta?.json)
        sqlite3_bind_int(statement, 11, item.starred ? 1 : 0)
        try step(statement, expecting: SQLITE_DONE)
    }

    /// Removes the rows and their thumbnails, and hands back the files they pointed at: the caller decides what
    /// happens to those (the gallery moves them to the Trash). Rows without a file contribute nothing.
    @discardableResult
    public func delete(ids: [UUID]) throws -> [URL] {
        var files: [URL] = []
        for id in ids {
            if let path = try filePath(id: id) { files.append(URL(fileURLWithPath: path)) }
            try delete(id: id)
        }
        return files
    }

    public func setStarred(_ starred: Bool, ids: [UUID]) throws {
        for id in ids {
            let statement = try prepare("UPDATE results SET starred = ? WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, starred ? 1 : 0)
            bind(statement, 2, id.uuidString)
            try step(statement, expecting: SQLITE_DONE)
        }
    }

    /// A thumbnail made after the fact, e.g. the poster frame of a recording logged before those were kept.
    public func setThumbnail(_ url: URL, id: UUID) throws {
        let statement = try prepare("UPDATE results SET thumb_path = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, url.path)
        bind(statement, 2, id.uuidString)
        try step(statement, expecting: SQLITE_DONE)
    }

    private func filePath(id: UUID) throws -> String? {
        let statement = try prepare("SELECT file_path FROM results WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, id.uuidString)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return column(statement, 0)
    }

    public func delete(id: UUID) throws {
        if let thumb = try thumbPath(id: id) {
            HistoryThumbnails.remove(URL(fileURLWithPath: thumb))
        }
        let statement = try prepare("DELETE FROM results WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, id.uuidString)
        try step(statement, expecting: SQLITE_DONE)
    }

    public func clear() throws {
        for thumb in try allThumbPaths() {
            HistoryThumbnails.remove(URL(fileURLWithPath: thumb))
        }
        try exec("DELETE FROM results")
    }

    private func thumbPath(id: UUID) throws -> String? {
        let statement = try prepare("SELECT thumb_path FROM results WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, id.uuidString)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return column(statement, 0)
    }

    private func allThumbPaths() throws -> [String] {
        let statement = try prepare("SELECT thumb_path FROM results WHERE thumb_path IS NOT NULL")
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

    // MARK: Reads

    /// Newest first.
    public func recent(limit: Int) throws -> [HistoryItem] {
        try items(matching: "", toolID: nil, limit: limit, offset: 0)
    }

    /// Newest first, filtered by a substring of the text or file name and optionally by tool, paged by `offset`.
    public func items(matching query: String, toolID: String?, limit: Int, offset: Int) throws -> [HistoryItem] {
        try items(HistoryQuery(text: query, toolID: toolID), limit: limit, offset: offset)
    }

    /// Newest first, paged by `offset`.
    public func items(_ query: HistoryQuery, limit: Int, offset: Int) throws -> [HistoryItem] {
        let filter = Self.filter(query)
        let statement = try prepare(
            """
            SELECT id, tool_id, created_at, text, file_path, duration, pasted_into, kind, thumb_path, meta, starred
            FROM results WHERE \(filter.sql)
            ORDER BY created_at DESC, rowid DESC LIMIT ? OFFSET ?
            """
        )
        defer { sqlite3_finalize(statement) }
        let next = bind(statement, filter.values)
        sqlite3_bind_int(statement, next, Int32(max(0, limit)))
        sqlite3_bind_int(statement, next + 1, Int32(max(0, offset)))
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
                pastedInto: column(statement, 6),
                kind: column(statement, 7).flatMap(HistoryKind.init(rawValue:)),
                thumbURL: column(statement, 8).map { URL(fileURLWithPath: $0) },
                meta: ResultMeta(json: column(statement, 9)),
                starred: sqlite3_column_int(statement, 10) != 0
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
        try count(HistoryQuery(text: query, toolID: toolID))
    }

    /// Rows `items(_:limit:offset:)` would page through.
    public func count(_ query: HistoryQuery) throws -> Int {
        let filter = Self.filter(query)
        let statement = try prepare("SELECT COUNT(*) FROM results WHERE \(filter.sql)")
        defer { sqlite3_finalize(statement) }
        bind(statement, filter.values)
        try step(statement, expecting: SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Rows per kind for the gallery's chips. `query.kinds` is left out on purpose: each chip says what picking it
    /// would show with the other filters as they are.
    public func countsByKind(_ query: HistoryQuery) throws -> [HistoryKind: Int] {
        var unrestricted = query
        unrestricted.kinds = nil
        let filter = Self.filter(unrestricted)
        let statement = try prepare("SELECT kind, COUNT(*) FROM results WHERE \(filter.sql) GROUP BY kind")
        defer { sqlite3_finalize(statement) }
        bind(statement, filter.values)
        var counts: [HistoryKind: Int] = [:]
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw StoreError.sql(errorMessage()) }
            if let kind = column(statement, 0).flatMap(HistoryKind.init(rawValue:)) {
                counts[kind] = Int(sqlite3_column_int64(statement, 1))
            }
        }
        return counts
    }

    /// Every app a result was pasted into, by name, for the gallery's filter.
    public func pastedIntoApps() throws -> [String] {
        let statement = try prepare(
            "SELECT DISTINCT pasted_into FROM results WHERE pasted_into IS NOT NULL ORDER BY pasted_into COLLATE NOCASE"
        )
        defer { sqlite3_finalize(statement) }
        var apps: [String] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw StoreError.sql(errorMessage()) }
            if let app = column(statement, 0) { apps.append(app) }
        }
        return apps
    }

    private enum Value {
        case text(String)
        case number(Double)
    }

    /// The WHERE clause for `query` and the values for its placeholders, in order.
    private static func filter(_ query: HistoryQuery) -> (sql: String, values: [Value]) {
        var clauses: [String] = []
        var values: [Value] = []
        if !query.text.isEmpty {
            clauses.append("(text LIKE ? ESCAPE '\\' OR file_path LIKE ? ESCAPE '\\')")
            let pattern = likePattern(query.text)
            values += [.text(pattern), .text(pattern)]
        }
        if let toolID = query.toolID {
            clauses.append("tool_id = ?")
            values.append(.text(toolID))
        }
        if let kinds = query.kinds {
            // An empty set matches nothing, as it says.
            let sorted = kinds.map(\.rawValue).sorted()
            clauses.append("kind IN (" + sorted.map { _ in "?" }.joined(separator: ", ") + ")")
            values += sorted.map(Value.text)
        }
        if let from = query.from {
            clauses.append("created_at >= ?")
            values.append(.number(from.timeIntervalSince1970))
        }
        if let before = query.before {
            clauses.append("created_at < ?")
            values.append(.number(before.timeIntervalSince1970))
        }
        if query.starredOnly {
            clauses.append("starred = 1")
        }
        if let app = query.pastedInto {
            clauses.append("pasted_into = ?")
            values.append(.text(app))
        }
        return (clauses.isEmpty ? "1" : clauses.joined(separator: " AND "), values)
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

    /// Binds `values` from placeholder 1 and returns the index of the next placeholder.
    @discardableResult
    private func bind(_ statement: OpaquePointer, _ values: [Value]) -> Int32 {
        var index: Int32 = 1
        for value in values {
            switch value {
            case .text(let text): bind(statement, index, text)
            case .number(let number): sqlite3_bind_double(statement, index, number)
            }
            index += 1
        }
        return index
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func errorMessage() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }
}
