import Foundation
import SQLite3

struct AppNotes: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int
}

struct StoredNote: Identifiable, Hashable {
    let id: String
    let appBundleID: String
    let appName: String
    let windowTitle: String
    let markdown: String
    let updatedAt: Date
    let isPinned: Bool
}

/// Markdown source is stored now, while the MVP editor remains plain text. This avoids a later
/// content migration when rendering, checklists, links, and code blocks are introduced.
@MainActor
final class NoteStore {
    nonisolated(unsafe) private var database: OpaquePointer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backside", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appendingPathComponent("notes.sqlite")
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            database = nil
            return
        }
        execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY NOT NULL,
                app_bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT NOT NULL,
                markdown TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_seen_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS notes_app_updated ON notes(app_bundle_id, updated_at DESC);
            """)
    }

    deinit { if let database { sqlite3_close(database) } }

    func note(for key: String) -> String {
        queryOne("SELECT markdown FROM notes WHERE id = ?", bindings: [.text(key)]) { statement in
            Self.text(statement, 0) ?? ""
        } ?? ""
    }

    func register(_ target: TargetWindow) {
        let now = Date().timeIntervalSince1970
        execute("""
            INSERT INTO notes (id, app_bundle_id, app_name, window_title, markdown, created_at, updated_at, last_seen_at)
            VALUES (?, ?, ?, ?, '', ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET app_name = excluded.app_name, window_title = excluded.window_title, last_seen_at = excluded.last_seen_at
            """, bindings: [.text(target.key), .text(target.appBundleID), .text(target.appName), .text(target.title), .number(now), .number(now), .number(now)])
    }

    func save(_ markdown: String, for target: TargetWindow) {
        register(target)
        let now = Date().timeIntervalSince1970
        execute("UPDATE notes SET markdown = ?, updated_at = ?, last_seen_at = ? WHERE id = ?", bindings: [.text(markdown), .number(now), .number(now), .text(target.key)])
    }

    func applications(search: String = "") -> [AppNotes] {
        let predicate = search.isEmpty ? "" : "WHERE app_name LIKE ? OR window_title LIKE ? OR markdown LIKE ?"
        let bindings: [SQLiteValue] = search.isEmpty ? [] : [.text("%\(search)%"), .text("%\(search)%"), .text("%\(search)%")]
        return query("SELECT app_bundle_id, MAX(app_name), COUNT(*) FROM notes \(predicate) GROUP BY app_bundle_id ORDER BY MAX(updated_at) DESC", bindings: bindings) { statement in
            AppNotes(id: Self.text(statement, 0) ?? "", name: Self.text(statement, 1) ?? "Unknown App", count: Int(sqlite3_column_int(statement, 2)))
        }
    }

    func notes(appID: String?, search: String = "") -> [StoredNote] {
        var clauses: [String] = []
        var bindings: [SQLiteValue] = []
        if let appID { clauses.append("app_bundle_id = ?"); bindings.append(.text(appID)) }
        if !search.isEmpty {
            clauses.append("(app_name LIKE ? OR window_title LIKE ? OR markdown LIKE ?)")
            bindings += [.text("%\(search)%"), .text("%\(search)%"), .text("%\(search)%")]
        }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        return query("SELECT id, app_bundle_id, app_name, window_title, markdown, updated_at, is_pinned FROM notes \(whereClause) ORDER BY is_pinned DESC, updated_at DESC", bindings: bindings) { statement in
            StoredNote(id: Self.text(statement, 0) ?? "", appBundleID: Self.text(statement, 1) ?? "", appName: Self.text(statement, 2) ?? "", windowTitle: Self.text(statement, 3) ?? "Untitled", markdown: Self.text(statement, 4) ?? "", updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)), isPinned: sqlite3_column_int(statement, 6) != 0)
        }
    }

    func update(markdown: String, id: String) {
        execute("UPDATE notes SET markdown = ?, updated_at = ? WHERE id = ?", bindings: [.text(markdown), .number(Date().timeIntervalSince1970), .text(id)])
    }

    func setPinned(_ pinned: Bool, id: String) {
        execute("UPDATE notes SET is_pinned = ? WHERE id = ?", bindings: [.integer(pinned ? 1 : 0), .text(id)])
    }

    private enum SQLiteValue { case text(String), number(Double), integer(Int) }

    private func execute(_ sql: String, bindings: [SQLiteValue] = []) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(bindings, to: statement)
        sqlite3_step(statement)
    }

    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func query<T>(_ sql: String, bindings: [SQLiteValue] = [], map: (OpaquePointer) -> T) -> [T] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(bindings, to: statement)
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { results.append(map(statement)) }
        return results
    }

    private func queryOne<T>(_ sql: String, bindings: [SQLiteValue], map: (OpaquePointer) -> T) -> T? { query(sql, bindings: bindings, map: map).first }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
            case .number(let number): sqlite3_bind_double(statement, index, number)
            case .integer(let integer): sqlite3_bind_int(statement, index, Int32(integer))
            }
        }
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}
